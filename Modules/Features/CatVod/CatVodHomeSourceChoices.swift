import SwiftUI

/// A content picker, never a second MD5 import flow. Fetch only the chosen package and site.
struct CatVodHomeSourceChoices: View {
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice) -> Void
    @ObservedObject private var library = Md5SourceLibrary.shared
    var body: some View {
        List {
            if library.isLoaded && library.sources.isEmpty {
                Text(localized("請先在設定的模組中匯入 MD5 源。"))
            }
            ForEach(library.sources) { source in
                NavigationLink(source.title) {
                    CatVodSiteChoices(source: source, current: current, choose: choose)
                }
            }
        }
        .navigationTitle(localized("貓源影視")).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore).task { library.loadIfNeeded() }
    }
}
private struct CatVodSiteChoices: View {
    let source: Md5Source
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice) -> Void
    @State private var sites: [CatVodSite]?
    @State private var failure: String?
    @State private var filter = ""
    @State private var attempt = 0
    var body: some View {
        List {
            if let failure {
                Text(failure); Button(localized("重試")) { attempt += 1 }
            } else if let sites {
                if sites.isEmpty { Text(localized("源已不再提供此站點。")) }
                ForEach(sites.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.key.localizedCaseInsensitiveContains(filter) }) { site in
                    NavigationLink(site.name) {
                        CatVodFeedChoices(source: source, site: site, current: current, choose: choose)
                    }
                }
            } else { ProgressView() }
        }
        .searchable(text: $filter, prompt: Text(localized("站點")))
        .navigationTitle(source.title).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task(id: attempt) {
            failure = nil
            do { let found = try await CatVodCatalog.shared.sites(sourceID: source.id); try Task.checkCancellation(); sites = found }
            catch { if !Task.isCancelled { failure = CatVodCatalog.message(error) } }
        }
    }
}
private struct CatVodFeedChoices: View {
    let source: Md5Source
    let site: CatVodSite
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice) -> Void
    @State private var home: CatVodHome?
    @State private var failure: String?
    @State private var attempt = 0
    var body: some View {
        List {
            if let failure {
                Text(failure); Button(localized("重試")) { attempt += 1 }
            } else if let home {
                if !home.videos.isEmpty { choice(nil) }
                ForEach(home.categories) { choice($0) }
                if home.videos.isEmpty && home.categories.isEmpty { Text(localized("此站點沒有可加入首頁的清單。")) }
            } else { ProgressView() }
        }
        .navigationTitle(site.name).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task(id: attempt) {
            failure = nil
            do { let result = try await CatVodCatalog.shared.home(sourceID: source.id, siteKey: site.key); try Task.checkCancellation(); home = result }
            catch { if !Task.isCancelled { failure = CatVodCatalog.message(error) } }
        }
    }
    private func choice(_ category: CatVodCategory?) -> some View {
        let ref = CatVodFeedRef(sourceID: source.id, siteKey: site.key, siteName: site.name,
                                categoryID: category?.id, categoryName: category?.name)
        return Button { choose(HomeContentChoice(binding: .catVod(ref), itemTitle: ref.title)) } label: {
            HStack {
                Text(category?.name ?? localized("站點推薦"))
                if current == .catVod(ref) { Spacer(); Image(systemName: "checkmark").accessibilityLabel(localized("目前")) }
            }
        }
    }
}

/// 「查看全部」 reopens the saved site and category after a cold app launch.
struct CatVodFeedPage: View {
    let ref: CatVodFeedRef
    @State private var site: CatVodSite?
    @State private var failure: String?
    @State private var attempt = 0
    var body: some View {
        Group {
            if let site { CatVodSiteBrowserView(sourceID: ref.sourceID, site: site, initialCategory: ref.categoryID) }
            else if let failure { VStack { Text(failure); Button(localized("重試")) { attempt += 1 } } }
            else { ProgressView() }
        }
        .navigationTitle(ref.title).toolbarTitleDisplayMode(.inline)
        .task(id: attempt) {
            guard site == nil else { return }
            failure = nil
            do {
                let all = try await CatVodCatalog.shared.sites(sourceID: ref.sourceID)
                try Task.checkCancellation()
                guard let found = all.first(where: { $0.key == ref.siteKey }) else { throw CatVodUseError.noSite }
                site = found
            } catch { if !Task.isCancelled { failure = CatVodCatalog.message(error) } }
        }
    }
}
