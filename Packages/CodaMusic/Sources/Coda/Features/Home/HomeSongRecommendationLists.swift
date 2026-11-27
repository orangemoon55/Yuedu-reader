import SwiftUI

/// Round-robin keeps several liked-song seeds represented, rather than taking
/// every recommendation from whichever network request finished first.
enum HomeSongSuggestionSelection {
    /// Prefer unused seeds; only reuse the previous batch for small libraries.
    static func seeds(from candidates: [Int], avoiding previous: Set<Int>, limit: Int = 3) -> [Int] {
        guard limit > 0 else { return [] }
        var seen = Set<Int>()
        let unique = candidates.filter { seen.insert($0).inserted }
        return Array((unique.filter { !previous.contains($0) } + unique.filter { previous.contains($0) }).prefix(limit))
    }

    static func select(_ groups: [[Track]], excluding excluded: Set<Int>, limit: Int = 36) -> [Track] {
        guard limit > 0 else { return [] }
        var seen = excluded
        var result: [Track] = []
        for index in 0..<(groups.map(\.count).max() ?? 0) {
            for group in groups where group.indices.contains(index) {
                let track = group[index]
                if seen.insert(track.id).inserted { result.append(track) }
                if result.count == limit { return result }
            }
        }
        return result
    }
}

@MainActor
final class HomeSongSuggestionsModel: ObservableObject {
    static let shared = HomeSongSuggestionsModel()

    struct Context: Hashable {
        /// Identifies the signed-in account of any provider; nil when signed out.
        let accountKey: String?
        /// NetEase user ID for play records; other providers read their own session.
        let uid: Int?
        let likedIDs: [Int]

        @MainActor
        static func current(_ account: AccountStore) -> Context {
            let key: String?
            if account.provider == .netease {
                key = account.authenticatedAccountID.map { "netease:\($0)" }
            } else {
                key = account.isLoggedIn ? "\(account.provider.rawValue):\(account.displayUserID)" : nil
            }
            return .init(accountKey: key, uid: account.authenticatedAccountID,
                         likedIDs: key == nil ? [] : account.likedTrackIDs.sorted())
        }
    }

    @Published private(set) var likedTracks: [Track] = []
    @Published private(set) var songTracks: [Track] = []
    @Published private(set) var seed: Track?
    @Published private(set) var isLoading = false
    @Published private(set) var hasCompletedLoad = false
    @Published private(set) var likedError: String?
    @Published private(set) var songError: String?
    private var generation = UUID()
    private var previousSeeds: Set<Int> = []
    private var seedAccountID: String?
    private var hasLoaded = false
    private var fetchedAt: Date?
    private var loadedContext: Context?
    private var requestedContext: Context?

    /// Sidebar navigation reuses the current batch; manual refresh always calls `load`.
    func loadIfNeeded(context: Context, currentTrack: Track?) async {
        // A request started before the liked library arrived cannot produce liked
        // suggestions, so it must not hold back the request that can.
        if isLoading, let requestedContext, requestedContext.accountKey == context.accountKey,
           requestedContext.likedIDs.isEmpty == context.likedIDs.isEmpty { return }
        if loadedContext == context, hasLoaded, let fetchedAt, Date().timeIntervalSince(fetchedAt) < 300 { return }
        await load(context: context, currentTrack: currentTrack)
    }

    func load(context: Context, currentTrack: Track?) async {
        let request = UUID()
        generation = request
        requestedContext = context
        let authentication = MusicProviderContext.shared.authenticationKey
        isLoading = true
        likedError = nil
        songError = nil
        // Keep the previous batch visible during a refresh in the same account.
        // Account changes must never display another user's recommendations.
        if seedAccountID != context.accountKey {
            likedTracks = []
            songTracks = []
            seed = nil
            hasLoaded = false
        }
        defer { if generation == request { isLoading = false; hasCompletedLoad = true } }

        if seedAccountID != context.accountKey {
            previousSeeds = []
            seedAccountID = context.accountKey
        }
        let seeds = HomeSongSuggestionSelection.seeds(from: context.likedIDs.shuffled(), avoiding: previousSeeds)
        async let liked = Self.likedSuggestions(ids: seeds)
        async let song = Self.songSuggestions(context: context, currentTrack: currentTrack)
        let (likedResult, songResult) = await (liked, song)
        guard !Task.isCancelled, generation == request,
              authentication == MusicProviderContext.shared.authenticationKey else { return }
        hasLoaded = !likedResult.failed && !songResult.failed
        loadedContext = context
        fetchedAt = Date()
        if !likedResult.failed { previousSeeds = Set(seeds) }
        likedTracks = HomeSongSuggestionSelection.select(likedResult.groups, excluding: Set(context.likedIDs))
        likedError = likedResult.failed ? String(localized: "推荐加载失败，请重试") : nil
        seed = songResult.seed
        songTracks = HomeSongSuggestionSelection.select([songResult.tracks], excluding: Set([songResult.seed?.id].compactMap { $0 }))
        songError = songResult.failed ? String(localized: "推荐加载失败，请重试") : nil
    }

    private static func likedSuggestions(ids: [Int]) async -> (groups: [[Track]], failed: Bool) {
        guard !ids.isEmpty else { return ([], false) }
        return await withTaskGroup(of: (Int, [Track]?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try? await NeteaseAPI.similarSongs(id: id, limit: 12)) }
            }
            var results: [Int: [Track]] = [:]
            for await (index, tracks) in group {
                if let tracks { results[index] = tracks }
            }
            return (ids.indices.compactMap { results[$0] }, results.isEmpty)
        }
    }

    private static func songSuggestions(context: Context, currentTrack: Track?) async -> (seed: Track?, tracks: [Track], failed: Bool) {
        var source = currentTrack
        if source == nil, context.accountKey != nil {
            source = try? await NeteaseAPI.playRecords(uid: context.uid ?? 0, week: true).first?.song
        }
        if source == nil, let id = context.likedIDs.first {
            source = try? await NeteaseAPI.songDetails(ids: [id]).songs.first
        }
        guard let source else { return (nil, [], false) }
        do {
            return (source, try await NeteaseAPI.similarSongs(id: source.id, limit: 12), false)
        } catch {
            return (source, [], true)
        }
    }
}

struct HomeSongRecommendationLists: View {
    @EnvironmentObject private var account: AccountStore
    private let player = PlayerService.shared
    @Environment(\.openLogin) private var openLogin
    @Environment(\.openDestination) private var openDestination
    @ObservedObject var model: HomeSongSuggestionsModel

    /// Sorting the liked library is only needed to start a request, never to render.
    private var needsLogin: Bool { !account.isLoggedIn }

    private var context: HomeSongSuggestionsModel.Context { .current(account) }

    var body: some View {
        VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
            likedList
            songList
        }
    }

    private var likedList: some View {
        recommendationList(title: String(localized: "根据你喜爱的歌曲推荐"), tracks: model.likedTracks,
                           error: model.likedError,
                           emptyText: needsLogin ? String(localized: "登录后发现你喜欢的音乐") : String(localized: "收藏一些喜欢的歌曲，发现更多相似音乐"),
                           needsLogin: needsLogin)
    }

    private var songList: some View {
        recommendationList(title: model.seed.map { String(localized: "根据「\($0.name)」为你推荐") }
                           ?? String(localized: "根据歌曲为你推荐"), tracks: model.songTracks,
                           error: model.songError, emptyText: String(localized: "播放一首歌曲，发现更多相似音乐"), destination: .song)
    }

    private func recommendationList(title: String, tracks: [Track], error: String?, emptyText: String,
                                    destination: HomeRecommendationPage = .liked, needsLogin: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SectionHeader(title: LocalizedStringKey(title), action: {
                openDestination(.homeRecommendation(destination))
            })
                .frame(maxWidth: .infinity, minHeight: HomeLayout.headerHeight, alignment: .leading)
                .padding(.bottom, HomeLayout.headerSpacing)
                .padding(.horizontal, Theme.Layout.contentInset)
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.bottom, Theme.Spacing.control)
                .padding(.horizontal, Theme.Layout.contentInset)
            if model.isLoading || !model.hasCompletedLoad {
                MusicLibraryLoadingView(rowsPerColumn: 3, scrollsHorizontally: true,
                                        showsHorizontalPanel: false,
                                        horizontalInset: Theme.Layout.trackListInset,
                                        fixedColumnWidth: Theme.Layout.homeSongColumnWidth)
            } else if !tracks.isEmpty {
                MusicTrackPanel(tracks: tracks, scrollsHorizontally: true,
                                horizontalRowLimit: 3, horizontalInset: Theme.Layout.trackListInset, fixedColumnWidth: Theme.Layout.homeSongColumnWidth, showsHorizontalPanel: false,
                                showsRowSeparators: false)
            } else {
                recommendationContents(tracks: tracks, error: error, emptyText: emptyText, needsLogin: needsLogin)
                    .padding(Theme.Spacing.component)
                    .padding(.horizontal, Theme.Layout.contentInset)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func recommendationContents(tracks: [Track], error: String?, emptyText: String,
                                         needsLogin: Bool) -> some View {
        if needsLogin {
            HomeLoginPrompt(message: String(localized: "根据你收藏的歌曲推荐相似音乐"), minHeight: 216)
        } else {
            VStack(spacing: Theme.Spacing.control) {
                    Text(error ?? emptyText)
                        .font(Theme.Typography.secondary).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if error != nil {
                        Button("重试") { Task { await model.load(context: context, currentTrack: player.currentTrack) } }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 216)
        }
    }

}
