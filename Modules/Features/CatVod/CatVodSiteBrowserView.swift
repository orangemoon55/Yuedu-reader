import SwiftUI

struct CatVodSiteBrowserView: View {
    @StateObject private var model: CatVodSession
    @State private var draft = ""
    @State private var searchPresented = false

    init(sourceID: String, site: CatVodSite, initialCategory: String? = nil) {
        _model = StateObject(wrappedValue: CatVodSession(sourceID: sourceID, site: site, initialCategory: initialCategory))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.md) {
                CatVodVideoSiteHeader(site: model.site)
                MediaHubVideoSearchField(text: $draft, loading: model.loading,
                    enabled: model.site.searchable, fieldIdentifier: "catvod.site.search",
                    buttonIdentifier: "catvod.site.searchSubmit",
                    submit: { searchPresented = true }, clear: { draft = "" })
                Text(localized("搜寻范围") + " · " + model.site.name)
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                categoryControls
                if MediaHubVideoLayout.showsSkeleton(loading: model.loading, itemCount: model.videos.count) {
                    MediaHubVideoSkeletonGrid()
                } else {
                    MediaHubVideoGrid(videos: model.videos, identifier: "catvod.site.fixedGrid") { video in
                        CatVodMovieLink(sourceID: model.sourceID, siteKey: model.site.key, video: video)
                    }
                    if model.loading { ProgressView(localized("加载中…")) }
                    else if let failure = model.failure {
                        Text(failure).foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("catvod.site.error")
                        Button(localized("重试")) { Task { await model.open(force: true) } }
                    } else if model.videos.isEmpty && model.home != nil {
                        Text(localized("暂无发现内容")).foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("catvod.site.empty")
                    } else if model.hasMore {
                        Button(localized("加载更多")) { Task { await model.more() } }
                            .frame(minHeight: 44).accessibilityIdentifier("catvod.site.loadMore")
                    }
                }
            }
            .padding(.horizontal, MediaHubVideoLayout.horizontalPadding)
            .padding(.vertical, DSSpacing.sm)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("catvod.site.browser")
        .navigationTitle(model.site.name).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .navigationDestination(isPresented: $searchPresented) {
            CatVodSearchPage(sourceID: model.sourceID, site: model.site, initialQuery: draft)
        }
        .task { await model.open() }.refreshable { await model.open(force: true) }
    }

    @ViewBuilder private var categoryControls: some View {
        if let home = model.home {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    if !home.categories.isEmpty {
                        Picker(localized("分类"), selection: Binding<String?>(get: { model.categoryID }, set: { value in
                            Task { await model.select(value) }
                        })) {
                            if !home.videos.isEmpty { Text(localized("站点推荐")).tag(nil as String?) }
                            ForEach(home.categories) { Text($0.name).tag(Optional($0.id)) }
                        }.pickerStyle(.menu).accessibilityIdentifier("catvod.site.category")
                    }
                    if let id = model.categoryID {
                        ForEach(home.filters[id] ?? []) { filter in
                            Picker(filter.name, selection: Binding(get: { model.filterValues[filter.key] ?? filter.initial }, set: { value in
                                var changed = model.filterValues; changed[filter.key] = value
                                Task { await model.select(id, values: changed) }
                            })) { ForEach(filter.options, id: \.value) { Text($0.name).tag($0.value) } }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
        }
    }
}

struct CatVodMovieLink: View {
    let sourceID: String, siteKey: String, video: CatVodVideo
    var body: some View {
        NavigationLink {
            CatVodMoviePage(sourceID: sourceID, siteKey: siteKey, videoID: video.id, title: video.title)
        } label: {
            MediaHubVideoPosterCard(sourceID: sourceID, video: video)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("catvod.site.video.\(video.id)")
    }
}
struct CatVodPoster: View {
    let sourceID: String, rawURL: String
    var body: some View {
        AsyncImage(url: CatVodCatalog.shared.poster(rawURL, sourceID: sourceID)) { phase in
            if let image = phase.image { image.resizable().scaledToFill() }
            else { Image(systemName: "film").foregroundStyle(DSColor.textSecondary) }
        }
        .frame(width: DSLayout.discoverRowCoverWidth, height: DSLayout.discoverRowCoverWidth / DSLayout.discoverCoverAspectRatio)
        .clipped().accessibilityHidden(true)
    }
}

private struct CatVodSearchPage: View {
    let sourceID: String, site: CatVodSite
    @State private var draft = ""
    @State private var submitted = ""
    @State private var results: [CatVodVideo] = []
    @State private var page = 0
    @State private var requestedPage = 1
    @State private var more = false
    @State private var loading = false
    @State private var failure: String?
    @State private var generation = UUID()
    init(sourceID: String, site: CatVodSite, initialQuery: String) {
        self.sourceID = sourceID
        self.site = site
        _draft = State(initialValue: initialQuery)
        _submitted = State(initialValue: initialQuery.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.md) {
                CatVodVideoSiteHeader(site: site)
                MediaHubVideoSearchField(text: $draft, loading: loading, enabled: site.searchable,
                    fieldIdentifier: "catvod.search.field", buttonIdentifier: "catvod.search.submit",
                    submit: submit, clear: clear)
                Text(localized("搜寻范围") + " · " + site.name)
                    .font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                if MediaHubVideoLayout.showsSkeleton(loading: loading, itemCount: results.count) {
                    MediaHubVideoSkeletonGrid()
                } else {
                    MediaHubVideoGrid(videos: results, identifier: "catvod.search.fixedGrid") { video in
                        CatVodMovieLink(sourceID: sourceID, siteKey: site.key, video: video)
                    }
                    if loading { ProgressView(localized("加载中…")) }
                    else if let failure {
                        Text(failure).accessibilityIdentifier("catvod.search.error")
                        Button(localized("重试")) { generation = UUID() }
                    } else if !submitted.isEmpty && results.isEmpty {
                        Text(localized("没有搜索结果")).accessibilityIdentifier("catvod.search.empty")
                    } else if more {
                        Button(localized("加载更多")) { requestedPage = page + 1; generation = UUID() }
                            .frame(minHeight: 44).accessibilityIdentifier("catvod.search.loadMore")
                    }
                }
            }
            .padding(.horizontal, MediaHubVideoLayout.horizontalPadding)
            .padding(.vertical, DSSpacing.sm)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localized("搜索本站影片")).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task(id: generation) {
            let query = submitted, token = generation, n = requestedPage
            guard !query.isEmpty else { return }
            loading = true; failure = nil
            defer { if token == generation { loading = false } }
            do {
                let result = try await CatVodCatalog.shared.search(sourceID: sourceID, siteKey: site.key, query: query, page: n)
                try Task.checkCancellation(); guard generation == token else { return }
                var seen = Set(results.map(\.id)); let fresh = result.videos.filter { seen.insert($0.id).inserted }
                results += fresh; page = result.page; more = result.hasMore && !fresh.isEmpty && result.page >= n
            } catch { if generation == token && !Task.isCancelled { failure = CatVodCatalog.message(error) } }
        }
    }
    private func clear() {
        draft = ""; submitted = ""; results = []; more = false; failure = nil; loading = false
        requestedPage = 1; page = 0; generation = UUID()
    }

    private func submit() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !q.isEmpty else { return }
        submitted = q; results = []; more = false; requestedPage = 1; page = 0; generation = UUID()
    }
}
