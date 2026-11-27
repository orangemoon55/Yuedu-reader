// Adapted from XIaodou0416/Beans-Music (MIT); see ThirdPartyNotices/Beans-Music.md.
import CoreFoundation
import Foundation

/// QQ 音乐搜索类型（musicu search_type：0 单曲 / 1 歌手 / 2 专辑 / 3 歌单 / 4 MV / 7 歌词 / 8 用户）
enum QQSearchType: Int {
    case song = 0
    case artist = 1
    case album = 2
}

/// QQ 音乐接口（搜索 / 播放地址 / 歌词 / 热搜）
/// 参考 wp_MusicApi（https://github.com/GitHub-ZC/wp_MusicApi）逆向结论：
/// - 歌曲搜索改用 client_search_cp（t=0），该接口对家庭/移动/数据中心网络均可用；
///   歌手/专辑搜索使用 musicu.fcg POST JSON（search_type 1/2），专辑空结果时自动用 client_search_cp t=8 兜底。
/// - vkey 播放地址经 musicu.fcg 获取，VIP 歌曲返回空；部分数据中心 IP 会被风控返回空，家庭网络正常。
final class QQMusicAPI {
    static let shared = QQMusicAPI()
    /// QQ「我的喜欢」不是“创建歌单”列表中的普通歌单，使用稳定占位 ID 进入专用加载流程。
    static let qqLikedPlaylistID = -201
    private static let qqLikedCoverURL = URL(string: "https://y.gtimg.cn/mediastyle/global/img/cover_like.png")

    private let base = "https://u.y.qq.com/cgi-bin/musicu.fcg"
    private let searchBase = "https://c.y.qq.com/soso/fcgi-bin/search_for_qq_cp"
    private let session: URLSession
    private let authentication: QQMusicAuth?
    private let collections: QQMusicCollectionTransport
    private let vkeyCache = QQMusicPlaybackCache<VkeyResource?>()
    private let detailCache = QQMusicPlaybackCache<QQSongPlaybackDetail?>()
    private let streamHost = QQStreamHostMemory()
    private let slowHosts = QQSlowHostMemory()
    private var currentAuth: QQMusicAuth { authentication ?? .shared }

    init(configuration: URLSessionConfiguration? = nil, authentication: QQMusicAuth? = nil) {
        self.authentication = authentication
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
        collections = QQMusicCollectionTransport(configuration: config, persistDevice: configuration == nil)
    }

    func loginCall(_ method: String, params: [String: Any], comm: [String: Any] = [:],
                   credential: QQMusicCollectionCredential? = nil) async throws -> [String: Any] {
        try await collections.loginCall(method, params: params, comm: comm, credential: credential)
    }

    // MARK: - 基础请求

    private func get(_ urlString: String, referer: String = "https://y.qq.com/", cookie: String = "") async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw ProviderRequestError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 QQMusic/9.0.5", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(cookie.isEmpty ? "uin=0; qqmusic_fromtag=66" : cookie, forHTTPHeaderField: "Cookie")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw ProviderRequestError.network
            }
            guard let json = parseJSON(data) else {
                let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
                throw ProviderRequestError.decoding(String(snippet))
            }
            return json
        } catch {
            throw error
        }
    }

    /// musicu.fcg 统一入口：POST JSON body（与 wp_MusicApi 一致）；登录后附加 QQ Cookie
    private func musicu(_ payload: [String: Any], cookie: String = "", timeout: TimeInterval = 6, userAgent: String? = nil) async throws -> [String: Any] {
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: base) else {
            throw ProviderRequestError.unknown("请求参数错误")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        // musicu 偶发挂起/风控，搜索保持短超时，歌单同步允许更长时间完成回退请求。
        request.timeoutInterval = timeout
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent ?? "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.1; WOW64; Trident/5.0)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        if !cookie.isEmpty {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        request.httpBody = body
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw ProviderRequestError.network
            }
            guard let json = parseJSON(data) else {
                let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
                throw ProviderRequestError.decoding(String(snippet))
            }
            return json
        } catch {
            throw error
        }
    }

    /// 表单 POST（fcg 老接口统一走这里，如 H5 评论接口）
    private func postForm(_ urlString: String, body: [String: Any], referer: String = "https://y.qq.com/", cookie: String = "") async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw ProviderRequestError.unknown("请求地址无效") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 QQMusic/9.0.5", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        request.setValue(cookie.isEmpty ? "uin=0; qqmusic_fromtag=66" : cookie, forHTTPHeaderField: "Cookie")
        var comps = URLComponents()
        comps.queryItems = body.map { URLQueryItem(name: $0.key, value: "\($0.value)") }
        request.httpBody = comps.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw ProviderRequestError.network
        }
        guard let json = parseJSON(data) else {
            let snippet = String(data: data, encoding: .utf8)?.prefix(120) ?? ""
            throw ProviderRequestError.decoding(String(snippet))
        }
        return json
    }

    /// 兼容纯 JSON 与 JSONP（`callback({...})`）两种响应；QQ 部分老接口会前置 `while(1);` 防护前缀
    private func parseJSON(_ data: Data) -> [String: Any]? {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return obj
        }
        guard var text = String(data: data, encoding: .utf8) else { return nil }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("while(1);") {
            text = String(text.dropFirst("while(1);".count))
        }
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}") else { return nil }
        let slice = text[start...end]
        return try? JSONSerialization.jsonObject(with: Data(slice.utf8)) as? [String: Any]
    }

    private static func photoURL(_ mid: String?, size: String = "300x300") -> URL? {
        guard let mid, !mid.isEmpty else { return nil }
        return URL(string: "https://y.gtimg.cn/music/photo_new/T002R\(size)M000\(mid).jpg")
    }

    /// 歌手头像（T001 歌手模板；T002 专辑模板对歌手 mid 会 404，搜索歌手必须用 T001）
    private static func singerPhotoURL(_ mid: String?, size: String = "300x300") -> URL? {
        guard let mid, !mid.isEmpty else { return nil }
        return URL(string: "https://y.gtimg.cn/music/photo_new/T001R\(size)M000\(mid).jpg")
    }

    private static func normalizedQQImageURL(_ raw: Any?) -> URL? {
        guard var value = raw as? String else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: "\\/", with: "/")
        value = decodeJSONStringValue(value)
        if value.hasPrefix("data:image") { return nil }
        if value.hasPrefix("http://") {
            value = "https://" + String(value.dropFirst(7))
        } else if value.hasPrefix("//") {
            value = "https:" + value
        } else if value.hasPrefix("/") {
            value = "https://y.gtimg.cn" + value
        } else if !value.hasPrefix("https://") {
            value = "https://y.gtimg.cn/" + value.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        }
        return URL(string: value)
            ?? value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed).flatMap(URL.init(string:))
    }

    private func musicuSearchPayload(keyword: String, limit: Int, type: QQSearchType) -> [String: Any] {
        [
            "comm": ["ct": 19, "cv": 1859, "uin": "0", "format": "json"],
            "req_1": [
                "module": "music.search.SearchCgiService",
                "method": "DoSearchForQQMusicDesktop",
                "param": [
                    "query": keyword,
                    "num_per_page": limit,
                    "page_num": 1,
                    "search_type": type.rawValue,
                    "grp": 1,
                ],
            ],
        ]
    }

    /// search_for_qq_cp 搜索 URL（未登录可用；t：0 单曲 / 8 专辑）
    private func clientSearchURL(keyword: String, limit: Int, type: Int, page: Int = 1) -> URL? {
        var comps = URLComponents(string: searchBase)
        comps?.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "w", value: keyword),
            URLQueryItem(name: "n", value: "\(limit)"),
            URLQueryItem(name: "p", value: "\(max(page, 1))"),
            URLQueryItem(name: "t", value: "\(type)"),
        ]
        return comps?.url
    }

    // MARK: - 搜索

    /// 搜索歌曲（client_search_cp，本机与手机网络均可）
    func searchSongs(keyword: String, limit: Int = 30, offset: Int = 0) async throws -> [ProviderSong] {
        let pageSize = max(limit, 1)
        let page = max(offset, 0) / pageSize + 1
        guard let url = clientSearchURL(keyword: keyword, limit: pageSize, type: 0, page: page) else {
            throw ProviderRequestError.unknown("搜索地址无效")
        }
        let json = try await get(url.absoluteString, referer: "https://y.qq.com/portal/player.html")
        let data = json["data"] as? [String: Any] ?? [:]
        let song = data["song"] as? [String: Any] ?? [:]
        let list = song["list"] as? [[String: Any]] ?? []
        var songs: [ProviderSong] = []
        for item in list {
            guard let songid = item["songid"] as? Int, let mid = item["songmid"] as? String else { continue }
            let singer = (item["singer"] as? [[String: Any]]) ?? []
            let artists = singer.compactMap { $0["name"] as? String }.joined(separator: " / ")
            let albumMid = item["albummid"] as? String ?? item["albumMID"] as? String
            let interval = (item["interval"] as? Int) ?? 0
            let pay = item["pay"] as? [String: Any]
            let fee = (item["fee"] as? Int) ?? (pay?["pay_play"] as? Int) ?? (pay?["payplay"] as? Int) ?? 0
            let file = item["file"] as? [String: Any]
            let mediaMid = file?["media_mid"] as? String
                ?? item["strMediaMid"] as? String
                ?? item["media_mid"] as? String
            songs.append(ProviderSong(
                id: songid,
                name: item["songname"] as? String ?? "",
                artists: artists,
                album: item["albumname"] as? String ?? item["albumName"] as? String ?? "",
                coverURL: Self.photoURL(albumMid),
                duration: TimeInterval(interval),
                source: .qq,
                qqMid: mid,
                qqMediaMid: mediaMid,
                fee: fee
            ))
        }
        return songs
    }

    /// 搜索歌手（musicu search_type=1 为主，字段 singerName/singerMID；musicu 被风控返回 2001 时用 smartbox_new 兜底）
    func searchArtists(keyword: String, limit: Int = 30) async throws -> [ProviderArtist] {
        if let json = try? await musicu(musicuSearchPayload(keyword: keyword, limit: limit, type: .artist)) {
            let list = nestedArray(json, path: ["req_1", "data", "body", "singer", "list"])
            var artists: [ProviderArtist] = []
            for item in list {
                let name = item["singerName"] as? String ?? (item["name"] as? String ?? (item["title"] as? String ?? ""))
                guard !name.isEmpty else { continue }
                let mid = item["singerMID"] as? String ?? (item["mid"] as? String)
                let numericID = item["singerID"] as? Int ?? (item["id"] as? Int ?? 0)
                artists.append(ProviderArtist(
                    id: mid ?? "qq-\(numericID)-\(name)",
                    name: name,
                    coverURL: Self.singerPhotoURL(mid),
                    source: .qq
                ))
            }
            if !artists.isEmpty { return artists }
        }
        // 兜底：smartbox_new.fcg 联想接口（含歌手/专辑，数据中心与移动网络均可用）
        if let encoded = keyword.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
           let url = URL(string: "https://c.y.qq.com/splcloud/fcgi-bin/smartbox_new.fcg?format=json&s_from=pc_header&type=1&key=\(encoded)"),
           let json = try? await get(url.absoluteString) {
            let singer = (json["data"] as? [String: Any])?["singer"] as? [String: Any] ?? [:]
            let list = singer["itemlist"] as? [[String: Any]] ?? []
            var artists: [ProviderArtist] = []
            for item in list.prefix(limit) {
                let name = item["name"] as? String ?? ""
                guard !name.isEmpty else { continue }
                let mid = item["mid"] as? String
                let numericID = item["id"] as? String ?? ""
                artists.append(ProviderArtist(
                    id: mid ?? "qq-\(numericID)-\(name)",
                    name: name,
                    coverURL: Self.normalizedQQImageURL(item["pic"]) ?? Self.singerPhotoURL(mid),
                    source: .qq
                ))
            }
            if !artists.isEmpty { return artists }
        }
        // 兜底 2：歌曲搜索结果里的歌手名去重（保证关键词搜索始终能出歌手）
        if let songs = try? await searchSongs(keyword: keyword, limit: 40) {
            var seen = Set<String>()
            var artists: [ProviderArtist] = []
            for song in songs {
                for part in song.artists.components(separatedBy: " / ") {
                    let name = part.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty, !seen.contains(name) else { continue }
                    seen.insert(name)
                    artists.append(ProviderArtist(id: "qq-name-\(name)", name: name, coverURL: nil, source: .qq))
                    if artists.count >= limit { break }
                }
                if artists.count >= limit { break }
            }
            if !artists.isEmpty { return artists }
        }
        return []
    }

    /// 搜索专辑（client_search_cp t=8 为主，与歌曲搜索同源、数据中心/移动网络均可用；musicu search_type=2 常被风控返回 2001 作为次选）
    func searchAlbums(keyword: String, limit: Int = 30) async throws -> [ProviderAlbum] {
        if let url = clientSearchURL(keyword: keyword, limit: limit, type: 8),
           let json = try? await get(url.absoluteString, referer: "https://y.qq.com/portal/player.html") {
            let data = json["data"] as? [String: Any] ?? [:]
            let album = data["album"] as? [String: Any] ?? [:]
            let list = album["list"] as? [[String: Any]] ?? []
            if !list.isEmpty {
                return parseAlbumItems(list)
            }
        }
        if let json = try? await musicu(musicuSearchPayload(keyword: keyword, limit: limit, type: .album)) {
            let list = nestedArray(json, path: ["req_1", "data", "body", "album", "list"])
            if !list.isEmpty {
                return parseAlbumItems(list)
            }
        }
        return []
    }

    private func parseAlbumItems(_ items: [[String: Any]]) -> [ProviderAlbum] {
        var albums: [ProviderAlbum] = []
        for item in items {
            let name = item["name"] as? String ?? (item["albumname"] as? String ?? item["albumName"] as? String ?? "")
            guard !name.isEmpty else { continue }
            let mid = item["mid"] as? String ?? (item["albummid"] as? String ?? item["albumMID"] as? String)
            let singer = (item["singer"] as? [[String: Any]]) ?? []
            var artistName = singer.compactMap { $0["name"] as? String }.joined(separator: " / ")
            if artistName.isEmpty { artistName = item["singerName"] as? String ?? "" }
            let numericID = item["id"] as? Int ?? 0
            albums.append(ProviderAlbum(
                id: mid ?? "qq-album-\(numericID)-\(name)",
                name: name,
                artistName: artistName,
                coverURL: Self.photoURL(mid),
                source: .qq,
                trackCount: item["total"] as? Int
            ))
        }
        return albums
    }

    struct CatalogSearchPage {
        var songs: [ProviderSong] = []
        var artists: [ProviderArtist] = []
        var albums: [ProviderAlbum] = []
        var playlists: [ProviderPlaylist] = []
        var total: Int?
    }

    func catalogSearch(keyword: String, type: NeteaseAPI.SearchType, limit: Int, offset: Int) async throws -> CatalogSearchPage {
        let listKey: String
        let searchType: Int
        switch type {
        case .songs: listKey = "item_song"; searchType = 0
        case .artists: listKey = "singer"; searchType = 1
        case .albums: listKey = "item_album"; searchType = 2
        case .playlists: listKey = "item_songlist"; searchType = 3
        }
        let pageSize = 20
        var start = offset % pageSize
        var next = offset / pageSize + 1
        var items: [[String: Any]] = []
        var total: Int?
        let credential = currentAuth.collectionCredential
        while items.count < limit {
            var params: [String: Any] = [
                "search_id": Self.searchID(), "remoteplace": "search.android.keyboard", "query": keyword, "search_type": searchType,
                "num_per_page": pageSize, "page_num": next, "highlight": 0, "nqc_flag": 0, "page_id": 1, "grp": 1
            ]
            let module = "music.search.SearchCgiService"
            let method = "DoSearchForQQMusicLite"
            let data: [String: Any]
            if let credential {
                data = try await collectionOperation(module, method, params, credential: credential)
            } else {
                if type == .songs { params["search_type"] = 7 }
                let json = try await musicu([
                    "comm": ["ct": 11, "cv": "1003006", "v": "1003006", "tmeAppID": "qqmusiclight",
                             "nettype": "NETWORK_WIFI", "udid": "0", "uid": "0"],
                    "req_0": ["module": module, "method": method, "param": params]
                ], cookie: "tmeLoginType=-1", userAgent: "okhttp/3.14.9")
                guard let block = json["req_0"] as? [String: Any], json["code"] as? Int == 0, block["code"] as? Int == 0,
                      let response = block["data"] as? [String: Any] else {
                    throw ProviderRequestError.decoding("QQ Music catalog search")
                }
                data = response
            }
            guard let body = data["body"] as? [String: Any], let rows = body[listKey] as? [[String: Any]],
                  let meta = data["meta"] as? [String: Any] else { throw ProviderRequestError.decoding("QQ Music catalog search") }
            total = Int(Self.text(meta["sum"]))
            items.append(contentsOf: rows.dropFirst(start))
            let nextPage = Self.integerValue(meta["nextpage"])
            guard nextPage > next, !rows.isEmpty else { break }
            start = 0
            next = nextPage
        }
        let rows = items.prefix(limit)
        var result = CatalogSearchPage(total: total)
        switch type {
        case .songs:
            result.songs = rows.compactMap { song(from: $0) }
        case .artists:
            result.artists = rows.compactMap { row in
                guard let mid = row["singerMID"] as? String, !mid.isEmpty, let name = row["singerName"] as? String else { return nil }
                return .init(id: mid, name: name, coverURL: Self.normalizedQQImageURL(row["singerPic"]) ?? Self.singerPhotoURL(mid), source: .qq)
            }
        case .albums:
            result.albums = rows.compactMap { row in
                guard let mid = row["albummid"] as? String, !mid.isEmpty, let name = row["name"] as? String else { return nil }
                return .init(id: mid, name: name, artistName: Self.text(row["singer"]),
                             coverURL: Self.normalizedQQImageURL(row["pic"]) ?? Self.photoURL(mid),
                             source: .qq, trackCount: Int(Self.text(row["song_num"])))
            }
        case .playlists:
            result.playlists = rows.compactMap(Self.playlist(fromQQDiss:))
        }
        return result
    }

    func searchSuggestions(keyword: String) async throws -> [String] {
        let data = try await operation("music.smartboxCgi.SmartBoxCgi", "GetSmartBoxResult",
            ["search_id": Self.searchID(), "query": keyword, "num_per_page": 0, "page_idx": 0])
        let rows = data["items"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return rows.compactMap { row in
            guard row["type"] as? Int == 0, let hint = row["hint"] as? String else { return nil }
            let keyword = hint.trimmingCharacters(in: .whitespacesAndNewlines)
            return !keyword.isEmpty && seen.insert(keyword).inserted ? keyword : nil
        }
    }

    private static func searchID() -> String {
        String(Int64.random(in: 100_000_000_000_000_000...999_999_999_999_999_999))
    }

    /// QQ 音乐热搜词
    func hotKeys(limit: Int = 10) async throws -> [String] {
        let data = try await operation("music.musicsearch.HotkeyService", "GetHotkeyForQQMusicMobile", [:])
        let rows = data["vec_hotkey"] as? [[String: Any]] ?? []
        return Array(rows.compactMap { $0["query"] as? String }.prefix(limit))
    }

    // MARK: - 歌单管理（创建 / 删除 / 我喜欢）

    /// 我喜欢（红心）歌单歌曲列表（dirid=201 解析真实歌单 ID，再拉歌单详情）
    /// QQ“我的喜欢”歌曲列表。limit <= 0 表示持续分页直到接口没有更多歌曲。
    func favoriteSongs(limit: Int = 0) async throws -> [ProviderSong] {
        let qqAuth = currentAuth
        let pageSize = 300
        let targetLimit = limit > 0 ? limit : Int.max
        guard qqAuth.isLoggedIn else {
            return []
        }
        if let credential = try await libraryCredential(), !credential.encryptedID.isEmpty {
            return try await ownedSongs(tid: 0, dirID: 201, limit: targetLimit, credential: credential)
        }
        let cookieCandidates = [qqAuth.playlistCookieHeader, qqAuth.cookieHeader]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        let identityCandidates = qqAuth.playlistIdentityCandidates

        // 保留旧版已验证的主路径：201 接口返回真实 map 后，详情请求必须使用
        // loginUin=0 + 完整 Cookie。部分微信登录态换成 wxuin 或裁剪 Cookie 后会返回空。
        let legacyFavURL = "https://c.y.qq.com/splcloud/fcgi-bin/fcg_musiclist_getmyfav.fcg?dirid=201&dirinfo=1&g_tk=\(qqAuth.gtk)&format=json&utf8=1"
        if let favJson = try? await get(legacyFavURL, referer: "https://y.qq.com/n/yqq/playlist", cookie: qqAuth.cookieHeader),
           let mapid = Self.likedMapID(favJson), mapid > 0 {
            let detailURL = "https://c.y.qq.com/qzone/fcgi-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=\(mapid)&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
            if let detailJson = try? await get(detailURL, referer: "https://y.qq.com/", cookie: qqAuth.cookieHeader),
               let cdlist = detailJson["cdlist"] as? [[String: Any]],
               let rawSongs = cdlist.first?["songlist"] as? [[String: Any]] {
                let songs = rawSongs.prefix(targetLimit).compactMap { song(from: Self.unwrapQQSong($0)) }
                if !songs.isEmpty && (limit > 0 || rawSongs.count < pageSize) { return songs }
            } else {
            }
        } else {
        }

        // 官方“我的喜欢”详情接口。它不依赖普通歌单的 disstid，
        // 而是用 dirid=201 返回专属收藏夹内容。
        let officialPayload: [String: Any] = [
            "comm": [
                "ct": 24,
                "cv": 0,
                "uin": qqAuth.playlistUin,
                "g_tk": qqAuth.gtk,
                "platform": "yqq",
            ],
            "req_1": [
                "module": "music.srfDissInfo.DissInfo",
                "method": "CgiGetDiss",
                "param": [
                    "new_format": 1,
                    "disstid": 201,
                    "dirid": 201,
                    "song_begin": 0,
                    "song_num": pageSize,
                    "enc_host_uin": qqAuth.playlistUin,
                    "onlysonglist": 0,
                    "userinfo": 1,
                ],
            ],
        ]
        for cookie in cookieCandidates {
            var allSongs: [ProviderSong] = []
            var seen = Set<String>()
            var begin = 0
            while allSongs.count < targetLimit {
                var pagePayload = officialPayload
                if var req = pagePayload["req_1"] as? [String: Any],
                   var param = req["param"] as? [String: Any] {
                    param["song_begin"] = begin
                    req["param"] = param
                    pagePayload["req_1"] = req
                }
                guard let json = try? await musicu(pagePayload, cookie: cookie, timeout: 20) else { break }
                let rawPage = Self.favoriteSongArray(from: json)
                let pageSongs = rawPage.compactMap { song(from: Self.unwrapQQSong($0)) }
                let newSongs = pageSongs.filter { seen.insert($0.identityKey).inserted }
                allSongs.append(contentsOf: newSongs)
                if rawPage.count < pageSize || newSongs.isEmpty { break }
                begin += rawPage.count
            }
            if !allSongs.isEmpty {
                return limit > 0 ? Array(allSongs.prefix(limit)) : allSongs
            }
        }

        // 201 收藏夹接口在不同登录态下有两种返回形式：
        // 有的直接返回 songlist，有的只返回 map/歌单 ID。必须先消费直接返回的歌曲，
        // 否则微信登录时会因为拿不到普通歌单 ID 而显示空列表。
        for identity in identityCandidates {
            let favURL = "https://c.y.qq.com/splcloud/fcgi-bin/fcg_musiclist_getmyfav.fcg?dirid=201&dirinfo=1&uin=\(identity)&loginUin=\(identity)&hostUin=0&g_tk=\(qqAuth.gtk)&format=json&utf8=1"
            for cookie in cookieCandidates {
                guard let favJson = try? await get(favURL, referer: "https://y.qq.com/n/ryqq_v2/profile/create", cookie: cookie) else { continue }
                let songs = Self.favoriteSongArray(from: favJson)
                    .prefix(targetLimit)
                    .compactMap { song(from: ($0["track_info"] as? [String: Any]) ?? $0) }
                if !songs.isEmpty { return songs }
            }
        }

        guard let mapid = await likedPlaylistID(qqAuth: qqAuth, cookies: cookieCandidates), mapid > 0 else {
            return []
        }
        let fallbackLimit = limit > 0 ? limit : pageSize
        for cookie in cookieCandidates {
            let songs = try await playlistSongs(listID: mapid, preferredCookie: cookie, limit: fallbackLimit)
            if !songs.isEmpty { return songs }
        }
        let songs = try await playlistSongs(listID: mapid, preferredCookie: nil, limit: fallbackLimit)
        return songs
    }

    /// 解析「我的喜欢」的真实歌单 ID。该歌单通常不会出现在 profile/create 的创建歌单列表中，
    /// 需要通过 dirid=201 专用接口或 GetUserPlaylist order=3 单独获取。
    private func likedPlaylistID(qqAuth: QQMusicAuth, cookies: [String]) async -> Int? {
        let favURL = "https://c.y.qq.com/splcloud/fcgi-bin/fcg_musiclist_getmyfav.fcg?dirid=201&dirinfo=1&g_tk=\(qqAuth.gtk)&format=json&utf8=1"
        for cookie in cookies {
            guard let favJson = try? await get(favURL, referer: "https://y.qq.com/n/yqq/playlist", cookie: cookie) else { continue }
            if let id = Self.likedMapID(favJson), id > 0 { return id }

            let data = favJson["data"] as? [String: Any] ?? favJson
            if let first = (data["cdlist"] as? [[String: Any]])?.first {
                let id = Self.integerValue(first["dissid"] ?? first["diss_id"])
                if id > 0 { return id }
            }
        }

        let identities = qqAuth.playlistIdentityCandidates
        for identity in identities {
            let numericUin = Int(identity) ?? 0
            let payload: [String: Any] = [
                "comm": [
                    "ct": 24,
                    "cv": 0,
                    "uin": numericUin,
                    "g_tk": qqAuth.gtk,
                    "platform": "yqq",
                ],
                "req_1": [
                    "module": "music.musichallSong.PlayListDataServer",
                    "method": "GetUserPlaylist",
                    "param": [
                        "uin": numericUin,
                        "sin": 0,
                        "size": 100,
                        "order": 3,
                    ],
                ],
            ]
            for cookie in cookies {
                guard let json = try? await musicu(payload, cookie: cookie, timeout: 15) else { continue }
                for item in Self.playlistArray(from: json) {
                    let id = Self.integerValue(item["dissid"] ?? item["diss_id"] ?? item["tid"])
                    if id > 0 { return id }
                }
            }
        }
        return nil
    }

    /// fcg_musiclist_getmyfav 的 map 可能是标量、嵌套在 data 中，或是 {"201": 真实歌单 ID}。
    private static func likedMapID(_ json: [String: Any]) -> Int? {
        let data = json["data"] as? [String: Any] ?? [:]
        for value in [json["map"], json["mapid"], json["id"], data["map"], data["mapid"], data["id"]] {
            if let dict = value as? [String: Any] {
                let preferredID = integerValue(dict["201"])
                if preferredID > 0 { return preferredID }
                if let id = dict.values.lazy.map({ integerValue($0) }).first(where: { $0 > 0 }) { return id }
            } else {
                let id = integerValue(value)
                if id > 0 { return id }
            }
        }
        return nil
    }

    /// 递归提取 fcg_musiclist_getmyfav 可能返回的 songlist/songList 数组。
    private static func favoriteSongArray(from json: [String: Any]) -> [[String: Any]] {
        var result: [[String: Any]] = []
        func walk(_ value: Any) {
            guard result.isEmpty else { return }
            if let dict = value as? [String: Any] {
                for key in ["songlist", "songList", "song_list", "tracks", "tracklist"] {
                    if let list = dict[key] as? [[String: Any]], !list.isEmpty {
                        result = list
                        return
                    }
                }
                for child in dict.values { walk(child) }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(json)
        return result
    }

    /// 收藏接口的曲目有时会包在 songInfo/data/track_info 内，统一解包到歌曲字段层。
    private static func unwrapQQSong(_ item: [String: Any]) -> [String: Any] {
        if item["songmid"] != nil || item["mid"] != nil || item["songname"] != nil {
            return item
        }
        for key in ["songInfo", "songinfo", "track_info", "trackInfo", "data", "song"] {
            if let nested = item[key] as? [String: Any] {
                let unwrapped = unwrapQQSong(nested)
                if unwrapped["songmid"] != nil || unwrapped["mid"] != nil || unwrapped["songname"] != nil {
                    return unwrapped
                }
            }
        }
        return item
    }

    // MARK: - 红心收藏

    private func ownedSongs(tid: Int, dirID: Int, limit: Int, credential: QQMusicCollectionCredential) async throws -> [ProviderSong] {
        var result: [ProviderSong] = []
        var seen = Set<String>()
        var offset = 0
        while result.count < limit {
            let data = try await collectionOperation("music.srfDissInfo.DissInfo", "CgiGetDiss",
                ["disstid": tid, "dirid": dirID, "tag": true, "song_begin": offset, "song_num": min(limit - result.count, 100),
                 "userinfo": true, "orderlist": true, "enc_host_uin": credential.encryptedID], credential: credential)
            guard let rows = data["songlist"] as? [[String: Any]] else {
                throw ProviderRequestError.decoding("QQ Music owned playlist songs")
            }
            let page = rows.compactMap { song(from: Self.unwrapQQSong($0)) }.filter { seen.insert($0.identityKey).inserted }
            result.append(contentsOf: page)
            offset += rows.count
            guard Self.integerValue(data["hasmore"]) == 1 else { break }
            guard !page.isEmpty else { throw ProviderRequestError.decoding("QQ Music repeated owned playlist page") }
        }
        return Array(result.prefix(limit))
    }

    func like(songID: Int, songmid: String, liked: Bool) async throws {
        let credential = try collectionCredential()
        let detail = try await collectionOperation("music.pf_song_detail_svr", "get_song_detail_yqq",
            ["song_type": 0, "song_mid": songmid], credential: credential)
        guard let track = detail["track_info"] as? [String: Any], track["mid"] as? String == songmid,
              let remoteID = Int(Self.text(track["id"])), remoteID > 0, songID <= 0 || songID == remoteID else {
            throw ProviderRequestError.unknown("QQ 音乐无法确认歌曲编号，请重新打开歌曲")
        }

        func state() async throws -> Bool {
            try await fanStatus("Song", "IsSongFanByMid", id: songmid, fields: ["v_songMid": [songmid]], credential: credential)
        }
        try await mutateCollection(liked, state: state) {
            let data = try await collectionOperation("music.musicasset.PlaylistDetailWrite", liked ? "AddSonglist" : "DelSonglist",
                ["dirId": 201, "v_songInfo": [["songId": remoteID, "songType": 0]]], credential: credential)
            try checkCollectionResult(data, key: "retCode")
            guard let result = data["result"] as? [String: Any], let dir = result["dirId"] as? Int,
                  let tid = Int(Self.text(result["tid"])), (dir == 201 && tid > 0) || (dir == 0 && tid == 0) else {
                throw ProviderRequestError.decoding("QQ Music favorite directory")
            }
        }
    }

    // MARK: - 播放 / 歌词

    /// 一档音质的 vkey 结果。`verified` 表示 CDN 探测确认可播，只有确认过的地址才会缓存。
    struct VkeyResource: Sendable, Equatable {
        let url: String
        let title: String?
        let verified: Bool
        /// RS01/F000 由探测拿到的文件头判断实际音质；拿不到时为 nil。
        let verifiedQuality: AudioQuality?
    }

    /// 已验证地址缓存 10 分钟；vkey 明确不给地址的档位缓存 1 分钟，让播放与音质菜单共用结果。
    static let verifiedVkeyLifetime: TimeInterval = 10 * 60
    static let emptyVkeyLifetime: TimeInterval = 60

    /// 指定音质获取播放地址（br: M800=320kbps 高质量 / M500=128kbps 低质量），下载用
    func songURL(songmid: String, mediaMid: String? = nil, br: String) async throws -> String? {
        let qqAuth = currentAuth
        let resolvedMediaMid = await resolveMediaMid(songmid: songmid, provided: mediaMid, qqAuth: qqAuth)
        return try await vkeyResource(songmid: songmid, mediaMid: resolvedMediaMid, br: br, qqAuth: qqAuth)?.url
    }

    struct SongURLResult {
        let url: String
        let br: String
        let attemptedBRs: [String]
        var title: String? = nil
        var verifiedQuality: AudioQuality? = nil

        var quality: AudioQuality? {
            if let verifiedQuality { return verifiedQuality }
            switch br {
            case "M500", "C400": return .standard
            case "M800": return .exhigh
            case "F000": return .lossless
            default: return nil
            }
        }
    }

    /// 通过 vkey 获取 QQ 音乐播放地址（对齐 wp_MusicApi：GET + data JSON + filename + CDN 分发）。
    /// 优先请求当前官方音质；会员歌曲在目标档位不可用时，继续尝试兼容档位。
    func songURL(
        songmid: String,
        mediaMid: String? = nil,
        quality: ProviderAudioQuality = .current
    ) async throws -> String? {
        try await songURLResult(songmid: songmid, mediaMid: mediaMid, quality: quality)?.url
    }

    /// 由高到低的降档顺序；同一 BR 只出现一次。
    static func fallbackBRs(preferred: String) -> [String] {
        var seen = Set<String>()
        return [preferred, "F000", "M800", "M500", "C400"].filter { seen.insert($0).inserted }
    }

    /// 返回 QQ 实际命中的 BR，供播放器在 AVPlayer 真正失败时继续向下切换。
    func songURLResult(
        songmid: String,
        mediaMid: String? = nil,
        quality: ProviderAudioQuality = .current
    ) async throws -> SongURLResult? {
        let qqAuth = currentAuth
        // 详情给出 media_mid 和各档文件大小。缺 media_mid 时必须先等详情；
        // 已有 media_mid 时与第一档 vkey 并行，只用来跳过后面明确没有文件的档位。
        let providedMid = mediaMid?.isEmpty == false ? mediaMid : nil
        var detail: QQSongPlaybackDetail?
        var pendingDetail: Task<QQSongPlaybackDetail?, Never>?
        if providedMid == nil {
            detail = await songDetail(songmid: songmid, qqAuth: qqAuth)
        } else {
            pendingDetail = Task { await self.songDetail(songmid: songmid, qqAuth: qqAuth) }
        }
        let resolvedMediaMid = providedMid ?? detail?.mediaMid ?? songmid
        var attemptedBRs: [String] = []
        var best: SongURLResult?
        for br in Self.fallbackBRs(preferred: Self.qqBR(for: quality)) {
            if !attemptedBRs.isEmpty, let task = pendingDetail {
                detail = await task.value
                pendingDetail = nil
            }
            if detail?.definitelyLacks(br: br) == true { continue }
            attemptedBRs.append(br)
            guard let resource = try await vkeyResource(
                songmid: songmid, mediaMid: resolvedMediaMid, br: br, qqAuth: qqAuth
            ) else { continue }
            try Task.checkCancellation()
            let result = SongURLResult(url: resource.url, br: br, attemptedBRs: attemptedBRs,
                                       title: resource.title, verifiedQuality: resource.verifiedQuality)
            let rank = result.quality.flatMap { AudioQuality.allCases.firstIndex(of: $0) } ?? -1
            let bestRank = best?.quality.flatMap { AudioQuality.allCases.firstIndex(of: $0) } ?? -1
            if best == nil || rank > bestRank { best = result }
            switch br {
            case "RS01" where result.quality != .hires: continue
            case "F000" where result.quality != .lossless && result.quality != .hires: continue
            default:
                pendingDetail?.cancel()
                return best
            }
        }
        pendingDetail?.cancel()
        return best
    }

    /// 兼容旧调用方：使用当前官方播放音质。
    func songURL(songmid: String, mediaMid: String? = nil) async throws -> String? {
        try await songURL(songmid: songmid, mediaMid: mediaMid, quality: .current)
    }

    /// QQ detail supplies byte counts and integral duration, not numeric bitrate.
    func averageBitrates(songmid: String) async throws -> [String: Double] {
        guard let detail = await songDetail(songmid: songmid, qqAuth: currentAuth),
              let duration = detail.duration, duration > 0 else { return [:] }
        return Self.averageBitrates(file: detail.fileSizes.mapValues { NSNumber(value: $0) }, duration: duration)
    }

    static func averageBitrates(file: [String: Any], duration: Double) -> [String: Double] {
        guard duration.isFinite, duration > 0 else { return [:] }
        var result: [String: Double] = [:]
        for (prefix, field) in [("M500", "size_128mp3"), ("M800", "size_320mp3"), ("F000", "size_flac"), ("RS01", "size_hires")] {
            if let bytes = file[field] as? NSNumber, bytes.doubleValue > 0 {
                result[prefix] = AudioQualityOption.estimatedBitrate(byteCount: bytes.doubleValue, durationSeconds: duration)
            }
        }
        return result
    }

    /// 单曲详情（media_mid、时长、各档文件大小），30 分钟内复用；播放、音质菜单、码率估算共用一次请求。
    private func songDetail(songmid: String, qqAuth: QQMusicAuth) async -> QQSongPlaybackDetail? {
        let uin = qqAuth.isLoggedIn ? qqAuth.uin : "0"
        let cookie = qqAuth.isLoggedIn ? qqAuth.cookieHeader : ""
        let payload: [String: Any] = [
            "comm": ["ct": 24, "cv": 0, "uin": uin],
            "songinfo": [
                "module": "music.pf_song_detail_svr",
                "method": "get_song_detail_yqq",
                "param": ["song_mid": songmid],
            ],
        ]
        let detail = try? await detailCache.value(for: "\(uin)|\(songmid)", ttl: { $0 == nil ? nil : 30 * 60 }) { [self] in
            guard let json = try? await musicu(payload, cookie: cookie),
                  let block = json["songinfo"] as? [String: Any],
                  let data = block["data"] as? [String: Any],
                  let track = data["track_info"] as? [String: Any] else { return nil }
            return QQSongPlaybackDetail(trackInfo: track)
        }
        return detail ?? nil
    }

    /// 搜索接口经常不返回 file.media_mid；独家 VIP 歌曲的 media_mid 又常与 songmid 不同，必须补拉详情。
    private func resolveMediaMid(songmid: String, provided: String?, qqAuth: QQMusicAuth) async -> String {
        if let provided, !provided.isEmpty { return provided }
        return await songDetail(songmid: songmid, qqAuth: qqAuth)?.mediaMid ?? songmid
    }

    /// 同一账号、同一首、同一档的 vkey 结果短时复用，并发调用共享同一次请求。
    private func vkeyResource(songmid: String, mediaMid: String, br: String, qqAuth: QQMusicAuth) async throws -> VkeyResource? {
        let uin = qqAuth.isLoggedIn ? qqAuth.uin : "0"
        let loginKey = qqAuth.isLoggedIn ? qqAuth.loginKey : ""
        let key = "\(uin)|\(loginKey.isEmpty ? 0 : 1)|\(songmid)|\(mediaMid)|\(br)"
        let resource = try await vkeyCache.value(for: key, ttl: { resource in
            guard let resource else { return Self.emptyVkeyLifetime }
            return resource.verified ? Self.verifiedVkeyLifetime : nil
        }) { [self] in
            try await vkeyResult(songmid: songmid, mediaMid: mediaMid, br: br, uin: uin,
                                 loginKey: loginKey, guid: Self.deviceGuid, qqAuth: qqAuth)
        }
        try Task.checkCancellation()
        return resource
    }

    /// 单次 vkey 请求（GET musicu.fcg，data 参数格式与 wp_MusicApi 完全一致）
    private func vkeyResult(songmid: String, mediaMid: String?, br: String, uin: String, loginKey: String, guid: String, qqAuth: QQMusicAuth) async throws -> VkeyResource? {
        // 音质与扩展名：M500/M800 为 mp3，F000（无损）为 flac
        let ext: String
        if br.hasPrefix("F") || br == "RS01" {
            ext = "flac"
        } else if br.hasPrefix("C") {
            ext = "m4a"
        } else {
            ext = "mp3"
        }
        let preferredMid = (mediaMid?.isEmpty == false ? mediaMid : nil) ?? songmid
        // QQ 官方 Web 格式为 prefix + songmid + media_mid；其余格式用于兼容不同年代接口。
        var filenames = [
            "\(br)\(songmid)\(preferredMid).\(ext)",
            "\(br)\(preferredMid).\(ext)",
            "\(br)\(songmid)\(songmid).\(ext)",
            "\(br)\(songmid).\(ext)",
        ]
        var seenFilenames = Set<String>()
        filenames = filenames.filter { seenFilenames.insert($0).inserted }
        let param: [String: Any] = [
            "filename": filenames,
            "guid": guid,
            "songmid": Array(repeating: songmid, count: filenames.count),
            "songtype": Array(repeating: 0, count: filenames.count),
            "uin": uin,
            "loginflag": qqAuth.isLoggedIn ? 1 : 0,
            "platform": "20",
        ]
        var comm: [String: Any] = [
            "uin": Int(uin) ?? 0,
            "format": "json",
            "ct": loginKey.isEmpty ? 24 : 19,
            "cv": 0,
            "g_tk": qqAuth.gtk,
        ]
        if !loginKey.isEmpty { comm["authst"] = loginKey }
        let payload: [String: Any] = [
            "comm": comm,
            "req": [
                "module": "CDN.SrfCdnDispatchServer",
                "method": "GetCdnDispatch",
                "param": ["guid": guid, "calltype": 0, "userip": ""],
            ],
            "req_0": [
                "module": "vkey.GetVkeyServer",
                "method": "CgiGetVkey",
                "param": param,
            ],
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let dataString = String(data: data, encoding: .utf8),
              var comps = URLComponents(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else { return nil }
        comps.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "data", value: dataString),
        ]
        guard let url = comps.url else { return nil }
        var request = URLRequest(url: url)
        // vkey 是播放前的关键一步：与 musicu 其他接口一样用短超时，挂起时尽快交给降档或重试。
        request.timeoutInterval = 8
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
        request.setValue(qqAuth.isLoggedIn ? qqAuth.cookieHeader : "uin=0; qqmusic_fromtag=66", forHTTPHeaderField: "Cookie")
        let (responseData, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = parseJSON(responseData),
              let req = json["req_0"] as? [String: Any],
              let reqData = req["data"] as? [String: Any],
              let infos = reqData["midurlinfo"] as? [[String: Any]] else { return nil }
        let playableInfos = infos.filter { ($0["purl"] as? String)?.isEmpty == false }
        guard !playableInfos.isEmpty else {
            return nil
        }
        let sips = reqData["sip"] as? [String] ?? []
        let cookie = qqAuth.isLoggedIn ? qqAuth.cookieHeader : ""
        let checksQuality = ["RS01", "F000"].contains(br)
        func verifiedResource(_ candidate: ProbeCandidate, _ probe: AudioProbe) async -> VkeyResource {
            var tier: AudioQuality?
            if checksQuality {
                tier = AudioQualityCheck.tier(header: probe.header, mimeType: probe.mimeType)
                // 探测没带回足够的文件头时再单独读一次，保持原来的无损/Hi-Res 校验。
                if tier == nil, probe.header.count < 42 {
                    tier = await AudioQualityCheck.remoteTier(url: candidate.address, session: session)
                }
            }
            if let base = candidate.base { streamHost.remember(base) }
            return VkeyResource(url: candidate.address, title: candidate.title, verified: true, verifiedQuality: tier)
        }
        // 所有文件名 × 所有节点一起探测，任意一个确认可播就用它。
        var candidates: [ProbeCandidate] = []
        let cdnBases = slowHosts.excluding(Self.qqCDNBases(from: sips))
        for info in playableInfos {
            guard let purl = info["purl"] as? String, !purl.isEmpty else { continue }
            let title = (info["quality_name"] ?? info["qualityName"] ?? reqData["quality_name"] ?? reqData["qualityName"]) as? String
            if purl.hasPrefix("http") {
                if let url = URL(string: purl) { candidates.append(.init(base: nil, address: purl, url: url, title: title)) }
                continue
            }
            let suffix = purl.hasPrefix("/") ? String(purl.dropFirst()) : purl
            for base in cdnBases {
                let address = base + suffix
                if let url = URL(string: address) { candidates.append(.init(base: base, address: address, url: url, title: title)) }
            }
        }
        guard !candidates.isEmpty else { return nil }
        // 30 分钟内验证过的节点先单独试，命中就只花这几次探测。
        var remaining = candidates
        var outcomes: [ProbeOutcome] = []
        if let remembered = streamHost.current, candidates.contains(where: { $0.base == remembered }) {
            let first = candidates.filter { $0.base == remembered }
            remaining = candidates.filter { $0.base != remembered }
            let race = await raceProbes(first, cookie: cookie)
            if let winner = race.winner { return await verifiedResource(winner.candidate, winner.probe) }
            streamHost.forget(remembered)
            outcomes += race.outcomes
        }
        let race = await raceProbes(remaining, cookie: cookie)
        if let winner = race.winner { return await verifiedResource(winner.candidate, winner.probe) }
        outcomes += race.outcomes
        // 有节点明确返回 404/403 而没有一个确认可播：这一档的文件实际不存在（vkey 会给出假链接），
        // 返回 nil 让调用方继续降档，不把必然失败的地址交给播放器。
        if outcomes.contains(where: { $0.kind == .forbidden }) { return nil }
        // 全部节点都无法确认（超时、不支持 Range）：不能证明会员地址失效，交给播放器继续验证。
        guard let fallback = candidates.first else { return nil }
        return VkeyResource(url: fallback.address, title: fallback.title, verified: false, verifiedQuality: nil)
    }

    private struct ProbeCandidate: Sendable {
        let base: String?
        let address: String
        let url: URL
        let title: String?
    }

    private struct ProbeOutcome: Sendable {
        let candidate: ProbeCandidate
        let kind: AudioProbe.Kind
    }

    private struct AudioProbe: Sendable {
        enum Kind: Sendable { case playable, forbidden, indeterminate }
        let kind: Kind
        var header = Data()
        var mimeType: String?
    }

    /// 一旦有节点明确拒绝，其余节点只再等这么久：实测某个备用节点会挂满 6 秒超时，
    /// 而真实可用的节点通常几十毫秒就返回 206。
    static let probeGraceAfterRefusal: TimeInterval = 1.0

    /// 并发探测，返回第一个确认可播的候选。有节点拒绝后，剩余节点只等 `probeGraceAfterRefusal`；
    /// 被截断的节点记为慢节点，接下来一段时间不再探测。
    private func raceProbes(_ candidates: [ProbeCandidate], cookie: String) async
        -> (winner: (candidate: ProbeCandidate, probe: AudioProbe)?, outcomes: [ProbeOutcome]) {
        guard !candidates.isEmpty else { return (nil, []) }
        enum Event: Sendable { case probe(Int, AudioProbe), deadline }
        let grace = UInt64(Self.probeGraceAfterRefusal * 1_000_000_000)
        return await withTaskGroup(of: Event.self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { .probe(index, await self.probeAudioURL(candidate.url, cookie: cookie)) }
            }
            var outcomes: [ProbeOutcome] = []
            var answered = Set<Int>()
            var deadlineArmed = false
            for await event in group {
                switch event {
                case .deadline:
                    group.cancelAll()
                    let stalled = candidates.indices.filter { !answered.contains($0) }.compactMap { candidates[$0].base }
                    slowHosts.mark(stalled)
                    return (nil, outcomes)
                case .probe(let index, let probe):
                    answered.insert(index)
                    if probe.kind == .playable {
                        group.cancelAll()
                        return ((candidates[index], probe), outcomes)
                    }
                    outcomes.append(ProbeOutcome(candidate: candidates[index], kind: probe.kind))
                    if answered.count == candidates.count {
                        group.cancelAll()
                        return (nil, outcomes)
                    }
                    if probe.kind == .forbidden, !deadlineArmed {
                        deadlineArmed = true
                        group.addTask {
                            try? await Task.sleep(nanoseconds: grace)
                            return .deadline
                        }
                    }
                }
            }
            return (nil, outcomes)
        }
    }

    /// 在交给 AVPlayer 前验证 CDN，避免 purl 非空但实际 404 的假成功地址。
    /// 读到的文件头同时用于判断 FLAC 实际音质，省掉一次单独的音质请求。
    private func probeAudioURL(_ url: URL, cookie: String) async -> AudioProbe {
        var request = URLRequest(url: url)
        request.timeoutInterval = 6
        request.setValue("bytes=0-2047", forHTTPHeaderField: "Range")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:80.0) Gecko/20100101 Firefox/80.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
        if !cookie.isEmpty { request.setValue(cookie, forHTTPHeaderField: "Cookie") }
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse else {
            // 超时、TLS/CDN 节点暂时不支持 Range 等情况不能证明会员地址失效，
            // 交给 AVPlayer 继续尝试，避免把有效地址错误降级到最低音质。
            return AudioProbe(kind: .indeterminate)
        }
        if [403, 404, 410, 451].contains(http.statusCode) {
            return AudioProbe(kind: .forbidden)
        }
        guard http.statusCode == 200 || http.statusCode == 206, !data.isEmpty else {
            return AudioProbe(kind: .indeterminate)
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if contentType.contains("text/html") || contentType.contains("application/json") {
            return AudioProbe(kind: .forbidden)
        }
        return AudioProbe(kind: .playable, header: data.prefix(2048), mimeType: http.mimeType)
    }

    /// 固定设备 GUID（持久化）：vkey 与 guid 强相关，随机 guid 会导致播放地址失效
    private static var deviceGuid: String {
        let key = "beans.qqmusic.guid.v1"
        if let saved = UserDefaults.standard.string(forKey: key), !saved.isEmpty {
            return saved
        }
        let guid = String(format: "%09d", Int.random(in: 100000000...999999999))
        UserDefaults.standard.set(guid, forKey: key)
        return guid
    }

    private static func qqBR(for quality: ProviderAudioQuality) -> String {
        switch quality {
        case .standard: return "M500"
        case .higher, .exhigh: return "M800"
        case .lossless: return "F000"
        case .hires: return "RS01"
        }
    }

    /// QQ 返回的 SIP 可能只包含当前分配到的节点。保留官方节点的同时补充
    /// 常见备用 CDN，避免会员地址只落到一个临时失效节点。
    private static func qqCDNBases(from sips: [String]) -> [String] {
        let fallbacks = [
            "https://isure.stream.qqmusic.qq.com/",
            "https://dl.stream.qqmusic.qq.com/",
            "https://ws.stream.qqmusic.qq.com/",
            "https://streamoc.music.tc.qq.com/",
        ]
        var result: [String] = []
        var seen = Set<String>()
        for raw in sips + fallbacks {
            var base = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !base.isEmpty else { continue }
            if !base.hasPrefix("http://") && !base.hasPrefix("https://") {
                base = "https://" + base
            }
            if !base.hasSuffix("/") {
                base += "/"
            }
            let key = base.lowercased()
            if seen.insert(key).inserted {
                result.append(base)
            }
        }
        return result
    }

    /// QQ 音乐歌词（LRC 文本）
    func lyric(songmid: String) async throws -> (original: String?, translation: String?) {
        guard let mid = songmid.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else { return (nil, nil) }
        let url = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg?songmid=\(mid)&format=json&nobase64=1&g_tk=5381"
        let json = try await get(url, referer: "https://y.qq.com/portal/player.html")
        let original = json["lyric"] as? String
        let translation = Self.readableTranslation(json["trans"])
        if let translation { return (original, translation) }
        let data = try? await operation("music.musichallSong.PlayLyricInfo", "GetPlayLyricInfo",
            ["songMID": songmid, "songName": "", "singerName": "", "albumName": "", "interval": 0, "crypt": 0,
             "ct": 19, "cv": 2111, "lrc_t": 0, "qrc": 0, "qrc_t": 0, "roma": 0, "roma_t": 0,
             "trans": 1, "trans_t": 0, "type": 0])
        try Task.checkCancellation()
        return (original, Self.readableTranslation(data?["trans"]))
    }

    private static func readableTranslation(_ value: Any?) -> String? {
        guard let text = value as? String, !text.isEmpty else { return nil }
        let decoded = Data(base64Encoded: text).flatMap { String(data: $0, encoding: .utf8) } ?? text
        guard decoded.range(of: #"\[\d{1,3}:\d{2}"#, options: .regularExpression) != nil else { return nil }
        return decoded
    }

    // MARK: - 评论区 / 排行榜 / 推荐 / 歌单

    /// QQ 音乐评论分页（fcg_global_comment_h5；topid 必须用数字 songid 并带 cid/reqtype，用 songmid 会返回空）
    /// pagenum 从 0 开始；热评只在第一页返回，翻页只取普通评论
    struct QQCommentPage {
        let comments: [ProviderSongComment]
        let total: Int
    }

    func comments(songID: Int, limit: Int = 25, pagenum: Int = 0) async throws -> QQCommentPage {
        let json = try await postForm("https://c.y.qq.com/base/fcgi-bin/fcg_global_comment_h5.fcg?format=json&cid=205360772&reqtype=2", body: [
            "biztype": 1,
            "topid": songID,
            "LoginUin": 0,
            "cmd": 8,
            "pagenum": max(pagenum, 0),
            "pagesize": min(max(limit, 1), 25)
        ])
        let hot = pagenum == 0 ? (((json["hot_comment"] as? [String: Any])?["commentlist"] as? [[String: Any]]) ?? []) : []
        let normal = ((json["comment"] as? [String: Any])?["commentlist"] as? [[String: Any]]) ?? []
        let commentTotal = ((json["comment"] as? [String: Any])?["commenttotal"] as? Int) ?? 0
        var seen = Set<String>()
        var result: [ProviderSongComment] = []
        for item in hot + normal {
            let rootID = item["rootcommentid"] as? String ?? ""
            let commentID = item["commentid"] as? String ?? ""
            let key = rootID + "_" + commentID
            guard !key.isEmpty, !seen.contains(key) else { continue }
            seen.insert(key)
            var content = Self.decodeCommentEmoji(item["rootcommentcontent"] as? String ?? "")
            content = content.replacingOccurrences(of: "\\n", with: "\n")
            guard !content.isEmpty else { continue }
            var nick = item["nick"] as? String ?? ""
            if nick.isEmpty { nick = item["rootcommentnick"] as? String ?? "" }
            if nick.hasPrefix("@") { nick = String(nick.dropFirst()) }
            let avatar = item["avatarurl"] as? String ?? ""
            let time = item["time"] as? TimeInterval ?? 0
            result.append(ProviderSongComment(
                id: key.hashValue,
                content: content,
                nickname: nick,
                avatarURL: avatar.isEmpty ? nil : URL(string: avatar),
                time: time > 0 ? Date(timeIntervalSince1970: time) : Date(),
                likedCount: item["praisenum"] as? Int ?? 0,
                isHot: true
            ))
        }
        return QQCommentPage(comments: result, total: commentTotal)
    }

    /// QQ 评论表情解码（[em]eXXXXXX[/em] → 对应 Unicode 表情）
    private static let commentEmojis: [String: String] = [
        "e400846": "😘",
        "e400874": "😴",
        "e400825": "😃",
        "e400847": "😙",
        "e400835": "😍",
        "e400873": "😳",
        "e400836": "😎",
        "e400867": "😭",
        "e400832": "😊",
        "e400837": "😏",
        "e400875": "😫",
        "e400831": "😉",
        "e400855": "😡",
        "e400823": "😄",
        "e400862": "😨",
        "e400844": "😖",
        "e400841": "😓",
        "e400830": "😈",
        "e400828": "😆",
        "e400833": "😋",
        "e400822": "😀",
        "e400843": "😕",
        "e400829": "😇",
        "e400824": "😂",
        "e400834": "😌",
        "e400877": "😷",
        "e400132": "🍉",
        "e400181": "🍺",
        "e401067": "☕️",
        "e400186": "🥧",
        "e400343": "🐷",
        "e400116": "🌹",
        "e400126": "🍃",
        "e400613": "💋",
        "e401236": "❤️",
        "e400622": "💔",
        "e400637": "💣",
        "e400643": "💩",
        "e400773": "🔪",
        "e400102": "🌛",
        "e401328": "🌞",
        "e400420": "👏",
        "e400914": "🙌",
        "e400408": "👍",
        "e400414": "👎",
        "e401121": "✋",
        "e400396": "👋",
        "e400384": "👉",
        "e401115": "✊",
        "e400402": "👌",
        "e400905": "🙈",
        "e400906": "🙉",
        "e400907": "🙊",
        "e400562": "👻",
        "e400932": "🙏",
        "e400644": "💪",
        "e400611": "💉",
        "e400185": "🎁",
        "e400655": "💰",
        "e400325": "🐥",
        "e400612": "💊",
        "e400198": "🎉",
        "e401685": "⚡️",
        "e400631": "💝",
        "e400768": "🔥",
        "e400432": "👑",
    ]
    private static func decodeCommentEmoji(_ raw: String) -> String {
        var text = raw
        while let range = text.range(of: #"\[em\]e\d+\[/em\]"#, options: .regularExpression) {
            let token = String(text[range])
            let code = token.replacingOccurrences(of: "[em]", with: "").replacingOccurrences(of: "[/em]", with: "")
            text.replaceSubrange(range, with: commentEmojis[code] ?? "")
        }
        return text
    }

    /// QQ 峰尖榜总览（榜单列表在响应的 data.topList，字段为 topTitle / picUrl）
    func topLists() async throws -> [QQTopInfo] {
        let url = "https://c.y.qq.com/v8/fcg-bin/fcg_myqq_toplist.fcg?format=json"
        let json = try await get(url)
        let data = json["data"] as? [String: Any] ?? json
        let list = data["topList"] as? [[String: Any]] ?? []
        var result: [QQTopInfo] = []
        for item in list {
            guard let id = item["id"] as? Int else { continue }
            let name = item["topTitle"] as? String ?? (item["title"] as? String ?? "")
            // 总览接口同时返回 MV/有声等非歌曲榜单；它们的详情接口没有可解析的歌曲，
            // 继续展示会让用户点进一个空白榜单。只保留歌曲榜单。
            guard !Self.isNonSongTopList(id: id, name: name) else { continue }
            let songs = (item["songList"] as? [[String: Any]]) ?? []
            let topNames = songs.compactMap { $0["songname"] as? String }.prefix(3).map { $0 }
            result.append(QQTopInfo(
                id: id,
                name: name,
                subTitle: item["subTitle"] as? String ?? "",
                topSongNames: topNames,
                coverURL: Self.normalizedQQImageURL(item["picUrl"])
            ))
        }
        return result
    }

    private static func isNonSongTopList(id: Int, name: String) -> Bool {
        // These IDs are currently exposed by QQ's overview endpoint but return no
        // playable song records from fcg_v8_toplist_cp.fcg.
        if id == 201 || id == 75 { return true }
        let normalized = name.lowercased()
        return normalized.contains("mv") || name.contains("有声") || name.contains("电台")
    }

    struct ToplistEntry {
        let song: ProviderSong
        /// One-based previous position; zero denotes a new entry.
        let previousRank: Int?
        let growthRatio: Double?
    }

    func topListEntries(topid: Int, limit: Int = 100) async throws -> [ToplistEntry] {
        let payload = try await operation("musicToplist.ToplistInfoServer", "GetDetail",
                                          ["topid": topid, "offset": 0, "num": limit])
        let chart = payload["data"] as? [String: Any] ?? [:]
        let ranks = chart["song"] as? [[String: Any]] ?? []
        let infos = payload["songInfoList"] as? [[String: Any]] ?? []
        let songs = Dictionary(infos.compactMap { raw -> (Int, ProviderSong)? in
            guard let song = song(from: raw) else { return nil }
            return (song.id, song)
        }, uniquingKeysWith: { first, _ in first })
        return ranks.compactMap { raw in
            guard let id = Self.chartInteger(raw["songId"]), let song = songs[id] else { return nil }
            let movement = Self.toplistMovement(raw)
            return ToplistEntry(song: song, previousRank: movement.previousRank, growthRatio: movement.growthRatio)
        }
    }

    private static func chartInteger(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        return (value as? String).flatMap(Int.init)
    }

    static func toplistMovement(_ raw: [String: Any]) -> (previousRank: Int?, growthRatio: Double?) {
        guard let rank = chartInteger(raw["rank"]), rank > 0,
              let type = chartInteger(raw["rankType"]) else { return (nil, nil) }
        let value = raw["rankValue"].map { String(describing: $0) } ?? ""
        switch type {
        case 1, 2:
            guard let delta = Int(value), delta >= 0 else { return (nil, nil) }
            let previous = type == 1 ? rank + delta : rank - delta
            return (previous > 0 ? previous : nil, nil)
        case 3: return (rank, nil)
        case 4: return (0, nil)
        case 6:
            guard let ratio = Double(value.replacingOccurrences(of: "%", with: "")), ratio.isFinite else { return (nil, nil) }
            return (nil, ratio)
        default: return (nil, nil)
        }
    }

    /// 某个峰尖榜的歌曲列表
    func topListSongs(topid: Int, limit: Int = 30) async throws -> [ProviderSong] {
        let url = "https://c.y.qq.com/v8/fcg-bin/fcg_v8_toplist_cp.fcg?format=json&page=detail&type=top&topid=\(topid)&song_begin=0&song_num=\(limit)"
        let json = try await get(url)
        let list = json["songlist"] as? [[String: Any]] ?? []
        return list.compactMap { item -> ProviderSong? in
            if let data = item["data"] as? [String: Any] {
                return song(from: data)
            }
            return song(from: item)
        }
    }

    /// QQ 每日推荐：热歌/新歌/飙升 三榜混合，按日期种子确定性打乱，每日轮换且与单个榜单内容区分
    func recommendSongs(limit: Int = 30) async throws -> [ProviderSong] {
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        var songs: [ProviderSong] = []
        var seen = Set<String>()
        let per = max(8, (limit + 2) / 3)
        for topid in [26, 27, 62] {
            guard let list = try? await topListSongs(topid: topid, limit: per) else { continue }
            for song in list where !seen.contains(song.identityKey) {
                seen.insert(song.identityKey)
                songs.append(song)
            }
        }
        var rng = SeededRNG(state: UInt64(day) &* 2654435761)
        songs.shuffle(using: &rng)
        return Array(songs.prefix(limit))
    }

    func discoveryPlaylists(limit: Int) async throws -> [ProviderPlaylist] {
        let module = "music.playlist.PlaylistSquare"
        let fields = ["From": 0, "Size": min(60, limit)]
        let data: [String: Any]
        if let credential = currentAuth.collectionCredential {
            data = try await collectionOperation(module, "GetRecommendFeed", fields, credential: credential)
        } else {
            data = try await operation(module, "GetRecommendFeed", fields)
        }
        let items = (data["List"] as? [[String: Any]] ?? []).compactMap { $0["Playlist"] as? [String: Any] }
        return items.compactMap(Self.feedPlaylist)
    }

    func playlistCategories() async throws -> [QQMusicCatalogOption] {
        let data = try await operation("music.web_category_svr", "get_hot_category", ["qq": ""])
        let groups = data["category"] as? [[String: Any]] ?? []
        var seen = Set<Int>()
        return groups.flatMap { $0["items"] as? [[String: Any]] ?? [] }.compactMap { item in
            guard let id = item["item_id"] as? Int, id > 0, seen.insert(id).inserted,
                  let name = item["item_name"] as? String, !name.isEmpty else { return nil }
            return .init(id: id, name: name)
        }
    }

    func categoryPlaylists(id: Int, page: Int) async throws -> (items: [ProviderPlaylist], more: Bool) {
        let size = 25
        let data = try await operation("music.playlist.PlayListCategory", "get_category_content",
            ["caller": "0", "category_id": id, "page": page, "size": size, "use_page": 1])
        guard Self.integerValue(data["retcode"]) == 0, let content = data["content"] as? [String: Any],
              let rows = content["v_item"] as? [[String: Any]] else { throw ProviderRequestError.decoding("QQ Music category playlists") }
        return (rows.compactMap(Self.feedPlaylist), (page + 1) * size < Self.integerValue(content["total_cnt"]))
    }

    private static func feedPlaylist(_ row: [String: Any]) -> ProviderPlaylist? {
        guard var basic = row["basic"] as? [String: Any] else { return nil }
        if let cover = basic["cover"] as? [String: Any] {
            basic["picurl"] = ["default_url", "big_url", "medium_url", "small_url"].lazy
                .compactMap { cover[$0] as? String }.first { !$0.isEmpty }
        }
        return playlist(fromQQDiss: basic)
    }

    func newSongs() async throws -> [ProviderSong] {
        let data = try await operation("newsong.NewSongServer", "get_new_song_info", ["type": 5])
        return try recommendationSongs(data["songlist"])
    }

    func radios() async throws -> [ProviderPlaylist] {
        let credential = try collectionCredential()
        let data = try await collectionOperation("pf.radiosvr", "GetRadiolist", ["uin": credential.id], credential: credential)
        let groups = data["radio_list"] as? [[String: Any]] ?? []
        var seen = Set<Int>()
        return groups.flatMap { $0["list"] as? [[String: Any]] ?? [] }.compactMap { row in
            guard let id = row["id"] as? Int, id > 0, seen.insert(id).inserted,
                  let name = row["title"] as? String, !name.isEmpty else { return nil }
            var item = ProviderPlaylist(id: id, name: name, coverURL: Self.normalizedQQImageURL(row["pic_url"]), source: .qq)
            item.isQQRadio = true
            return item
        }
    }

    func radioSongs(id: Int) async throws -> [ProviderSong] {
        if id == 99 { return try await guessYouLike() }
        let data = try await collectionOperation("pf.radiosvr", "GetRadiosonglist",
            ["id": id, "firstplay": 0, "num": 9], credential: collectionCredential())
        return try recommendationSongs(data["track_list"])
    }

    func singers(limit: Int) async throws -> [ProviderArtist] {
        let data = try await operation("music.musichallSinger.SingerList", "GetSingerListIndex",
            ["area": -100, "sex": -100, "genre": -100, "index": -100, "sin": 0, "cur_page": 1])
        let list = data["singerlist"] as? [[String: Any]] ?? []
        return Array(list.compactMap { row -> ProviderArtist? in
            guard let id = row["singer_mid"] as? String, !id.isEmpty, let name = row["singer_name"] as? String else { return nil }
            return .init(id: id, name: name, coverURL: Self.normalizedQQImageURL(row["singer_pic"]) ?? Self.singerPhotoURL(id), source: .qq)
        }.prefix(limit))
    }

    func singerProfile(mid: String, name: String) async throws -> (name: String, cover: URL?, description: String) {
        let mid = try await resolvedSingerMID(mid, name: name)
        let data = try await operation("music.musichallSinger.SingerInfoInter", "GetSingerDetail",
            ["singer_mids": [mid], "pic": 1, "group_singer": 1, "wiki_singer": 1, "ex_singer": 1])
        guard let row = (data["singer_list"] as? [[String: Any]])?.first,
              let basic = row["basic_info"] as? [String: Any], basic["singer_mid"] as? String == mid else {
            throw ProviderRequestError.decoding("QQ Music singer profile")
        }
        let extra = row["ex_info"] as? [String: Any]
        let pic = row["pic"] as? [String: Any]
        return (basic["name"] as? String ?? name, Self.normalizedQQImageURL(pic?["pic"] ?? pic?["big_black"]),
                extra?["desc"] as? String ?? "")
    }

    func dailySongs() async throws -> [ProviderSong] {
        let data = try await collectionOperation("music.srfDissInfo.aiDissInfo", "uniform_get_Dissinfo",
            ["dirid": 202, "optype": 3, "tag": 1, "userinfo": 0, "pic_dpi": 300], credential: collectionCredential())
        return try recommendationSongs(data["songlist"])
    }

    func radioRadar(page: Int) async throws -> (songs: [ProviderSong], more: Bool) {
        let data = try await collectionOperation("music.recommend.TrackRelationServer", "GetRadarSong",
            ["Page": page, "ReqType": 0, "FavSongs": [], "EntranceSongs": []], credential: collectionCredential())
        let rows = (data["VecSongs"] as? [[String: Any]] ?? []).compactMap { $0["Track"] as? [String: Any] }
        return (try recommendationSongs(rows), data["HasMore"] as? Bool == true)
    }

    func guessYouLike(poolID: String? = nil) async throws -> [ProviderSong] {
        let credential = try collectionCredential()
        var params: [String: Any] = ["id": 99, "firstplay": 1, "num": 15]
        if let poolID {
            params = ["id": 99, "num": 5, "ext": ["scene_id": poolID]]
        }
        let data = try await collectionOperation("music.radioProxy.MbTrackRadioSvr", "get_radio_track", params, credential: credential)
        return try recommendationSongs(data["tracks"])
    }

    /// The logged-in user's QQ Music profile name and avatar. Web profile calls can
    /// return 1000 or the blank QQ nickname, while the app session sees the music profile.
    func loginProfileHeader() async throws -> (name: String, avatar: String?) {
        let credential = try collectionCredential()
        var lastError: Error = ProviderRequestError.decoding("QQ Music profile header")
        for uin in [credential.encryptedID, credential.id] where !uin.isEmpty {
            do {
                let data = try await collectionOperation("music.UnifiedHomepage.UnifiedHomepageSrv", "GetHomepageHeader",
                    ["uin": uin, "IsQueryTabDetail": 0], credential: credential)
                let base = (data["Info"] as? [String: Any])?["BaseInfo"] as? [String: Any]
                let name = Self.text(base?["Name"]).trimmingCharacters(in: .whitespacesAndNewlines)
                guard !name.isEmpty else { continue }
                let avatar = [base?["BigAvatar"], base?["Avatar"]].map { Self.text($0) }.first { !$0.isEmpty }
                return (name, avatar)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func recommendationSongs(_ value: Any?) throws -> [ProviderSong] {
        guard let rows = value as? [[String: Any]] else { throw ProviderRequestError.decoding("QQ Music recommendations") }
        return rows.compactMap { song(from: Self.unwrapQQSong($0)) }
    }

    /// Checks a saved login with an account-only call. It never renews the key, so checking
    /// an inactive account cannot rotate credentials that another session still holds.
    func sessionValidity(credential: QQMusicCollectionCredential?) async -> MusicAccountValidity {
        guard let credential else { return .invalid }
        do {
            _ = try await collections.call("music.individuation.ListenReportSvr", "GetRank",
                ["type": 1, "uin": "", "version": "v2", "token": ""], credential: credential) { true }
            return .valid
        } catch QQMusicSessionError.expired {
            return .invalid
        } catch {
            return .unknown
        }
    }

    func listeningRank(period: Int, date: String? = nil) async throws -> [(song: ProviderSong, count: Int)] {
        var fields: [String: Any] = ["type": period, "uin": "", "version": "v2", "token": ""]
        fields["date"] = date
        let data = try await collectionOperation("music.individuation.ListenReportSvr", "GetRank", fields,
            credential: collectionCredential())
        return (data["rank"] as? [[String: Any]] ?? []).compactMap { row in
            guard let track = row["track"] as? [String: Any], let item = song(from: track),
                  let count = row["listenCnt"] as? Int, count >= 0 else { return nil }
            return (item, count)
        }
    }

    func songVersions(songID: Int) async throws -> [ProviderSong] {
        let data = try await operation("music.musichallSong.OtherVersionServer", "GetOtherVersionSongs", ["songid": songID])
        return (data["versionList"] as? [[String: Any]] ?? []).compactMap { song(from: Self.unwrapQQSong($0)) }
    }

    func songLabels(songID: Int) async throws -> [String] {
        let data = try await operation("music.recommend.TrackRelationServer", "GetSongLabels", ["songid": songID])
        return (data["labels"] as? [[String: Any]] ?? []).compactMap { $0["tagTxt"] as? String }.filter { !$0.isEmpty }
    }

    func songFavoriteCount(songID: Int) async throws -> Int? {
        let data = try await operation("music.musicasset.SongFavRead", "GetSongFansNumberById", ["v_songId": [songID]])
        let counts = data["m_numbers"] as? [String: Any]
        return Int(Self.text(counts?[String(songID)]))
    }

    func similarSongs(songID: Int, limit: Int) async throws -> [ProviderSong] {
        let data = try await collectionOperation("music.recommend.TrackRelationServer", "GetSimilarSongs",
            ["songid": songID], credential: collectionCredential())
        let groups = data["vecSongNew"] as? [[String: Any]] ?? []
        let rows = groups.flatMap { $0["songs"] as? [[String: Any]] ?? [] }.compactMap { $0["track"] as? [String: Any] }
        return Array(try recommendationSongs(rows).prefix(limit))
    }

    func relatedPlaylists(songID: Int) async throws -> [ProviderPlaylist] {
        let data = try await collectionOperation("music.recommend.TrackRelationServer", "GetRelatedPlaylist",
            ["songid": songID, "vecPlaylist": []], credential: collectionCredential())
        let groups = data["vecPlaylistNew"] as? [[String: Any]] ?? []
        return groups.flatMap { $0["playlists"] as? [[String: Any]] ?? [] }.compactMap(Self.playlist(fromQQDiss:))
    }

    func newAlbums(area: Int = 1, limit: Int, offset: Int) async throws -> [ProviderAlbum] {
        let data = try await operation("newalbum.NewAlbumServer", "get_new_album_info",
            ["area": area, "sin": 0, "start": offset, "num": min(60, limit)])
        let rows = data["albums"] as? [[String: Any]] ?? []
        return rows.compactMap { row in
            guard let mid = row["mid"] as? String, !mid.isEmpty, let name = row["name"] as? String else { return nil }
            let singers = (row["singers"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
            let extras = row["ex"] as? [String: Any]
            return .init(id: mid, name: name, artistName: singers.joined(separator: " / "), coverURL: Self.photoURL(mid),
                         source: .qq, trackCount: extras?["track_nums"] as? Int)
        }
    }

    func similarArtists(mid: String, name: String) async throws -> [ProviderArtist] {
        let mid = try await resolvedSingerMID(mid, name: name)
        let data = try await operation("music.SimilarSingerSvr", "GetSimilarSingerList", ["singerMid": mid, "number": 10])
        return (data["singerlist"] as? [[String: Any]] ?? []).compactMap { row in
            guard let mid = row["singerMid"] as? String, !mid.isEmpty, let name = row["singerName"] as? String else { return nil }
            return .init(id: mid, name: name, coverURL: Self.normalizedQQImageURL(row["singerPic"]) ?? Self.singerPhotoURL(mid), source: .qq)
        }
    }

    struct CloudEntry {
        let fileID: String
        let fileName: String
        let song: ProviderSong?
    }

    func cloudEntries() async throws -> [CloudEntry] {
        let credential = try collectionCredential()
        var result: [CloudEntry] = []
        var seen = Set<String>()
        for page in 1...10 {
            let data = try await collectionOperation("music.WeiyunMusic.WeiyunMusicRead", "GetMatchAudio",
                ["uin": credential.id, "file_id": "", "page_no": page, "page_size": 2000], credential: credential)
            let rows = data["info_list"] as? [[String: Any]] ?? []
            let previous = result.count
            for (index, row) in rows.enumerated() {
                let id = Self.text(row["file_id"])
                let fileID = id.isEmpty ? "\(page):\(index)" : id
                guard seen.insert(fileID).inserted else { continue }
                var name = Self.text(row["filename"])
                if let bytes = Data(base64Encoded: name), let decoded = String(data: bytes, encoding: .utf8),
                   !decoded.isEmpty, decoded.rangeOfCharacter(from: .controlCharacters) == nil { name = decoded }
                let track = (row["song_info"] as? [String: Any]).flatMap { song(from: $0) }
                let playable = Self.integerValue(row["matched"]) != 2 && track?.qqMid?.isEmpty == false
                result.append(.init(fileID: fileID, fileName: name.isEmpty ? track?.name ?? "" : name, song: playable ? track : nil))
            }
            if Self.integerValue(data["has_more"]) != 1 || result.count == previous { break }
        }
        return result
    }

    /// 用户歌单（创建 + 收藏合并）。
    /// 微信网页登录可能没有 QQ uin，优先使用带微信 Cookie 的官方 GetUserPlaylist 接口，
    /// 同时保留旧版 fcg 接口作为 QQ 登录和部分旧账号的快速通道。
    func userPlaylists(uin: String) async throws -> [ProviderPlaylist] {
        let qqAuth = currentAuth
        guard qqAuth.isLoggedIn else { return [] }

        let requestUin = qqAuth.playlistUin
        let cookieCandidates = [qqAuth.playlistCookieHeader, qqAuth.cookieHeader]
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        let legacyUins = (qqAuth.playlistIdentityCandidates + [requestUin, uin])
            .filter { !$0.isEmpty && $0 != "0" }
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }

        var playlists: [ProviderPlaylist] = []
        var seen = Set<Int>()

        func append(_ item: [String: Any], owned: Bool) {
            guard var playlist = Self.playlist(fromQQDiss: item), !seen.contains(playlist.id) else { return }
            let text = playlist.name + " " + (item["hostname"] as? String ?? "")
            if text.lowercased().contains("qzone") || text.contains("空间") || text.contains("背景音乐") { return }
            seen.insert(playlist.id)
            playlist.isOwned = owned
            if owned { playlist.ownerID = qqAuth.uin }
            playlist.isSubscribed = !owned
            playlists.append(playlist)
        }

        var createdLoaded = false
        var collectedLoaded = false
        let credential = try await libraryCredential()
        let usesModernLibrary = credential?.encryptedID.isEmpty == false
        if let credential, usesModernLibrary {
            try await ownedPlaylistRows(credential: credential).forEach { append($0, owned: true) }
            var offset = 0
            for _ in 0..<100 {
                let data = try await collectionOperation("music.musicasset.PlaylistFavRead", "CgiGetPlaylistFavInfo",
                    ["uin": credential.encryptedID, "offset": offset, "size": 100], credential: credential)
                guard let rows = data["v_list"] as? [[String: Any]] else {
                    throw ProviderRequestError.decoding("QQ Music favorite playlists")
                }
                let previous = playlists.count
                rows.forEach { append($0, owned: false) }
                offset += rows.count
                if Self.integerValue(data["hasmore"]) != 1 { break }
                if playlists.count == previous { throw ProviderRequestError.decoding("QQ Music repeated favorite playlists page") }
            }
            createdLoaded = true
            collectedLoaded = true
        } else if let credential, let rows = try? await ownedPlaylistRows(credential: credential) {
            rows.forEach { append($0, owned: true) }
            createdLoaded = true
        }
        try Task.checkCancellation()

        // QQ/微信登录都尝试旧接口；部分微信态账号必须显式带 wxuin 才会返回歌单。
        for legacyUin in legacyUins where !createdLoaded {
            let createdURL = "https://c.y.qq.com/rsc/fcgi-bin/fcg_user_created_diss?hostUin=0&hostuin=\(legacyUin)&sin=0&size=200&g_tk=\(qqAuth.gtk)&loginUin=\(legacyUin)&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
            for cookie in cookieCandidates {
                guard let created = try? await get(createdURL, referer: "https://y.qq.com/portal/profile.html", cookie: cookie) else { continue }
                let data = created["data"] as? [String: Any] ?? created
                let disslist = (data["disslist"] as? [[String: Any]]) ?? (created["disslist"] as? [[String: Any]]) ?? []
                if !disslist.isEmpty {
                    createdLoaded = true
                    disslist.forEach { append($0, owned: true) }
                    break
                }
            }
            if createdLoaded { break }
        }

        for legacyUin in legacyUins where !collectedLoaded {
            let collectURL = "https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg?ct=20&cid=205360956&userid=\(legacyUin)&reqtype=3&sin=0&ein=80&g_tk=\(qqAuth.gtk)"
            for cookie in cookieCandidates {
                guard let collected = try? await get(collectURL, referer: "https://y.qq.com/portal/profile.html", cookie: cookie) else { continue }
                let data = collected["data"] as? [String: Any] ?? collected
                let cdlist = (data["cdlist"] as? [[String: Any]]) ?? (collected["cdlist"] as? [[String: Any]]) ?? []
                if !cdlist.isEmpty {
                    collectedLoaded = true
                    cdlist.forEach { append($0, owned: false) }
                    break
                }
            }
            if collectedLoaded { break }
        }

        // 官方 App 接口按多个身份候选依次尝试，兼容 QQ 登录和微信网页登录。
        // order：1=创建，2=收藏，3=我喜欢。空响应仍继续尝试下一个身份参数。
        let officialUins = (qqAuth.playlistIdentityCandidates + [requestUin, "0"]).reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
        for (order, loaded) in [(1, createdLoaded), (2, collectedLoaded), (3, usesModernLibrary)] {
            if loaded { continue }
            for officialUin in officialUins {
                let numericUin = Int(officialUin) ?? 0
                let payload: [String: Any] = [
                    "comm": [
                        "ct": 24,
                        "cv": 0,
                        "uin": numericUin,
                        "g_tk": qqAuth.gtk,
                        "platform": "yqq",
                    ],
                    "req_1": [
                        "module": "music.musichallSong.PlayListDataServer",
                        "method": "GetUserPlaylist",
                        "param": [
                            "uin": numericUin,
                            "sin": 0,
                            "size": 200,
                            "order": order,
                        ],
                    ],
                ]
                for cookie in cookieCandidates {
                    guard let json = try? await musicu(payload, cookie: cookie, timeout: 15) else { continue }
                    let list = Self.playlistArray(from: json)
                    if !list.isEmpty {
                        list.forEach { append($0, owned: order != 2) }
                        break
                    }
                }
                if !playlists.isEmpty && order != 3 { break }
            }
        }

        // The built-in favorites directory stays visible even when the API omits it.
        if !seen.contains(Self.qqLikedPlaylistID) {
            var liked = ProviderPlaylist(id: Self.qqLikedPlaylistID, name: "我的喜欢", coverURL: Self.qqLikedCoverURL, source: .qq)
            liked.isOwned = true
            liked.isSubscribed = false
            playlists.insert(liked, at: 0)
        }

        playlists.sort { lhs, rhs in
            let a = lhs.name.contains("我喜欢") || lhs.name.contains("我的喜欢") || lhs.name.contains("喜欢的音乐")
            let b = rhs.name.contains("我喜欢") || rhs.name.contains("我的喜欢") || rhs.name.contains("喜欢的音乐")
            if a != b { return a }
            return lhs.name < rhs.name
        }
        return playlists
    }

    /// QQ 歌单项解析，兼容旧 fcg 和 musicu GetUserPlaylist 的字段命名。
    private static func playlist(fromQQDiss item: [String: Any]) -> ProviderPlaylist? {
        let rawName = text(item["dirName"] ?? item["diss_name"] ?? item["dissname"] ?? item["name"] ?? item["title"] ?? item["dissName"])
        let dirid = integerValue(item["dirid"] ?? item["dirId"])
        let dissid = integerValue(item["dissid"] ?? item["diss_id"] ?? item["dissId"])
        let tid = integerValue(item["tid"])

        let trimmedName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if dirid == 201 || (dirid == 0 && ["我喜欢", "我的喜欢", "喜欢的音乐"].contains(trimmedName)) {
            return ProviderPlaylist(
                id: Self.qqLikedPlaylistID,
                name: "我的喜欢",
                coverURL: URL(string: "https://y.gtimg.cn/mediastyle/global/img/cover_like.png"),
                trackCount: integerValue(item["songNum"] ?? item["song_cnt"] ?? item["songnum"] ?? item["total_song_num"]),
                source: .qq
            )
        }

        // 目录项没有真实歌单 ID，不能展示成可打开但永远为空的歌单。
        if dissid == 0 && tid == 0 && dirid > 0 { return nil }
        let id = dissid > 0 ? dissid : (tid > 0 ? tid : (dirid > 0 ? dirid : integerValue(item["id"])))
        guard id > 0, !trimmedName.isEmpty else { return nil }

        let coverURL = [
            "diss_cover", "dir_pic_url", "logo", "albumPicUrl", "bigpicUrl", "picUrl", "picurl", "pic_url",
            "cover", "cover_url", "headurl", "imgurl",
        ].lazy.compactMap { normalizedQQImageURL(item[$0]) }.first
        let count = integerValue(item["songNum"] ?? item["song_cnt"] ?? item["songnum"] ?? item["total_song_num"] ?? item["song_count"])
        var playlist = ProviderPlaylist(id: id, name: trimmedName, coverURL: coverURL, trackCount: count, source: .qq)
        if dirid > 0 { playlist.qqDirectoryID = dirid }
        return playlist
    }

    private static func integerValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? Double { return Int(value) }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    private static func decodeJSONStringValue(_ value: String) -> String {
        let quoted = "\"\(value)\""
        guard let data = quoted.data(using: .utf8),
              let decoded = try? JSONSerialization.jsonObject(with: data) as? String else {
            return value
        }
        return decoded
    }

    private static func initialData(from html: String) -> [String: Any]? {
        guard let marker = html.range(of: "window.__INITIAL_DATA__") ?? html.range(of: "__INITIAL_DATA__"),
              let start = html[marker.upperBound...].firstIndex(of: "{") else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var index = start
        while index < html.endIndex {
            let ch = html[index]
            if escaped {
                escaped = false
            } else if ch == "\\" {
                escaped = inString
            } else if ch == "\"" {
                inString.toggle()
            } else if !inString {
                if ch == "{" {
                    depth += 1
                } else if ch == "}" {
                    depth -= 1
                    if depth == 0 {
                        let jsonText = String(html[start...index])
                        return try? JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as? [String: Any]
                    }
                }
            }
            index = html.index(after: index)
        }
        return nil
    }

    private static func hotRecommendArray(from json: [String: Any]) -> [[String: Any]] {
        if let list = json["hotRecommend"] as? [[String: Any]], !list.isEmpty { return list }
        var result: [[String: Any]] = []
        func walk(_ value: Any) {
            guard result.isEmpty else { return }
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    if key == "hotRecommend", let list = child as? [[String: Any]], !list.isEmpty {
                        result = list
                        return
                    }
                    walk(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)
        return result
    }

    private static func hotRecommendPlaylist(_ item: [String: Any]) -> ProviderPlaylist? {
        let id = integerValue(item["dissid"] ?? item["diss_id"] ?? item["tid"] ?? item["id"])
        let name = (item["dissname"] as? String) ?? (item["title"] as? String) ?? (item["name"] as? String) ?? ""
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard id > 0, !trimmedName.isEmpty else { return nil }
        let cover = normalizedQQImageURL(item["imgurl"] ?? item["picurl"] ?? item["pic_url"] ?? item["cover"])
        let count = integerValue(item["listennum"] ?? item["songnum"] ?? item["song_cnt"] ?? item["listen_num"])
        return ProviderPlaylist(id: id, name: trimmedName, coverURL: cover, trackCount: count, source: .qq)
    }

    /// 兼容 GetUserPlaylist 在不同客户端版本中的嵌套位置。
    private static func playlistArray(from json: [String: Any]) -> [[String: Any]] {
        let paths = [
            ["req_1", "data", "v_playlist"],
            ["req_1", "data", "playlist"],
            ["req_1", "data", "list"],
            ["req_1", "data", "data", "v_playlist"],
            ["req_1", "data", "body", "v_playlist"],
        ]
        for path in paths {
            var current: Any = json
            for key in path {
                guard let dict = current as? [String: Any], let next = dict[key] else {
                    current = NSNull()
                    break
                }
                current = next
            }
            if let list = current as? [[String: Any]], !list.isEmpty {
                return list
            }
        }

        var result: [[String: Any]] = []
        func walk(_ value: Any) {
            guard result.isEmpty else { return }
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    if key == "v_playlist", let list = child as? [[String: Any]], !list.isEmpty {
                        result = list
                        return
                    }
                    walk(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(json)
        return result
    }

    /// QQ 官网首页热门歌单。
    /// 官网首页会把这组数据放在 SSR 的 __INITIAL_DATA__.hotRecommend 中，
    /// 比旧的 RecommendPlaylist musicu 接口更接近官网实际展示内容。
    func hotPlaylists(limit: Int = 18) async throws -> [ProviderPlaylist] {
        guard let url = URL(string: "https://y.qq.com/") else {
            throw ProviderRequestError.unknown("QQ 音乐官网地址无效")
        }
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 QQMusic/9.0.5", forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        guard status == 200, let html = String(data: data, encoding: .utf8) else {
            throw ProviderRequestError.network
        }

        if let initialData = Self.initialData(from: html) {
            var seen = Set<Int>()
            let playlists = Self.hotRecommendArray(from: initialData)
                .compactMap(Self.hotRecommendPlaylist)
                .filter { playlist in
                    guard !seen.contains(playlist.id) else { return false }
                    seen.insert(playlist.id)
                    return true
                }
                .prefix(max(1, limit))
            if !playlists.isEmpty {
                return await enrichHotPlaylistCovers(Array(playlists))
            }
        } else {
        }

        let pattern = #""imgurl"\s*:\s*"([^"]+)".*?"dissname"\s*:\s*"([^"]*)".*?"listennum"\s*:\s*([0-9]+).*?"dissid"\s*:\s*([0-9]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else {
            throw ProviderRequestError.decoding("QQ 官网热门歌单解析器初始化失败")
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var playlists: [ProviderPlaylist] = []
        var seen = Set<Int>()
        for match in regex.matches(in: html, range: range) {
            guard match.numberOfRanges == 5,
                  let imageRange = Range(match.range(at: 1), in: html),
                  let nameRange = Range(match.range(at: 2), in: html),
                  let countRange = Range(match.range(at: 3), in: html),
                  let idRange = Range(match.range(at: 4), in: html),
                  let id = Int(html[idRange]),
                  !seen.contains(id) else { continue }
            let image = Self.decodeJSONStringValue(String(html[imageRange]))
            let name = Self.decodeJSONStringValue(String(html[nameRange]))
            let count = Int(html[countRange]) ?? 0
            guard !name.isEmpty else { continue }
            seen.insert(id)
            playlists.append(ProviderPlaylist(id: id, name: name, coverURL: Self.normalizedQQImageURL(image), trackCount: count, source: .qq))
            if playlists.count >= max(1, limit) { break }
        }
        if !playlists.isEmpty { return await enrichHotPlaylistCovers(playlists) }
        return try await recommendPlaylistsFallback(limit: limit)
    }

    /// 官网 SSR 为了懒加载通常只返回占位 data URI，使用歌单详情接口一次性补齐真实 logo。
    private func enrichHotPlaylistCovers(_ playlists: [ProviderPlaylist]) async -> [ProviderPlaylist] {
        let ids = playlists.map(\.id).map(String.init).joined(separator: ",")
        guard !ids.isEmpty else { return playlists }
        let url = "https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=\(ids)&loginUin=0&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
        guard let json = try? await get(url, referer: "https://y.qq.com/") else {
            return playlists
        }
        let cdlist = json["cdlist"] as? [[String: Any]] ?? []
        var covers: [Int: URL] = [:]
        for item in cdlist {
            let id = Self.integerValue(item["disstid"] ?? item["dissid"])
            if let cover = Self.normalizedQQImageURL(item["logo"]) ?? Self.normalizedQQImageURL(item["coveradurl"]) {
                covers[id] = cover
            }
        }
        let result = playlists.map { playlist -> ProviderPlaylist in
            var updated = playlist
            if let cover = covers[playlist.id] {
                updated.coverURL = cover
            }
            return updated
        }
        return result
    }

    /// QQ 推荐歌单 musicu 兜底接口
    private func recommendPlaylistsFallback(limit: Int = 12) async throws -> [ProviderPlaylist] {
        let payload: [String: Any] = [
            "comm": ["ct": 24, "cv": 0],
            "req_1": [
                "module": "music.srfDissInfo.RecommendPlaylist",
                "method": "GetRecommendPlaylist",
                "param": ["uin": 0, "lastDissid": 0, "songtype": 1, "scene": 0]
            ]
        ]
        let json = try await musicu(payload)
        let list = nestedArray(json, path: ["req_1", "data", "v_playlist"])
        var playlists: [ProviderPlaylist] = []
        for item in list {
            guard let id = item["tid"] as? Int ?? (item["id"] as? Int) else { continue }
            let name = item["title"] as? String ?? ""
            let pic = Self.normalizedQQImageURL(item["cover"]) ?? Self.normalizedQQImageURL(item["pic_url"])
            let songNum = item["songnum"] as? Int ?? 0
            playlists.append(ProviderPlaylist(id: id, name: name, coverURL: pic, trackCount: songNum, source: .qq))
        }
        return playlists
    }

    /// QQ 歌单内歌曲（主通道 fcg_ucc_getcdinfo_byids_cp，Mineradio 逆向；兜底 musicu GetPlaylistDetail）
    func playlistSongs(listID: Int, ownedDirectoryID: Int? = nil) async throws -> [ProviderSong] {
        if let ownedDirectoryID, (1..<200).contains(ownedDirectoryID),
           let credential = try await libraryCredential(), !credential.encryptedID.isEmpty {
            return try await ownedSongs(tid: listID, dirID: ownedDirectoryID, limit: .max, credential: credential)
        }
        return try await playlistSongsUnlimited(listID: listID)
    }

    private func playlistSongs(listID: Int, preferredCookie: String?, limit: Int) async throws -> [ProviderSong] {
        if listID == Self.qqLikedPlaylistID {
            return try await favoriteSongs(limit: limit)
        }
        let qqAuth = currentAuth
        let cookie = preferredCookie ?? (qqAuth.isLoggedIn ? qqAuth.playlistCookieHeader : "")
        let loginUins = (qqAuth.isLoggedIn ? qqAuth.playlistIdentityCandidates : ["0"])
            .reduce(into: [String]()) { result, value in
                if !result.contains(value) { result.append(value) }
            }
        for loginUin in loginUins {
            let detailURL = "https://c.y.qq.com/qzone/fcg-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=\(listID)&loginUin=\(loginUin)&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
            if let detailJson = try? await get(detailURL, referer: "https://y.qq.com/n/yqq/playlist", cookie: cookie),
               let cdlist = detailJson["cdlist"] as? [[String: Any]],
               let songlist = cdlist.first?["songlist"] as? [[String: Any]],
               !songlist.isEmpty {
                let songs = songlist.prefix(limit).compactMap { item -> ProviderSong? in
                    // 部分接口返回会把歌曲包在 track_info 里，先解包再走统一解析
                    let raw = (item["track_info"] as? [String: Any]) ?? item
                    return song(from: raw)
                }
                if !songs.isEmpty { return songs }
            }
        }
        // 兜底：musicu GetPlaylistDetail
        for loginUin in loginUins {
            let payload: [String: Any] = [
                "comm": ["ct": 24, "cv": 0, "uin": Int(loginUin) ?? 0, "g_tk": qqAuth.gtk, "platform": "yqq"],
                "req_1": [
                    "module": "music.playlist.PlayListDataServer",
                    "method": "GetPlaylistDetail",
                    "param": ["id": listID, "uin": Int(loginUin) ?? 0, "song_begin": 0, "song_num": limit]
                ]
            ]
            guard let json = try? await musicu(payload, cookie: cookie) else { continue }
            let list = nestedArray(json, path: ["req_1", "data", "songlist"])
            let songs = list.prefix(limit).compactMap { item -> ProviderSong? in
                let raw = (item["track_info"] as? [String: Any]) ?? item
                return song(from: raw)
            }
            if !songs.isEmpty { return songs }
        }
        return []
    }

    /// 加载 QQ 普通歌单的全部歌曲。QQ 单次接口最多返回约 300 首，
    /// 这里按 song_begin 分页，直到接口返回不足一页或没有新歌曲。
    private func playlistSongsUnlimited(listID: Int) async throws -> [ProviderSong] {
        if listID == Self.qqLikedPlaylistID {
            return try await favoriteSongs(limit: 0)
        }

        let pageSize = 300
        let firstPage = try await playlistSongs(listID: listID, preferredCookie: nil, limit: pageSize)
        guard firstPage.count >= pageSize else { return firstPage }

        let qqAuth = currentAuth
        let cookie = qqAuth.isLoggedIn ? qqAuth.playlistCookieHeader : ""
        let loginUin = qqAuth.playlistIdentityCandidates.first ?? "0"
        var songs = firstPage
        var seen = Set(firstPage.map(\.identityKey))
        var begin = firstPage.count

        while true {
            let detailURL = "https://c.y.qq.com/qzone/fcgi-bin/fcg_ucc_getcdinfo_byids_cp.fcg?type=1&json=1&utf8=1&onlysong=0&new_format=1&disstid=\(listID)&loginUin=\(loginUin)&hostUin=0&song_begin=\(begin)&song_num=\(pageSize)&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
            guard let detailJson = try? await get(detailURL, referer: "https://y.qq.com/n/yqq/playlist", cookie: cookie),
                  let cdlist = detailJson["cdlist"] as? [[String: Any]],
                  let songlist = cdlist.first?["songlist"] as? [[String: Any]],
                  !songlist.isEmpty else { break }

            let pageSongs = songlist.compactMap { item -> ProviderSong? in
                let raw = (item["track_info"] as? [String: Any]) ?? item
                return song(from: raw)
            }
            let newSongs = pageSongs.filter { seen.insert($0.identityKey).inserted }
            songs.append(contentsOf: newSongs)
            if songlist.count < pageSize || newSongs.isEmpty { break }
            begin += songlist.count
        }
        return songs
    }

    // Protocol references: ThirdPartyNotices/QQMusicProtocolReferences.md.
    /// Modern musicu endpoints retain the singer MID and report service errors.
    func artistHotSongs(mid: String?, name: String, limit: Int = 120) async throws -> [ProviderSong] {
        let mid = try await resolvedSingerMID(mid, name: name)
        var result: [ProviderSong] = []
        var seen = Set<String>()
        var begin = 0
        while result.count < limit {
            let count = min(100, limit - result.count)
            let data = try await operation("musichall.song_list_server", "GetSingerSongList",
                ["singerMid": mid, "order": 1, "begin": begin, "num": count])
            guard let list = data["songList"] as? [[String: Any]] else { throw ProviderRequestError.decoding("Singer song list") }
            let page = list.compactMap { song(from: ($0["songInfo"] as? [String: Any]) ?? $0) }
            let fresh = page.filter { seen.insert($0.identityKey).inserted }
            result += fresh
            begin += list.count
            if list.count < count || fresh.isEmpty { break }
        }
        return result
    }

    func artistAlbums(mid: String?, name: String, limit: Int = 30) async throws -> [ProviderAlbum] {
        let mid = try await resolvedSingerMID(mid, name: name)
        var result: [ProviderAlbum] = []
        var seen = Set<String>()
        var begin = 0
        while result.count < limit {
            let count = min(80, limit - result.count)
            let data = try await operation("music.musichallAlbum.AlbumListServer", "GetAlbumList",
                ["singerMid": mid, "order": 1, "begin": begin, "num": count])
            guard let list = data["albumList"] as? [[String: Any]] else { throw ProviderRequestError.decoding("Singer album list") }
            var added = 0
            for raw in list {
                let album = (raw["albumInfo"] as? [String: Any]) ?? raw
                let id = Self.text(album["albumMid"] ?? album["albumMID"] ?? album["mid"])
                let title = Self.text(album["albumName"] ?? album["name"])
                guard !id.isEmpty, !title.isEmpty, seen.insert(id).inserted else { continue }
                result.append(ProviderAlbum(id: id, name: title, artistName: name, coverURL: Self.photoURL(id),
                    source: .qq, trackCount: Int(Self.text(album["totalNum"] ?? album["songnum"] ?? album["songNum"])), releaseType: album["albumType"] as? String))
                added += 1
            }
            begin += list.count
            if list.count < count || added == 0 { break }
        }
        return result
    }

    func albumSongs(mid: String) async throws -> [ProviderSong] {
        let mid = Self.normalizedAlbumMID(mid)
        var result: [ProviderSong] = []
        var seen = Set<String>()
        var begin = 0
        while true {
            let data = try await operation("music.musichallAlbum.AlbumSongList", "GetAlbumSongList",
                ["albumMid": mid, "begin": begin, "num": 100, "order": 2])
            guard let list = (data["songList"] ?? data["songlist"]) as? [[String: Any]] else { throw ProviderRequestError.decoding("Album song list") }
            let page = list.compactMap { song(from: ($0["songInfo"] as? [String: Any]) ?? $0) }
            let fresh = page.filter { seen.insert($0.identityKey).inserted }
            result += fresh; begin += list.count
            if list.count < 100 || fresh.isEmpty { break }
        }
        return result
    }

    private func resolvedSingerMID(_ mid: String?, name: String) async throws -> String {
        if let mid, !mid.isEmpty, !mid.hasPrefix("qq-") { return mid }
        let candidates = try await searchArtists(keyword: name, limit: 20)
        guard let resolved = candidates.first(where: { $0.name == name && !$0.id.hasPrefix("qq-") && !$0.id.isEmpty }) else {
            throw ProviderRequestError.unknown("未取得歌手 MID，请重新搜索并打开歌手页面")
        }
        return resolved.id
    }

    static func normalizedAlbumMID(_ id: String) -> String {
        // Earlier releases persisted the legacy adapter's display identifier.
        if id.hasPrefix("qq-album-") {
            return String(id.dropFirst("qq-album-".count).split(separator: "-", maxSplits: 1).first ?? "")
        }
        return id
    }

    private static func text(_ value: Any?) -> String {
        if let value = value as? String { return value }
        return (value as? NSNumber)?.stringValue ?? ""
    }

    private func operation(_ module: String, _ method: String, _ param: [String: Any]) async throws -> [String: Any] {
        let auth = currentAuth
        let json = try await musicu(["comm": ["ct": 24, "cv": 0, "uin": Int(auth.uin) ?? 0, "g_tk": auth.gtk, "platform": "yqq"],
            "req_1": ["module": module, "method": method, "param": param]], cookie: auth.cookieHeader, timeout: 20)
        guard let block = json["req_1"] as? [String: Any], let data = block["data"] as? [String: Any] else { throw ProviderRequestError.decoding("Missing operation response") }
        let codes = [json["code"], block["code"], data["retCode"]].compactMap { Int(Self.text($0)) }
        if let code = codes.first(where: { $0 != 0 }) { throw ProviderRequestError.unknown("QQ 音乐操作失败（\(code)），请检查登录状态后重试") }
        return data
    }

    func createPlaylist(name: String, isPrivate: Bool) async throws -> ProviderPlaylist {
        let credential = try collectionCredential()
        let name = try Self.playlistName(name)
        var params: [String: Any] = ["dirName": name]
        if isPrivate { params["dirShow"] = 2 }
        let unconfirmed = ProviderRequestError.unknown("QQ 音乐尚未确认新歌单，请先刷新「我的歌单」，避免重复创建")
        let data: [String: Any]
        do {
            data = try await collectionOperation("music.musicasset.PlaylistBaseWrite", "AddPlaylist", params, credential: credential)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as ProviderRequestError {
            if case .unknown = error { throw error }
            throw unconfirmed
        } catch {
            try Task.checkCancellation()
            throw unconfirmed
        }
        guard let retCode = data["retCode"] as? Int else { throw unconfirmed }
        guard retCode == 0 else { throw ProviderRequestError.unknown("QQ 音乐创建歌单失败（\(retCode)）") }
        guard let result = data["result"] as? [String: Any],
              let tid = Int(Self.text(result["tid"])), tid > 0,
              let dirID = Int(Self.text(result["dirId"])), (1..<200).contains(dirID) else { throw unconfirmed }

        // Verify by both identifiers and display the canonical name from the owned list.
        for delay in [0, 250, 750] {
            if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
            let rows = try? await ownedPlaylistRows(credential: credential)
            try Task.checkCancellation()
            guard currentAuth.collectionCredential?.matchesLogin(credential) == true else { throw CancellationError() }
            let matches = rows?.filter { Self.text($0["tid"]) == String(tid) } ?? []
            guard matches.count == 1, let row = matches.first,
                  Self.integerValue(row["dirId"]) == dirID,
                  row["dirType"] == nil || Self.integerValue(row["dirType"]) == 0,
                  !isPrivate || Self.integerValue(row["dirShow"]) == 2,
                  var item = Self.playlist(fromQQDiss: row), item.id == tid else { continue }
            item.isOwned = true
            item.isSubscribed = false
            item.ownerID = currentAuth.uin
            return item
        }
        throw unconfirmed
    }

    private static func playlistName(_ name: String) throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 20,
              !name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) else {
            throw ProviderRequestError.unknown("QQ 音乐歌单名称须为 1 至 20 个字符，且不能包含换行或控制字符")
        }

        return name
    }

    private func ownedPlaylistDirectory(tid: Int, credential: QQMusicCollectionCredential) async throws -> Int {
        let matches = try await ownedPlaylistRows(credential: credential).filter { Self.integerValue($0["tid"]) == tid }
        guard matches.count == 1, let row = matches.first,
              let dirID = Int(Self.text(row["dirId"])), (1..<200).contains(dirID),
              row["dirType"] == nil || Self.integerValue(row["dirType"]) == 0 else {
            throw ProviderRequestError.unknown("只能修改当前 QQ 音乐账号的自建歌单")
        }
        return dirID
    }

    func deletePlaylist(tid: Int) async throws {
        let credential = try collectionCredential()
        let dirID = try await ownedPlaylistDirectory(tid: tid, credential: credential)
        let data = try await collectionOperation("music.musicasset.PlaylistBaseWrite", "DelPlaylist",
            ["dirId": dirID], credential: credential)
        try checkCollectionResult(data, key: "retCode")
        guard let result = data["result"] as? [String: Any],
              Self.integerValue(result["tid"]) == tid, Self.integerValue(result["dirId"]) == dirID,
              result["updateTime"] as? Int == 0 else { throw ProviderRequestError.decoding("QQ Music playlist deletion") }
        try await confirmCollection(true) {
            try await !self.ownedPlaylistRows(credential: credential).contains {
                Self.integerValue($0["tid"]) == tid || Self.integerValue($0["dirId"]) == dirID
            }
        }
    }

    func renamePlaylist(tid: Int, name: String) async throws -> String {
        let name = try Self.playlistName(name)
        let credential = try collectionCredential()
        let dirID = try await ownedPlaylistDirectory(tid: tid, credential: credential)
        func metadata() async throws -> QQPlaylistEditMetadata {
            let data = try await collectionOperation("music.srfDissInfo.aiDissInfo", "uniform_get_Dissinfo",
                ["dirid": dirID, "optype": 3, "tag": 1, "userinfo": 0, "pic_dpi": 300], credential: credential)
            guard let info = data["dirinfo"] as? [String: Any], Self.integerValue(info["dirid"]) == dirID,
                  let title = info["title"] as? String, let description = info["desc"] as? String,
                  let cover = info["picurl"] as? String, info["picurl2"] as? String == "",
                  let visibility = info["dir_show"] as? Int, [1, 2].contains(visibility),
                  let tags = info["tag"] as? [[String: Any]], tags.count <= 3 else {
                throw ProviderRequestError.decoding("QQ Music playlist metadata")
            }
            let ids = tags.compactMap { tag -> Int? in
                guard let id = tag["id"] as? Int, id > 0, tag["name"] is String else { return nil }
                return id
            }
            guard ids.count == tags.count else { throw ProviderRequestError.decoding("QQ Music playlist tags") }
            return .init(title: title, description: description, cover: cover, visibility: visibility, tags: ids)
        }
        let before = try await metadata()
        if before.title == name { return name }
        let data = try await collectionOperation("music.musicasset.PlaylistBaseWrite", "EditPlaylist",
            ["dirId": dirID, "mask": 95, "dirNewName": name, "dirNewDesc": before.description,
             "dirNewPicUrl": before.cover, "dirNewPicUrl2": "", "dirNewtaglist": before.tags.map(String.init).joined(separator: ","),
             "dirShow": before.visibility], credential: credential)
        try checkCollectionResult(data, key: "retCode")
        guard let result = data["result"] as? [String: Any],
              Self.integerValue(result["tid"]) == tid, Self.integerValue(result["dirId"]) == dirID else {
            throw ProviderRequestError.decoding("QQ Music playlist rename")
        }
        var expected = before
        expected.title = name
        try await confirmCollection(true) { try await metadata() == expected }
        return expected.title
    }

    private struct QQPlaylistEditMetadata: Equatable {
        var title: String
        let description: String
        let cover: String
        let visibility: Int
        let tags: [Int]
    }

    func updatePlaylistTracks(tid: Int, songIDs: [Int], adding: Bool) async throws {
        guard (1...100).contains(songIDs.count), songIDs.allSatisfy({ $0 > 0 }) else { throw MusicProviderError.missingTrack }
        let credential = try collectionCredential()
        let dirID = try await ownedPlaylistDirectory(tid: tid, credential: credential)
        let fields = songIDs.map { ["songId": $0, "songType": 0] }
        let data = try await collectionOperation("music.musicasset.PlaylistDetailWrite", adding ? "AddSonglist" : "DelSonglist",
            ["dirId": dirID, "v_songInfo": fields], credential: credential)
        try checkCollectionResult(data, key: "retCode")
        guard let result = data["result"] as? [String: Any] else {
            throw ProviderRequestError.decoding("QQ Music playlist track update")
        }
        let returnedDir = Int(Self.text(result["dirId"]))
        let returnedTID = Int(Self.text(result["tid"]))
        if returnedDir == dirID, returnedTID == tid { return }
        guard returnedDir == 0, returnedTID == 0,
              let library = try await libraryCredential(), library.matchesLogin(credential), !library.encryptedID.isEmpty else {
            throw ProviderRequestError.decoding("QQ Music playlist track update")
        }
        try await confirmCollection(true) {
            let ids = Set(try await self.ownedSongs(tid: tid, dirID: dirID, limit: .max, credential: library).map(\.id))
            return songIDs.allSatisfy { ids.contains($0) == adding }
        }
    }

    private func ownedPlaylistRows(credential: QQMusicCollectionCredential) async throws -> [[String: Any]] {
        let data = try await collectionOperation("music.musicasset.PlaylistBaseRead", "GetPlaylistByUin",
            ["uin": credential.id], credential: credential)
        guard let rows = data["v_playlist"] as? [[String: Any]] else {
            throw ProviderRequestError.decoding("QQ Music created playlists")
        }
        return rows
    }

    private func collectionCredential() throws -> QQMusicCollectionCredential {
        guard currentAuth.isLoggedIn else { throw NeteaseAPIError.needLogin }
        guard let credential = currentAuth.collectionCredential else {
            throw ProviderRequestError.unknown("缺少 QQ 音乐收藏凭证，请重新登录 QQ 音乐")
        }
        return credential
    }

    private func libraryCredential() async throws -> QQMusicCollectionCredential? {
        guard let credential = currentAuth.collectionCredential, credential.encryptedID.isEmpty else {
            return currentAuth.collectionCredential
        }
        // Web sessions saved by older Coda versions did not retain encryptUin.
        let url = "https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg?cid=205360838&ct=20&userid=0&reqfrom=1&reqtype=0&format=json"
        let json = try? await get(url, cookie: credential.cookie)
        try Task.checkCancellation()
        guard currentAuth.collectionCredential?.matchesLogin(credential) == true else { throw CancellationError() }
        guard Self.integerValue(json?["code"]) == 0, let data = json?["data"] as? [String: Any],
              let creator = data["creator"] as? [String: Any], let encryptedID = creator["encrypt_uin"] as? String,
              !encryptedID.isEmpty else { return credential }
        return .init(id: credential.id, key: credential.key, loginType: credential.loginType, encryptedID: encryptedID)
    }

    private func collectionOperation(_ module: String, _ method: String, _ params: [String: Any],
                                     credential: QQMusicCollectionCredential) async throws -> [String: Any] {
        guard currentAuth.collectionCredential?.matchesLogin(credential) == true else { throw CancellationError() }
        do {
            let data = try await collections.call(module, method, params, credential: credential) {
                self.currentAuth.collectionCredential?.matchesLogin(credential) == true
            }
            guard currentAuth.collectionCredential?.matchesLogin(credential) == true else { throw CancellationError() }
            return data
        } catch QQMusicSessionError.expired {
            // The key expired while the app was running; renew it once and repeat the request.
            let renewed = try await renewedCredential(after: credential)
            let data = try await collections.call(module, method, params, credential: renewed) {
                self.currentAuth.collectionCredential?.matchesLogin(renewed) == true
            }
            guard currentAuth.collectionCredential?.matchesLogin(renewed) == true else { throw CancellationError() }
            return data
        }
    }

    /// Renews an expired login; throws `.expired` when QQ gave no refresh token (re-scan needed).
    private func renewedCredential(after expired: QQMusicCollectionCredential) async throws -> QQMusicCollectionCredential {
        let auth = currentAuth
        let current = auth.collectionCredential
        if let current, current.id == expired.id, current.key != expired.key { return current }
        guard current?.matchesLogin(expired) == true else { throw CancellationError() }
        guard await auth.refreshCredentialIfNeeded(force: true, api: self), let renewed = auth.collectionCredential,
              renewed.id == expired.id, renewed.key != expired.key else { throw QQMusicSessionError.expired }
        return renewed
    }

    private func fanStatus(_ kind: String, _ method: String, id: String, fields: [String: Any],
                           credential: QQMusicCollectionCredential) async throws -> Bool {
        let data = try await collectionOperation("music.musicasset.\(kind)FavRead", method, fields, credential: credential)
        guard let fan = (data["m_fan"] as? [String: Any])?[id] as? NSNumber,
              CFGetTypeID(fan) == CFBooleanGetTypeID() else {
            throw ProviderRequestError.decoding("QQ Music \(method) status")
        }
        return fan.boolValue
    }

    private func checkCollectionResult(_ data: [String: Any], key: String = "result", failed: [String] = []) throws {
        guard let code = data[key] as? Int else { throw ProviderRequestError.decoding("QQ Music collection result") }
        guard code == 0 else { throw ProviderRequestError.unknown("QQ 音乐收藏失败（\(code)）") }
        for name in failed {
            guard let items = data[name] as? [Any] else { throw ProviderRequestError.decoding("QQ Music collection result") }
            guard items.isEmpty else { throw ProviderRequestError.unknown("QQ 音乐拒绝修改该收藏") }
        }
    }

    private func mutateCollection(_ target: Bool, state: () async throws -> Bool, write: () async throws -> Void) async throws {
        if try await state() == target { return }
        do {
            try await write()
        } catch let error as ProviderRequestError {
            // A truncated acknowledgment can arrive after the server committed the write.
            // Resolve it with an independent read and never send the mutation twice.
            switch error {
            case .decoding, .network:
                do { try await confirmCollection(target, state: state) }
                catch is CancellationError { throw CancellationError() }
                catch { throw error }
                return
            default: throw error
            }
        }
        try await confirmCollection(target, state: state)
    }

    private func confirmCollection(_ target: Bool, state: () async throws -> Bool) async throws {
        for delay in [0, 250, 750] {
            if delay > 0 { try await Task.sleep(for: .milliseconds(delay)) }
            do {
                if try await state() == target { return }
            } catch is CancellationError { throw CancellationError() }
            catch {
                if delay == 750 { throw error }
            }
        }
        throw ProviderRequestError.unknown("QQ 音乐尚未确认收藏变更，请刷新后查看")
    }

    func playlistSubscribed(id: Int) async throws -> Bool {
        try await playlistSubscribed(id: id, credential: collectionCredential())
    }

    private func playlistSubscribed(id: Int, credential: QQMusicCollectionCredential) async throws -> Bool {
        try await fanStatus("Playlist", "IsPlaylistFan", id: String(id), fields: ["v_tid": [id]], credential: credential)
    }

    func subscribePlaylist(id: Int, subscribe: Bool) async throws {
        let credential = try collectionCredential()
        func state() async throws -> Bool { try await playlistSubscribed(id: id, credential: credential) }
        try await mutateCollection(subscribe, state: state) {
            let data = try await collectionOperation("music.musicasset.PlaylistFavWrite", subscribe ? "FavPlaylist" : "CancelFavPlaylist",
                ["uin": credential.id, "v_playlistId": [id]], credential: credential)
            try checkCollectionResult(data, failed: ["v_failedPlaylistId"])
        }
    }

    func albumSubscribed(mid: String) async throws -> Bool {
        try await albumSubscribed(mid: Self.normalizedAlbumMID(mid), credential: collectionCredential())
    }

    private func albumSubscribed(mid: String, credential: QQMusicCollectionCredential) async throws -> Bool {
        try await fanStatus("Album", "IsAlbumFan", id: mid,
            fields: ["uin": credential.albumStatusOwner, "v_albumMid": [mid]], credential: credential)
    }

    func subscribeAlbum(mid: String, subscribe: Bool) async throws {
        let mid = Self.normalizedAlbumMID(mid)
        let credential = try collectionCredential()
        func state() async throws -> Bool { try await albumSubscribed(mid: mid, credential: credential) }
        try await mutateCollection(subscribe, state: state) {
            let data = try await collectionOperation("music.musicasset.AlbumFavWrite", subscribe ? "FavAlbum" : "CancelFavAlbum",
                ["uin": credential.id, "v_albumMid": [mid]], credential: credential)
            try checkCollectionResult(data, failed: ["v_failedAlbumId", "v_failedAlbumMid"])
        }
    }

    func favoriteAlbums() async throws -> [ProviderAlbum] {
        let credential = try collectionCredential()
        do {
            return try await favoriteAlbums(credential: credential)
        } catch QQMusicSessionError.expired {
            return try await favoriteAlbums(credential: try await renewedCredential(after: credential))
        }
    }

    private func favoriteAlbums(credential: QQMusicCollectionCredential) async throws -> [ProviderAlbum] {
        var albums: [ProviderAlbum] = []
        var seen = Set<String>()
        var offset = 0
        for _ in 0..<100 {
            let url = "https://c.y.qq.com/fav/fcgi-bin/fcg_get_profile_order_asset.fcg?ct=20&cid=205360956&userid=\(credential.id)&reqtype=2&sin=\(offset)&ein=\(offset + 99)&format=json"
            let json = try await get(url, cookie: credential.cookie)
            guard currentAuth.collectionCredential?.matchesLogin(credential) == true else { throw CancellationError() }
            if let code = json["code"] as? Int, QQMusicSessionError.isExpiredCode(code) { throw QQMusicSessionError.expired }
            try checkCollectionResult(json, key: "code")
            guard let data = json["data"] as? [String: Any], let rows = data["albumlist"] as? [[String: Any]] else {
                throw ProviderRequestError.decoding("QQ Music favorite albums")
            }
            let previous = albums.count
            for row in rows {
                let mid = Self.text(row["albummid"] ?? row["albumMid"] ?? row["mid"])
                let name = Self.text(row["albumname"] ?? row["albumName"] ?? row["title"] ?? row["name"])
                guard !mid.isEmpty, !name.isEmpty, seen.insert(mid).inserted else { continue }
                let singers = (row["singers"] ?? row["singer"]) as? [[String: Any]] ?? []
                let artist = singers.map { Self.text($0["name"] ?? $0["singername"]) }.filter { !$0.isEmpty }.joined(separator: " / ")
                let cover = URL(string: "https://y.gtimg.cn/music/photo_new/T002R500x500M000\(mid).jpg")
                albums.append(.init(id: mid, name: name, artistName: artist.isEmpty ? Self.text(row["singername"]) : artist,
                                    coverURL: cover, source: .qq, trackCount: Int(Self.text(row["songnum"]))))
            }
            offset += rows.count
            guard albums.count > previous, Self.integerValue(data["has_more"]) == 1 || offset < Self.integerValue(data["totalalbum"]) else { break }
        }
        return albums
    }

    func artistFollowed(mid: String, name: String? = nil) async throws -> Bool {
        let credential = try collectionCredential()
        let mid = try await resolvedSingerMID(mid, name: name ?? "")
        return try await artistFollowed(mid: mid, credential: credential)
    }

    private func artistOperation(_ method: String, _ params: [String: Any],
                                 credential: QQMusicCollectionCredential) async throws -> [String: Any] {
        let auth = currentAuth
        let saved = auth.exportedCredentials
        let extraNames = ["wxuin", "wxopenid", "p_uin", "p_skey", "skey", "eas_sid", "music_ignore_pskey", "login_type"]
        let extra = extraNames.compactMap { name in
            saved[name].flatMap { $0.isEmpty ? nil : "\(name)=\($0)" }
        }
        let cookie = ([credential.cookie, "tmeLoginType=\(credential.loginType)"] + extra).joined(separator: "; ")
        let token = QQMusicAuth.hash5381(saved["skey"].flatMap { $0.isEmpty ? nil : $0 } ?? credential.key)
        let data = try await collections.webArtistCall(method, params: params, credential: credential, webCookie: cookie, legacyToken: token) {
            auth.collectionCredential?.matchesLogin(credential) == true
        }
        guard auth.collectionCredential?.matchesLogin(credential) == true else { throw CancellationError() }
        return data
    }

    private func artistFollowed(mid: String, credential: QQMusicCollectionCredential) async throws -> Bool {
        let data = try await artistOperation("cgi_qry_concern_status",
            ["vec_userinfo": [["userid": mid, "usertype": 1]], "opertype": 5, "encrypt_singerid": 1], credential: credential)
        guard let values = data["map_singer_status"] as? [String: Any] else {
            throw ProviderRequestError.decoding("QQ Music singer follow status")
        }
        return (values[mid] as? NSNumber)?.boolValue ?? false
    }

    func followArtist(mid: String, follow: Bool, name: String? = nil) async throws {
        let credential = try collectionCredential()
        let mid = try await resolvedSingerMID(mid, name: name ?? "")
        func state() async throws -> Bool { try await artistFollowed(mid: mid, credential: credential) }
        try await mutateCollection(follow, state: state) {
            _ = try await artistOperation("cgi_concern_user_v2",
                ["opertype": follow ? 0 : 1, "source": 0, "userinfo": ["userid": mid, "usertype": 1], "encrypt_singerid": 1],
                credential: credential)
        }
    }

    func followedArtists() async throws -> [ProviderArtist] {
        let authenticated = try collectionCredential()
        let credential = try await libraryCredential() ?? authenticated
        var result: [ProviderArtist] = []
        var seen = Set<String>()
        var offset = 0
        for _ in 0..<100 {
            let data = try await collectionOperation("music.concern.RelationList", "GetFollowSingerList",
                ["HostUin": credential.encryptedID, "From": offset, "Size": 100], credential: credential)
            guard let list = data["List"] as? [[String: Any]] else { throw ProviderRequestError.decoding("QQ Music followed singers") }
            let previous = result.count
            for item in list {
                let mid = Self.text(item["MID"])
                guard !mid.isEmpty, seen.insert(mid).inserted else { continue }
                result.append(.init(id: mid, name: Self.text(item["Name"]), coverURL: Self.singerPhotoURL(mid), source: .qq))
            }
            offset += list.count
            guard result.count > previous, Self.integerValue(data["HasMore"]) == 1 else { break }
        }
        return result
    }

    /// 通用 QQ 歌曲解析（各接口字段略有差异，此处统一容错）
    private func song(from item: [String: Any]) -> ProviderSong? {
        let mid = item["songmid"] as? String ?? (item["mid"] as? String ?? "")
        let sid = item["songid"] as? Int ?? (item["id"] as? Int ?? 0)
        guard !mid.isEmpty || sid > 0 else { return nil }
        let singers = (item["singer"] as? [[String: Any]]) ?? (item["songer"] as? [[String: Any]]) ?? []
        let artists = singers.compactMap { $0["name"] as? String }.joined(separator: " / ")
        let albumDict = item["album"] as? [String: Any] ?? [:]
        let albumName = albumDict["name"] as? String ?? (item["albumname"] as? String ?? "")
        let albumMid = albumDict["mid"] as? String ?? (item["albummid"] as? String ?? "")
        let interval = item["interval"] as? Int ?? 0
        let pay = item["pay"] as? [String: Any]
        let fee = (item["fee"] as? Int) ?? (pay?["pay_play"] as? Int) ?? (pay?["payplay"] as? Int) ?? 0
        let file = item["file"] as? [String: Any]
        let mediaMid = file?["media_mid"] as? String
            ?? item["strMediaMid"] as? String
            ?? item["media_mid"] as? String
        return ProviderSong(
            id: sid,
            name: item["songname"] as? String ?? (item["name"] as? String ?? ""),
            artists: artists,
            album: albumName,
            coverURL: Self.photoURL(albumMid.isEmpty ? nil : albumMid),
            duration: TimeInterval(interval),
            source: .qq,
            qqMid: mid.isEmpty ? nil : mid,
            qqMediaMid: mediaMid,
            qqAlbumMID: albumMid.isEmpty ? nil : albumMid,
            qqArtistReferences: singers.compactMap { row in
                guard let mid = (row["mid"] ?? row["singermid"]) as? String, !mid.isEmpty,
                      let name = row["name"] as? String else { return nil }
                return .init(id: mid, name: name, coverURL: Self.singerPhotoURL(mid), source: .qq)
            },
            fee: fee
        )
    }

    // MARK: - 工具

    private static func elapsed(_ start: Date) -> String {
        String(format: "%.3fs", Date().timeIntervalSince(start))
    }

    private func nestedArray(_ json: [String: Any], path: [String]) -> [[String: Any]] {
        var current: Any = json
        for key in path {
            if let dict = current as? [String: Any] {
                current = dict[key] ?? [:]
            } else {
                return []
            }
        }
        return (current as? [[String: Any]]) ?? []
    }
}

/// 可播种随机数生成器（用于每日推荐按日期确定性打乱，同一天内刷新结果一致）
private struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        return state
    }
}
