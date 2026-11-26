// SPDX-License-Identifier: GPL-3.0-only
// Kuwo/Migu field mappings adapted from Yingxia / TVBox-Silicon, Copyright (C) 2026
// jo32 and Yingxia contributors, a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c.
// See MusicAdditionalCatalogs.NOTICE.md and MusicQQCatalog.COPYING.
// Other mappings independently implemented from anonymous provider responses / public APIs.
import CoreFoundation
import Foundation

/// Anonymous metadata only. No audio, entitlement, signature, device ID, cookie or account APIs.
/// A separate session per request pins redirects to the original exact host and path family.
enum MusicAnonymousCatalogHTTP {
    static let hosts: Set<String> = ["songsearch.kugou.com", "search.kuwo.cn", "jadeite.migu.cn", "api.qishui.com", "itunes.apple.com"]
    static func allows(_ url: URL?, host: String) -> Bool {
        guard let url, hosts.contains(host), url.scheme?.lowercased() == "https",
              url.host?.lowercased() == host, url.user == nil, url.password == nil,
              url.port == nil || url.port == 443, url.fragment == nil else { return false }
        switch host {
        case "songsearch.kugou.com": return url.path == "/song_search_v2"
        case "search.kuwo.cn": return url.path == "/r.s"
        case "jadeite.migu.cn": return url.path == "/music_search/v3/search/searchAll"
        case "api.qishui.com": return url.path == "/luna/h5/track_v2"
        case "itunes.apple.com": return ["/search", "/lookup"].contains(url.path)
        default: return false
        }
    }
    static func request(host: String, path: String, query: [(String, String)]) throws -> URLRequest {
        var parts = URLComponents(); parts.scheme = "https"; parts.host = host; parts.path = path
        parts.queryItems = query.map { URLQueryItem(name: $0.0, value: $0.1) }
        guard let url = parts.url, allows(url, host: host) else { throw MusicCatalogError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Readcc/1.0 (Public Music Metadata)", forHTTPHeaderField: "User-Agent")
        return request
    }
    static func send(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
        guard let host = request.url?.host?.lowercased(), allows(request.url, host: host) else { throw MusicCatalogError.invalidResponse }
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.httpCookieStorage = nil
        config.urlCredentialStorage = nil; config.urlCache = nil
        config.timeoutIntervalForRequest = 15; config.timeoutIntervalForResource = 25
        let session = URLSession(configuration: config, delegate: MusicAnonymousCatalogRedirectGate(host: host), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, allows(response.url, host: host) else { throw MusicCatalogError.invalidResponse }
        guard (200...299).contains(response.statusCode) else { throw MusicCatalogError.http(response.statusCode) }
        guard response.expectedContentLength <= Int64(MusicCatalogParser.bodyLimit) else { throw MusicCatalogError.invalidResponse }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < MusicCatalogParser.bodyLimit else { throw MusicCatalogError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard !data.isEmpty else { throw MusicCatalogError.invalidResponse }
        return data
    }
}
private final class MusicAnonymousCatalogRedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(MusicAnonymousCatalogHTTP.allows(request.url, host: host) ? request : nil)
    }
}

enum MusicAdditionalCatalogParser {
    static func object(_ data: Data) throws -> [String: Any] {
        guard !data.isEmpty, data.count <= MusicCatalogParser.bodyLimit,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MusicCatalogError.invalidResponse }
        return object
    }
    static func keyword(_ query: String) throws -> String {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value.count <= 300 else { throw MusicCatalogError.invalidQuery }
        return value
    }
    static func integer(_ value: Any?) -> Int? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return Int(value.stringValue) }
        return (value as? String).flatMap(Int.init)
    }
    static func seconds(_ value: Any?) -> Int { max(0, min(integer(value) ?? 0, 86_400)) * 1000 }
    static func milliseconds(_ value: Any?) -> Int { max(0, min(integer(value) ?? 0, 86_400_000)) }
    static func artwork(_ value: Any?, suffixes: [String]) -> String {
        guard let value = value as? String, value.utf8.count <= 2048,
              var url = URLComponents(string: value), let host = url.host?.lowercased(),
              suffixes.contains(where: { host == $0 || host.hasSuffix("." + $0) }),
              ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.port == nil,
              url.user == nil, url.password == nil, url.fragment == nil else { return "" }
        url.scheme = "https"; return url.string ?? ""
    }
    static func entry(_ track: MusicCatalogTrack) -> MusicCatalogEntry {
        MusicCatalogEntry(identifier: track.identifier, kind: .song, title: track.title,
            subtitle: [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "),
            poster: track.poster, track: track, platform: track.platform)
    }
    static func checked(_ objects: [[String: Any]], track: ([String: Any]) -> MusicCatalogTrack?) throws -> [MusicCatalogEntry] {
        var seen = Set<String>()
        let parsed = objects.prefix(MusicCatalogParser.resultLimit).compactMap(track).map(entry).filter { seen.insert($0.id).inserted }
        guard objects.isEmpty || !parsed.isEmpty else { throw MusicCatalogError.invalidResponse }
        return parsed
    }
}

/// Public song search; hash identity is not an audio locator or an entitlement.
enum MusicKugouCatalog {
    static func makeRequest(_ query: String) throws -> URLRequest {
        try MusicAnonymousCatalogHTTP.request(host: "songsearch.kugou.com", path: "/song_search_v2", query: [
            ("keyword", try MusicAdditionalCatalogParser.keyword(query)), ("page", "1"), ("pagesize", "30"), ("platform", "WebFilter")])
    }
    static func hash(_ value: Any?) -> String? {
        guard let value = value as? String, value.utf8.count == 32,
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) || (97...102).contains($0) }) else { return nil }
        return value.uppercased()
    }
    static func parse(_ data: Data) throws -> [MusicCatalogEntry] {
        let root = try MusicAdditionalCatalogParser.object(data)
        guard let status = MusicAdditionalCatalogParser.integer(root["status"]),
              let error = MusicAdditionalCatalogParser.integer(root["error_code"]) else { throw MusicCatalogError.invalidResponse }
        guard status == 1, error == 0 else { throw MusicCatalogError.rejected(error == 0 ? status : error) }
        guard let values = (root["data"] as? [String: Any])?["lists"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
        return try MusicAdditionalCatalogParser.checked(values) { object in
            guard let id = hash(object["FileHash"]) else { return nil }
            let title = MusicCatalogParser.text(object["SongName"])
            guard !title.isEmpty else { return nil }
            return MusicCatalogTrack(identifier: id, title: title, artist: MusicCatalogParser.text(object["SingerName"]),
                album: MusicCatalogParser.text(object["AlbumName"]), poster: MusicAdditionalCatalogParser.artwork(object["Image"], suffixes: ["kugou.com"]),
                durationMilliseconds: MusicAdditionalCatalogParser.seconds(object["Duration"]), platform: .kg)
        }
    }
    static func search(_ query: String) async throws -> [MusicCatalogEntry] { try parse(await MusicAnonymousCatalogHTTP.send(makeRequest(query))) }
}

enum MusicKuwoCatalog {
    static func makeRequest(_ query: String) throws -> URLRequest {
        try MusicAnonymousCatalogHTTP.request(host: "search.kuwo.cn", path: "/r.s", query: [
            ("client", "kt"), ("all", try MusicAdditionalCatalogParser.keyword(query)), ("pn", "0"), ("rn", "30"),
            ("ft", "music"), ("encoding", "utf8"), ("rformat", "json")])
    }
    /// This public endpoint returns single-quoted JSON-like strings even with rformat=json.
    /// Translate string delimiters only, then use the strict Foundation JSON parser. Never eval.
    /// Not a general JavaScript parser: comments, expressions, bare keys and functions are rejected.
    static func normalizedJSON(_ data: Data) throws -> Data {
        guard data.count <= MusicCatalogParser.bodyLimit, let source = String(data: data, encoding: .utf8) else { throw MusicCatalogError.invalidResponse }
        var output = ""; output.reserveCapacity(source.utf8.count)
        var quote: Character?; var escaped = false
        for char in source {
            if let active = quote {
                if escaped {
                    if active == "'", char == "'" { output.append("'") }
                    else if active == "'", char == "\"" { output.append("\\\"") }
                    else {
                        guard "\"\\/bfnrtu".contains(char) else { throw MusicCatalogError.invalidResponse }
                        output.append("\\"); output.append(char)
                    }
                    escaped = false
                } else if char == "\\" { escaped = true }
                else if char == active { output.append("\""); quote = nil }
                else if char == "\"", active == "'" { output.append("\\\"") }
                else { output.append(char) }
            } else if char == "'" || char == "\"" { quote = char; output.append("\"") }
            else { output.append(char) }
        }
        guard quote == nil, !escaped else { throw MusicCatalogError.invalidResponse }
        return Data(output.utf8)
    }
    static func parse(_ data: Data) throws -> [MusicCatalogEntry] {
        let root = try MusicAdditionalCatalogParser.object(normalizedJSON(data))
        for key in ["code", "error_code"] {
            if let raw = root[key] {
                guard let code = MusicAdditionalCatalogParser.integer(raw) else { throw MusicCatalogError.invalidResponse }
                guard code == 0 || (key == "code" && code == 200) else { throw MusicCatalogError.rejected(code) }
            }
        }
        guard let values = root["abslist"] as? [[String: Any]],
              let total = MusicAdditionalCatalogParser.integer(root["TOTAL"]), total >= 0,
              !values.isEmpty || total == 0 else { throw MusicCatalogError.invalidResponse }
        return try MusicAdditionalCatalogParser.checked(values) { object in
            guard let raw = object["MUSICRID"] as? String, raw.hasPrefix("MUSIC_"),
                  let id = MusicCatalogParser.identifier(String(raw.dropFirst(6))) else { return nil }
            let title = MusicCatalogParser.text(object["SONGNAME"] ?? object["NAME"])
            guard !title.isEmpty else { return nil }
            var poster = ""
            if let short = object["web_albumpic_short"] as? String, short.utf8.count < 1500,
               let slash = short.firstIndex(of: "/"), !short.contains(".."), !short.contains("?") {
                poster = MusicAdditionalCatalogParser.artwork("https://img4.kuwo.cn/star/albumcover/500" + short[slash...], suffixes: ["kuwo.cn"])
            }
            return MusicCatalogTrack(identifier: id, title: title, artist: MusicCatalogParser.text(object["ARTIST"]),
                album: MusicCatalogParser.text(object["ALBUM"]), poster: poster,
                durationMilliseconds: MusicAdditionalCatalogParser.seconds(object["DURATION"]), platform: .kw)
        }
    }
    static func search(_ query: String) async throws -> [MusicCatalogEntry] { try parse(await MusicAnonymousCatalogHTTP.send(makeRequest(query))) }
}

enum MusicMiguCatalog {
    /// Deliberately anonymous: no copied signing constants, synthetic device identity or private key.
    /// The public service may deny unsigned requests; a denial remains a visible failure.
    static func makeRequest(_ query: String) throws -> URLRequest {
        try MusicAnonymousCatalogHTTP.request(host: "jadeite.migu.cn", path: "/music_search/v3/search/searchAll", query: [
            ("text", try MusicAdditionalCatalogParser.keyword(query)), ("pageNo", "1"), ("pageSize", "30"),
            ("isCorrect", "0"), ("isCopyright", "1"), ("sort", "0"), ("sid", "USS"),
            ("searchSwitch", "{\"song\":1,\"album\":0,\"singer\":0,\"tagSong\":1,\"mvSong\":0,\"bestShow\":1,\"songlist\":0,\"lyricSong\":0}")])
    }
    static func ids(_ value: String) -> (content: String, copyright: String)? {
        let parts = value.split(separator: "_", omittingEmptySubsequences: false)
        guard parts.count == 2, let content = MusicCatalogParser.identifier(String(parts[0])),
              let copyright = MusicQQCatalogParser.mid(String(parts[1])) else { return nil }
        return (content, copyright)
    }
    static func parse(_ data: Data) throws -> [MusicCatalogEntry] {
        let root = try MusicAdditionalCatalogParser.object(data)
        guard let code = root["code"] as? String else { throw MusicCatalogError.invalidResponse }
        guard code == "000000" else { throw MusicCatalogError.rejected(Int(code) ?? -1) }
        guard let groups = (root["songResultData"] as? [String: Any])?["resultList"] as? [[[String: Any]]] else { throw MusicCatalogError.invalidResponse }
        let values = Array(groups.prefix(100).flatMap { $0.prefix(100) }.prefix(100))
        return try MusicAdditionalCatalogParser.checked(values) { object in
            guard let content = MusicCatalogParser.identifier(object["contentId"]),
                  let copyright = MusicQQCatalogParser.mid(object["copyrightId"]) else { return nil }
            let title = MusicCatalogParser.text(object["name"] ?? object["songName"])
            guard !title.isEmpty else { return nil }
            let singers = object["singerList"] as? [[String: Any]] ?? []
            let image = object["img3"] ?? object["img2"] ?? object["img1"]
            let raw = image as? String ?? ""
            let picture = raw.hasPrefix("/") && !raw.hasPrefix("//") ? "https://d.musicapp.migu.cn" + raw : raw
            return MusicCatalogTrack(identifier: content + "_" + copyright, title: title,
                artist: singers.prefix(12).map { MusicCatalogParser.text($0["name"]) }.joined(separator: " / "),
                album: MusicCatalogParser.text(object["album"]), poster: MusicAdditionalCatalogParser.artwork(picture, suffixes: ["migu.cn"]),
                durationMilliseconds: MusicAdditionalCatalogParser.seconds(object["duration"]), platform: .mg)
        }
    }
    static func search(_ query: String) async throws -> [MusicCatalogEntry] { try parse(await MusicAnonymousCatalogHTTP.send(makeRequest(query))) }
}

/// Independently implemented from the public H5 track_v2 JSON observed 2026-11-26.
/// Static binary key strings are NOT treated as a confirmed keyword-search schema.
/// Only a user-supplied numeric song ID is supported. We never read track_player / audio fields.
enum MusicSodaCatalog {
    static func makeRequest(_ songID: String) throws -> URLRequest {
        let value = try MusicAdditionalCatalogParser.keyword(songID)
        guard let id = MusicCatalogParser.identifier(value) else { throw MusicCatalogError.invalidSongLookup }
        return try MusicAnonymousCatalogHTTP.request(host: "api.qishui.com", path: "/luna/h5/track_v2", query: [
            ("track_id", id), ("media_type", "track"), ("device_platform", "web")])
    }
    static func parse(_ data: Data, expectedID: String) throws -> [MusicCatalogEntry] {
        guard MusicCatalogParser.identifier(expectedID) != nil else { throw MusicCatalogError.invalidSongLookup }
        let root = try MusicAdditionalCatalogParser.object(data)
        guard let status = root["status_info"] as? [String: Any] else { throw MusicCatalogError.invalidResponse }
        // The observed anonymous H5 success omits status_code; do not invent one.
        // Require its timestamp envelope and explicit risk_result after rejecting any supplied errors.
        for object in [root, status] {
            for key in ["status_code", "code", "error_code"] {
                if let raw = object[key] {
                    guard let code = MusicAdditionalCatalogParser.integer(raw) else { throw MusicCatalogError.invalidResponse }
                    guard code == 0 else { throw MusicCatalogError.rejected(code) }
                }
            }
        }
        guard let now = MusicAdditionalCatalogParser.integer(status["now"]), now > 0,
              let risk = MusicAdditionalCatalogParser.integer(root["risk_result"]) else { throw MusicCatalogError.invalidResponse }
        guard risk == 0 else { throw MusicCatalogError.rejected(-1) }
        guard let object = root["track"] as? [String: Any], let id = MusicCatalogParser.identifier(object["id"]), id == expectedID,
              let duration = MusicAdditionalCatalogParser.integer(object["duration"]), duration >= 0,
              let artists = object["artists"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
        let title = MusicCatalogParser.text(object["name"])
        guard !title.isEmpty else { throw MusicCatalogError.invalidResponse }
        let album = object["album"] as? [String: Any] ?? [:]
        // The observed cover is a URI/template descriptor, not a complete URL. Do not guess it.
        let track = MusicCatalogTrack(identifier: id, title: title,
            artist: artists.prefix(12).map { MusicCatalogParser.text($0["name"]) }.joined(separator: " / "),
            album: MusicCatalogParser.text(album["name"]), poster: "",
            durationMilliseconds: MusicAdditionalCatalogParser.milliseconds(duration), platform: .sd)
        return [MusicAdditionalCatalogParser.entry(track)]
    }
    static func lookup(_ songID: String) async throws -> [MusicCatalogEntry] {
        let id = try MusicAdditionalCatalogParser.keyword(songID)
        return try parse(await MusicAnonymousCatalogHTTP.send(makeRequest(id)), expectedID: id)
    }
}

/// Apple iTunes Search API: public store metadata, NOT MusicKit or Apple Music playback rights.
/// The fixed US storefront is explicit in UI; no authorization or preview/audio URL is collected.
enum MusicAppleCatalog {
    static let country = "US"
    static func entity(_ kind: MusicCatalogKind) throws -> String {
        switch kind {
        case .song: return "song"
        case .album: return "album"
        case .artist: return "musicArtist"
        case .playlist: throw MusicCatalogError.unsupportedCapability
        }
    }
    static func makeRequest(_ query: String, kind: MusicCatalogKind) throws -> URLRequest {
        try MusicAnonymousCatalogHTTP.request(host: "itunes.apple.com", path: "/search", query: [
            ("term", try MusicAdditionalCatalogParser.keyword(query)), ("media", "music"), ("entity", try entity(kind)),
            ("country", country), ("limit", "30"), ("explicit", "Yes")])
    }
    static func makeDetailRequest(_ entry: MusicCatalogEntry) throws -> URLRequest {
        guard entry.platform == .apple, [.album, .artist].contains(entry.kind),
              let id = MusicCatalogParser.identifier(entry.identifier) else { throw MusicCatalogError.unsupportedCapability }
        return try MusicAnonymousCatalogHTTP.request(host: "itunes.apple.com", path: "/lookup", query: [
            ("id", id), ("entity", "song"), ("country", country), ("limit", "100")])
    }
    static func track(_ object: [String: Any]) -> MusicCatalogTrack? {
        guard object["wrapperType"] as? String == "track", object["kind"] as? String == "song",
              let id = MusicCatalogParser.identifier(object["trackId"]) else { return nil }
        let title = MusicCatalogParser.text(object["trackName"])
        guard !title.isEmpty else { return nil }
        return MusicCatalogTrack(identifier: id, title: title, artist: MusicCatalogParser.text(object["artistName"]),
            album: MusicCatalogParser.text(object["collectionName"]),
            poster: MusicAdditionalCatalogParser.artwork(object["artworkUrl100"], suffixes: ["mzstatic.com"]),
            durationMilliseconds: MusicAdditionalCatalogParser.milliseconds(object["trackTimeMillis"]), platform: .apple)
    }
    static func parse(_ data: Data, kind: MusicCatalogKind) throws -> [MusicCatalogEntry] {
        _ = try entity(kind)
        let root = try MusicAdditionalCatalogParser.object(data)
        guard let count = MusicAdditionalCatalogParser.integer(root["resultCount"]), count >= 0,
              let values = root["results"] as? [[String: Any]], count == values.count else { throw MusicCatalogError.invalidResponse }
        if root["errorMessage"] != nil || root["errorCode"] != nil { throw MusicCatalogError.rejected(-1) }
        if kind == .song { return try MusicAdditionalCatalogParser.checked(values, track: track) }
        var seen = Set<String>()
        let parsed = values.prefix(100).compactMap { object -> MusicCatalogEntry? in
            let key = kind == .artist ? "artistId" : "collectionId"
            guard object["wrapperType"] as? String == (kind == .artist ? "artist" : "collection"),
                  let id = MusicCatalogParser.identifier(object[key]) else { return nil }
            let title = MusicCatalogParser.text(object[kind == .artist ? "artistName" : "collectionName"])
            guard !title.isEmpty else { return nil }
            return MusicCatalogEntry(identifier: id, kind: kind, title: title, subtitle: MusicCatalogParser.text(object["artistName"]),
                poster: MusicAdditionalCatalogParser.artwork(object["artworkUrl100"], suffixes: ["mzstatic.com"]), track: nil, platform: .apple)
        }.filter { seen.insert($0.id).inserted }
        guard values.isEmpty || !parsed.isEmpty else { throw MusicCatalogError.invalidResponse }
        return parsed
    }
    static func parseDetail(_ data: Data, entry: MusicCatalogEntry) throws -> [MusicCatalogEntry] {
        _ = try makeDetailRequest(entry)
        let root = try MusicAdditionalCatalogParser.object(data)
        if root["errorMessage"] != nil || root["errorCode"] != nil { throw MusicCatalogError.rejected(-1) }
        guard let count = MusicAdditionalCatalogParser.integer(root["resultCount"]), count > 0,
              let values = root["results"] as? [[String: Any]], count == values.count,
              let header = values.first, MusicCatalogParser.identifier(header[entry.kind == .album ? "collectionId" : "artistId"]) == entry.identifier,
              header["wrapperType"] as? String == (entry.kind == .album ? "collection" : "artist") else { throw MusicCatalogError.invalidResponse }
        let songs = Array(values.dropFirst())
        guard songs.allSatisfy({ MusicCatalogParser.identifier($0[entry.kind == .album ? "collectionId" : "artistId"]) == entry.identifier }) else { throw MusicCatalogError.invalidResponse }
        return try MusicAdditionalCatalogParser.checked(songs, track: track)
    }
    static func search(_ query: String, kind: MusicCatalogKind) async throws -> [MusicCatalogEntry] {
        try parse(await MusicAnonymousCatalogHTTP.send(makeRequest(query, kind: kind)), kind: kind)
    }
    static func tracks(in entry: MusicCatalogEntry) async throws -> [MusicCatalogEntry] {
        try parseDetail(await MusicAnonymousCatalogHTTP.send(makeDetailRequest(entry)), entry: entry)
    }
}
