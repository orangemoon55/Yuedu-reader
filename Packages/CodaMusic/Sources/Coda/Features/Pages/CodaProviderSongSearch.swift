import Combine
import Foundation

/// These are music providers, never Readcc book sources. Aggregation is SONG-only.
enum CodaSongSearchScope: String, CaseIterable, Identifiable, Sendable {
    case all, netease, qq, kugou, qishui
    var id: String { rawValue }
    var title: String {
        self == .all ? "全源聚合" : providers[0].name
    }
    var providers: [MusicProvider] {
        switch self {
        case .all: return [.netease, .qq, .kugou, .qishui]
        case .netease: return [.netease]
        case .qq: return [.qq]
        case .kugou: return [.kugou]
        case .qishui: return [.qishui]
        }
    }
}

@MainActor
enum CodaProviderSongSearch {
    // Track and its nested structs contain immutable value metadata only. The
    // unchecked conformance bridges existing non-Sendable legacy Track models;
    // all consumption, registration and publication remain on the main actor.
    struct Page: @unchecked Sendable {
        let tracks: [Track]
        let nextOffset: Int
        let hasMore: Bool
    }

    static func page(provider: MusicProvider, query: String, limit: Int, offset: Int) async throws -> Page {
        let context = MusicProviderContext.shared
        let ticket = context.ticket
        let session = AccountStore.shared.sessionRevision
        let result = try await NeteaseAPI.search(query, type: .songs, limit: limit,
                                                 offset: offset, provider: provider)
        try context.check(ticket)
        guard session == AccountStore.shared.sessionRevision else { throw CancellationError() }
        let raw = result.songs ?? []
        let tracks = try PlatformMusicAPI.shared.registerSearchTracks(raw, provider: provider)
        // Offset advances by consumed rows, not by post-deduplication count. Each
        // provider owns its own offset; a failed provider never advances it.
        let next = offset + raw.count
        let more = !raw.isEmpty && (result.songCount.map { next < $0 } ?? (raw.count >= limit))
        return Page(tracks: tracks, nextOffset: next, hasMore: more)
    }
}

/// Supplies native Track rows to MusicTrackPanel (group by provider for native
/// queues). NetEase keeps its positive native IDs (nil platformSong means NetEase
/// throughout Coda); vendors carry ProviderSong and negative provider-scoped IDs.
/// Playback still obeys PlayerService's active-provider guard: provenance does
/// not silently switch accounts or authorize a mixed/cross-provider queue.
@MainActor
final class CodaProviderSongSearchModel: ObservableObject {
    typealias Loader = @MainActor @Sendable (MusicProvider, String, Int, Int) async throws -> CodaProviderSongSearch.Page
    typealias SessionIdentity = @MainActor () -> String

    @Published private(set) var tracks: [Track] = []
    @Published private(set) var isLoading = false
    @Published private(set) var isLoadingMore = false
    @Published private(set) var hasMore = false
    @Published private(set) var failureMessage: String?
    @Published private(set) var failedProviders: [MusicProvider] = []

    private struct Cursor {
        var offset = 0
        var hasMore = true
        var failed = false
    }
    private enum Outcome: Sendable {
        case success(MusicProvider, Int, CodaProviderSongSearch.Page)
        case failure(MusicProvider)
        case cancelled
    }
    private let pageSize: Int
    private let loader: Loader
    private let sessionIdentity: SessionIdentity
    private var query = ""
    private var scope: CodaSongSearchScope = .all
    private var cursors: [MusicProvider: Cursor] = [:]
    private var rows: [MusicProvider: [Track]] = [:]
    private var generation = UUID()
    private var activeBatchID: UUID?
    private var activeTask: Task<Void, Never>?
    private var searchSession = ""

    init(pageSize: Int = 30,
         loader: @escaping Loader = { provider, query, limit, offset in
             try await CodaProviderSongSearch.page(provider: provider, query: query, limit: limit, offset: offset)
         },
         sessionIdentity: @escaping SessionIdentity = {
             "\(MusicProviderContext.shared.ticket):\(AccountStore.shared.sessionRevision)"
         }) {
        self.pageSize = min(max(pageSize, 1), 100)
        self.loader = loader
        self.sessionIdentity = sessionIdentity
    }

    func load(query: String, scope: CodaSongSearchScope) async {
        activeTask?.cancel()
        generation = UUID()
        activeTask = nil
        activeBatchID = nil
        self.query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        self.scope = scope
        searchSession = sessionIdentity()
        rows = [:]
        cursors = [:]
        tracks = []
        failureMessage = nil
        failedProviders = []
        isLoading = false
        isLoadingMore = false
        hasMore = false
        guard !self.query.isEmpty, !Task.isCancelled else { return }
        cursors = Dictionary(uniqueKeysWithValues: scope.providers.map { ($0, Cursor()) })
        await run(scope.providers, initial: true)
    }

    func loadMore() async {
        guard activeTask == nil, !query.isEmpty, !Task.isCancelled else { return }
        let providers = scope.providers.filter { cursors[$0].map { $0.hasMore && !$0.failed } ?? false }
        await run(providers, initial: false)
    }

    /// Explicit retry only: keeps successful rows/pages and retries each failed
    /// source at exactly its previous offset, including failures on later pages.
    /// If the account changed, nothing from the old session may be retained, so
    /// this explicit user action starts a fresh search under the new session.
    func retryFailures() async {
        guard activeTask == nil, !query.isEmpty, !Task.isCancelled else { return }
        if sessionIdentity() != searchSession {
            await load(query: query, scope: scope)
            return
        }
        await run(scope.providers.filter { cursors[$0]?.failed == true }, initial: tracks.isEmpty)
    }

    private func run(_ providers: [MusicProvider], initial: Bool) async {
        guard !providers.isEmpty else { return }
        guard sessionIdentity() == searchSession else { invalidateSession(); return }
        let batchID = UUID()
        let requestID = generation
        let session = searchSession
        let keyword = query
        let requests = providers.map { ($0, cursors[$0]?.offset ?? 0) }
        activeBatchID = batchID
        isLoading = initial
        isLoadingMore = !initial
        let task = Task { [weak self] in
            guard let self else { return }
            await self.fetch(requests, keyword: keyword, requestID: requestID,
                             batchID: batchID, session: session)
        }
        activeTask = task
        // Task{} is deliberately owned so superseding loads can cancel it. Also
        // propagate SwiftUI .task cancellation, not just query/scope changes.
        await withTaskCancellationHandler(operation: { await task.value }, onCancel: { task.cancel() })
    }

    private func fetch(_ requests: [(MusicProvider, Int)], keyword: String,
                       requestID: UUID, batchID: UUID, session: String) async {
        defer {
            // An older request must not stop a newer request's spinner or task.
            if generation == requestID, activeBatchID == batchID {
                activeTask = nil
                activeBatchID = nil
                isLoading = false
                isLoadingMore = false
                if sessionIdentity() != session { invalidateSession() }
                else { updateStatus() }
            }
        }
        let load = loader
        let limit = pageSize
        await withTaskGroup(of: Outcome.self) { group in
            for (provider, offset) in requests {
                group.addTask { @MainActor in
                    do {
                        try Task.checkCancellation()
                        let page = try await load(provider, keyword, limit, offset)
                        try Task.checkCancellation()
                        return .success(provider, offset, page)
                    } catch is CancellationError {
                        return .cancelled
                    } catch let error as URLError where error.code == .cancelled {
                        return .cancelled
                    } catch {
                        // No cookies, request URLs, server messages or credential
                        // payloads escape into the UI's failure string.
                        return .failure(provider)
                    }
                }
            }
            for await outcome in group {
                guard generation == requestID, activeBatchID == batchID,
                      !Task.isCancelled, sessionIdentity() == session else {
                    group.cancelAll()
                    continue
                }
                switch outcome {
                case let .success(provider, offset, page):
                    guard var cursor = cursors[provider], cursor.offset == offset else { continue }
                    // Validate provenance even for an injected loader. Never let a
                    // wrong-source page become playable under a different label.
                    guard page.tracks.allSatisfy({ track in
                        if provider == .netease { return track.id > 0 && track.platformSong == nil }
                        return track.id < 0 && track.platformSong?.source.rawValue == provider.rawValue
                    }), page.nextOffset >= offset,
                    page.tracks.isEmpty || page.nextOffset > offset else {
                        cursor.failed = true
                        cursors[provider] = cursor
                        updateStatus()
                        continue
                    }
                    var seen = Set((rows[provider] ?? []).map(\.id))
                    let novel = page.tracks.filter { seen.insert($0.id).inserted }
                    rows[provider, default: []].append(contentsOf: novel)
                    cursor.offset = page.nextOffset
                    // A full repeated page with no new identities cannot keep an
                    // infinite-scroll spinner alive, even if a vendor says more.
                    cursor.hasMore = page.hasMore && !page.tracks.isEmpty && !novel.isEmpty
                    cursor.failed = false
                    cursors[provider] = cursor
                    rebuildTracks()
                case let .failure(provider):
                    cursors[provider]?.failed = true
                case .cancelled:
                    break // Cancellation is not a provider failure or empty result.
                }
                updateStatus()
            }
        }
    }

    private func rebuildTracks() {
        // Deterministic rank interleaving, independent of network completion order.
        // Deduplicate only within a provider: the same recording on two services
        // remains two results with independent playback handles.
        let count = scope.providers.map { rows[$0]?.count ?? 0 }.max() ?? 0
        tracks = (0..<count).flatMap { index in
            scope.providers.compactMap { provider in
                guard let items = rows[provider], index < items.count else { return nil as Track? }
                return items[index]
            }
        }
    }

    private func updateStatus() {
        failedProviders = scope.providers.filter { cursors[$0]?.failed == true }
        hasMore = scope.providers.contains { cursors[$0].map { $0.hasMore && !$0.failed } ?? false }
        guard !failedProviders.isEmpty else { failureMessage = nil; return }
        let names = failedProviders.map(\.name).joined(separator: "、")
        failureMessage = tracks.isEmpty
            ? "\(names)搜索失败，请重试"
            : "\(names)搜索失败，已保留其他结果，请重试"
    }

    private func invalidateSession() {
        rows = [:]
        cursors = [:]
        tracks = []
        failedProviders = []
        hasMore = false
        failureMessage = "音乐账号或平台已变更，请重新搜索"
    }
}
