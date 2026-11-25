import Foundation

/// Presentation rules deliberately depend on source metadata, never inferred charts or ratings.
enum MediaHubPresentation {
    static let heroLimit = 5
    static let categoryRailLimit = 3

    /// CatVodRuntime currently exposes video.sites only. A site's name is not a music contract.
    static func compatibleSites(_ sites: [CatVodSite], kind: MediaHubKind) -> [CatVodSite] {
        guard kind == .video else { return [] }
        var seen = Set<String>()
        return sites.filter { !$0.key.isEmpty && seen.insert($0.key).inserted }
    }

    static func uniqueVideos(_ videos: [CatVodVideo]) -> [CatVodVideo] {
        var seen = Set<String>()
        return videos.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
    }

    static func heroVideos(_ videos: [CatVodVideo]) -> [CatVodVideo] {
        Array(uniqueVideos(videos).filter { !plainText($0.poster).isEmpty }.prefix(heroLimit))
    }

    static func facts(for video: CatVodVideo) -> String {
        distinctText([video.year, video.area, video.remarks]).joined(separator: " · ")
    }

    static func facts(for item: MediaHubLibraryItem) -> String {
        distinctText([item.year ?? "", item.area ?? "", item.remarks ?? ""]).joined(separator: " · ")
    }

    static func categoryCandidates(_ categories: [CatVodCategory]) -> [CatVodCategory] {
        var seen = Set<String>()
        return Array(categories.filter { !$0.id.isEmpty && seen.insert($0.id).inserted }
            .prefix(categoryRailLimit))
    }

    static func savedItems(_ items: [MediaHubLibraryItem], kind: MediaHubKind,
                           query: String = "", sourceID: String? = nil) -> [MediaHubLibraryItem] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            item.kind == kind && (sourceID == nil || sourceID == item.sourceID)
                && (query.isEmpty || [item.title, item.siteName, item.categoryName ?? ""]
                    .contains { $0.localizedCaseInsensitiveContains(query) })
        }
    }

    /// Old bookmarks have no category. Group those by their actual site, not a guessed genre.
    static func savedRails(_ items: [MediaHubLibraryItem]) -> [MediaHubSavedRail] {
        var rails: [MediaHubSavedRail] = []
        for item in items {
            let category = plainText(item.categoryName ?? "")
            let id = [item.sourceID, item.siteKey, category]
                .map { Data($0.utf8).base64EncodedString() }.joined(separator: ".")
            if let index = rails.firstIndex(where: { $0.id == id }) {
                rails[index].items.append(item)
            } else {
                rails.append(MediaHubSavedRail(id: id,
                    title: category.isEmpty ? item.siteName : category,
                    subtitle: category.isEmpty ? "" : item.siteName, items: [item]))
            }
        }
        return rails
    }

    /// Public saved artwork can render without booting an unrelated CatVod source.
    /// Relative references still require the source-aware runtime resolver.
    static func publicArtworkURL(_ raw: String) -> URL? {
        let safe = MediaHubLibraryItem.persistablePoster(raw)
        guard let url = URL(string: safe), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func posterColumnCount(_ preference: Int, accessibility: Bool) -> Int {
        accessibility ? 1 : min(5, max(2, preference))
    }

    /// Source summaries can contain simple HTML. Show readable source text, not markup.
    static func plainText(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func distinctText(_ input: [String]) -> [String] {
        var seen = Set<String>()
        return input.map(plainText).filter { !$0.isEmpty && seen.insert($0).inserted }
    }
}

struct MediaHubVideoRail: Identifiable, Sendable {
    let category: CatVodCategory
    let videos: [CatVodVideo]
    var id: String { category.id }
}

struct MediaHubSavedRail: Identifiable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    var items: [MediaHubLibraryItem]
}
