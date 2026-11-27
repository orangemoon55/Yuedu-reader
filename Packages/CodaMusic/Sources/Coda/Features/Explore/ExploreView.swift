import SwiftUI

private struct ExploreCategoryChip: Identifiable, Equatable {
    let id: String
    let title: String
    var qqCategoryID: Int? = nil
}

@MainActor
final class ExploreViewModel: ObservableObject {
    static let categories: [String] = [
        "全部", "推荐歌单", "精品歌单", "排行榜", "官方",
        "华语", "流行", "摇滚", "民谣", "电子", "轻音乐", "说唱", "爵士", "古典",
        "影视原声", "ACG", "古风", "怀旧", "治愈", "放松", "伤感", "快乐",
        "学习", "工作", "运动", "驾车", "夜晚",
    ]

    @Published var selectedCategory = "全部"
    @Published var playlists: [PlaylistSummary] = []
    @Published var toplists: [ToplistItem] = []
    @Published var isLoading = false
    @Published var hasMore = true
    @Published private var qqCategories: [ExploreCategoryChip] = []
    @Published private(set) var qqCategoriesFailed = false
    private let qqCategoryRefresh = PanelRefreshGate()
    private var offset = 0
    private var highQualityBefore = 0
    private var exposureIDs: [UInt64] = []
    private var loadTask: Task<Void, Never>?

    @Published var errorMessage: String?
    private struct Snapshot {
        var playlists: [PlaylistSummary]
        var toplists: [ToplistItem]
        var offset: Int
        var before: Int
        var exposureIDs: [UInt64]
        var hasMore: Bool
        var fetchedAt: Date
    }
    private var snapshots: [String: Snapshot] = [:]
    private var requestID = UUID()
    private var authentication: String?

    fileprivate func categoryChips(for provider: MusicProvider) -> [ExploreCategoryChip] {
        let builtIn = provider.exploreCategories.map { ExploreCategoryChip(id: $0, title: $0) }
        return provider == .qq ? builtIn + qqCategories : builtIn
    }

    func refreshQQCategories(force: Bool = false) async {
        guard MusicProviderContext.shared.current == .qq,
              let request = qqCategoryRefresh.begin(key: "qq", lifetime: 900, force: force) else { return }
        var success = false
        defer { qqCategoryRefresh.finish(request, success: success) }
        do {
            let categories = try await QQMusicAPI.shared.playlistCategories()
            guard qqCategoryRefresh.accepts(request), MusicProviderContext.shared.current == .qq else { return }
            qqCategories = categories.map {
                ExploreCategoryChip(id: "qq-category-\($0.id)", title: $0.name, qqCategoryID: $0.id)
            }
            if selectedCategory.hasPrefix("qq-category-"), !qqCategories.contains(where: { $0.id == selectedCategory }) {
                select("全部")
            }
            success = true
            qqCategoriesFailed = false
        } catch {
            guard qqCategoryRefresh.accepts(request), MusicProviderContext.shared.current == .qq else { return }
            qqCategoriesFailed = qqCategories.isEmpty
        }
    }

    func select(_ category: String) {
        guard category != selectedCategory else { return }
        loadTask?.cancel()
        requestID = UUID()
        isLoading = false
        selectedCategory = category
        restore(category)
        loadTask = Task { await refresh() }
    }

    private func restore(_ category: String) {
        let saved = snapshots[category]
        playlists = saved?.playlists ?? []
        toplists = saved?.toplists ?? []
        offset = saved?.offset ?? 0
        highQualityBefore = saved?.before ?? 0
        exposureIDs = saved?.exposureIDs ?? []
        hasMore = saved?.hasMore ?? true
        errorMessage = nil
    }

    func refresh(force: Bool = false) async {
        let binding = MusicProviderContext.shared.authenticationKey
        if binding != authentication {
            authentication = binding
            snapshots = [:]
            requestID = UUID(); isLoading = false
            restore(selectedCategory)
        }
        // 各平台分类不同（酷狗没有“全部”），当前分类不存在时回到该平台的第一个分类。
        let chips = categoryChips(for: MusicProviderContext.shared.current)
        if !chips.contains(where: { $0.id == selectedCategory }) {
            selectedCategory = chips.first?.id ?? "全部"
            restore(selectedCategory)
        }
        if !force, let saved = snapshots[selectedCategory], Date().timeIntervalSince(saved.fetchedAt) < 900 { return }
        await loadMore(reset: true)
    }

    func loadMore(reset: Bool = false) async {
        guard reset || (!isLoading && hasMore) else { return }
        let request = UUID()
        requestID = request
        let category = selectedCategory
        let binding = MusicProviderContext.shared.authenticationKey
        let provider = MusicProviderContext.shared.current
        let qqCategoryID = provider == .qq ? qqCategories.first { $0.id == category }?.qqCategoryID : nil
        let kugouSort = provider == .kugou ? KugouMusicAPI.PlaylistSort.allCases.first { $0.title == category } : nil
        let requestedOffset = reset ? 0 : offset
        let requestedBefore = reset ? 0 : highQualityBefore
        let requestedExposure = reset ? [] : exposureIDs
        isLoading = true
        defer { if requestID == request { isLoading = false } }
        do {
            var fresh: [PlaylistSummary] = []
            var charts: [ToplistItem] = []
            var more = false
            var before = 0
            var nextExposure = requestedExposure
            switch (provider, category, qqCategoryID) {
            case (.qq, _, let id?):
                let page = try await PlatformMusicAPI.shared.qqCategoryPlaylists(id: id, page: requestedOffset)
                fresh = page.items
                more = page.more
            case (.qishui, "全部", _), (.qishui, "推荐歌单", _):
                let page = try await PlatformMusicAPI.shared.qishuiFeaturedPlaylists(excluding: requestedExposure)
                fresh = page.playlists
                var seen = Set(requestedExposure)
                nextExposure += page.exposureIDs.filter { seen.insert($0).inserted }
                more = page.hasMore && nextExposure.count > requestedExposure.count
            case (.kugou, _, _) where kugouSort != nil:
                // 酷狗分类每次固定返回 40 个，没有下一页。
                fresh = try await PlatformMusicAPI.shared.kugouSortedPlaylists(kugouSort!)
            case (_, "排行榜", _): charts = try await NeteaseAPI.toplists()
            case (_, "推荐歌单", _): fresh = try await NeteaseAPI.personalizedPlaylists(limit: 100)
            case (_, "精品歌单", _):
                let result = try await NeteaseAPI.highQualityPlaylists(before: requestedBefore)
                fresh = result.playlists; before = result.lasttime ?? 0; more = result.more ?? false
            default:
                let result = try await NeteaseAPI.topPlaylists(category: category, offset: requestedOffset)
                fresh = result.playlists; more = (result.more ?? false) && requestedOffset + 50 < 500
            }
            guard !Task.isCancelled, requestID == request, selectedCategory == category,
                  binding == MusicProviderContext.shared.authenticationKey else { return }
            let existing = reset ? Set<Int>() : Set(playlists.map(\.id))
            let additions = fresh.filter { !existing.contains($0.id) }
            playlists = (reset ? [] : playlists) + additions
            toplists = charts
            offset = requestedOffset + (qqCategoryID == nil ? 50 : 1); highQualityBefore = before
            exposureIDs = nextExposure
            hasMore = more && ((provider != .qishui && qqCategoryID == nil) || !additions.isEmpty)
            errorMessage = nil
            snapshots[category] = Snapshot(playlists: playlists, toplists: toplists, offset: offset,
                                           before: before, exposureIDs: exposureIDs, hasMore: hasMore,
                                           fetchedAt: reset ? Date() : snapshots[category]?.fetchedAt ?? Date())
        } catch {
            guard !Task.isCancelled, requestID == request else { return }
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Toplist grid

struct ToplistGrid: View {
    let toplists: [ToplistItem]

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: Theme.Spacing.group)],
            alignment: .leading, spacing: Theme.Spacing.section
        ) {
            ForEach(toplists) { toplist in
                NavigationLink(value: Destination.playlist(toplist.id)) {
                    HStack(spacing: Theme.Spacing.component) {
                        CachedAsyncImage(url: toplist.coverImgUrl?.resizedImageURL(256))
                            .frame(width: 110, height: 110)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
                        VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                            Text(toplist.name)
                                .font(Theme.Typography.secondary.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text(toplist.updateFrequency ?? "")
                                .font(Theme.Typography.caption)
                                .foregroundStyle(.tertiary)
                            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                                ForEach(Array(toplist.tracks.prefix(3).enumerated()), id: \.offset) { i, preview in
                                    Text("\(i + 1). \(preview.first) - \(preview.second)")
                                        .font(Theme.Typography.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(Theme.Spacing.control)
                    .background(.primary.opacity(0.04),
                                in: RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ToplistsView: View {
    @State private var toplists: [ToplistItem] = []

    var body: some View {
        ScenePreservingScrollView {
            VStack(spacing: 0) {
                ToplistGrid(toplists: toplists)
                    .padding(Theme.Layout.contentInset)
                PlayerClearanceSpacer()
            }
        }
        .navigationTitle("排行榜")
        .task {
            if toplists.isEmpty {
                toplists = (try? await NeteaseAPI.toplists()) ?? []
            }
        }
    }
}


extension MusicProvider {
    var exploreCategories: [String] {
        switch self {
        case .netease: return ExploreViewModel.categories
        case .qishui: return ["全部", "推荐歌单"]
        case .kugou: return KugouMusicAPI.PlaylistSort.allCases.map(\.title) + ["排行榜"]
        default: return ["全部", "推荐歌单", "排行榜"]
        }
    }
}
