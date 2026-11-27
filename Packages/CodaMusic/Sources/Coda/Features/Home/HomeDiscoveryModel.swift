import Foundation
import Combine

@MainActor
final class HomeDiscoveryModel: ObservableObject {
    static let shared = HomeDiscoveryModel()
    typealias Content = HomeDiscoveryContent
    typealias Slot = HomeDiscoverySlot

    @Published private(set) var contents: [Slot: Content] = [:]
    @Published private(set) var failedSlots: Set<Slot> = []
    @Published private(set) var isLoading = false
    @Published private(set) var loadingSlots = Set(Slot.allCases)
    private var authentication: String?
    private var request: UUID?
    private var fetchedAt: Date?
    private let fetchHome: (Bool) async throws -> [Slot: Content]
    private let fetchPlaylists: (Bool) async throws -> [PlaylistSummary]
    private let availableSlots: () -> [Slot]
    private let fetchSongs: (Int) async throws -> [Track]

    init(fetchHome: @escaping (Bool) async throws -> [Slot: Content] = { try await NeteaseAPI.homeDiscovery(refresh: $0) },
         fetchPlaylists: @escaping (Bool) async throws -> [PlaylistSummary] = { loggedIn in
             async let general = NeteaseAPI.personalizedPlaylists(limit: 30)
             let daily = loggedIn ? try? await NeteaseAPI.recommendResource() : nil
             let common = try? await general
             guard daily != nil || common != nil else { throw URLError(.cannotLoadFromNetwork) }
             var seen = Set<Int>()
             return ((daily ?? []) + (common ?? [])).filter { seen.insert($0.id).inserted }
         },
         fetchSongs: @escaping (Int) async throws -> [Track] = { try await NeteaseAPI.homeTopSongs(areaID: $0) },
         availableSlots: @escaping () -> [Slot] = { MusicProviderContext.shared.current.homeDiscoverySlots }) {
        self.fetchHome = fetchHome
        self.fetchPlaylists = fetchPlaylists
        self.fetchSongs = fetchSongs
        self.availableSlots = availableSlots
    }

    func load(loggedIn: Bool, force: Bool = false, now: Date = Date()) async {
        let binding = MusicProviderContext.shared.authenticationKey
        if binding != authentication {
            authentication = binding
            contents = [:]; failedSlots = []; fetchedAt = nil; request = nil
        }
        if !force {
            guard request == nil else { return }
            if failedSlots.isEmpty, let fetchedAt, now.timeIntervalSince(fetchedAt) >= 0,
               now.timeIntervalSince(fetchedAt) < 900 { return }
        }
        let token = UUID()
        request = token
        isLoading = true
        loadingSlots = Set(availableSlots())
        failedSlots = []
        defer {
            if request == token { request = nil; isLoading = false; loadingSlots = [] }
        }
        let slots = availableSlots()
        let server = (try? await fetchHome(force)) ?? [:]
        guard !Task.isCancelled, request == token, binding == MusicProviderContext.shared.authenticationKey else { return }
        // Make server modules visible before any slower fallback completes.
        for slot in slots {
            if let fresh = server[slot] {
                contents[slot] = fresh
                loadingSlots.remove(slot)
            }
        }
        await withTaskGroup(of: (Slot, Content?).self) { group in
            for slot in slots where server[slot] == nil {
                group.addTask {
                    let content: Content?
                    switch slot {
                    case .playlists: content = await self.fallbackPlaylists(needed: true, loggedIn: loggedIn)
                    case .trending: content = await self.fallbackSongs(needed: true)
                    case .regional: content = await self.fallbackRegional(needed: true)
                    case .newSongs, .radios, .forYou, .hiddenGems: content = nil
                    }
                    return (slot, content)
                }
            }
            var failures = Set<Slot>()
            for await (slot, fresh) in group {
                guard !Task.isCancelled, request == token,
                      binding == MusicProviderContext.shared.authenticationKey else { continue }
                if let fresh { contents[slot] = fresh }
                else { failures.insert(slot); failedSlots.insert(slot) }
                loadingSlots.remove(slot)
            }
            guard !Task.isCancelled, request == token,
                  binding == MusicProviderContext.shared.authenticationKey else { return }
            failedSlots = failures
        }
        guard !Task.isCancelled, request == token, binding == MusicProviderContext.shared.authenticationKey else { return }
        fetchedAt = now
    }

    private func fallbackPlaylists(needed: Bool, loggedIn: Bool) async -> Content? {
        guard needed else { return nil }
        guard let playlists = try? await fetchPlaylists(loggedIn) else { return nil }
        return .playlists(playlists)
    }

    private func fallbackSongs(needed: Bool) async -> Content? {
        guard needed else { return nil }
        guard let songs = try? await fetchSongs(0) else { return nil }
        return .songs(Self.mergeSongs([songs], limit: 100))
    }

    private func fallbackRegional(needed: Bool) async -> Content? {
        guard needed else { return nil }
        let fetch = fetchSongs
        return await withTaskGroup(of: (Int, [Track]?).self) { group in
            for (index, area) in [7, 96, 8, 16].enumerated() {
                group.addTask { (index, try? await fetch(area)) }
            }
            var batches: [Int: [Track]] = [:]
            for await (index, songs) in group { if let songs { batches[index] = songs } }
            guard !batches.isEmpty else { return nil }
            return .songs(Self.mergeSongs((0..<4).compactMap { batches[$0] }, limit: 100))
        }
    }

    /// Interleave regions so a full first page represents every available region.
    static func mergeSongs(_ groups: [[Track]], limit: Int) -> [Track] {
        HomeSongSuggestionSelection.select(groups, excluding: [], limit: limit)
    }
}
