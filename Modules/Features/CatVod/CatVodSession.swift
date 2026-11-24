import Foundation
import Combine

@MainActor
final class CatVodSession: ObservableObject {
    let sourceID: String
    let site: CatVodSite
    @Published private(set) var home: CatVodHome?
    @Published private(set) var categoryID: String?
    @Published private(set) var filterValues: [String:String] = [:]
    @Published private(set) var videos: [CatVodVideo] = []
    @Published private(set) var loading = false
    @Published private(set) var hasMore = false
    @Published private(set) var failure: String?
    private var page = 0
    private var generation = UUID()
    private var initialized = false
    private let catalog = CatVodCatalog.shared
    init(sourceID: String, site: CatVodSite, initialCategory: String?) {
        self.sourceID = sourceID; self.site = site; self.categoryID = initialCategory
    }
    func open(force: Bool = false) async {
        guard !initialized || force else { return }
        let token = UUID(); generation = token
        loading = true; failure = nil
        do {
            let result = try await catalog.home(sourceID: sourceID, siteKey: site.key)
            try Task.checkCancellation(); guard generation == token else { return }
            home = result; initialized = true
            // A site can publish only classes: use a real class instead of hiding all the tabs.
            let id = categoryID ?? (result.videos.isEmpty ? result.categories.first?.id : nil)
            if let id, !result.categories.contains(where: { $0.id == id }) { throw CatVodUseError.noSite }
            await select(id)
        } catch { if generation == token { if !Task.isCancelled { failure = CatVodCatalog.message(error) }; loading = false } }
    }
    func select(_ id: String?, values: [String:String]? = nil) async {
        generation = UUID(); categoryID = id
        filterValues = values ?? (home?.filters[id ?? ""] ?? []).reduce(into: [:]) { $0[$1.key] = $1.initial }
        page = 0; failure = nil; hasMore = false; videos = []
        guard let id else { videos = home?.videos ?? []; loading = false; return }
        await load(id: id, number: 1)
    }
    func more() async {
        guard !loading, hasMore, let id = categoryID else { return }
        await load(id: id, number: page + 1)
    }
    private func load(id: String, number: Int) async {
        let token = generation; loading = true; failure = nil
        defer { if generation == token { loading = false } }
        do {
            let result = try await catalog.category(sourceID: sourceID, siteKey: site.key, id: id, page: number, filters: filterValues)
            try Task.checkCancellation(); guard generation == token else { return }
            var seen = Set(videos.map(\.id)); let fresh = result.videos.filter { seen.insert($0.id).inserted }
            videos += fresh; page = result.page; hasMore = result.hasMore && !fresh.isEmpty && result.page >= number
        } catch { if generation == token && !Task.isCancelled { failure = CatVodCatalog.message(error) } }
    }
}
