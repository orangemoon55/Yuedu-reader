// SPDX-License-Identifier: GPL-3.0-only
// Adapted protocol/field mappings from Yingxia, Copyright (C) 2026 jo32 and Yingxia contributors.
// Source: tvbox-silicon-study/source @ a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c
// MusicCatalog.swift, MusicBrowse.swift, MusicCollectionCatalogs.swift, MusicLXSources.swift.
// See MusicQQCatalog.NOTICE.md and MusicQQCatalog.COPYING for attribution/license.
import Foundation

enum MusicPlatformCatalog {
    static func charts(platform: MusicCatalogPlatform) async throws -> [MusicCatalogEntry] {
        switch platform {
        case .wy: return try await MusicPublicCatalog.shared.charts()
        case .tx: return try await MusicQQCatalog.shared.charts()
        }
    }
    static func playlists(platform: MusicCatalogPlatform) async throws -> [MusicCatalogEntry] {
        switch platform {
        case .wy: return try await MusicPublicCatalog.shared.playlists()
        case .tx: return try await MusicQQCatalog.shared.playlists()
        }
    }
    static func search(_ query: String, kind: MusicCatalogKind, platform: MusicCatalogPlatform) async throws -> [MusicCatalogEntry] {
        guard platform.searchKinds.contains(kind) else { throw MusicCatalogError.unsupportedCapability }
        switch platform {
        case .wy: return try await MusicPublicCatalog.shared.search(query, kind: kind)
        case .tx: return try await MusicQQCatalog.shared.search(query, kind: kind)
        }
    }
    static func tracks(in entry: MusicCatalogEntry) async throws -> [MusicCatalogEntry] {
        switch entry.platform {
        case .wy: return try await MusicPublicCatalog.shared.tracks(in: entry)
        case .tx: return try await MusicQQCatalog.shared.tracks(in: entry)
        }
    }
}

/// Reject malformed/restricted responses, rather than converting missing schema into empty success.
enum MusicQQCatalogParser {
    static func mid(_ value: Any?) -> String? {
        guard let value = value as? String, (1...64).contains(value.utf8.count),
              value.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }) else { return nil }
        return value
    }
    static func data(_ bytes: Data) throws -> [String: Any] {
        guard !bytes.isEmpty, bytes.count <= MusicCatalogParser.bodyLimit,
              let root = try JSONSerialization.jsonObject(with: bytes) as? [String: Any],
              let code = root["code"] as? Int else { throw MusicCatalogError.invalidResponse }
        guard code == 0 else { throw MusicCatalogError.rejected(code) }
        guard let req = root["req"] as? [String: Any], let reqCode = req["code"] as? Int else { throw MusicCatalogError.invalidResponse }
        guard reqCode == 0 else { throw MusicCatalogError.rejected(reqCode) }
        guard let result = req["data"] as? [String: Any] else { throw MusicCatalogError.invalidResponse }
        return result
    }
    static func artwork(_ value: Any?) -> String {
        guard let value = value as? String, value.utf8.count <= 2048,
              var url = URLComponents(string: value), url.user == nil, url.password == nil,
              url.port == nil, ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), ["y.gtimg.cn", "qpic.y.qq.com"].contains(host),
              url.query == nil, url.fragment == nil else { return "" }
        url.scheme = "https"
        return url.string ?? ""
    }
    static func albumArtwork(_ value: Any?) -> String {
        guard let value = mid(value) else { return "" }
        return "https://y.gtimg.cn/music/photo_new/T002R300x300M000\(value).jpg"
    }
    static func track(_ object: [String: Any]) -> MusicCatalogTrack? {
        guard let id = mid(object["mid"]), !MusicCatalogParser.text(object["title"] ?? object["name"]).isEmpty else { return nil }
        let album = object["album"] as? [String: Any] ?? [:]
        let singers = object["singer"] as? [[String: Any]] ?? []
        let file = object["file"] as? [String: Any] ?? [:]
        let seconds = max(0, min(object["interval"] as? Int ?? 0, 86_400))
        return MusicCatalogTrack(identifier: id, title: MusicCatalogParser.text(object["title"] ?? object["name"]),
            artist: singers.prefix(12).map { MusicCatalogParser.text($0["name"]) }.filter { !$0.isEmpty }.joined(separator: " / "),
            album: MusicCatalogParser.text(album["name"]), poster: albumArtwork(album["mid"]),
            durationMilliseconds: seconds * 1000, platform: .tx,
            numericSongID: MusicCatalogParser.identifier(object["id"]), mediaMid: mid(file["media_mid"]))
    }
    static func songs(_ objects: [[String: Any]]) throws -> [MusicCatalogEntry] {
        let values = objects.prefix(MusicCatalogParser.resultLimit).compactMap { object -> MusicCatalogEntry? in
            guard let track = track(object) else { return nil }
            return MusicCatalogEntry(identifier: track.identifier, kind: .song, title: track.title,
                subtitle: [track.artist, track.album].filter { !$0.isEmpty }.joined(separator: " · "),
                poster: track.poster, track: track, platform: .tx)
        }
        return try checked(values, originalCount: objects.count)
    }
    static func checked(_ values: [MusicCatalogEntry], originalCount: Int) throws -> [MusicCatalogEntry] {
        guard originalCount == 0 || !values.isEmpty else { throw MusicCatalogError.invalidResponse }
        var seen = Set<String>()
        return values.filter { seen.insert($0.id).inserted }
    }
    static func collection(_ object: [String: Any], kind: MusicCatalogKind, browse: Bool = false) -> MusicCatalogEntry? {
        let identifier: String?, title: String, poster: String, subtitle: String
        if kind == .album {
            identifier = mid(object["albummid"] ?? object["albumMID"])
            title = MusicCatalogParser.text(object["name"] ?? object["albumName"])
            poster = albumArtwork(identifier)
            let singers = object["singer_list"] as? [[String: Any]] ?? []
            subtitle = singers.isEmpty ? MusicCatalogParser.text(object["singer"]) : singers.prefix(12).map { MusicCatalogParser.text($0["name"]) }.joined(separator: " / ")
        } else if kind == .playlist {
            identifier = MusicCatalogParser.identifier(object[browse ? "tid" : "dissid"])
            title = MusicCatalogParser.text(object[browse ? "title" : "dissname"])
            poster = artwork(object[browse ? "cover_url_medium" : "logo"] ?? object[browse ? "cover_url_big" : "imgurl"])
            subtitle = browse ? MusicCatalogParser.text((object["creator_info"] as? [String: Any])?["nick"]) : MusicCatalogParser.text(object["nickname"])
        } else { return nil }
        guard let identifier, !title.isEmpty else { return nil }
        return MusicCatalogEntry(identifier: identifier, kind: kind, title: title, subtitle: subtitle, poster: poster, track: nil, platform: .tx)
    }
    static func search(_ bytes: Data, kind: MusicCatalogKind) throws -> [MusicCatalogEntry] {
        guard kind != .artist else { throw MusicCatalogError.unsupportedCapability }
        let result = try data(bytes)
        guard let body = result["body"] as? [String: Any] else { throw MusicCatalogError.invalidResponse }
        if kind == .song {
            guard let songs = body["item_song"] as? [[String: Any]] ?? (body["song"] as? [String: Any])?["list"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
            return try self.songs(songs)
        }
        guard let items = body[kind == .album ? "item_album" : "item_songlist"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
        return try checked(items.prefix(100).compactMap { collection($0, kind: kind) }, originalCount: items.count)
    }
    static func charts(_ bytes: Data) throws -> [MusicCatalogEntry] {
        let result = try data(bytes)
        guard let groups = result["group"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
        var objects: [[String: Any]] = []
        for group in groups.prefix(100) {
            guard let charts = group["toplist"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
            objects += charts.prefix(max(0, 100 - objects.count))
        }
        let entries = objects.compactMap { object -> MusicCatalogEntry? in
            guard let id = MusicCatalogParser.identifier(object["topId"]) else { return nil }
            let title = MusicCatalogParser.text(object["title"])
            guard !title.isEmpty else { return nil }
            return MusicCatalogEntry(identifier: "toplist:" + id, kind: .playlist, title: title, subtitle: "",
                poster: artwork(object["mbFrontPicUrl"] ?? object["frontPicUrl"] ?? object["headPicUrl"]), track: nil, platform: .tx)
        }
        return try checked(entries, originalCount: objects.count)
    }
    static func playlists(_ bytes: Data) throws -> [MusicCatalogEntry] {
        guard let items = try data(bytes)["v_playlist"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
        return try checked(items.prefix(100).compactMap { collection($0, kind: .playlist, browse: true) }, originalCount: items.count)
    }
    static func tracks(_ bytes: Data, entry: MusicCatalogEntry) throws -> [MusicCatalogEntry] {
        guard entry.platform == .tx else { throw MusicCatalogError.invalidResponse }
        let result = try data(bytes)
        if entry.identifier.hasPrefix("toplist:"), entry.kind == .playlist {
            guard let items = result["songInfoList"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
            return try songs(items)
        }
        switch entry.kind {
        case .playlist:
            guard let items = result["songlist"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
            return try songs(items)
        case .album:
            guard let items = result["songList"] as? [[String: Any]] else { throw MusicCatalogError.invalidResponse }
            let songs = items.prefix(100).compactMap { $0["songInfo"] as? [String: Any] }
            guard items.isEmpty || !songs.isEmpty else { throw MusicCatalogError.invalidResponse }
            return try self.songs(songs)
        default: throw MusicCatalogError.unsupportedCapability
        }
    }
}

actor MusicQQCatalog {
    static let shared = MusicQQCatalog()
    private let session: URLSession
    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 25
        session = URLSession(configuration: configuration, delegate: MusicQQCatalogRedirectGate(), delegateQueue: nil)
    }
    enum Operation: Sendable {
        case charts, playlists, search(String, MusicCatalogKind), tracks(MusicCatalogEntry)
    }
    func charts() async throws -> [MusicCatalogEntry] {
        try MusicQQCatalogParser.charts(await send(Self.makeRequest(.charts)))
    }
    func playlists() async throws -> [MusicCatalogEntry] {
        try MusicQQCatalogParser.playlists(await send(Self.makeRequest(.playlists)))
    }
    func search(_ query: String, kind: MusicCatalogKind) async throws -> [MusicCatalogEntry] {
        try MusicQQCatalogParser.search(await send(Self.makeRequest(.search(query, kind))), kind: kind)
    }
    func tracks(in entry: MusicCatalogEntry) async throws -> [MusicCatalogEntry] {
        try MusicQQCatalogParser.tracks(await send(Self.makeRequest(.tracks(entry))), entry: entry)
    }
    /// The exact builder used by live requests is also exercised by offline native tests.
    nonisolated static func makeRequest(_ operation: Operation) throws -> URLRequest {
        let module: String, method: String, param: [String: Any]
        switch operation {
        case .charts:
            module = "musicToplist.ToplistInfoServer"; method = "GetAll"; param = [:]
        case .playlists:
            module = "playlist.PlayListPlazaServer"; method = "get_playlist_by_tag"
            param = ["id": 10_000_000, "sin": 0, "size": 12, "order": 5, "cur_page": 1]
        case .search(let query, let kind):
            let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !keyword.isEmpty, keyword.count <= 300 else { throw MusicCatalogError.invalidQuery }
            let type: Int
            switch kind {
            case .song: type = 0
            case .album: type = 2
            case .playlist: type = 3
            case .artist: throw MusicCatalogError.unsupportedCapability
            }
            module = "music.search.SearchCgiService"; method = "DoSearchForQQMusicMobile"
            param = ["query": keyword, "num_per_page": 30, "page_num": 1, "search_type": type,
                     "searchid": String(UInt64.random(in: 1_000_000_000...9_999_999_999))]
        case .tracks(let entry):
            guard entry.platform == .tx else { throw MusicCatalogError.invalidResponse }
            switch entry.kind {
            case .playlist:
                if entry.identifier.hasPrefix("toplist:") {
                    guard let id = MusicCatalogParser.identifier(String(entry.identifier.dropFirst(8))), let number = UInt64(id) else { throw MusicCatalogError.invalidResponse }
                    module = "musicToplist.ToplistInfoServer"; method = "GetDetail"
                    param = ["topId": number, "offset": 0, "num": 100, "period": ""]
                } else {
                    guard let id = MusicCatalogParser.identifier(entry.identifier), let number = UInt64(id) else { throw MusicCatalogError.invalidResponse }
                    module = "music.srfDissInfo.aiDissInfo"; method = "uniform_get_Dissinfo"
                    param = ["disstid": number, "userinfo": 0, "tag": 1, "is_pc": 1, "orderlist": 1,
                             "song_begin": 0, "song_num": 100, "onlysonglist": 0]
                }
            case .album:
                guard let mid = MusicQQCatalogParser.mid(entry.identifier) else { throw MusicCatalogError.invalidResponse }
                module = "music.musichallAlbum.AlbumSongList"; method = "GetAlbumSongList"
                param = ["albumMid": mid, "begin": 0, "num": 100, "order": 2]
            default: throw MusicCatalogError.unsupportedCapability
            }
        }
        guard let url = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg"), allowedURL(url) else { throw MusicCatalogError.invalidResponse }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.httpMethod = "POST"
        let body: [String: Any] = ["comm": ["ct": 11, "cv": "1003006", "uin": "0"],
            "req": ["module": module, "method": method, "param": param]]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Readcc/1.0 (Public Music Metadata)", forHTTPHeaderField: "User-Agent")
        return request
    }
    private func send(_ request: URLRequest) async throws -> Data {
        try Task.checkCancellation()
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
    nonisolated static func allowedURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.host == "u.y.qq.com" && url.path == "/cgi-bin/musicu.fcg" &&
        url.port == nil && url.user == nil && url.password == nil && url.query == nil && url.fragment == nil
    }
}

private final class MusicQQCatalogRedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        guard let url = request.url, MusicQQCatalog.allowedURL(url) else { completionHandler(nil); return }
        completionHandler(request)
    }
}
