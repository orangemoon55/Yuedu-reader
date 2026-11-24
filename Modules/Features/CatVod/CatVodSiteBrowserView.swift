import SwiftUI

struct CatVodSiteBrowserView: View {
    @StateObject private var model: CatVodSession
    init(sourceID: String, site: CatVodSite, initialCategory: String? = nil) {
        _model = StateObject(wrappedValue: CatVodSession(sourceID: sourceID, site: site, initialCategory: initialCategory))
    }
    var body: some View {
        List {
            if model.site.searchable {
                NavigationLink {
                    CatVodSearchPage(sourceID: model.sourceID, site: model.site)
                } label: { Label(localized("搜尋本站影片"), systemImage: "magnifyingglass") }
                .accessibilityIdentifier("catvod.site.search")
            }
            if let home = model.home {
                Section {
                    if !home.categories.isEmpty {
                        Picker(localized("分類"), selection: Binding<String?>(get: { model.categoryID }, set: { value in Task { await model.select(value) } })) {
                            if !home.videos.isEmpty { Text(localized("站點推薦")).tag(nil as String?) }
                            ForEach(home.categories) { Text($0.name).tag(Optional($0.id)) }
                        }
                    }
                    if let id = model.categoryID {
                        ForEach(home.filters[id] ?? []) { filter in
                            Picker(filter.name, selection: Binding(get: { model.filterValues[filter.key] ?? filter.initial }, set: { value in
                                var changed = model.filterValues; changed[filter.key] = value
                                Task { await model.select(id, values: changed) }
                            })) { ForEach(filter.options, id: \.value) { Text($0.name).tag($0.value) } }
                        }
                    }
                }.interfaceSectionSurface()
            }
            Section {
                ForEach(model.videos) { video in
                    CatVodMovieLink(sourceID: model.sourceID, siteKey: model.site.key, video: video)
                }
                if model.loading { ProgressView(localized("載入中")) }
                else if let failure = model.failure {
                    Text(failure).foregroundStyle(DSColor.textSecondary)
                    Button(localized("重試")) { Task { await model.open(force: true) } }
                } else if model.videos.isEmpty && model.home != nil {
                    Text(localized("暫無發現內容")).foregroundStyle(DSColor.textSecondary)
                } else if model.hasMore {
                    Button(localized("載入更多")) { Task { await model.more() } }
                }
            }.interfaceSectionSurface()
        }
        .navigationTitle(model.site.name).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task { await model.open() }.refreshable { await model.open(force: true) }
    }
}

struct CatVodMovieLink: View {
    let sourceID: String, siteKey: String, video: CatVodVideo
    var body: some View {
        NavigationLink {
            CatVodMoviePage(sourceID: sourceID, siteKey: siteKey, videoID: video.id, title: video.title)
        } label: {
            HStack(spacing: DSSpacing.sm) {
                CatVodPoster(sourceID: sourceID, rawURL: video.poster)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(video.title).font(DSFont.headline).lineLimit(2)
                    if !video.remarks.isEmpty { Text(video.remarks).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary) }
                }
            }
        }
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
    var body: some View {
        List {
            Section {
                TextField(localized("片名"), text: $draft).submitLabel(.search).onSubmit { submit() }
                Button(localized("搜索")) { submit() }.disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }.interfaceSectionSurface()
            Section {
                ForEach(results) { video in CatVodMovieLink(sourceID: sourceID, siteKey: site.key, video: video) }
                if loading { ProgressView(localized("載入中")) }
                else if let failure { Text(failure); Button(localized("重試")) { generation = UUID() } }
                else if !submitted.isEmpty && results.isEmpty { Text(localized("沒有搜尋結果")) }
                else if more { Button(localized("載入更多")) { requestedPage = page + 1; generation = UUID() } }
            }.interfaceSectionSurface()
        }
        .navigationTitle(localized("搜尋本站影片")).toolbarTitleDisplayMode(.inline)
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
    private func submit() {
        let q = draft.trimmingCharacters(in: .whitespacesAndNewlines); guard !q.isEmpty else { return }
        submitted = q; results = []; more = false; requestedPage = 1; page = 0; generation = UUID()
    }
}
