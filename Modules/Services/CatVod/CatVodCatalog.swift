import Foundation
import CryptoKit

/// Persistent selection: an installed bundle's digest, its own site and optional category.
/// Never persist the ephemeral host, authentication, or a resolved playback URL.
struct CatVodFeedRef: Codable, Hashable, Sendable {
    let sourceID: String
    let siteKey: String
    let siteName: String
    let categoryID: String?
    let categoryName: String?
    var title: String { categoryName.map { "\(siteName) · \($0)" } ?? siteName }
}

struct CatVodMovieRef: Hashable, Sendable {
    let sourceID: String
    let siteKey: String
    let siteName: String
    let videoID: String
    let title: String
}

enum CatVodUseError: LocalizedError {
    case removed, noSite, notSearchable, parsePage, inUse
    var errorDescription: String? {
        switch self {
        case .removed: localized("這個 MD5 源已移除，請重新選擇內容來源。")
        case .noSite: localized("源已不再提供此站點。")
        case .notSearchable: localized("這個站點不支援搜尋。")
        case .parsePage: localized("此線路需要網頁解析，請換一條提供直連的線路。")
        case .inUse: localized("另一個貓源正在播放，關閉播放器後再試。")
        }
    }
}

/// Select the exact installed site for *each* operation. A single Node instance serves several
/// saved home rows: activation AND invocation form one serial operation, not two racing awaits.
@MainActor
final class CatVodCatalog {
    static let shared = CatVodCatalog()
    private var tail: Task<Void, Never>?
    private var lastJob: UUID?
    private var playing: (sourceID: String, id: UUID)?
    private func perform<T: Sendable>(_ body: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tail, id = UUID()
        lastJob = id
        let work = Task { @MainActor in
            await previous?.value
            try Task.checkCancellation()
            return try await body()
        }
        tail = Task { _ = await work.result }
        defer { if lastJob == id { tail = nil; lastJob = nil } }
        return try await withTaskCancellationHandler { try await work.value } onCancel: { work.cancel() }
    }
    private func activate(_ sourceID: String) async throws -> [CatVodSite] {
        if let playing, playing.sourceID != sourceID { throw CatVodUseError.inUse }
        let library = Md5SourceLibrary.shared
        library.loadIfNeeded()
        guard let item = library.sources.first(where: { $0.id == sourceID }) else { throw CatVodUseError.removed }
        return try await CatVodRuntime.shared.activate(source: item, bundleURL: library.bundleURL(for: item),
                                                      dataDirectory: library.dataDirectory(for: item))
    }
    func sites(sourceID: String) async throws -> [CatVodSite] {
        try await perform { try await self.activate(sourceID) }
    }
    // Configuration uses the same serialized source activation as browsing/playback.
    // A stale settings page must never read or write another source's login database.
    func credentials(sourceID: String) async throws -> CatVodCredentials {
        try await perform {
            _ = try await self.activate(sourceID)
            return try await CatVodRuntime.shared.credentials()
        }
    }
    func saveCredential(sourceID: String, provider: String, field: String, value: String) async throws {
        try await perform {
            _ = try await self.activate(sourceID)
            try await CatVodRuntime.shared.saveCredential(provider: provider, field: field, value: value)
        }
    }
    func clearCredential(sourceID: String, provider: String, field: String) async throws {
        try await perform {
            _ = try await self.activate(sourceID)
            try await CatVodRuntime.shared.clearCredential(provider: provider, field: field)
        }
    }
    private func request(_ sourceID: String, _ key: String, _ action: String, _ args: [String: Any]) async throws -> Data {
        guard let site = try await activate(sourceID).first(where: { $0.key == key }) else { throw CatVodUseError.noSite }
        if action == "search", !site.searchable { throw CatVodUseError.notSearchable }
        return try await CatVodRuntime.shared.invoke(sourceID: sourceID, site: site, action: action, arguments: args)
    }
    func home(sourceID: String, siteKey: String) async throws -> CatVodHome {
        try await perform { try CatVodContentParser.home(await self.request(sourceID, siteKey, "home", ["filter": true])) }
    }
    func category(sourceID: String, siteKey: String, id: String, page: Int, filters: [String:String]) async throws -> CatVodPage {
        try await perform {
            let data = try await self.request(sourceID, siteKey, "category", ["id": id, "page": page, "filters": filters, "tid": id, "pg": page, "extend": filters, "filter": true])
            return try CatVodContentParser.page(data, requestedPage: page)
        }
    }
    func search(sourceID: String, siteKey: String, query: String, page: Int) async throws -> CatVodPage {
        try await perform {
            let data = try await self.request(sourceID, siteKey, "search", ["wd": query, "page": page, "pg": page, "quick": false])
            return try CatVodContentParser.page(data, requestedPage: page)
        }
    }
    func detail(sourceID: String, siteKey: String, videoID: String) async throws -> CatVodVideo {
        try await perform { try CatVodContentParser.detail(await self.request(sourceID, siteKey, "detail", ["id": [videoID], "ids": videoID])) }
    }
    func poster(_ text: String, sourceID: String) -> URL? {
        guard !text.isEmpty else { return nil }
        return try? CatVodRuntime.shared.mediaURL(text, sourceID: sourceID)
    }
    func play(sourceID: String, siteKey: String, videoID: String, flag: String, episode: CatVodEpisode) async throws -> CatVodPlayTicket {
        try await perform {
            let data = try await self.request(sourceID, siteKey, "play", ["flag": flag, "id": episode.playID])
            let stream = try CatVodPlaybackFactory.stream(data: data, sourceID: sourceID, siteKey: siteKey,
                                                          videoID: videoID, flag: flag, episode: episode) {
                try CatVodRuntime.shared.mediaURL($0, sourceID: sourceID)
            }
            try Task.checkCancellation()
            let ticket = CatVodPlayTicket(id: UUID(), stream: stream)
            self.playing = (sourceID, ticket.id)
            return ticket
        }
    }
    func release(_ ticket: UUID) { if playing?.id == ticket { playing = nil } }
    static func message(_ error: Error) -> String {
        (error as? CatVodRuntimeError)?.message ?? error.localizedDescription
    }
}
struct CatVodPlayTicket: Identifiable, Sendable {
    let id: UUID
    let stream: VideoStream
}

/// The production JSON → stream path. URL ownership/authentication stays in the runtime:
/// the catalog always supplies `CatVodRuntime.mediaURL`, while tests supply a local fixture.
/// This does not activate a source, acquire a lease, sniff a page, or access the network.
enum CatVodPlaybackFactory {
    static func stream(data: Data, sourceID: String, siteKey: String, videoID: String,
                       flag: String, episode: CatVodEpisode,
                       resolveURL: (String) throws -> URL) throws -> VideoStream {
        let result = try CatVodContentParser.playback(data)
        guard !result.requiresWebParsing else { throw CatVodUseError.parsePage }
        let url = try resolveURL(result.url)
        guard url.pathExtension.lowercased() != "mpd" else { throw VideoChapterLinkError.dashManifest }
        // These headers belong to this source's selected playback response, not the global
        // cookie store. Pan/CDN links may require them; discarding them turns valid media
        // requests into 401/403 even after the source has resolved an authorized URL.
        let allowed = Set(["user-agent", "referer", "origin", "accept", "accept-language", "cookie", "authorization"])
        let headers = result.headers.filter {
            allowed.contains($0.key.lowercased()) && $0.value.utf8.count <= 16 * 1024
                && $0.value.utf8.allSatisfy { ($0 == 9 || $0 >= 32) && $0 != 127 }
        }
        let resumeBytes = try JSONEncoder().encode([sourceID, siteKey, videoID, flag, episode.id])
        let digest = SHA256.hash(data: resumeBytes).map { String(format: "%02x", $0) }.joined()
        return VideoStream(url: url, headers: headers, resumeKey: URL(string: "readcc-catvod://episode/" + digest))
    }
}
