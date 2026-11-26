import CoreFoundation
import Foundation

/// Public catalogue facts only. This service never fetches an audio URL, sends credentials,
/// executes a source script, or treats a search result as permission to play a recording.
enum MusicCatalogKind: String, CaseIterable, Identifiable, Sendable {
    case song, artist, album, playlist
    var id: String { rawValue }
    var title: String {
        switch self {
        case .song: return "歌曲"
        case .artist: return "歌手"
        case .album: return "專輯"
        case .playlist: return "歌單"
        }
    }
    var searchType: String {
        switch self {
        case .song: return "1"
        case .artist: return "100"
        case .album: return "10"
        case .playlist: return "1000"
        }
    }
    var resultKey: String {
        switch self {
        case .song: return "songs"
        case .artist: return "artists"
        case .album: return "albums"
        case .playlist: return "playlists"
        }
    }
}

enum MusicCatalogPlatform: String, CaseIterable, Identifiable, Sendable {
    case wy, tx, kg, kw, mg, sd, apple
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wy: return "網易雲音樂"
        case .tx: return "QQ 音樂"
        case .kg: return "酷狗音樂"
        case .kw: return "酷我音樂"
        case .mg: return "咪咕音樂"
        case .sd: return "汽水音樂"
        case .apple: return "Apple Music"
        }
    }
    var providerName: String { title + " · 公開元資料" }
    var searchKinds: [MusicCatalogKind] {
        switch self {
        case .wy: return MusicCatalogKind.allCases
        case .tx: return [.song, .album, .playlist]
        case .apple: return [.song, .album, .artist]
        case .kg, .kw, .mg, .sd: return [.song]
        }
    }
    var detailKinds: [MusicCatalogKind] {
        switch self {
        case .wy: return [.artist, .album, .playlist]
        case .tx: return [.album, .playlist]
        case .apple: return [.artist, .album]
        case .kg, .kw, .mg, .sd: return []
        }
    }
    var hasCharts: Bool { self == .wy || self == .tx }
    var hasPlaylists: Bool { self == .wy || self == .tx }
    /// Only providers with a known LX identity mapping may be offered for resolution.
    var hasResolverMapping: Bool { ![.sd, .apple].contains(self) }
    var capabilityNotice: String {
        switch self {
        case .wy: return "支援歌曲、歌手、專輯、歌單搜尋與公開目錄。"
        case .tx: return "QQ 目錄支援歌曲、專輯與歌單；暫不支援歌手搜尋／詳情。"
        case .kg, .kw: return "支援公開歌曲搜尋；排行榜、歌單及集合詳情尚不支援。線上歌詞尚不支援。"
        case .mg: return "提供匿名歌曲搜尋；服務可能拒絕未授權請求，屆時顯示錯誤，不繞過驗證。暫無首頁、集合詳情與線上歌詞。"
        case .sd: return "僅支援輸入數字曲目 ID 查詢公開單曲。關鍵字搜尋、首頁、集合、JS 播放映射及線上歌詞尚未確認，已停用。"
        case .apple: return "使用 Apple 公開 iTunes 美國商店目錄，支援歌曲、專輯、歌手。不是 Apple Music 播放授權；此處不提供播放、歌詞或歌單。"
        }
    }
}

struct MusicCatalogTrack: Hashable, Identifiable, Sendable {
    let platform: MusicCatalogPlatform
    let numericSongID: String?
    let mediaMid: String?
    var id: String { platform.rawValue + ":song:" + identifier }
    init(identifier: String, title: String, artist: String, album: String, poster: String,
         durationMilliseconds: Int, platform: MusicCatalogPlatform = .wy,
         numericSongID: String? = nil, mediaMid: String? = nil) {
        self.identifier = identifier; self.title = title; self.artist = artist; self.album = album
        self.poster = poster; self.durationMilliseconds = durationMilliseconds; self.platform = platform
        self.numericSongID = numericSongID; self.mediaMid = mediaMid
    }
    let identifier: String
    let title: String
    let artist: String
    let album: String
    let poster: String
    let durationMilliseconds: Int
}

struct MusicCatalogEntry: Hashable, Identifiable, Sendable {
    let platform: MusicCatalogPlatform
    init(identifier: String, kind: MusicCatalogKind, title: String, subtitle: String, poster: String,
         track: MusicCatalogTrack?, platform: MusicCatalogPlatform = .wy) {
        self.identifier = identifier; self.kind = kind; self.title = title; self.subtitle = subtitle
        self.poster = poster; self.track = track; self.platform = platform
    }
    let identifier: String
    let kind: MusicCatalogKind
    let title: String
    let subtitle: String
    let poster: String
    let track: MusicCatalogTrack?
    var id: String { platform.rawValue + ":" + kind.rawValue + ":" + identifier }
}

enum MusicCatalogError: LocalizedError, Equatable {
    case invalidResponse, http(Int), rejected(Int), unsupportedResolver, invalidQuery, invalidSongLookup, unsupportedCapability
    var errorDescription: String? {
        switch self {
        case .invalidResponse: return localized("音樂目錄回應格式不支援或超出安全上限。")
        case .http(let status): return "公開音樂目錄 HTTP \(status)"
        case .rejected(let code): return "公開音樂目錄暫不可用（服務代碼 \(code)）；不會嘗試登入或繞過限制。"
        case .unsupportedResolver: return localized("此曲需要已實作身份映射、平台完全一致且支援 musicUrl 的 JS 音源。Apple 與汽水元資料不代表播放授權；切換目錄不會切換播放平台。")
        case .invalidSongLookup: return localized("汽水目前僅支援數字曲目 ID 查詢；關鍵字搜尋協議尚未確認。")
        case .unsupportedCapability: return localized("此平台尚未支援這類搜尋或詳情；不會使用其他平台的結果代替。")
        case .invalidQuery: return localized("請輸入 1 至 300 字的搜尋內容。")
        }
    }
}

/// Parsing is bounded before JSON decoding and never forwards the catalogue's arbitrary fields
/// (including fee, URL, privilege or account data) to the JavaScript resolver.
enum MusicCatalogParser {
    static let bodyLimit = 2 * 1024 * 1024
    static let resultLimit = 100
    static func root(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= bodyLimit,
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let code = root["code"] as? Int else { throw MusicCatalogError.invalidResponse }
        guard code == 200 else { throw MusicCatalogError.rejected(code) }
        return root
    }
    static func identifier(_ value: Any?) -> String? {
        let text: String
        if let value = value as? String { text = value }
        else if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { text = value.stringValue }
        else { return nil }
        guard !text.isEmpty, text.count <= 20, text.utf8.allSatisfy({ (48...57).contains($0) }),
              let number = UInt64(text), number > 0 else { return nil }
        return text
    }
    static func text(_ value: Any?) -> String { String((value as? String ?? "").prefix(500)) }
    /// Only public provider artwork; upgrade the service's legacy HTTP CDN links to HTTPS.
    static func artwork(_ value: Any?) -> String {
        guard let value = value as? String, value.utf8.count <= 2048,
              var parts = URLComponents(string: value), parts.user == nil, parts.password == nil,
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.port == nil, let host = parts.host?.lowercased(),
              host.hasSuffix(".music.126.net"), parts.query == nil, parts.fragment == nil else { return "" }
        parts.scheme = "https"
        return parts.string ?? ""
    }
    static func track(_ object: [String: Any]) -> MusicCatalogTrack? {
        guard let id = identifier(object["id"]) else { return nil }
        let title = text(object["name"])
        guard !title.isEmpty else { return nil }
        let album = object["album"] as? [String: Any] ?? object["al"] as? [String: Any] ?? [:]
        let artists = object["artists"] as? [[String: Any]] ?? object["ar"] as? [[String: Any]] ?? []
        return MusicCatalogTrack(identifier: id, title: title,
            artist: artists.prefix(12).map { text($0["name"]) }.filter { !$0.isEmpty }.joined(separator: " / "),
            album: text(album["name"]), poster: artwork(album["picUrl"]),
            durationMilliseconds: max(0, min(object["duration"] as? Int ?? object["dt"] as? Int ?? 0, 86_400_000)))
    }
    static func entry(_ object: [String: Any], kind: MusicCatalogKind) -> MusicCatalogEntry? {
        guard let id = identifier(object["id"]) else { return nil }
        let title = text(object["name"])
        guard !title.isEmpty else { return nil }
        let song = kind == .song ? track(object) : nil
        if kind == .song && song == nil { return nil }
        let creator = object["creator"] as? [String: Any] ?? [:]
        let artist = object["artist"] as? [String: Any] ?? [:]
        let subtitle: String
        switch kind {
        case .song: subtitle = [song?.artist ?? "", song?.album ?? ""].filter { !$0.isEmpty }.joined(separator: " · ")
        case .playlist: subtitle = text(creator["nickname"])
        case .artist: subtitle = localized("歌手")
        case .album: subtitle = text(artist["name"])
        }
        return MusicCatalogEntry(identifier: id, kind: kind, title: title, subtitle: subtitle,
            poster: song?.poster ?? artwork(object["coverImgUrl"] ?? object["picUrl"] ?? object["img1v1Url"]), track: song)
    }
    static func entries(_ values: [[String: Any]], kind: MusicCatalogKind) -> [MusicCatalogEntry] {
        var seen = Set<String>()
        return values.prefix(resultLimit).compactMap { object in
            guard let value = entry(object, kind: kind), seen.insert(value.id).inserted else { return nil }
            return value
        }
    }
    static func collection(_ data: Data, key: String) throws -> [MusicCatalogEntry] {
        let object = try root(data)
        guard let values = object[key] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
        let result = entries(values, kind: .playlist)
        guard values.isEmpty || !result.isEmpty else { throw MusicCatalogError.invalidResponse }
        return result
    }
    static func search(_ data: Data, kind: MusicCatalogKind) throws -> [MusicCatalogEntry] {
        let object = try root(data)
        guard let result = object["result"] as? [String: Any] else { throw MusicCatalogError.invalidResponse }
        if let values = result[kind.resultKey] as? [[String: Any]] {
            let parsed = entries(values, kind: kind)
            guard values.isEmpty || !parsed.isEmpty else { throw MusicCatalogError.invalidResponse }
            return parsed
        }
        let countKey = kind == .song ? "songCount" : kind == .artist ? "artistCount" : kind == .album ? "albumCount" : "playlistCount"
        guard result[countKey] as? Int == 0 else { throw MusicCatalogError.invalidResponse }
        return []
    }
    static func tracks(_ data: Data, kind: MusicCatalogKind) throws -> [MusicCatalogEntry] {
        let object = try root(data)
        let values: [[String: Any]]?
        switch kind {
        case .playlist: values = (object["result"] as? [String: Any])?["tracks"] as? [[String: Any]]
        case .artist: values = object["hotSongs"] as? [[String: Any]]
        case .album: values = (object["album"] as? [String: Any])?["songs"] as? [[String: Any]] ?? object["songs"] as? [[String: Any]]
        case .song: throw MusicCatalogError.invalidResponse
        }
        guard let values else { throw MusicCatalogError.invalidResponse }
        let result = entries(values, kind: .song)
        guard values.isEmpty || !result.isEmpty else { throw MusicCatalogError.invalidResponse }
        return result
    }
}

/// Metadata identity, not the current discovery selection, determines the resolver platform.
enum MusicCatalogResolverMapping {
    static func song(_ track: MusicCatalogTrack, source: MusicJSSource?, providerID: String) throws -> MusicJSSong {
        let platform = track.platform.rawValue
        guard track.platform.hasResolverMapping, let source, providerID == platform,
              source.providers.contains(where: { $0.id == platform && $0.actions.contains("musicUrl") }) else {
            throw MusicCatalogError.unsupportedResolver
        }
        var info: [String: Any] = ["name": track.title, "singer": track.artist, "source": platform,
            "albumName": track.album, "img": track.poster, "interval": String(track.durationMilliseconds / 1000)]
        switch track.platform {
        case .wy:
            guard let id = MusicCatalogParser.identifier(track.identifier), let number = UInt64(id) else {
                throw MusicCatalogError.invalidResponse
            }
            info["songmid"] = id
            info["meta"] = ["songId": number, "albumName": track.album, "picUrl": track.poster]
        case .tx:
            guard let mid = MusicQQCatalogParser.mid(track.identifier) else { throw MusicCatalogError.invalidResponse }
            info["songmid"] = track.numericSongID.flatMap(MusicCatalogParser.identifier) ?? mid
            info["mid"] = mid
            info["strMediaMid"] = track.mediaMid.flatMap(MusicQQCatalogParser.mid) ?? mid
            info["meta"] = ["songId": mid, "albumName": track.album, "picUrl": track.poster]
        case .kg:
            guard let hash = MusicKugouCatalog.hash(track.identifier) else { throw MusicCatalogError.invalidResponse }
            info["hash"] = hash; info["songmid"] = hash
        case .kw:
            guard let rid = MusicCatalogParser.identifier(track.identifier) else { throw MusicCatalogError.invalidResponse }
            info["rid"] = rid; info["songmid"] = rid
        case .mg:
            guard let ids = MusicMiguCatalog.ids(track.identifier) else { throw MusicCatalogError.invalidResponse }
            info["songmid"] = ids.copyright; info["copyrightId"] = ids.copyright; info["contentId"] = ids.content
        case .sd, .apple:
            throw MusicCatalogError.unsupportedResolver
        }
        let data = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
        return MusicJSSong(sourceID: source.id, provider: platform, title: track.title, artist: track.artist,
            album: track.album, poster: track.poster, musicInfoJSON: String(decoding: data, as: UTF8.self))
    }
}

actor MusicPublicCatalog {
    static let shared = MusicPublicCatalog()
    static let providerName = "網易雲音樂 · 公開元資料"
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration, delegate: MusicCatalogRedirectGate(), delegateQueue: nil)
    }
    func charts() async throws -> [MusicCatalogEntry] {
        try MusicCatalogParser.collection(await request(path: "/api/toplist"), key: "list")
    }
    func playlists() async throws -> [MusicCatalogEntry] {
        try MusicCatalogParser.collection(await request(path: "/api/playlist/list", query: [
            .init(name: "cat", value: "全部"), .init(name: "order", value: "hot"),
            .init(name: "limit", value: "12"), .init(name: "offset", value: "0")]), key: "playlists")
    }
    func search(_ query: String, kind: MusicCatalogKind) async throws -> [MusicCatalogEntry] {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, keyword.count <= 300 else { throw MusicCatalogError.invalidQuery }
        return try MusicCatalogParser.search(await request(path: "/api/search/get", query: [
            .init(name: "s", value: keyword), .init(name: "type", value: kind.searchType),
            .init(name: "limit", value: "30"), .init(name: "offset", value: "0")]), kind: kind)
    }
    func tracks(in entry: MusicCatalogEntry) async throws -> [MusicCatalogEntry] {
        guard entry.platform == .wy, MusicCatalogParser.identifier(entry.identifier) != nil else { throw MusicCatalogError.invalidResponse }
        let path: String
        var query: [URLQueryItem] = []
        switch entry.kind {
        case .playlist: path = "/api/playlist/detail"; query = [.init(name: "id", value: entry.identifier), .init(name: "n", value: "100")]
        case .artist: path = "/api/artist/" + entry.identifier
        case .album: path = "/api/album/" + entry.identifier
        case .song: throw MusicCatalogError.invalidResponse
        }
        return try MusicCatalogParser.tracks(await request(path: path, query: query), kind: entry.kind)
    }
    private func request(path: String, query: [URLQueryItem] = []) async throws -> Data {
        try Task.checkCancellation()
        var components = URLComponents()
        components.scheme = "https"; components.host = "music.163.com"; components.path = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw MusicCatalogError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Readcc/1.0 (Public Music Metadata)", forHTTPHeaderField: "User-Agent")
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse else { throw MusicCatalogError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw MusicCatalogError.http(http.statusCode) }
        guard response.expectedContentLength <= Int64(MusicCatalogParser.bodyLimit) else { throw MusicCatalogError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < MusicCatalogParser.bodyLimit else { throw MusicCatalogError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        return data
    }
}

/// Metadata may only remain on this exact HTTPS origin; no downgrade, private host or login hop.
private final class MusicCatalogRedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.host == "music.163.com",
              url.port == nil, url.user == nil, url.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
}
