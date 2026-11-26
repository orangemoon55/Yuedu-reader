import Foundation

/// Serves only .catVod rows. Registering this provider is local: no bundle starts until the
/// reader actually selects a source or displays one of its saved sections. HomeModel serializes
/// these rows on one lane, matching the single Node instance. Missing sources fail visibly.
@MainActor
final class CatVodHomeProvider: HomeSectionProviding {
    let instance = SourceInstanceKey(type: .module, id: "readcc:catvod:home")
    var displayName: String { localized("猫源影视") }
    var availability: ProviderAvailability { .available }
    var hosts: [String] { [] }
    func loadPolicy(for section: HomeSection) -> SectionLoadPolicy? {
        if case .catVod = section.binding { return .serialPerSource }; return nil
    }
    func inputsKey(for section: HomeSection) -> String? {
        guard case .catVod(let ref) = section.binding else { return nil }
        return Md5SourceLibrary.shared.sources.contains(where: { $0.id == ref.sourceID }) ? ref.sourceID : "removed"
    }
    func rowName(for section: HomeSection) -> String {
        if case .catVod(let ref) = section.binding { return ref.title }; return displayName
    }
    func load(_ section: HomeSection) async throws -> [CollectionEntry] {
        guard case .catVod(let ref) = section.binding else { return [] }
        let catalog = CatVodCatalog.shared
        let videos: [CatVodVideo]
        if let id = ref.categoryID {
            videos = try await catalog.category(sourceID: ref.sourceID, siteKey: ref.siteKey, id: id, page: 1, filters: [:]).videos
        } else {
            videos = try await catalog.home(sourceID: ref.sourceID, siteKey: ref.siteKey).videos
        }
        try Task.checkCancellation()
        return Self.entries(videos, for: ref) { catalog.poster($0, sourceID: ref.sourceID) }
    }
    static func entries(_ videos: [CatVodVideo], for ref: CatVodFeedRef, poster: (String) -> URL?) -> [CollectionEntry] {
        videos.prefix(HomeRow.limit).map { video in
            let movie = CatVodMovieRef(sourceID: ref.sourceID, siteKey: ref.siteKey, siteName: ref.siteName,
                                       videoID: video.id, title: video.title)
            let key = SourceItemKey(instance: SourceInstanceKey(type: .module, id: "readcc:catvod:" + ref.sourceID + ":" + ref.siteKey), item: video.id)
            let record = SourceRecord(key: key, title: video.title, authors: video.actor.isEmpty ? [] : [video.actor],
                                      language: nil, contentKind: .video, identifiers: [], copyID: nil, acquisitions: [.viewOnly])
            let cover: CoverReference = poster(video.poster).map { .remote($0, headers: [:]) } ?? .generated(seed: video.title)
            let summary = WorkSummary(title: video.title, authors: record.authors, cover: cover, blurb: video.summary,
                                      language: nil, contentKind: .video, category: video.remarks)
            return .item(record, summary, .catVodMovie(movie))
        }
    }
}
