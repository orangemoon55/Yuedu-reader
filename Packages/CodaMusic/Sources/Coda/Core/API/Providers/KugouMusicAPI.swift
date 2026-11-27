// Adapted from XIaodou0416/Beans-Music (MIT); see ThirdPartyNotices/Beans-Music.md.
import Foundation
import Security
import CommonCrypto

final class KugouMusicAPI {
    static let shared = KugouMusicAPI()

    private let gateway = "https://gateway.kugou.com"
    private let loginBase = "https://login-user.kugou.com"
    private let userService = "https://userservice.kugou.com"
    // Keep the app's existing login flow, but use the current public KuGouMusicApi
    // request profile for search, recommendations, charts, FM, and playback.
    private let upstreamAppID = "1005"
    private let upstreamClientVersion = "20489"
    private let upstreamSignSalt = "OIlwieks28dk2k092lksi2UIkp"
    private let appid = "3116"
    private let clientver = "11440"
    private let qrAppid = "1001"
    private let qrSrcAppid = "2919"
    private let androidSignKey = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
    private let webSignKey = "NVPh5oo715z5DIWAeQlhMDsWXXQV4hwt"
    private let playSalt = "kgcloudv2"
    private let androidUA = "Android15-1070-11440-46-0-DiscoveryDRADProtocol-wifi"
    private let rsaPublicKeyBase64 = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDECi0Np2UR87scwrvTr72L6oO01rBbbBPriSDFPxr3Z5syug0O24QyQO8bg27+0+4kBzTBTBOZ/WWU0WryL1JSXRTXLgFVxtzIY41Pe7lPOgsfTCn5kZcvKhYKJesKnnJDNr5/abvTGf+rHG3YRwsCHcQ08/q6ifSioBszvb3QiwIDAQAB"

    private let session: URLSession
    private let playbackCredentials: [String: String]?
    private let playlistCredentials: [String: String]?
    private var registeredPlaylistDFID: String?

    init(configuration: URLSessionConfiguration? = nil, playbackCredentials: [String: String]? = nil, playlistCredentials: [String: String]? = nil) {
        self.playbackCredentials = playbackCredentials
        self.playlistCredentials = playlistCredentials
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 18
        config.httpShouldSetCookies = false
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        session = URLSession(configuration: config)
    }

    struct QRLogin: Equatable {
        let key: String
        let url: String
    }

    enum QRState: Equatable {
        case waiting
        case scanned
        case expired
        case success([String: String])
        case error(String)
    }

    func qrKey() async throws -> QRLogin {
        KugouMusicAuth.shared.prepareDevice()
        let qrcodeText = "https://h5.kugou.com/apps/loginQRCode/html/index.html?appid=\(appid)&"
        let response = try await gatewayRequest(
            "/v2/qrcode",
            baseURL: loginBase,
            signType: .web,
            params: [
                "appid": qrAppid,
                "type": "1",
                "plat": "4",
                "qrcode_txt": qrcodeText,
                "srcappid": qrSrcAppid,
            ],
            headers: [
                "User-Agent": Self.browserUA,
                "x-router": "login-user.kugou.com",
            ]
        )
        let json = response.json
        let key = Self.deepString(json, names: ["qrcode", "key"])
        guard !key.isEmpty else { throw ProviderRequestError.unknown("酷狗二维码生成失败") }
        return QRLogin(key: key, url: "https://h5.kugou.com/apps/loginQRCode/html/index.html?qrcode=\(Self.urlEncode(key))")
    }

    func pollQR(key: String) async throws -> QRState {
        let response = try await gatewayRequest(
            "/v2/get_userinfo_qrcode",
            baseURL: loginBase,
            signType: .web,
            params: [
                "plat": "4",
                "appid": appid,
                "srcappid": qrSrcAppid,
                "qrcode": key,
            ],
            headers: [
                "User-Agent": Self.browserUA,
                "x-router": "login-user.kugou.com",
            ]
        )
        try Task.checkCancellation()
        let json = response.json
        let status = Self.deepInt(json, names: ["status"])
        let token = Self.deepString(json, names: ["token", "user_token", "access_token", "key"])
        let userId = Self.deepString(json, names: ["userid", "user_id", "uid", "kugooid", "kugouid"]).filter(\.isNumber)
        guard !token.isEmpty, !userId.isEmpty else {
            if status == 2 { return .scanned }
            if status == 3 { return .expired }
            return .waiting
        }
        let nick = Self.deepString(json, names: ["nickname", "nick", "username", "user_name", "uname"])
        let avatar = Self.deepString(json, names: ["avatar", "pic", "img", "headpic", "user_pic", "userpic"])
        let vip = Self.deepInt(json, names: ["vip_type", "vipType", "viptype", "isvip", "is_vip", "vip"])
        try Task.checkCancellation()
        var credentials = KugouMusicAuth.shared.exportedCredentials
        credentials["userid"] = userId
        credentials["token"] = token
        credentials["nickname"] = nick.isEmpty ? "酷狗音乐用户 \(userId)" : nick
        credentials["avatar"] = avatar
        credentials["vipType"] = "\(vip)"
        return .success(credentials)
    }

    func loginValidity(credentials: [String: String]) async throws -> MusicAccountValidity {
        let uid = credentials["userid"] ?? credentials["user_id"] ?? ""
        guard !uid.isEmpty, let token = credentials["token"], !token.isEmpty else { return .invalid }
        let mid = credentials["KUGOU_API_MID"] ?? credentials["mid"] ?? "-"
        let dfid = credentials["dfid"] ?? credentials["DFID"] ?? "-"
        var params = ["appid": appid, "clientver": clientver,
                      "clienttime": "\(Int(Date().timeIntervalSince1970))", "mid": mid,
                      "dfid": dfid, "uuid": "-", "userid": uid, "token": token, "module_id": "51"]
        params["signature"] = androidSignature(params: params, data: "")
        let result = try await request("/v1/user_verify", baseURL: gateway, method: "GET", params: params, body: nil,
                                       headers: ["User-Agent": androidUA, "mid": mid, "dfid": dfid,
                                                 "x-router": "trackercdngz.kugou.com"])
        guard Self.int(result.json["status"]) == 1,
              let data = result.json["data"] as? [String: Any], let valid = data["valid"] else { return .unknown }
        let flag = (valid as? NSNumber)?.intValue ?? (valid as? String).flatMap(Int.init)
        switch flag {
        case 1: return .valid
        case 0: return .invalid
        default: return .unknown
        }
    }

    func membershipStatus(credentials: [String: String]) async throws -> MusicMembership {
        let mid = credentials["KUGOU_API_MID"] ?? credentials["mid"] ?? "-"
        let dfid = credentials["dfid"] ?? credentials["DFID"] ?? "-"
        // Build from this saved account only, without swapping the active
        // playback session or including another account's cookie.
        var params: [String: String] = [
            "appid": appid, "clientver": clientver, "clienttime": "\(Int(Date().timeIntervalSince1970))",
            "mid": mid, "dfid": dfid, "uuid": "-", "busi_type": "concept",
            "product_type": "svip", "opt_product_types": "dvip,qvip",
            "userid": credentials["userid"] ?? credentials["user_id"] ?? "", "token": credentials["token"] ?? ""
        ]
        params["signature"] = androidSignature(params: params, data: "")
        let result = try await request("/v1/get_union_vip", baseURL: "https://kugouvip.kugou.com", method: "GET", params: params, body: nil,
                                       headers: ["User-Agent": androidUA, "mid": mid, "dfid": dfid])
        return MusicMembership.kugou(result.json)
    }

    func userPlaylists() async throws -> [ProviderPlaylist] {
        let auth = KugouMusicAuth.shared
        guard auth.isLoggedIn else { return [] }
        let dataBody: [String: Any] = [
            "total_ver": 979,
            "type": 2,
            "page": 1,
            "pagesize": 200,
            "userid": Int(auth.userId) ?? 0,
            "token": auth.token,
        ]
        let response = try await gatewayRequest(
            "/v7/get_all_list",
            method: "POST",
            params: [
                "total_ver": "979",
                "type": "2",
                "page": "1",
                "pagesize": "200",
                "userid": auth.userId,
                "token": auth.token,
            ],
            data: dataBody,
            headers: ["x-router": "cloudlist.service.kugou.com"]
        )
        let json = response.json
        let code = Self.deepInt(json, names: ["error_code", "errcode", "code"])
        let status = Self.deepInt(json, names: ["status"])
        guard code == 0 || code == 200, status != 0 else { throw ProviderRequestError.unknown("酷狗歌单读取失败，请检查登录凭证后重试") }
        let raw = Self.deepArrays(json, names: ["lists", "list", "info", "data", "listinfo", "collection_list", "playlist"])
        var seen = Set<Int>()
        return raw.compactMap { item in
            guard let playlist = Self.mapPlaylist(item, accountUserID: auth.userId), !seen.contains(playlist.id) else { return nil }
            seen.insert(playlist.id)
            return playlist
        }
    }

    // Protocol reference: MakcRe/KuGouMusicApi module/playlist_{add,tracks_add,del}.js.
    static func validatePlaylistMutation(_ json: [String: Any]) throws {
        let code = int(json["error_code"] ?? json["errcode"] ?? json["code"])
        guard int(json["status"]) == 1, code == 0 || code == 200 else {
            let message = string(json["error_msg"] ?? json["err_msg"] ?? json["msg"] ?? json["message"])
            throw ProviderRequestError.unknown(message.isEmpty ? "酷狗歌单操作失败（\(code)）" : message)
        }
    }

    static func createdPlaylistID(_ json: [String: Any]) throws -> Int {
        try validatePlaylistMutation(json)
        let data = json["data"] as? [String: Any] ?? json
        let info = data["info"] as? [String: Any] ?? (data["info"] as? [[String: Any]])?.first ?? data
        let id = int(info["listid"] ?? info["id"])
        guard id > 0 else { throw ProviderRequestError.unknown("酷狗未返回新歌单编号，请刷新歌单列表") }
        return id
    }

    private struct PlaylistIdentity {
        let userId: String
        let token: String
        let mid: String
        let dfid: String
        var cookieHeader: String { "userid=\(userId); token=\(token); KUGOU_API_MID=\(mid); dfid=\(dfid)" }
    }

    private var playlistIdentity: PlaylistIdentity {
        let credentials = playlistCredentials ?? KugouMusicAuth.shared.exportedCredentials
        return PlaylistIdentity(userId: credentials["userid"] ?? "", token: credentials["token"] ?? "",
            mid: credentials["KUGOU_API_MID"] ?? credentials["mid"] ?? "-",
            dfid: registeredPlaylistDFID ?? credentials["dfid"] ?? credentials["DFID"] ?? "-")
    }

    private func requirePlaylistLogin() throws {
        let auth = playlistIdentity
        guard !auth.userId.isEmpty, !auth.token.isEmpty else {
            throw ProviderRequestError.unknown("请先登录酷狗音乐")
        }
    }

    private func preparePlaylistDevice() async throws {
        try requirePlaylistLogin()
        if playlistCredentials == nil { KugouMusicAuth.shared.prepareDevice() }
        if playlistIdentity.dfid.isEmpty || playlistIdentity.dfid == "-" { try await registerDevice() }
        guard !playlistIdentity.dfid.isEmpty, playlistIdentity.dfid != "-" else {
            throw ProviderRequestError.unknown("酷狗设备注册失败，请稍后重试")
        }
    }

    func createPlaylist(name: String, isPrivate: Bool, source: ProviderPlaylist? = nil) async throws -> ProviderPlaylist {
        try await preparePlaylistDevice()
        let auth = playlistIdentity
        var body: [String: Any] = [
            "userid": Int(auth.userId) ?? 0, "token": auth.token, "total_ver": 0,
            "name": name, "type": source == nil ? 0 : 1, "source": 1,
            "is_pri": isPrivate ? 1 : 0, "from_shupinmv": 0,
            "list_create_userid": source?.kugouCreateUserID ?? auth.userId,
            "list_create_listid": source?.kugouCreateListID ?? "0",
            "list_create_gid": source?.kugouCreateGID ?? ""
        ]
        if source != nil { body["is_pri"] = 0 }
        let json = try await cloudlistRequest("/v5/add_list",
            params: ["last_time": "\(Int(Date().timeIntervalSince1970))", "last_area": "gztx"], data: body)
        try Self.validatePlaylistMutation(json)
        let id = try Self.createdPlaylistID(json)
        var item = ProviderPlaylist(id: id, name: name, coverURL: source?.coverURL, trackCount: source?.trackCount ?? 0, source: .kugou)
        item.ownerID = auth.userId
        item.isOwned = source == nil
        item.isSubscribed = source != nil
        item.kugouGlobalCollectionID = source?.kugouGlobalCollectionID
        item.kugouCreateUserID = source?.kugouCreateUserID ?? auth.userId
        item.kugouCreateListID = source?.kugouCreateListID ?? String(id)
        item.kugouCreateGID = source?.kugouCreateGID
        return item
    }

    static func playlistSongResource(_ song: ProviderSong) throws -> [String: Any] {
        guard song.source == .kugou, let hash = song.kugouHash, !hash.isEmpty else {
            throw MusicProviderError.missingTrack
        }
        return ["number": 1, "name": song.artists.isEmpty ? song.name : "\(song.artists) - \(song.name)",
                "hash": hash, "size": 0, "sort": 0, "timelen": 0, "bitrate": 0,
                "album_id": Int(song.kugouAlbumId ?? "") ?? 0,
                "mixsongid": Int(song.kugouAlbumAudioId ?? "") ?? 0]
    }

    func addSongs(listID: Int, songs: [ProviderSong]) async throws {
        try await preparePlaylistDevice()
        guard !songs.isEmpty else { return }
        let auth = playlistIdentity
        let resources = try songs.map(Self.playlistSongResource)
        let json = try await cloudlistRequest("/v6/add_song",
            params: ["last_time": "\(Int(Date().timeIntervalSince1970))", "last_area": "gztx"],
            data: ["userid": Int(auth.userId) ?? 0, "token": auth.token, "listid": listID,
                   "list_ver": 0, "type": 0, "slow_upload": 1, "scene": "false;null", "data": resources])
        try Self.validatePlaylistMutation(json)
    }

    func collectionSource(_ playlist: ProviderPlaylist) async throws -> ProviderPlaylist {
        if !(playlist.kugouCreateUserID ?? "").isEmpty, !(playlist.kugouCreateListID ?? "").isEmpty { return playlist }
        var globalID = playlist.kugouGlobalCollectionID ?? ""
        // Website songlist links carry an encoded share ID (gcid_*). The
        // collection endpoint only accepts the canonical ID in specialInfo.
        if globalID.isEmpty || globalID.hasPrefix("gcid_") {
            let html = try await getString(URL(string: "https://www.kugou.com/yy/special/single/\(playlist.id).html")!, ua: Self.browserUA)
            let info = Self.javascriptJSON(named: "specialInfo", in: html, opening: "{", closing: "}") as? [String: Any]
            globalID = Self.string(info?["global_collection_id"])
        }
        guard !globalID.isEmpty, !globalID.hasPrefix("gcid_") else { throw ProviderRequestError.unknown("未能获取酷狗歌单收藏信息，请刷新后重试") }
        let auth = KugouMusicAuth.shared
        let response = try await upstreamRequest("/v3/get_list_info", method: "POST",
            data: ["data": [["global_collection_id": globalID]], "userid": Int(auth.userId) ?? 0, "token": auth.token],
            headers: ["x-router": "pubsongs.kugou.com"])
        try Self.validatePlaylistMutation(response.json)
        let rows = Self.deepArrays(response.json, names: ["info", "list", "data"])
        guard let raw = rows.first(where: { Self.string($0["global_collection_id"]) == globalID }) ?? rows.first else {
            throw ProviderRequestError.unknown("酷狗歌单收藏信息为空")
        }
        var result = playlist
        result.kugouGlobalCollectionID = globalID
        result.kugouCreateUserID = Self.string(raw["list_create_userid"] ?? raw["create_userid"] ?? raw["userid"])
        result.kugouCreateListID = Self.string(raw["list_create_listid"] ?? raw["create_listid"] ?? raw["listid"])
        result.kugouCreateGID = Self.string(raw["list_create_gid"] ?? raw["create_gid"])
        guard !(result.kugouCreateUserID ?? "").isEmpty, !(result.kugouCreateListID ?? "").isEmpty else {
            throw ProviderRequestError.unknown("酷狗未返回歌单创建者信息")
        }
        return result
    }

    func unsubscribePlaylist(listID: Int) async throws {
        try await preparePlaylistDevice()
        let auth = playlistIdentity
        guard let password = Self.randomLower(6) else { throw ProviderRequestError.network }
        let data = try JSONSerialization.data(withJSONObject: ["listid": listID, "total_ver": 0, "type": 1])
        let credentials = try JSONSerialization.data(withJSONObject: ["aes": password, "uid": Int(auth.userId) ?? 0, "token": auth.token])
        let key = rsaPublicKeyBase64
        guard let encrypted = Self.aesCBCEncrypt(data, password: password),
              let rsa = Self.rsaEncryptPKCS1(credentials, publicKeyBase64: key) else { throw ProviderRequestError.network }
        let timestamp = "\(Int(Date().timeIntervalSince1970))"
        let response = try await playlistRequest("/v2/delete_list",
            params: ["clienttime": timestamp, "key": "\(appid)\(androidSignKey)\(clientver)\(timestamp)".kgMD5Hex, "last_area": "gztx", "last_time": timestamp, "p": rsa.kgHexString.uppercased()],
            // The endpoint accepts a base64 ciphertext body, not a JSON string.
            dataRaw: Data(encrypted.base64EncodedString().utf8),
            headers: ["x-router": "cloudlist.service.kugou.com", "Content-Type": "application/json"])
        let json = (Self.aesCBCDecrypt(response.rawData, password: password)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? response.json
        try Self.validatePlaylistMutation(json)
    }

    /// 酷狗私人漫游：使用 KuGouMusicApi 的 personal_fm 请求协议，连续取几批推荐，
    /// 让首页不会被固定在首批三首歌曲。
    func personalFM(limit: Int = 12) async throws -> [ProviderSong] {
        let auth = KugouMusicAuth.shared
        guard auth.isLoggedIn else { return [] }
        auth.prepareDevice()

        let target = max(limit, 1)
        var songs: [ProviderSong] = []
        var seen = Set<String>()
        var lastHash: String?
        var lastSongID: String?
        let batchCount = max(1, min(8, Int(ceil(Double(target) / 3.0)) + 1))

        for _ in 0..<batchCount {
            let clientTime = Int(Date().timeIntervalSince1970 * 1000)
            var data: [String: Any] = [
                "appid": upstreamAppID,
                "clienttime": clientTime,
                "mid": auth.mid,
                "action": "play",
                "recommend_source_locked": 0,
                "song_pool_id": 0,
                "callerid": 0,
                "m_type": 1,
                "platform": "ios",
                "area_code": 1,
                "remain_songcnt": 0,
                "clientver": upstreamClientVersion,
                "is_overplay": lastHash == nil ? 0 : 1,
                "mode": "normal",
                "fakem": "ca981cfc583a4c37f28d2d49000013c16a0a",
                "key": upstreamParamsKey("\(clientTime)"),
            ]
            if !auth.userId.isEmpty {
                data["userid"] = Int(auth.userId) ?? 0
                data["kguid"] = Int(auth.userId) ?? 0
            }
            if !auth.token.isEmpty { data["token"] = auth.token }
            if auth.vipType > 0 { data["vip_type"] = auth.vipType }
            if let lastHash { data["hash"] = lastHash }
            if let lastSongID { data["songid"] = lastSongID }
            if let lastHash, let lastSongID {
                data["playtime"] = max(0, Int(songs.last?.duration ?? 0))
                data["hash"] = lastHash
                data["songid"] = lastSongID
            }

            let response = try await upstreamRequest(
                "/v2/personal_recommend",
                method: "POST",
                data: data,
                headers: ["x-router": "persnfm.service.kugou.com"]
            )
            let rows = Self.deepArrays(
                response.json,
                names: ["songs", "song", "songlist", "list", "data", "recommend", "recommend_list", "recommend_song", "personal_fm", "result"]
            )
            let batch = rows.compactMap(Self.mapCompleteTrack)
            if batch.isEmpty {
                break
            }
            for song in batch where seen.insert(song.identityKey).inserted {
                songs.append(song)
                if songs.count >= target { return Array(songs.prefix(target)) }
            }
            lastHash = batch.last?.kugouHash
            lastSongID = batch.last?.kugouAlbumAudioId
            if lastHash == nil && lastSongID == nil { break }
        }

        // Keep the feature usable when the personal-FM service returns an empty
        // payload for a valid login by falling back to Kugou daily suggestions.
        if songs.isEmpty,
           let fallback = try? await everydayRecommend(limit: target),
           !fallback.isEmpty {
            return Array(fallback.prefix(target))
        }
        return songs
    }

    /// 酷狗每日推荐，替代首页原先用“热门歌曲”搜索模拟推荐的方式。
    func everydayRecommend(limit: Int = 30) async throws -> [ProviderSong] {
        KugouMusicAuth.shared.prepareDevice()
        let response = try await upstreamRequest(
            "/everyday_song_recommend",
            method: "POST",
            params: ["platform": "ios"],
            headers: ["x-router": "everydayrec.service.kugou.com"]
        )
        let rows = Self.deepArrays(
            response.json,
            names: ["songs", "songlist", "list", "data", "recommend", "recommend_list"]
        )
        return Array(rows.compactMap(Self.mapCompleteTrack).prefix(max(limit, 1)))
    }

    /// 酷狗手机版首页的歌曲推荐卡片。
    enum SongCard: Int, CaseIterable, Sendable {
        case forYou = 1, classics = 2, hot = 3, hiddenGems = 4, vip = 6
    }

    /// 歌曲推荐卡片。未登录也能返回，登录后“专属好歌”按账号推荐。
    func cardSongs(_ card: SongCard, limit: Int = 30) async throws -> [ProviderSong] {
        let auth = KugouMusicAuth.shared
        let clientTime = Int(Date().timeIntervalSince1970 * 1000)
        let fakem = "60f7ebf1f812edbac3c63a7310001701760f"
        let response = try await upstreamRequest(
            "/singlecardrec.service/v1/single_card_recommend",
            method: "POST",
            params: ["card_id": "\(card.rawValue)", "fakem": fakem, "area_code": "1", "platform": "ios"],
            data: [
                "appid": Int(upstreamAppID) ?? 1005, "clientver": Int(upstreamClientVersion) ?? 20489,
                "platform": "android", "clienttime": clientTime, "userid": Int(auth.userId) ?? 0,
                "key": upstreamParamsKey("\(clientTime)"), "fakem": fakem, "area_code": 1, "mid": auth.mid,
                "uuid": "-", "client_playlist": [], "u_info": "a0c35cd40af564444b5584c2754dedec",
            ]
        )
        guard let data = response.json["data"] as? [String: Any],
              let rows = data["song_list"] as? [[String: Any]] else {
            throw ProviderRequestError.decoding("酷狗推荐卡片数据格式异常")
        }
        return Self.uniqueSongs(rows.compactMap(Self.mapCompleteTrack), limit: limit)
    }

    /// 新歌速递（酷狗手机版首页同名模块）。
    func newSongs(page: Int = 1, limit: Int = 30) async throws -> [ProviderSong] {
        let response = try await upstreamRequest(
            "/musicadservice/container/v1/newsong_publish",
            method: "POST",
            data: ["rank_id": 21608, "userid": Int(KugouMusicAuth.shared.userId) ?? 0,
                   "page": max(page, 1), "pagesize": min(max(limit, 1), 30), "tags": []]
        )
        guard let rows = response.json["data"] as? [[String: Any]] else {
            throw ProviderRequestError.decoding("酷狗新歌速递数据格式异常")
        }
        return Self.uniqueSongs(rows.compactMap(Self.mapCompleteTrack), limit: limit)
    }

    private static func uniqueSongs(_ songs: [ProviderSong], limit: Int) -> [ProviderSong] {
        var seen = Set<String>()
        return Array(songs.filter { seen.insert($0.identityKey).inserted }.prefix(max(limit, 1)))
    }

    /// 酷狗自有移动端搜索接口：搜索结果携带 hash、专辑和封面，可直接复用酷狗播放地址解析。
    /// 优先使用 KuGouMusicApi 的 v2/search/song，现有综合搜索和网页接口作为兜底。
    func searchSongs(keyword: String, limit: Int = 30) async throws -> [ProviderSong] {
        if let upstream = try? await upstreamSearchSongs(keyword: keyword, limit: limit), !upstream.isEmpty {
            return upstream
        }
        if let complete = try? await searchSongsComplete(keyword: keyword, limit: limit), !complete.isEmpty {
            return complete
        }

        var components = URLComponents(string: "https://songsearch.kugou.com/song_search_v2")!
        components.queryItems = [
            URLQueryItem(name: "keyword", value: keyword),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "pagesize", value: "\(min(max(limit, 1), 100))"),
        ]
        guard let url = components.url else {
            throw ProviderRequestError.unknown("酷狗搜索地址无效")
        }
        let json = try await getJSON(url, ua: Self.browserUA)
        let raw = Self.deepArrays(json, names: ["info", "songs", "song", "list", "data"])
        let songs = raw.compactMap(Self.mapTrack)
        return songs
    }

    private func upstreamSearchSongs(keyword: String, limit: Int) async throws -> [ProviderSong] {
        let pageSize = min(max(limit, 1), 30)
        // The upstream endpoint commonly returns 15 rows even when pagesize is 30.
        // Keep paging in that case so artist pages do not stop at the first 15 songs.
        let pageCount = max(1, min(40, Int(ceil(Double(max(limit, 1)) / 15.0)) + 2))
        var result: [ProviderSong] = []
        var seen = Set<String>()
        for page in 1...pageCount {
            let response = try await upstreamRequest(
                "/v2/search/song",
                params: [
                    "privilegefilter": "0",
                    "area_code": "1",
                    "dopicfull": "1",
                    "iscorrection": "1",
                    "keyword": keyword,
                    "nocollect": "0",
                    "page": "\(page)",
                    "pagesize": "\(pageSize)",
                    "platform": "AndroidFilter",
                ],
                headers: ["x-router": "complexsearch.kugou.com"]
            )
            let rows = Self.deepArrays(
                response.json,
                names: ["lists", "info", "songs", "song", "list", "data"]
            )
            let batch = rows.compactMap(Self.mapCompleteTrack)
            if batch.isEmpty { break }
            let before = result.count
            for song in batch where seen.insert(song.identityKey).inserted {
                result.append(song)
                if result.count >= limit { return Array(result.prefix(limit)) }
            }
            if result.count == before { break }
        }
        return result
    }

    /// 酷狗 iOS 综合搜索接口。该接口返回的结果比旧网页接口完整，
    /// 同时携带歌曲 hash、专辑、歌手、封面和权限字段。
    private func searchSongsComplete(keyword: String, limit: Int) async throws -> [ProviderSong] {
        var result: [ProviderSong] = []
        var seen = Set<String>()
        let pageSize = min(max(limit, 1), 50)
        // 综合搜索接口经常固定只返回 15 条，即使 pagesize 请求更大；
        // 不要用 songs.count < pageSize 判断分页结束，否则歌手页永远只得到首屏。
        let pages = max(1, min(30, Int(ceil(Double(min(max(limit, 1), 300)) / 15.0)) + 2))
        for page in 1...pages {
            let songs = try await searchSongsCompletePage(keyword: keyword, page: page, pageSize: pageSize)
            guard !songs.isEmpty else { break }
            let before = result.count
            for song in songs where seen.insert(song.identityKey).inserted {
                result.append(song)
                if result.count >= limit { return result }
            }
            if result.count == before { break }
        }
        return result
    }

    private func searchSongsCompletePage(keyword: String, page: Int, pageSize: Int) async throws -> [ProviderSong] {
        let auth = KugouMusicAuth.shared
        auth.prepareDevice()
        let clientTime = "\(Int(Date().timeIntervalSince1970))"
        let userID = auth.isLoggedIn ? auth.userId : "0"
        let token = auth.isLoggedIn ? auth.token : ""
        let mid = auth.mid
        let dfid = auth.dfid
        let uuid = auth.guid.isEmpty ? mid : auth.guid
        var params: [String: String] = [
            "ab_tag": "1",
            "ability": "57343",
            "albumhide": "1",
            "apiver": "22",
            "appid": "1000",
            "area_code": "1",
            "clienttime": clientTime,
            "clientver": "20549",
            "com_user_type": "0",
            "cursor": "\(max(page, 1))",
            "dfid": dfid,
            "is_gpay": "0",
            "iscorrection": "1",
            "keyword": keyword,
            "mid": mid,
            "mode_ability": "0",
            "nocollect": "0",
            "osversion": "16.0",
            "platform": "IOSFilter",
            "recver": "2",
            "req_ai": "1",
            "search_ability": "31",
            "search_source": "手动输入",
            "sec_aggre": "1",
            "sec_aggre_bitmap": "22",
            "style_type": "3",
            "tag": "em",
            "token": token,
            "userid": userID,
            "uuid": uuid,
        ]
        params["signature"] = Self.searchSignature(params)

        var components = URLComponents(string: "https://gateway.kugou.com/complexsearch/v3/search/mixed")!
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = components.url else { throw ProviderRequestError.unknown("酷狗综合搜索地址无效") }
        let headers = [
            "KG-RF": "D4407D2505656C0FDC1621BA6FA3FEB5",
            "KG-FAKE": "359933394",
            "KG-FAKE-TYPE": "29,1",
            "KG-RC": "1",
            "UNI-UserAgent": "iOS16.0-Phone-1009-0-WiFi",
            "Accept": "*/*",
            "Accept-Language": "zh-Hans-CN;q=1",
        ]
        let json = try await getJSON(url, ua: "IPhone-20549-Search#183534257/723988397/625045823/284854956-SearchGeneralInfoWithKeyWordV8", headers: headers)
        guard let data = json["data"] as? [String: Any],
              let groups = data["lists"] as? [[String: Any]],
              let songGroup = groups.first(where: {
                  let type = Self.string($0["type"]).lowercased()
                  return type == "song" || type == "songs"
              }),
              let rows = songGroup["lists"] as? [[String: Any]] else {
            return []
        }
        return rows.prefix(min(max(pageSize, 1), 100)).compactMap(Self.mapCompleteTrack)
    }

    /// 酷狗官方歌手搜索，保留 author_id，供歌手主页调用作者歌曲接口。
    private func upstreamSearchArtists(keyword: String, limit: Int) async throws -> [ProviderArtist] {
        let pageSize = min(max(limit, 1), 30)
        let pageCount = max(1, min(10, Int(ceil(Double(max(limit, 1)) / Double(pageSize)))))
        var result: [ProviderArtist] = []
        var seen = Set<String>()

        for page in 1...pageCount {
            let response = try await upstreamRequest(
                "/v1/search/author",
                params: [
                    "albumhide": "0",
                    "iscorrection": "1",
                    "keyword": keyword,
                    "nocollect": "0",
                    "page": "\(page)",
                    "pagesize": "\(pageSize)",
                    "platform": "AndroidFilter",
                ],
                headers: ["x-router": "complexsearch.kugou.com"]
            )
            let rows = Self.deepArrays(
                response.json,
                names: ["lists", "info", "authors", "artists", "author", "list", "data"]
            )
            if rows.isEmpty { break }

            for item in rows {
                let id = Self.string(
                    item["AuthorId"] ?? item["author_id"] ?? item["authorid"] ?? item["singerid"] ?? item["singer_id"] ?? item["id"]
                )
                let name = Self.clean(
                    Self.string(item["AuthorName"] ?? item["author_name"] ?? item["authorname"] ?? item["singername"] ?? item["name"])
                )
                guard !id.isEmpty, !name.isEmpty, seen.insert(id).inserted else { continue }
                let cover = Self.normalizeURL(
                    Self.string(item["Avatar"] ?? item["avatar"] ?? item["pic"] ?? item["imgurl"] ?? item["img_url"] ?? item["author_pic"])
                        .replacingOccurrences(of: "{size}", with: "400")
                )
                result.append(ProviderArtist(
                    id: id,
                    name: name,
                    coverURL: URL(string: cover),
                    source: .kugou
                ))
                if result.count >= limit { return result }
            }
            if rows.count < pageSize { break }
        }
        return result
    }

    /// 基于酷狗官方歌曲搜索结果聚合歌手，保留官方歌手名与封面。
    func searchArtists(keyword: String, limit: Int = 40) async throws -> [ProviderArtist] {
        if let artists = try? await upstreamSearchArtists(keyword: keyword, limit: limit), !artists.isEmpty {
            return artists
        }
        let songs = try await searchSongs(keyword: keyword, limit: limit)
        var result: [ProviderArtist] = []
        var seen = Set<String>()
        for song in songs {
            for name in song.artists.split(separator: "/").map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }) {
                let value = String(name)
                guard !value.isEmpty, seen.insert(value).inserted else { continue }
                result.append(ProviderArtist(
                    id: value,
                    name: value,
                    coverURL: song.coverURL,
                    source: .kugou
                ))
            }
        }
        return result
    }

    /// 酷狗官方歌手歌曲接口。每页最多 100 首，按热度排序。
    func artistSongs(authorID: String, page: Int = 1, limit: Int = 100) async throws -> [ProviderSong] {
        let target = min(max(limit, 1), 100)
        var songs: [ProviderSong] = []
        var seen = Set<String>()

        let upstream = (try? await upstreamArtistSongs(authorID: authorID, page: page, limit: target)) ?? []
        for song in upstream where seen.insert(song.identityKey).inserted {
            songs.append(song)
        }

        if songs.count < target {
            let singer = (try? await officialArtistSongs(authorID: authorID, page: page, limit: target)) ?? []
            if !singer.isEmpty {
                for song in singer where seen.insert(song.identityKey).inserted {
                    songs.append(song)
                }
            }
        }

        if songs.count < target {
            let legacy = (try? await legacyArtistSongs(authorID: authorID, page: page, limit: target)) ?? []
            if !legacy.isEmpty {
                for song in legacy where seen.insert(song.identityKey).inserted {
                    songs.append(song)
                }
            }
        }

        return Array(songs.prefix(target))
    }

    private func upstreamArtistSongs(authorID: String, page: Int, limit: Int) async throws -> [ProviderSong] {
        let target = min(max(limit, 1), 100)
        let response = try await upstreamRequest(
            "/openapi/kmr/v2/audio_group/author",
            params: [
                "author_id": authorID,
                "area_code": "all",
                "sort": "1",
                "page": "\(max(page, 1))",
                "pagesize": "\(target)",
                "replace_api_version": "1",
                "mvdata_need": "1",
                "show_audio_honor": "1",
                "show_audio_tag": "1",
                "replace_need": "1",
            ],
            headers: ["kg-tid": "36"]
        )
        let rows = Self.deepArrays(
            response.json,
            names: ["songs", "songlist", "list", "info", "audio", "data"]
        )
        return rows.compactMap(Self.mapCompleteTrack)
    }

    /// 酷狗移动端歌手歌曲列表，通常比作者接口更完整。
    private func officialArtistSongs(authorID: String, page: Int, limit: Int) async throws -> [ProviderSong] {
        let target = min(max(limit, 1), 100)
        var components = URLComponents(string: "https://mobilecdn.kugou.com/api/v3/singer/song")!
        components.queryItems = [
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "singerid", value: authorID),
            URLQueryItem(name: "page", value: "\(max(page, 1))"),
            URLQueryItem(name: "pagesize", value: "\(target)"),
            URLQueryItem(name: "sorttype", value: "2"),
            URLQueryItem(name: "sort", value: "1"),
            URLQueryItem(name: "with_res_tag", value: "1"),
            URLQueryItem(name: "identity", value: "3"),
            URLQueryItem(name: "plat", value: "0"),
            URLQueryItem(name: "area_code", value: "1"),
            URLQueryItem(name: "version", value: "9108"),
        ]
        guard let url = components.url else { return [] }
        let json = try await getJSON(url, ua: Self.browserUA)
        let rows = Self.deepArrays(json, names: ["info", "songs", "songlist", "list", "data"])
        let songs = rows.compactMap(Self.mapCompleteTrack)
        if !songs.isEmpty {
        }
        return songs
    }

    /// 老版作者歌曲接口作为分页补充，避免新版接口固定只返回 19 首。
    private func legacyArtistSongs(authorID: String, page: Int, limit: Int) async throws -> [ProviderSong] {
        let auth = KugouMusicAuth.shared
        let clientTime = Int(Date().timeIntervalSince1970)
        var data: [String: Any] = [
            "appid": upstreamAppID,
            "clientver": upstreamClientVersion,
            "mid": auth.mid,
            "clienttime": clientTime,
            "key": upstreamParamsKey("\(clientTime)"),
            "author_id": authorID,
            "pagesize": min(max(limit, 1), 100),
            "page": max(page, 1),
            "sort": 1,
            "area_code": "all",
        ]
        if !auth.userId.isEmpty {
            data["userid"] = Int(auth.userId) ?? 0
            data["kguid"] = Int(auth.userId) ?? 0
        }
        if !auth.token.isEmpty { data["token"] = auth.token }
        let body = try JSONSerialization.data(withJSONObject: data)
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        var params = upstreamBaseParams()
        params["clienttime"] = "\(clientTime)"
        params["signature"] = upstreamAndroidSignature(params: params, data: bodyString)
        let response = try await request(
            "/kmr/v1/audio_group/author",
            baseURL: "https://openapi.kugou.com",
            method: "POST",
            params: params,
            body: body,
            headers: upstreamHeaders(extra: [
                "x-router": "openapi.kugou.com",
                "kg-tid": "220",
                "clienttime": "\(clientTime)",
                "Content-Type": "application/json",
            ])
        )
        let rows = Self.deepArrays(response.json, names: ["songs", "songlist", "list", "info", "audio", "data"])
        return rows.compactMap(Self.mapCompleteTrack)
    }

    /// 基于酷狗官方歌曲搜索结果聚合专辑，保留官方专辑名、歌手与封面。
    func albumSongs(album: ProviderAlbum) async throws -> [ProviderSong] {
        var albumID = Int64(album.id)
        if albumID == nil {
            let candidates = try await searchSongs(keyword: "\(album.artistName) \(album.name)", limit: 100)
            let ids = Set(candidates.filter {
                $0.album.trimmingCharacters(in: .whitespacesAndNewlines).localizedCaseInsensitiveCompare(album.name.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame &&
                !$0.artists.isEmpty && $0.artists.localizedCaseInsensitiveCompare(album.artistName) == .orderedSame
            }.compactMap { $0.kugouAlbumId.flatMap(Int64.init) })
            guard ids.count == 1 else { throw ProviderRequestError.unknown("无法确定此专辑的唯一编号，请重新搜索专辑") }
            albumID = ids.first
        }
        guard let albumID, albumID > 0 else { throw ProviderRequestError.unknown("专辑编号无效") }
        var result: [ProviderSong] = []
        var seen = Set<String>()
        for page in 1...100 {
            let response = try await upstreamRequest("/v1/album_audio/lite", method: "POST",
                data: ["album_id": albumID, "is_buy": "", "page": page, "pagesize": 30],
                headers: ["x-router": "openapi.kugou.com", "kg-tid": "255"])
            guard Self.int(response.json["status"]) == 1,
                  let data = response.json["data"] as? [String: Any],
                  let rows = data["songs"] as? [[String: Any]] else {
                throw ProviderRequestError.unknown("专辑曲目加载失败")
            }
            var added = 0
            for row in rows {
                guard let song = Self.mapAlbumTrack(row, albumID: String(albumID)),
                      seen.insert(song.identityKey).inserted else { continue }
                result.append(song); added += 1
            }
            let total = Self.int(data["total"])
            if rows.count < 30 || (total > 0 && result.count >= total) { return result }
            guard added > 0 else { throw ProviderRequestError.unknown("专辑分页没有返回新的曲目") }
        }
        throw ProviderRequestError.unknown("专辑曲目超出分页范围")
    }

    static func mapAlbumTrack(_ raw: [String: Any], albumID: String) -> ProviderSong? {
        guard let base = raw["base"] as? [String: Any], string(base["album_id"]) == albumID,
              let audio = raw["audio_info"] as? [String: Any] else { return nil }
        let album = raw["album_info"] as? [String: Any] ?? [:]
        var flat = raw
        flat["hash"] = audio["hash_128"] ?? audio["hash"]
        flat["320hash"] = audio["hash_320"]
        flat["sqhash"] = audio["hash_flac"]
        flat["hrhash"] = audio["hash_high"]
        flat["songname"] = base["audio_name"]
        flat["singername"] = base["author_name"]
        flat["album_audio_id"] = base["album_audio_id"]
        flat["album_id"] = albumID
        flat["album_name"] = album["album_name"]
        flat["pic"] = album["cover"]
        flat["duration"] = audio["duration"]
        return mapTrack(flat)
    }

    func searchAlbums(keyword: String, limit: Int = 40) async throws -> [ProviderAlbum] {
        let songs = try await searchSongs(keyword: keyword, limit: limit)
        var result: [ProviderAlbum] = []
        var seen = Set<String>()
        for song in songs where !song.album.isEmpty {
            let key = song.kugouAlbumId.flatMap { Int64($0) }.map(String.init) ?? "\(song.album)|\(song.artists)"
            guard seen.insert(key).inserted else { continue }
            result.append(ProviderAlbum(
                id: key,
                name: song.album,
                artistName: song.artists,
                coverURL: song.coverURL,
                source: .kugou,
                trackCount: nil
            ))
        }
        return result
    }

    /// 新碟上架。接口按华语、欧美、日本、韩国分组，每组固定只返回几张，不支持翻页；
    /// 这里按地区轮流合并，避免首页前几张全是同一地区。
    func newAlbums(limit: Int = 20) async throws -> [ProviderAlbum] {
        let response = try await upstreamRequest(
            "/musicadservice/v1/mobile_newalbum_sp",
            method: "POST",
            data: ["apiver": 20, "page": 1, "pagesize": 30, "withpriv": 1],
            anonymous: true
        )
        guard let data = response.json["data"] as? [String: Any] else {
            throw ProviderRequestError.decoding("酷狗新碟数据格式异常")
        }
        let groups = ["chn", "eur", "jpn", "kor"].compactMap { data[$0] as? [[String: Any]] }
        var result: [ProviderAlbum] = []
        var seen = Set<String>()
        for index in 0..<(groups.map(\.count).max() ?? 0) {
            for group in groups where index < group.count {
                let item = group[index]
                let id = Self.string(item["albumid"])
                let name = Self.clean(Self.string(item["albumname"]))
                guard Int64(id) ?? 0 > 0, !name.isEmpty, seen.insert(id).inserted else { continue }
                let cover = Self.normalizeURL(Self.string(item["imgurl"]).replacingOccurrences(of: "{size}", with: "400"))
                let date = Self.string(item["publishtime"])
                result.append(ProviderAlbum(
                    id: id, name: name,
                    artistName: Self.clean(Self.string(item["singername"])),
                    coverURL: URL(string: cover), source: .kugou,
                    trackCount: Self.int(item["songcount"]) > 0 ? Self.int(item["songcount"]) : nil,
                    releaseDateMS: Self.publishDateFormatter.date(from: date).map { Int($0.timeIntervalSince1970 * 1000) }
                ))
            }
        }
        return Array(result.prefix(max(limit, 1)))
    }

    private static let publishDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    /// 热门歌手（歌手列表的“热门”分组）。
    func hotSingers(limit: Int = 30) async throws -> [ProviderArtist] {
        let response = try await upstreamRequest(
            "/ocean/v6/singer/list",
            params: ["musician": "0", "sextype": "0", "showtype": "2", "type": "0",
                     "hotsize": "\(min(max(limit, 1), 100))", "sort": "1", "filtrate": "0",
                     "pagesize": "30", "page": "1"],
            anonymous: true
        )
        guard let data = response.json["data"] as? [String: Any],
              let groups = data["info"] as? [[String: Any]],
              let hot = groups.first?["singer"] as? [[String: Any]] else {
            throw ProviderRequestError.decoding("酷狗歌手列表数据格式异常")
        }
        var seen = Set<String>()
        return Array(hot.compactMap { item -> ProviderArtist? in
            let id = Self.string(item["singerid"])
            let name = Self.clean(Self.string(item["singername"]))
            guard Int(id) ?? 0 > 0, !name.isEmpty, seen.insert(id).inserted else { return nil }
            let cover = Self.normalizeURL(Self.string(item["imgurl"]).replacingOccurrences(of: "{size}", with: "400"))
            return ProviderArtist(id: id, name: name, coverURL: URL(string: cover), source: .kugou)
        }.prefix(max(limit, 1)))
    }

    /// 酷狗官方排行榜列表（移动站点 JSON）。
    func topLists(limit: Int = 10) async throws -> [KugouTopInfo] {
        if let upstream = try? await upstreamTopLists(limit: limit), !upstream.isEmpty {
            return upstream
        }
        if let lists = try? await officialWebTopLists(limit: limit), !lists.isEmpty {
            return lists
        }
        guard let url = URL(string: "https://m.kugou.com/rank/list?json=true") else {
            throw ProviderRequestError.unknown("酷狗排行榜地址无效")
        }
        let json = try await getJSON(url, ua: Self.browserUA)
        guard let rank = json["rank"] as? [String: Any],
              let list = rank["list"] as? [[String: Any]] else {
            throw ProviderRequestError.decoding("酷狗排行榜数据格式异常")
        }
        return list.prefix(limit).compactMap { item in
            let id = Self.int(item["rankid"] ?? item["id"])
            guard id > 0 else { return nil }
            let name = Self.string(item["rankname"] ?? item["name"])
            guard !name.isEmpty else { return nil }
            let cover = Self.normalizeURL(Self.string(item["album_img_9"] ?? item["img_9"] ?? item["imgurl"])
                .replacingOccurrences(of: "{size}", with: "400")
            )
            return KugouTopInfo(
                id: id,
                name: name,
                updateFrequency: Self.string(item["update_frequency"] ?? item["updateFrequency"]),
                coverURL: URL(string: cover)
            )
        }
    }

    private func upstreamTopLists(limit: Int) async throws -> [KugouTopInfo] {
        let response = try await upstreamRequest(
            "/ocean/v6/rank/list",
            params: [
                "plat": "2",
                "withsong": "1",
                "parentid": "0",
            ]
        )
        let rows = Self.deepArrays(response.json, names: ["rank", "list", "ranklist", "data", "info"])
        var seen = Set<Int>()
        return rows.compactMap { item in
            let id = Self.int(item["rankid"] ?? item["rank_id"] ?? item["id"])
            let name = Self.clean(Self.string(item["rankname"] ?? item["rank_name"] ?? item["name"] ?? item["title"]))
            guard id > 0, !name.isEmpty, seen.insert(id).inserted else { return nil }
            let cover = Self.normalizeURL(
                Self.string(item["imgurl"] ?? item["img_url"] ?? item["img_9"] ?? item["album_img_9"] ?? item["cover"])
                    .replacingOccurrences(of: "{size}", with: "400")
            )
            return KugouTopInfo(
                id: id,
                name: name,
                updateFrequency: Self.clean(Self.string(item["update_frequency"] ?? item["updateFrequency"])),
                coverURL: URL(string: cover)
            )
        }.prefix(max(limit, 1)).map { $0 }
    }

    private func upstreamRankSongs(rankID: Int, limit: Int) async throws -> [ProviderSong] {
        let target = max(limit, 1)
        // The KMR endpoint may cap a response at roughly 20 rows regardless of
        // pagesize, so a single request silently truncates chart details.
        let pageSize = min(max(target, 1), 100)
        let pageCount = max(1, min(50, Int(ceil(Double(target) / 30.0)) + 2))
        var songs: [ProviderSong] = []
        var seen = Set<String>()

        for page in 1...pageCount {
            let response = try await upstreamRequest(
                "/openapi/kmr/v2/rank/audio",
                method: "POST",
                data: [
                    "show_portrait_mv": 1,
                    "show_type_total": 1,
                    "filter_original_remarks": 1,
                    "area_code": 1,
                    "pagesize": pageSize,
                    "rank_cid": 0,
                    "type": 1,
                    "page": page,
                    "rank_id": rankID,
                ],
                headers: ["kg-tid": "369"]
            )
            let rows = Self.deepArrays(
                response.json,
                names: ["songs", "songlist", "list", "info", "data", "audio"]
            )
            let batch = rows.compactMap(Self.mapCompleteTrack)
            if batch.isEmpty { break }

            let before = songs.count
            for song in batch where seen.insert(song.identityKey).inserted {
                songs.append(song)
                if songs.count >= target { return Array(songs.prefix(target)) }
            }
            // Some server-side chart variants repeat page one when they do not
            // support pagination. Stop instead of issuing identical requests.
            if songs.count == before { break }
        }

        return Array(songs.prefix(target))
    }

    /// 酷狗官方排行榜歌曲。
    func rankSongs(rankID: Int, limit: Int = 100) async throws -> [ProviderSong] {
        let target = max(limit, 1)
        let upstream = (try? await upstreamRankSongs(rankID: rankID, limit: target)) ?? []
        if !upstream.isEmpty {
        }

        // Keep the KMR order, but use the other official endpoints to fill a
        // short page. This handles chart variants that expose only 20-22 rows
        // through one of the APIs.
        var merged = upstream
        if merged.count < target,
           let official = try? await officialWebRankSongs(rankID: rankID, limit: target),
           !official.isEmpty {
            merged = Self.mergeRankSongs(primary: merged, fallback: official, limit: target)
        }

        if merged.count < target,
           let mobile = try? await mobileRankSongs(rankID: rankID, limit: target),
           !mobile.isEmpty {
            merged = Self.mergeRankSongs(primary: merged, fallback: mobile, limit: target)
        }

        if merged.isEmpty {
            throw ProviderRequestError.decoding("酷狗排行榜歌曲为空")
        }

        // If the main source has rows but missing covers, enrich them without
        // changing the order or the song metadata selected above.
        if merged.contains(where: { $0.coverURL == nil }),
           let mobile = try? await mobileRankSongs(rankID: rankID, limit: target),
           !mobile.isEmpty {
            merged = Self.mergeRankCovers(primary: merged, fallback: mobile)
        }
        return Array(merged.prefix(target))
    }

    private func mobileRankSongs(rankID: Int, limit: Int) async throws -> [ProviderSong] {
        let target = max(limit, 1)
        let pageSize = min(max(target, 1), 100)
        let pageCount = max(1, min(50, Int(ceil(Double(target) / 20.0)) + 2))
        var songs: [ProviderSong] = []
        var seen = Set<String>()

        for page in 1...pageCount {
            var components = URLComponents(string: "https://m.kugou.com/rank/info")!
            components.queryItems = [
                URLQueryItem(name: "rankid", value: "\(rankID)"),
                URLQueryItem(name: "page", value: "\(page)"),
                URLQueryItem(name: "pagesize", value: "\(pageSize)"),
                URLQueryItem(name: "json", value: "true"),
            ]
            guard let url = components.url else { throw ProviderRequestError.unknown("酷狗排行榜地址无效") }
            let json = try await getJSON(url, ua: Self.browserUA)
            let rows = (json["songs"] as? [String: Any])?["list"] as? [[String: Any]] ?? []
            let batch = rows.compactMap(Self.mapCompleteTrack)
            if batch.isEmpty { break }

            let before = songs.count
            for song in batch where seen.insert(song.identityKey).inserted {
                songs.append(song)
                if songs.count >= target { return Array(songs.prefix(target)) }
            }
            if songs.count == before { break }
        }

        return Array(songs.prefix(target))
    }

    /// 酷狗官方歌单广场（移动站点 JSON）。
    func recommendPlaylists(limit: Int = 12) async throws -> [ProviderPlaylist] {
        if let upstream = try? await upstreamRecommendPlaylists(limit: limit), !upstream.isEmpty {
            return upstream
        }
        if let playlists = try? await officialWebPlaylists(limit: limit), !playlists.isEmpty {
            return playlists
        }
        guard let url = URL(string: "https://m.kugou.com/plist/index?json=true&page=1") else {
            throw ProviderRequestError.unknown("酷狗歌单广场地址无效")
        }
        let json = try await getJSON(url, ua: Self.browserUA)
        let rows = (((json["plist"] as? [String: Any])?["list"] as? [String: Any])?["info"] as? [[String: Any]]) ?? []
        return rows.prefix(limit).compactMap { item in
            let id = Self.int(item["specialid"] ?? item["id"])
            guard id > 0 else { return nil }
            let name = Self.string(item["specialname"] ?? item["name"] ?? item["title"])
            guard !name.isEmpty else { return nil }
            let cover = Self.normalizeURL(Self.string(item["imgurl"] ?? item["pic"] ?? item["cover"])
                .replacingOccurrences(of: "{size}", with: "400")
            )
            return ProviderPlaylist(
                id: id,
                name: name,
                coverURL: URL(string: cover),
                trackCount: Self.int(item["songcount"] ?? item["song_count"]),
                source: .kugou
            )
        }
    }

    private func upstreamRecommendPlaylists(limit: Int) async throws -> [ProviderPlaylist] {
        let auth = KugouMusicAuth.shared
        let clientTime = Int(Date().timeIntervalSince1970)
        let specialRecommend: [String: Any] = [
            "withtag": 1,
            "withsong": 1,
            "sort": 1,
            "ugc": 1,
            "is_selected": 0,
            "withrecommend": 1,
            "area_code": 1,
            "categoryid": 0,
        ]
        let response = try await upstreamRequest(
            "/v2/special_recommend",
            method: "POST",
            data: [
                "appid": upstreamAppID,
                "mid": auth.mid,
                "clientver": upstreamClientVersion,
                "platform": "android",
                "clienttime": clientTime,
                "userid": Int(auth.userId) ?? 0,
                "module_id": 1,
                "page": 1,
                "pagesize": min(max(limit, 1), 30),
                "key": upstreamParamsKey("\(clientTime)"),
                "special_recommend": specialRecommend,
                "req_multi": 1,
                "retrun_min": 5,
                "return_special_falg": 1,
            ],
            headers: ["x-router": "specialrec.service.kugou.com"]
        )
        let rows = Self.deepArrays(
            response.json,
            names: ["special_recommend", "playlists", "playlist", "list", "info", "data"]
        )
        var seen = Set<Int>()
        return rows.compactMap { item in
            guard let playlist = Self.mapPlaylist(item), seen.insert(playlist.id).inserted else { return nil }
            return playlist
        }.prefix(max(limit, 1)).map { $0 }
    }

    private func officialWebTopLists(limit: Int) async throws -> [KugouTopInfo] {
        guard let url = URL(string: "https://www.kugou.com/yy/html/rank.html") else {
            throw ProviderRequestError.unknown("酷狗官网排行榜地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        let pattern = #"<a title="([^"]+)"[^>]*href="https://www\.kugou\.com/yy/rank/home/1-(\d+)\.html\?from=rank"[\s\S]*?background-image:url\(([^\)]+)\)"#
        var seen = Set<Int>()
        let rows = Self.regexMatches(pattern, in: html).compactMap { groups -> KugouTopInfo? in
            guard groups.count >= 4 else { return nil }
            let id = Int(groups[2]) ?? 0
            guard id > 0, seen.insert(id).inserted else { return nil }
            let cover = Self.normalizeURL(groups[3].trimmingCharacters(in: .whitespacesAndNewlines))
            return KugouTopInfo(
                id: id,
                name: Self.clean(Self.htmlDecode(groups[1])),
                updateFrequency: "酷狗官网热门榜单",
                coverURL: URL(string: cover)
            )
        }
        return Array(rows.prefix(limit))
    }

    private func officialWebRankSongs(rankID: Int, limit: Int) async throws -> [ProviderSong] {
        guard let url = URL(string: "https://www.kugou.com/yy/rank/home/1-\(rankID).html?from=rank") else {
            throw ProviderRequestError.unknown("酷狗官网排行榜歌曲地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        guard let rows = Self.javascriptArray(named: "global.features", in: html) else {
            throw ProviderRequestError.decoding("酷狗官网排行榜歌曲格式异常")
        }
        let songs = rows.prefix(limit).compactMap(Self.mapCompleteTrack)
        return songs
    }

    /// 网页版歌单广场的排序，用作探索页分类。
    enum PlaylistSort: Int, CaseIterable, Sendable {
        case recommended = 5, hottest = 6, newest = 7, mostCollected = 3, rising = 8

        var title: String {
            switch self {
            case .recommended: return String(localized: "推荐")
            case .hottest: return String(localized: "最热")
            case .newest: return String(localized: "最新")
            case .mostCollected: return String(localized: "热藏")
            case .rising: return String(localized: "飙升")
            }
        }
    }

    /// 网页版按排序列出的歌单。页面固定返回 40 个，翻页参数不生效。
    func sortedPlaylists(_ sort: PlaylistSort, limit: Int = 40) async throws -> [ProviderPlaylist] {
        try await officialWebPlaylists(limit: limit, page: "https://www.kugou.com/yy/special/index/1-\(sort.rawValue)-0.html")
    }

    private func officialWebPlaylists(limit: Int, page: String = "https://www.kugou.com/yy/html/special.html") async throws -> [ProviderPlaylist] {
        guard let url = URL(string: page) else {
            throw ProviderRequestError.unknown("酷狗官网歌单广场地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        let pattern = #"<li class="s_(\d+)"[\s\S]*?<a[^>]+title="([^"]+)" href="https://www\.kugou\.com/songlist/(gcid_[^/]+)/"[\s\S]*?_src="([^"]+)""#
        var seen = Set<Int>()
        let rows = Self.regexMatches(pattern, in: html).compactMap { groups -> ProviderPlaylist? in
            guard groups.count >= 5 else { return nil }
            let id = Int(groups[1]) ?? 0
            guard id > 0, seen.insert(id).inserted else { return nil }
            let cover = Self.normalizeURL(groups[4].replacingOccurrences(of: "{size}", with: "400"))
            var playlist = ProviderPlaylist(
                id: id,
                name: Self.clean(Self.htmlDecode(groups[2])),
                coverURL: URL(string: cover),
                trackCount: 0,
                source: .kugou
            )
            playlist.kugouGlobalCollectionID = groups[3]
            return playlist
        }
        return Array(rows.prefix(limit))
    }

    private func officialWebPlaylistSongs(listID: Int) async throws -> [ProviderSong] {
        guard let url = URL(string: "https://www.kugou.com/yy/special/single/\(listID).html") else {
            throw ProviderRequestError.unknown("酷狗官网歌单歌曲地址无效")
        }
        let html = try await getString(url, ua: Self.browserUA)
        guard let rows = Self.javascriptArray(named: "data", in: html) else {
            throw ProviderRequestError.decoding("酷狗官网歌单歌曲格式异常")
        }
        let songs = rows.compactMap(Self.mapCompleteTrack)
        return songs
    }

    /// 酷狗热搜榜（msearch hot_tab 的第一个榜单）。
    func hotWords(limit: Int = 10) async throws -> [String] {
        // msearch 从请求头读取 clienttime，只放在查询参数里会被拒绝。
        let clientTime = "\(Int(Date().timeIntervalSince1970))"
        var params = upstreamBaseParams()
        params["token"] = nil
        params["userid"] = nil
        params["clienttime"] = clientTime
        params["navid"] = "1"
        params["plat"] = "2"
        params["signature"] = upstreamAndroidSignature(params: params, data: "")
        var headers = upstreamHeaders(extra: ["clienttime": clientTime])
        headers["Cookie"] = nil
        let response = try await request("/api/v3/search/hot_tab", baseURL: "https://msearch.kugou.com", method: "GET",
                                         params: params, body: nil, headers: headers)
        guard let data = response.json["data"] as? [String: Any],
              let lists = data["list"] as? [[String: Any]],
              let keywords = lists.first?["keywords"] as? [[String: Any]] else {
            throw ProviderRequestError.decoding("酷狗热搜数据格式异常")
        }
        var seen = Set<String>()
        return Array(keywords.compactMap { item -> String? in
            let word = Self.clean(Self.string(item["keyword"]))
            return word.isEmpty || !seen.insert(word).inserted ? nil : word
        }.prefix(max(limit, 1)))
    }

    /// Account collections are references to an author's public list. Their
    /// account-local ID has no files in the private cloud-list endpoint.
    func playlistSongs(playlist: ProviderPlaylist) async throws -> [ProviderSong] {
        if playlist.ownerID == playlistIdentity.userId {
            if playlist.isSubscribed == true {
                guard let id = Self.collectionTrackID(playlist) else {
                    throw ProviderRequestError.unknown("酷狗收藏歌单缺少原歌单编号，请刷新歌单列表")
                }
                return try await publicPlaylistSongs(globalID: id)
            }
            return try await playlistSongs(listID: playlist.id, cloud: true)
        }
        if let source = try? await collectionSource(playlist), let id = Self.collectionTrackID(source) {
            return try await publicPlaylistSongs(globalID: id)
        }
        return try await playlistSongs(listID: playlist.id)
    }

    static func collectionTrackID(_ playlist: ProviderPlaylist) -> String? {
        if let id = playlist.kugouCreateGID, id.hasPrefix("collection_") { return id }
        // An account collection's global ID identifies the empty reference,
        // not the author's songs. Only public records can use it directly.
        if playlist.ownerID == nil, let id = playlist.kugouGlobalCollectionID, id.hasPrefix("collection_") { return id }
        return nil
    }

    private func publicPlaylistSongs(globalID: String) async throws -> [ProviderSong] {
        let pageSize = 200
        let maxSongs = 10_000
        var rows: [[String: Any]] = []
        while rows.count < maxSongs {
            let response = try await upstreamRequest("/pubsongs/v2/get_other_list_file_nofilt", params: [
                "global_collection_id": globalID, "begin_idx": String(rows.count),
                "pagesize": String(pageSize), "area_code": "1", "plat": "1", "type": "1",
                "mode": "1", "personal_switch": "1", "extend_fields": "abtags,hot_cmt,popularization"
            ])
            try Self.validatePlaylistMutation(response.json)
            guard let data = response.json["data"] as? [String: Any],
                  let page = data["songs"] as? [[String: Any]] else {
                throw ProviderRequestError.decoding("酷狗公开歌单歌曲格式异常")
            }
            let total = Self.int(data["count"])
            if page.isEmpty {
                guard total <= rows.count else { throw ProviderRequestError.decoding("酷狗歌单歌曲未完整返回，请重试") }
                break
            }
            rows.append(contentsOf: page)
            if total > 0 ? rows.count >= total : page.count < pageSize { break }
        }
        return rows.prefix(maxSongs).compactMap(Self.mapCloudPlaylistTrack)
    }

    func playlistSongs(listID: Int, cloud: Bool = false) async throws -> [ProviderSong] {
        if !cloud, listID >= 1000,
           let songs = try? await officialWebPlaylistSongs(listID: listID),
           !songs.isEmpty {
            return songs
        }
        return try await cloudPlaylistRows(listID: listID).compactMap(Self.mapCloudPlaylistTrack)
    }

    /// Raw account-list rows, sorted by position. Rows carry the list-local
    /// `fileid` that track removal needs.
    private func cloudPlaylistRows(listID: Int) async throws -> [[String: Any]] {
        let auth = playlistIdentity
        guard !auth.userId.isEmpty, !auth.token.isEmpty else { return [] }
        let pid = "\(listID)"
        var all: [[String: Any]] = []
        var page = 1
        let pageSize = 200
        let maxSongs = 10_000
        repeat {
            let body: [String: Any] = [
                "listid": pid,
                "page": page,
                "pagesize": pageSize,
                "area_code": 1,
                "show_relate_goods": 0,
                "allplatform": 1,
                "show_cover": 1,
                "type": 0,
                "userid": Int(auth.userId) ?? 0,
                "token": auth.token,
            ]
            let json = try await cloudlistRequest("/v4/get_list_all_file", params: ["listid": pid, "page": "\(page)", "pagesize": "200"], data: body)
            try Self.validatePlaylistMutation(json)
            let pageTracks = Self.deepArrays(json, names: ["songs", "songlist", "list", "info", "files", "data"])
            all.append(contentsOf: pageTracks)
            if all.count >= maxSongs { break }
            if pageTracks.count < pageSize { break }
            page += 1
        } while page <= maxSongs / pageSize
        if all.count > maxSongs {
            all = Array(all.prefix(maxSongs))
        }
        return all
            .sorted { (Self.int($0["fsort"] ?? $0["sort"] ?? $0["position"]) ) < (Self.int($1["fsort"] ?? $1["sort"] ?? $1["position"])) }
    }

    struct SongURLResult {
        let url: String
        let quality: ProviderAudioQuality?
        var title: String? = nil
    }

    func songURL(song: ProviderSong, quality: ProviderAudioQuality? = nil) async throws -> String? {
        try await songURLResult(song: song, quality: quality)?.url
    }

    static func hasAliasedQualityHashes(_ hashes: [String: String]?) -> Bool {
        guard let hashes, hashes.count > 1 else { return false }
        return Set(hashes.values.map { $0.uppercased() }).count < hashes.count
    }

    static func metadataQualities(_ song: ProviderSong) -> [ProviderAudioQuality] {
        let hashes = song.kugouQualityHashes ?? [:]
        var result: [ProviderAudioQuality] = []
        var seen = Set<String>()
        for quality: ProviderAudioQuality in [.standard, .exhigh, .lossless, .hires] {
            let hash = (hashes[quality.rawValue] ?? (quality == .standard ? song.kugouHash : nil) ?? "").uppercased()
            if !hash.isEmpty, seen.insert(hash).inserted { result.append(quality) }
        }
        return result
    }

    func qualityOptions(song: ProviderSong) async throws -> [AudioQualityOption] {
        let metadata = await playbackMetadata(for: song)
        var options: [AudioQualityOption] = []
        for candidate in Self.metadataQualities(metadata) {
            guard let result = try await songURLResult(song: metadata, quality: candidate),
                  let served = result.quality, let quality = AudioQuality(rawValue: served.rawValue),
                  !options.contains(where: { $0.quality == quality }) else { continue }
            options.append(.init(quality: quality, title: result.title ?? AudioQualityOption.unifiedTitle(quality: quality)))
        }
        return options
    }

    func playbackMetadata(for song: ProviderSong) async -> ProviderSong {
        (try? await completePlaybackMetadata(for: song)) ?? song
    }

    func songURLResult(song: ProviderSong, quality: ProviderAudioQuality? = nil) async throws -> SongURLResult? {
        let requestedQuality = quality ?? ProviderAudioQuality.current
        var primary = song.kugouHash
        var qualityHashes = song.kugouQualityHashes
        var albumAudioId = song.kugouAlbumAudioId
        var albumId = song.kugouAlbumId
        if (Self.qualityHashCandidates(primary: primary, qualityHashes: qualityHashes, quality: requestedQuality).isEmpty ||
            (requestedQuality != .standard && (Self.hasAliasedQualityHashes(qualityHashes) ||
                (qualityHashes?[requestedQuality.rawValue]?.isEmpty != false)))),
           let completed = try? await completePlaybackMetadata(for: song) {
            primary = completed.kugouHash ?? primary
            qualityHashes = completed.kugouQualityHashes ?? qualityHashes
            albumAudioId = completed.kugouAlbumAudioId ?? albumAudioId
            albumId = completed.kugouAlbumId ?? albumId
        }
        let hashes = Self.qualityHashCandidates(primary: primary, qualityHashes: qualityHashes, quality: requestedQuality)
        guard !hashes.isEmpty else { return nil }
        if let result = try await resolveSongURLWithQualityFallback(hashes: hashes, albumAudioId: albumAudioId, albumId: albumId, quality: requestedQuality) { return result }
        // Saved playlists can retain obsolete hashes. Only retry a verified recording.
        guard let completed = try? await completePlaybackMetadata(for: song) else { return nil }
        let refreshed = Self.qualityHashCandidates(primary: completed.kugouHash, qualityHashes: completed.kugouQualityHashes, quality: requestedQuality)
        guard refreshed != hashes || completed.kugouAlbumAudioId != albumAudioId else { return nil }
        return try await resolveSongURLWithQualityFallback(hashes: refreshed, albumAudioId: completed.kugouAlbumAudioId, albumId: completed.kugouAlbumId, quality: requestedQuality)
    }

    func songURL(hash: String, albumAudioId: String?, albumId: String?) async throws -> String? {
        try await resolveSongURL(hashes: [hash], albumAudioId: albumAudioId, albumId: albumId, quality: ProviderAudioQuality.current)?.url
    }

    private func resolveSongURLWithQualityFallback(hashes: [String], albumAudioId: String?, albumId: String?, quality: ProviderAudioQuality) async throws -> SongURLResult? {
        let ranks = ProviderAudioQuality.allCases
        let requestedRank = ranks.firstIndex(of: quality) ?? 0
        let candidates: [ProviderAudioQuality] = [.hires, .lossless, .exhigh, .standard].filter {
            (ranks.firstIndex(of: $0) ?? 0) <= requestedRank
        }
        var best: SongURLResult?
        for candidate in candidates {
            guard let result = try await resolveSongURL(hashes: hashes, albumAudioId: albumAudioId, albumId: albumId, quality: candidate) else { continue }
            let rank = result.quality.flatMap { ranks.firstIndex(of: $0) } ?? -1
            let previous = best?.quality.flatMap { ranks.firstIndex(of: $0) } ?? -1
            if best == nil || rank > previous { best = result }
            if rank >= (ranks.firstIndex(of: candidate) ?? 0) { return best }
        }
        return best
    }

    private func resolveSongURL(hashes: [String], albumAudioId: String?, albumId: String?, quality: ProviderAudioQuality) async throws -> SongURLResult? {
        let auth = KugouMusicAuth.shared
        let vipTypes = Self.vipTypeCandidates(auth.vipType)
        let ranks = ProviderAudioQuality.allCases
        let requestedRank = ranks.firstIndex(of: quality) ?? 0
        var best: SongURLResult?
        func consider(_ result: SongURLResult) -> Bool {
            let rank = result.quality.flatMap { ranks.firstIndex(of: $0) } ?? -1
            let previous = best?.quality.flatMap { ranks.firstIndex(of: $0) } ?? -1
            if best == nil || rank > previous { best = result }
            return rank >= requestedRank
        }
        for hash in hashes {
            if let latest = try? await upstreamSongURLOnce(
                hash: hash,
                albumAudioId: albumAudioId,
                albumId: albumId,
                quality: quality
            ), let url = latest.url, !url.isEmpty {
                if consider(SongURLResult(url: url, quality: latest.quality, title: latest.title)) { return best }
            }
            for vipType in vipTypes {
                guard let result = try? await songURLOnce(hash: hash, albumAudioId: albumAudioId, albumId: albumId, vipType: vipType) else {
                    continue
                }
                if let url = result.url, !url.isEmpty {
                    if consider(SongURLResult(url: url, quality: result.quality)) { return best }
                }
            }
            guard let web = try? await songURLWebOnce(hash: hash, albumAudioId: albumAudioId, albumId: albumId) else { continue }
            if let url = web.url, !url.isEmpty {
                if consider(SongURLResult(url: url, quality: web.quality)) { return best }
            }
        }
        return best
    }

    static func playbackURL(in response: [String: Any]) -> String {
        let file = response["data"] as? [String: Any] ?? response
        for key in ["play_url", "url", "src", "play_backup_url", "backup_url"] {
            let values = (file[key] as? [String]) ?? [string(file[key])]
            for value in values {
                guard let url = URL(string: value),
                      ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { continue }
                return value
            }
        }
        return ""
    }

    private func verifiedPlaybackQuality(url: String, reported: ProviderAudioQuality?, bitrate: Double? = nil,
                                         probeUnknown: Bool = false) async -> ProviderAudioQuality? {
        guard reported.map({ [.lossless, .hires].contains($0) }) ?? probeUnknown else { return reported }
        let verified = await AudioQualityCheck.remoteTier(url: url, session: session, bitrate: bitrate)
        return verified.flatMap { ProviderAudioQuality(rawValue: $0.rawValue) } ?? reported
    }

    static func flacQuality(header: Data) -> ProviderAudioQuality? {
        AudioQualityCheck.flacTier(header: header).flatMap { ProviderAudioQuality(rawValue: $0.rawValue) }
    }

    /// Read the returned file's encoding, never the requested preference: the
    /// tracker may return a lower quality for this recording or account.
    static func playbackQuality(in response: [String: Any]) -> ProviderAudioQuality? {
        let file = response["data"] as? [String: Any] ?? response
        let format = string(file["extName"] ?? file["extname"] ?? file["format"] ?? file["audio_format"] ?? file["type"]).lowercased()
        let rate = double(file["bitRate"] ?? file["bitrate"] ?? file["bit_rate"])
        let bitrate = AudioQualityCheck.bitrateBPS(rate)
        let sampleRate = double(file["sampleRate"] ?? file["sample_rate"] ?? file["samplerate"])
        let bitDepth = int(file["bitDepth"] ?? file["bit_depth"] ?? file["bitdepth"])
        let reported = string(file["quality"] ?? file["audio_quality"]).lowercased()
        if AudioQualityCheck.isLossless(format) {
            let tier = AudioQualityCheck.losslessTier(sampleRate: sampleRate, bitDepth: bitDepth)
            return ProviderAudioQuality(rawValue: tier.rawValue)
        }
        if AudioQualityCheck.isLossy(format) || (bitrate ?? .infinity) <= 320_000 {
            let fallback: AudioQuality?
            switch reported {
            case "128", "standard": fallback = .standard
            case "320", "exhigh": fallback = .exhigh
            default: fallback = nil
            }
            return AudioQualityCheck.lossyTier(bitrate: bitrate, fallback: fallback).flatMap { ProviderAudioQuality(rawValue: $0.rawValue) }
        }
        switch reported {
        case "128", "standard": return .standard
        case "320", "exhigh": return .exhigh
        case "flac", "lossless", "sq": return .lossless
        default: return nil
        }
    }

    /// KuGouMusicApi 使用的 song_url 请求：v5/url + signKey，不依赖网页播放地址。
    private func upstreamSongURLOnce(
        hash: String,
        albumAudioId: String?,
        albumId: String?,
        quality requestedQuality: ProviderAudioQuality
    ) async throws -> (url: String?, status: Int, code: Int, quality: ProviderAudioQuality?, title: String?) {
        let credentials: [String: String]
        if let playbackCredentials { credentials = playbackCredentials }
        else {
            let auth = KugouMusicAuth.shared
            auth.prepareDevice()
            credentials = auth.exportedCredentials
        }
        let profiles = credentials["token"]?.isEmpty == false ? ["3116", "1005"] : ["1005"]
        var fallback: (url: String?, status: Int, code: Int, quality: ProviderAudioQuality?, title: String?)?
        let ranks = ProviderAudioQuality.allCases
        var lastStatus = 0
        var lastCode = 0
        for profile in profiles {
            try Task.checkCancellation()
            let params = Self.playbackParameters(hash: hash, albumAudioId: albumAudioId, albumId: albumId,
                quality: requestedQuality, credentials: credentials, timestamp: Int(Date().timeIntervalSince1970), clientAppID: profile)
            guard let response = try? await request(
                "/v5/url", baseURL: gateway, method: "GET", params: params, body: nil,
                headers: ["x-router": "trackercdn.kugou.com", "User-Agent": androidUA,
                          "mid": params["mid"] ?? "-", "dfid": params["dfid"] ?? "-",
                          "clienttime": params["clienttime"] ?? "", "kg-rc": "1", "kg-thash": "5d816a0"]
            ) else { continue }
            lastStatus = Self.deepInt(response.json, names: ["status", "result"])
            lastCode = Self.deepInt(response.json, names: ["error_code", "errcode", "code"])
            let raw = Self.playbackURL(in: response.json)
            guard !raw.isEmpty else { continue }
            let file = response.json["data"] as? [String: Any] ?? response.json
            let rawRate = Self.double(file["bitRate"] ?? file["bitrate"] ?? file["bit_rate"])
            let direct = AudioQualityCheck.bitrateBPS(rawRate)
            let reported = Self.playbackQuality(in: response.json)
            let served = await verifiedPlaybackQuality(url: raw, reported: reported, bitrate: direct,
                                                       probeUnknown: [.lossless, .hires].contains(requestedQuality))
            let title = served.flatMap { AudioQuality(rawValue: $0.rawValue) }.map {
                AudioQualityOption.unifiedTitle(
                    quality: $0, reportedBitrate: direct,
                    byteCount: Self.double(file["fileSize"] ?? file["filesize"] ?? file["file_size"]),
                    durationSeconds: Self.double(file["timeLength"] ?? file["timelength"] ?? file["time_length"]))
            }
            let candidate = (url: Optional(raw), status: lastStatus, code: lastCode, quality: served, title: title)
            let rank = served.flatMap { ranks.firstIndex(of: $0) } ?? -1
            if rank >= (ranks.firstIndex(of: requestedQuality) ?? 0) { return candidate }
            let previousRank = fallback?.quality.flatMap { ranks.firstIndex(of: $0) } ?? -1
            if fallback == nil || rank > previousRank { fallback = candidate }
        }
        return fallback ?? (nil, lastStatus, lastCode, nil, nil)
    }

    static func playbackParameters(hash: String, albumAudioId: String?, albumId: String?, quality: ProviderAudioQuality,
                                   credentials: [String: String], timestamp: Int, clientAppID: String? = nil) -> [String: String] {
        let userID = (credentials["userid"] ?? credentials["user_id"] ?? "").filter(\.isNumber)
        let token = credentials["token"] ?? ""
        let mid = credentials["KUGOU_API_MID"] ?? credentials["mid"] ?? "-"
        let fileHash = hash.lowercased()
        // QR login uses the concept client. Its token must keep that client
        // identity for paid recordings; a standard-client request returns 20018.
        let concept = clientAppID.map { $0 == "3116" } ?? (!userID.isEmpty && !token.isEmpty)
        let playbackAppID = concept ? "3116" : "1005"
        let keySalt = concept ? "185672dd44712f60bb1736df5a377e82" : "57ae12eb6890223e355ccfcb74edf70d"
        let wireQuality: String
        switch quality {
        case .standard:
            wireQuality = "128"
        case .higher, .exhigh:
            wireQuality = "320"
        case .lossless:
            wireQuality = "flac"
        case .hires:
            wireQuality = "high"
        }

        var params: [String: String] = [
            "mid": mid, "dfid": credentials["dfid"] ?? credentials["DFID"] ?? "-",
            "uuid": "-", "clienttime": String(timestamp),
        ]
        if !userID.isEmpty && !token.isEmpty {
            params["userid"] = userID
            params["token"] = token
        }
        params["appid"] = playbackAppID
        params["album_id"] = albumId ?? "0"
        params["area_code"] = "1"
        params["hash"] = fileHash
        params["ssa_flag"] = "is_fromtrack"
        params["version"] = "11430"
        params["quality"] = wireQuality
        params["IsFreePart"] = "0"
        params["behavior"] = "play"
        params["pid"] = concept ? "411" : "2"
        params["pidversion"] = "3001"
        params["cmd"] = "26"
        params["page_id"] = concept ? "967177915" : "151369488"
        params["ppage_id"] = concept ? "356753938,823673182,967485191" : "463467626,350369493,788954147"
        params["cdnBackup"] = "1"
        params["module"] = ""
        params["clientver"] = "11430"
        params["key"] = "\(fileHash)\(keySalt)\(playbackAppID)\(mid)\(userID.isEmpty ? "0" : userID)".kgMD5Hex
        params["album_audio_id"] = albumAudioId.flatMap { Int64($0) }.map(String.init) ?? "0"

        // The reference's `notSign` is not `notSignature`: v5 needs both
        // the per-file key and the Android request signature.
        let salt = concept ? "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA" : "OIlwieks28dk2k092lksi2UIkp"
        let signingText = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined()
        params["signature"] = "\(salt)\(signingText)\(salt)".kgMD5Hex
        return params
    }

    /// 网页播放通道。部分帐号登录态在移动端 tracker 返回 20006 时，网页接口仍会返回授权后的播放地址。
    private func songURLWebOnce(hash: String, albumAudioId: String?, albumId: String?) async throws -> (url: String?, status: Int, code: Int, quality: ProviderAudioQuality?) {
        let auth = KugouMusicAuth.shared
        var components = URLComponents(string: "https://wwwapi.kugou.com/yy/index.php")!
        var params: [String: String] = [
            "r": "play/getdata",
            "hash": hash.uppercased(),
            "appid": "1014",
            "platid": "4",
            "mid": auth.mid,
            "dfid": auth.dfid,
            "userid": auth.userId.isEmpty ? "0" : auth.userId,
            "token": auth.token,
        ]
        if let albumId, !albumId.isEmpty { params["album_id"] = albumId }
        if let albumAudioId, !albumAudioId.isEmpty { params["album_audio_id"] = albumAudioId }
        components.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        request.setValue(Self.browserUA, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        request.setValue(auth.cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, 0, -1, nil) }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = Self.deepInt(json, names: ["status", "result"])
        let code = Self.deepInt(json, names: ["error_code", "errcode", "code"])
        let raw = Self.playbackURL(in: json)
        let quality = raw.isEmpty ? nil : await verifiedPlaybackQuality(url: raw, reported: Self.playbackQuality(in: json))
        return (raw.isEmpty ? nil : raw, status, code, quality)
    }

    private func completePlaybackMetadata(for song: ProviderSong) async throws -> ProviderSong? {
        let keyword = ([song.name, song.artists].filter { !$0.isEmpty }).joined(separator: " ")
        guard !keyword.isEmpty else { return nil }
        let candidates = try await searchSongs(keyword: keyword, limit: 8)
        let targetDuration = song.duration
        return candidates.first { candidate in
            if let expected = song.kugouAlbumAudioId,
               let actual = candidate.kugouAlbumAudioId,
               !expected.isEmpty,
               expected == actual {
                return true
            }
            let nameOK = candidate.name == song.name
            let artistOK = Self.playbackArtistsMatch(song.artists, candidate.artists)
            let durationOK = targetDuration <= 0 || abs(candidate.duration - targetDuration) < 12
            return nameOK && artistOK && durationOK
        }
    }

    // Cloud lists join collaborators with " / ", search uses "、".
    // Compare complete artist names so refreshing an old recording ID still
    // verifies the performers instead of rejecting the same collaboration.
    static func playbackArtistsMatch(_ expected: String, _ actual: String) -> Bool {
        func names(_ value: String) -> Set<String> {
            Set(value.components(separatedBy: CharacterSet(charactersIn: "/、;；"))
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
                .filter { !$0.isEmpty })
        }
        let expectedNames = names(expected)
        return expectedNames.isEmpty || expectedNames == names(actual)
    }

    private func songURLOnce(hash: String, albumAudioId: String?, albumId: String?, vipType: Int) async throws -> (url: String?, status: Int, code: Int, quality: ProviderAudioQuality?) {
        let auth = KugouMusicAuth.shared
        let h = hash.uppercased()
        var comps = URLComponents(string: "https://trackercdn.kugou.com/i/v2/")!
        var params: [String: String] = [
            "cmd": "26",
            "hash": h,
            "behavior": "play",
            "appid": appid,
            "pid": "2",
            "mid": auth.mid,
            "userid": auth.userId.isEmpty ? "0" : auth.userId,
            "version": clientver,
            "vipType": "\(vipType)",
            "token": auth.token.isEmpty ? "0" : auth.token,
            "key": "\(h)\(playSalt)\(appid)\(auth.mid)\(auth.userId.isEmpty ? "0" : auth.userId)".kgMD5Hex,
        ]
        if let albumAudioId, !albumAudioId.isEmpty { params["album_audio_id"] = albumAudioId }
        if let albumId, !albumId.isEmpty { params["album_id"] = albumId }
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        var request = URLRequest(url: comps.url!)
        request.setValue(androidUA, forHTTPHeaderField: "User-Agent")
        request.setValue(auth.cookieHeader, forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { return (nil, 0, -1, nil) }
        var text = String(data: data, encoding: .utf8) ?? ""
        text = text.replacingOccurrences(of: "<!--KG_TAG_RES_START-->", with: "").replacingOccurrences(of: "<!--KG_TAG_RES_END-->", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] else { return (nil, 0, -2, nil) }
        let status = Self.deepInt(json, names: ["status"])
        let code = Self.deepInt(json, names: ["error_code", "errcode", "code"])
        let raw = Self.playbackURL(in: json)
        let quality = raw.isEmpty ? nil : await verifiedPlaybackQuality(url: raw, reported: Self.playbackQuality(in: json))
        return (raw.isEmpty ? nil : raw, status, code, quality)
    }

    func lyric(song: ProviderSong) async -> String {
        let hashes = Self.qualityHashCandidates(primary: song.kugouHash, qualityHashes: song.kugouQualityHashes, quality: .standard)
        for hash in hashes {
            let result = await lyric(hash: hash, duration: song.duration, albumAudioID: song.kugouAlbumAudioId)
            if !result.isEmpty { return result }
        }
        return await lyric(hash: "", duration: song.duration, albumAudioID: song.kugouAlbumAudioId,
                           keyword: "\(song.name) \(song.artists)")
    }

    func lyric(hash: String, duration: TimeInterval, albumAudioID: String? = nil, keyword: String = "") async -> String {
        guard !hash.isEmpty || !keyword.isEmpty || albumAudioID?.isEmpty == false else { return "" }
        for path in ["/v1/search", "/search"] {
            var search = URLComponents(string: "https://lyrics.kugou.com\(path)")!
            search.queryItems = [
                URLQueryItem(name: "ver", value: "1"),
                URLQueryItem(name: "man", value: "no"),
                URLQueryItem(name: "client", value: "android"),
                URLQueryItem(name: "appid", value: upstreamAppID),
                URLQueryItem(name: "clientver", value: upstreamClientVersion),
                URLQueryItem(name: "hash", value: hash.uppercased()),
                URLQueryItem(name: "album_audio_id", value: albumAudioID ?? "0"),
                URLQueryItem(name: "keyword", value: keyword),
                URLQueryItem(name: "duration", value: "\(Int(duration * 1000))"),
                URLQueryItem(name: "lrctxt", value: "1"),
            ]
            guard let json = try? await getJSON(search.url!, ua: androidUA) else { continue }
            let candidates = (json["candidates"] as? [[String: Any]]) ??
                ((json["data"] as? [String: Any])?["candidates"] as? [[String: Any]]) ?? []
            for candidate in candidates.prefix(5) {
                guard let id = candidate["id"], let key = candidate["accesskey"] else { continue }
                var download = URLComponents(string: "https://lyrics.kugou.com/download")!
                download.queryItems = [
                    URLQueryItem(name: "ver", value: "1"),
                    URLQueryItem(name: "client", value: "android"),
                    URLQueryItem(name: "id", value: "\(id)"),
                    URLQueryItem(name: "accesskey", value: "\(key)"),
                    URLQueryItem(name: "fmt", value: "lrc"),
                    URLQueryItem(name: "charset", value: "utf8"),
                ]
                guard let result = try? await getJSON(download.url!, ua: androidUA),
                      let content = result["content"] as? String,
                      let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
                      let text = String(data: data, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
                return text
            }
        }
        return ""
    }

    // MARK: - 酷狗评论

    struct KugouCommentPage {
        let comments: [ProviderSongComment]
        let total: Int
    }

    /// 酷狗官方移动评论接口。评论读取不依赖会员权限。
    func comments(mixSongID: String, hash: String?, page: Int = 1, limit: Int = 30) async throws -> KugouCommentPage {
        var commentID = mixSongID.trimmingCharacters(in: .whitespacesAndNewlines)
        if commentID.isEmpty || Int(commentID) == nil {
            commentID = try await commentAudioID(hash: hash) ?? commentID
        }
        guard !commentID.isEmpty else {
            throw ProviderRequestError.unknown("酷狗评论缺少歌曲 ID")
        }
        let params = [
            "mixsongid": commentID,
            "need_show_image": "1",
            "p": "\(max(page, 1))",
            "pagesize": "\(min(max(limit, 1), 30))",
            "show_classify": "1",
            "show_hotword_list": "1",
            "extdata": "0",
            "code": "fc4be23b4e972707f36b8a828a93ba8a",
        ]
        let json: [String: Any]
        do {
            let response = try await gatewayRequest(
                "/mcomment/v1/cmtlist",
                baseURL: gateway,
                method: "POST",
                params: params,
                headers: ["x-router": "mcomment.service.kugou.com"]
            )
            json = response.json
        } catch {
            do {
                json = try await gatewayCommentJSON(params: params)
            } catch {
                json = try await legacyCommentJSON(childrenID: commentID, page: page, limit: limit)
            }
        }
        let parsed = Self.parseComments(json: json, page: page, songName: commentID)
        if parsed.comments.isEmpty, let legacy = try? await legacyCommentJSON(childrenID: commentID, page: page, limit: limit) {
            return Self.parseComments(json: legacy, page: page, songName: commentID)
        }
        return parsed
    }

    private func gatewayCommentJSON(params: [String: String]) async throws -> [String: Any] {
        do {
            let response = try await gatewayRequest(
                "/mcomment/v1/cmtlist",
                baseURL: gateway,
                method: "GET",
                params: params,
                headers: ["x-router": "mcomment.service.kugou.com"]
            )
            return response.json
        } catch {
            let response = try await gatewayRequest(
                "/m.comment.service/v1/cmtlist",
                baseURL: gateway,
                method: "GET",
                params: params,
                headers: ["x-router": "m.comment.service.kugou.com"]
            )
            return response.json
        }
    }

    private func legacyCommentJSON(childrenID: String, page: Int, limit: Int) async throws -> [String: Any] {
        var components = URLComponents(string: "http://m.comment.service.kugou.com/index.php")!
        components.queryItems = [
            URLQueryItem(name: "r", value: "commentsv2/getCommentWithLike"),
            URLQueryItem(name: "childrenid", value: childrenID),
            URLQueryItem(name: "code", value: "fc4be23b4e972707f36b8a828a93ba8a"),
            URLQueryItem(name: "extdata", value: "0"),
            URLQueryItem(name: "p", value: "\(max(page, 1))"),
            URLQueryItem(name: "pagesize", value: "\(min(max(limit, 1), 30))"),
        ]
        guard let url = components.url else { throw ProviderRequestError.network }
        return try await getJSON(url, ua: Self.browserUA)
    }

    private func commentAudioID(hash: String?) async throws -> String? {
        guard let hash, !hash.isEmpty else { return nil }
        var components = URLComponents(string: "https://wwwapi.kugou.com/yy/index.php")!
        components.queryItems = [
            URLQueryItem(name: "r", value: "play/getdata"),
            URLQueryItem(name: "hash", value: hash.uppercased()),
            URLQueryItem(name: "appid", value: "1014"),
            URLQueryItem(name: "platid", value: "4"),
        ]
        guard let url = components.url else { return nil }
        let json = try await getJSON(url, ua: Self.browserUA)
        let value = Self.deepString(json, names: ["album_audio_id", "audio_id", "mixsongid", "songid", "id"])
        return value.isEmpty ? nil : value
    }

    private static func parseComments(json: [String: Any], page: Int, songName: String) -> KugouCommentPage {
        let rows = Self.deepArrays(
            json,
            names: ["commentlist", "comments", "list", "comment", "hot_comment", "hot_comments"]
        )
        var seen = Set<Int>()
        let comments = rows.compactMap { raw -> ProviderSongComment? in
            let rawID = Self.string(raw["commentid"] ?? raw["comment_id"] ?? raw["id"] ?? raw["cid"])
            let content = Self.clean(Self.string(
                raw["content"] ?? raw["comment_content"] ?? raw["commentContent"] ?? raw["text"]
            ))
            guard !content.isEmpty else { return nil }
            let nickname = Self.clean(Self.string(
                raw["nick"] ?? raw["nickname"] ?? raw["username"] ?? raw["user_name"] ?? raw["author"]
            ))
            let avatar = Self.string(
                raw["avatarurl"] ?? raw["avatar_url"] ?? raw["avatar"] ?? raw["user_pic"] ?? raw["headurl"]
            )
            let timestamp = Self.double(
                raw["addtime"] ?? raw["add_time"] ?? raw["time"] ?? raw["timestamp"] ?? raw["created_at"]
            )
            let seconds = timestamp > 10_000_000_000 ? timestamp / 1000 : timestamp
            let id = rawID.isEmpty ? abs(content.hashValue) : abs(rawID.hashValue)
            guard seen.insert(id).inserted else { return nil }
            return ProviderSongComment(
                id: id,
                content: content,
                nickname: nickname.isEmpty ? "酷狗用户" : nickname,
                avatarURL: avatar.isEmpty ? nil : URL(string: avatar),
                time: seconds > 0 ? Date(timeIntervalSince1970: seconds) : Date(),
                likedCount: Self.int(raw["praisenum"] ?? raw["like_count"] ?? raw["liked_count"] ?? raw["likes"]),
                isHot: page == 1
            )
        }
        let total = Self.deepInt(json, names: ["total", "commenttotal", "comment_total", "count"])
        return KugouCommentPage(comments: comments, total: total)
    }

    private func registerDevice() async throws {
        let auth = playlistIdentity
        let credentials = playlistCredentials ?? KugouMusicAuth.shared.exportedCredentials
        let guid = credentials["KUGOU_API_GUID"] ?? auth.mid
        let dataMap: [String: Any] = [
            "availableRamSize": 4983533568,
            "availableRomSize": 48114719,
            "availableSDSize": 48114717,
            "basebandVer": "",
            "batteryLevel": 100,
            "batteryStatus": 3,
            "brand": "Redmi",
            "buildSerial": "unknown",
            "device": "marble",
            "imei": guid,
            "imsi": "",
            "manufacturer": "Xiaomi",
            "uuid": guid,
            "accelerometer": false,
            "gyroscope": false,
        ]
        guard let jsonData = try? JSONSerialization.data(withJSONObject: dataMap),
              let aes = Self.randomLower(6),
              let encrypted = Self.aesCBCEncrypt(jsonData, password: aes),
              let pData = try? JSONSerialization.data(withJSONObject: ["aes": aes, "uid": Int(auth.userId) ?? 0, "token": auth.token]),
              let rsa = Self.rsaEncryptPKCS1(pData, publicKeyBase64: rsaPublicKeyBase64) else { throw ProviderRequestError.network }
        let registeredUser = auth.userId
        let registeredToken = auth.token
        do {
            let response = try await playlistRequest(
                "/risk/v2/r_register_dev",
                baseURL: userService,
                params: ["part": "1", "platid": "1", "p": rsa.kgHexString],
                dataRaw: Data(encrypted.base64EncodedString().utf8),
                headers: [
                    "x-router": "userservice.kugou.com",
                    "Content-Type": "application/json",
                ]
            )
            var json: [String: Any]?
            if let parsed = try? JSONSerialization.jsonObject(with: response.rawData) as? [String: Any] {
                json = parsed
            } else if let decrypted = Self.aesCBCDecrypt(response.rawData, password: aes),
                      let parsed = try? JSONSerialization.jsonObject(with: decrypted) as? [String: Any] {
                json = parsed
            }
            let dfid = Self.deepString(json ?? [:], names: ["dfid"])
            guard !dfid.isEmpty else { throw ProviderRequestError.unknown("酷狗设备注册失败") }
            guard playlistIdentity.userId == registeredUser, playlistIdentity.token == registeredToken else { throw CancellationError() }
            if playlistCredentials != nil { registeredPlaylistDFID = dfid }
            else { KugouMusicAuth.shared.saveDeviceDFID(dfid) }
        } catch {
            throw error
        }
    }

    // Protocol references: KuGouMusicApi user_history, user_listen, user_cloud,
    // user_cloud_url. These requests go directly to KuGou with the saved token's
    // concept-client identity; no third-party backend receives account credentials.
    struct HistoryEntry {
        let song: ProviderSong
        let playedAt: Date
    }
    struct ListeningEntry {
        let song: ProviderSong
        let count: Int
    }
    struct CloudLibrary {
        let songs: [ProviderSong]
        let usedBytes: Int64?
        let maxBytes: Int64?
    }

    private var libraryCredentials: [String: String] {
        playlistCredentials ?? playbackCredentials ?? KugouMusicAuth.shared.exportedCredentials
    }

    private func libraryIdentity() throws -> (credentials: [String: String], uid: String, token: String) {
        let credentials = libraryCredentials
        let uid = credentials["userid"] ?? credentials["user_id"] ?? ""
        let token = credentials["token"] ?? ""
        guard !uid.isEmpty, !token.isEmpty else { throw NeteaseAPIError.needLogin }
        return (credentials, uid, token)
    }

    private func libraryRequest(_ path: String, baseURL: String? = nil, method: String = "POST",
                                params: [String: String] = [:], data: [String: Any]? = nil, requiresData: Bool = true,
                                headers extraHeaders: [String: String] = [:]) async throws -> [String: Any] {
        let identity = try libraryIdentity()
        let body = try data.map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys, .withoutEscapingSlashes]) }
        var query = ["appid": appid, "clientver": clientver, "uuid": "-",
                     "clienttime": "\(Int(Date().timeIntervalSince1970))",
                     "mid": identity.credentials["KUGOU_API_MID"] ?? identity.credentials["mid"] ?? "-",
                     "dfid": identity.credentials["dfid"] ?? "-", "userid": identity.uid, "token": identity.token]
        params.forEach { query[$0.key] = $0.value }
        query["signature"] = androidSignature(params: query, data: body.map { String(decoding: $0, as: UTF8.self) } ?? "")
        var headers = ["User-Agent": androidUA, "Content-Type": "application/json",
                       "mid": query["mid"]!, "dfid": query["dfid"]!, "clienttime": query["clienttime"]!]
        extraHeaders.forEach { headers[$0.key] = $0.value }
        let response = try await request(path, baseURL: baseURL ?? gateway, method: method, params: query, body: body, headers: headers)
        try Self.validateLibraryResponse(response.json, requiresData: requiresData)
        return response.json
    }

    static func validateLibraryResponse(_ json: [String: Any], requiresData: Bool = true) throws {
        guard int(json["status"]) == 1, int(json["error_code"] ?? 0) == 0,
              (!requiresData || json["data"] is [String: Any]) else {
            throw ProviderRequestError.unknown("酷狗账号数据读取失败（\(int(json["error_code"]))），请刷新或重新登录")
        }
    }

    func uploadPlayHistory(songID: String, playedAt: Date) async throws {
        let identity = try libraryIdentity()
        guard let id = Int64(songID), id > 0 else { throw MusicProviderError.missingTrack }
        _ = try await libraryRequest("/playhistory/v1/upload_songs", params: ["plat": "3"],
            data: ["userid": Int64(identity.uid) ?? 0, "token": identity.token,
                   "songs": [["mxid": id, "op": 1, "ot": Int64(playedAt.timeIntervalSince1970), "pc": 1]]], requiresData: false)
    }

    func recentSongPlays(limit: Int = 500) async throws -> [HistoryEntry] {
        let identity = try libraryIdentity()
        let target = min(max(limit, 1), 500)
        var entries: [HistoryEntry] = []
        var seenSongs = Set<String>(), cursors = Set<String>()
        var cursor: String?
        for _ in 0..<20 {
            try Task.checkCancellation()
            var body: [String: Any] = ["userid": Int64(identity.uid) ?? 0, "token": identity.token,
                                      "source_classify": "app", "to_subdivide_sr": 1]
            if let cursor { body["bp"] = cursor }
            let json = try await libraryRequest("/playhistory/v1/get_songs", data: body)
            let data = json["data"] as! [String: Any]
            guard let rows = data["songs"] as? [[String: Any]] else { throw ProviderRequestError.unknown("酷狗历史记录格式无法识别") }
            for row in rows {
                guard var info = row["info"] as? [String: Any] else { continue }
                if info["mixsongid"] == nil { info["mixsongid"] = row["mxid"] }
                guard let song = Self.mapAccountSong(info),
                      let hash = song.kugouHash, seenSongs.insert(hash.lowercased()).inserted else { continue }
                let time = Self.double(row["ot"])
                guard time > 0 else { continue }
                entries.append(.init(song: song, playedAt: Date(timeIntervalSince1970: time > 10_000_000_000 ? time / 1000 : time)))
            }
            if entries.count >= target || Self.int(data["has_more"]) != 1 { break }
            let next = Self.string(data["bp"])
            guard !rows.isEmpty, !next.isEmpty, cursors.insert(next).inserted else { break }
            cursor = next
        }
        return Array(entries.sorted { $0.playedAt > $1.playedAt }.prefix(target))
    }

    func listeningRanking(week: Bool) async throws -> [ListeningEntry] {
        let identity = try libraryIdentity()
        let timestamp = Int(Date().timeIntervalSince1970)
        let message = try JSONSerialization.data(withJSONObject: ["clienttime": timestamp, "token": identity.token], options: [.sortedKeys])
        guard let encrypted = Self.rsaEncryptRaw(message, publicKeyBase64: rsaPublicKeyBase64) else { throw ProviderRequestError.network }
        let json = try await libraryRequest("/v2/get_list", baseURL: "https://listenservice.kugou.com",
            params: ["clienttime": String(timestamp), "plat": "0"],
            data: ["t_userid": identity.uid, "userid": identity.uid, "list_type": week ? 0 : 1,
                   "area_code": 1, "cover": 2, "p": encrypted.kgHexString.uppercased()])
        let data = json["data"] as! [String: Any]
        guard let rows = data["lists"] as? [[String: Any]] else { throw ProviderRequestError.unknown("酷狗听歌排行格式无法识别") }
        var seen = Set<String>()
        return rows.compactMap { row in
            guard let song = Self.mapAccountSong(row), let hash = song.kugouHash,
                  seen.insert(hash.lowercased()).inserted else { return nil }
            return ListeningEntry(song: song, count: max(0, Self.int(row["listen_count"])))
        }
    }

    func cloudLibrary() async throws -> CloudLibrary {
        let identity = try libraryIdentity()
        var songs: [ProviderSong] = [], seen = Set<String>()
        var used: Int64?, maximum: Int64?
        for page in 1...100 {
            try Task.checkCancellation()
            let decoded = try await cloudServiceRequest("/v1/get_list", payload: ["page": page, "pagesize": 100, "getkmr": 1],
                                                        uid: Int64(identity.uid) ?? 0, identity: identity)
            try Self.validateLibraryResponse(decoded)
            let data = decoded["data"] as! [String: Any]
            used = Int64(Self.string(data["used_size"]))
            maximum = Int64(Self.string(data["max_size"]))
            let rows: [[String: Any]]
            if let list = data["list"] as? [[String: Any]] { rows = list }
            else if Self.int(data["list_count"]) == 0 { rows = [] }
            else { throw ProviderRequestError.unknown("酷狗云盘列表格式无法识别") }
            let previousCount = songs.count
            for row in rows {
                guard let song = Self.mapCloudSong(row, ownerID: identity.uid),
                      let hash = song.kugouHash, seen.insert(hash.lowercased()).inserted else { continue }
                songs.append(song)
            }
            if rows.count < 100 || page * 100 >= Self.int(data["list_count"]) { break }
            guard songs.count > previousCount else { throw ProviderRequestError.unknown("酷狗云盘分页未继续，请重试") }
            if page == 100 { throw ProviderRequestError.unknown("云盘歌曲过多，暂无法完整载入") }
        }
        return CloudLibrary(songs: songs, usedBytes: used, maxBytes: maximum)
    }

    func userCloudURL(song: ProviderSong) async throws -> String {
        let identity = try libraryIdentity()
        guard let cloud = song.kugouCloud, cloud.ownerID == identity.uid, let hash = song.kugouHash else { throw MusicProviderError.missingTrack }
        let lower = hash.lowercased()
        let json = try await libraryRequest("/bsstrackercdngz/v2/query_musicclound_url", method: "GET", params: [
            "hash": lower, "ssa_flag": "is_fromtrack", "version": "20102", "ssl": "1", "pid": "20026",
            "album_audio_id": song.kugouAlbumAudioId ?? "0", "audio_id": cloud.audioID,
            "kv_id": "2", "key": "musicclound\(lower)20026ebd1ac3134c880bda6a2194537843caa0162e2e7".kgMD5Hex,
            "bucket": "musicclound", "name": cloud.name, "with_res_tag": "0"])
        let data = json["data"] as! [String: Any]
        let address = Self.string(data["url"] ?? data["backup_url"])
        guard let url = URL(string: address), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw OfflineAudioError.unavailable }
        return address
    }

    /// mcloudservice 请求：AES-CBC 加密请求体，RSA 信封携带 AES 口令与账号凭证。
    private func cloudServiceRequest(_ path: String, payload: [String: Any], uid: Any,
                                     identity: (credentials: [String: String], uid: String, token: String)) async throws -> [String: Any] {
        guard let password = Self.randomLower(6),
              let body = Self.aesCBCEncrypt(try JSONSerialization.data(withJSONObject: payload), password: password),
              let envelope = Self.rsaEncryptPKCS1(try JSONSerialization.data(withJSONObject: ["aes": password, "uid": uid, "token": identity.token]), publicKeyBase64: rsaPublicKeyBase64) else { throw ProviderRequestError.network }
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let response = try await request(path, baseURL: "https://mcloudservice.kugou.com", method: "POST",
            params: ["clienttime": timestamp, "mid": identity.credentials["KUGOU_API_MID"] ?? "-",
                     "key": "\(appid)\(androidSignKey)\(clientver)\(timestamp)".kgMD5Hex,
                     "clientver": clientver, "appid": appid, "p": envelope.kgHexString.uppercased()], body: body,
            headers: ["User-Agent": androidUA, "Content-Type": "application/octet-stream"])
        return Self.aesCBCDecrypt(response.rawData, password: password).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? response.json
    }

    static func validateCloudChange(_ json: [String: Any], action: String) throws {
        guard int(json["status"]) == 1, int(json["error_code"] ?? 0) == 0 else {
            let message = string(json["error_msg"] ?? json["msg"])
            throw ProviderRequestError.unknown("酷狗云盘\(action)失败（\(int(json["error_code"]))）\(message.isEmpty ? "" : "：\(message)")")
        }
    }

    /// 删除当前账号云盘中的歌曲；拒绝删除其他账号的云盘引用。
    func deleteCloudSongs(_ songs: [ProviderSong]) async throws {
        let identity = try libraryIdentity()
        let rows: [[String: Any]] = try songs.map { song in
            guard let cloud = song.kugouCloud, cloud.ownerID == identity.uid, !cloud.fileID.isEmpty else { throw MusicProviderError.missingTrack }
            return ["kv_id": Int64(cloud.fileID).map { $0 as Any } ?? cloud.fileID,
                    "album_audio_id": Int64(song.kugouAlbumAudioId ?? "") ?? 0]
        }
        guard !rows.isEmpty else { return }
        let json = try await cloudServiceRequest("/v1/del_files", payload: ["data": rows], uid: identity.uid, identity: identity)
        try Self.validateCloudChange(json, action: "删除")
    }

    struct CloudUploadSource {
        let url: URL
        let md5: String
        let size: Int64
        let ext: String
        let title: String
        let artist: String?
        let durationMS: Int
    }

    struct CloudMatch: Equatable {
        let albumAudioID: Int64
        let audioID: Int64
        let hashStd: String
        let authorName: String
        let audioName: String

        init?(_ raw: Any?) {
            let candidate = (raw as? [Any])?.first ?? raw
            guard let row = candidate as? [String: Any] else { return nil }
            let info = row["audio_info"] as? [String: Any] ?? [:]
            albumAudioID = Int64(KugouMusicAPI.string(row["album_audio_id"])) ?? 0
            audioID = Int64(KugouMusicAPI.string(info["audio_id"] ?? row["audio_id"])) ?? 0
            hashStd = KugouMusicAPI.string(info["hash"] ?? row["hash"]).lowercased()
            authorName = KugouMusicAPI.string(row["author_name"])
            audioName = KugouMusicAPI.string(row["ori_audio_name"] ?? row["audio_name"] ?? row["songname"])
            guard albumAudioID > 0 || audioID > 0 || !hashStd.isEmpty else { return nil }
        }
    }

    /// 上传前按文件 MD5 匹配曲库，命中时云盘歌曲可带上曲库信息；失败不影响上传。
    private func matchCloudFile(md5: String, identity: (credentials: [String: String], uid: String, token: String)) async -> CloudMatch? {
        let timestamp = Int(Date().timeIntervalSince1970)
        let payload: [String: Any] = ["appid": appid, "clienttime": timestamp, "clientver": clientver,
            "data": [["hash": md5]], "dfid": identity.credentials["dfid"] ?? "-",
            "key": "\(appid)\(androidSignKey)\(clientver)\(timestamp)".kgMD5Hex,
            "mid": identity.credentials["KUGOU_API_MID"] ?? identity.credentials["mid"] ?? "",
            "show_privilege": 0, "show_author_alias": 0, "show_rel_album_audio_info": 0, "show_remarks": 0]
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let response = try? await request("/v2/album_audio/audio", baseURL: gateway, method: "POST",
                  params: [:], body: body, headers: ["User-Agent": androidUA, "x-router": "kmr.service.kugou.com", "Content-Type": "application/json"]),
              Self.int(response.json["status"]) == 1, let rows = response.json["data"] as? [Any] else { return nil }
        return CloudMatch(rows.first)
    }

    /// 上传本地音频到云盘：授权 → 初始化分片 → 1MB 分片上传 → 完成 → 加入云盘列表。
    /// 服务端已有同一文件时初始化不返回 upload_id，直接加入列表（秒传）。
    func uploadCloudFile(_ file: CloudUploadSource) async throws {
        let identity = try libraryIdentity()
        let filename = file.md5.lowercased()
        let bucket = "musicclound"
        let match = await matchCloudFile(md5: filename, identity: identity)
        let common: [String: String] = ["userid": identity.uid, "token": identity.token, "version": clientver,
            "dfid": identity.credentials["dfid"] ?? "-", "mid": identity.credentials["KUGOU_API_MID"] ?? identity.credentials["mid"] ?? "",
            "uuid": identity.credentials["KUGOU_API_GUID"] ?? "-", "appid": appid, "clientver": clientver]
        func signed(_ extra: [String: String]) -> [String: String] {
            var params = common
            extra.forEach { params[$0.key] = $0.value }
            params["clienttime"] = String(Int(Date().timeIntervalSince1970))
            params["signature"] = androidSignature(params: params, data: "")
            return params
        }
        func headers(_ extra: [String: String] = [:]) -> [String: String] {
            var result = ["User-Agent": "Android15-1070-\(clientver)-201-0-wifi", "KG-RC": "1", "KG-Rec": "1",
                          "KG-THash": String(format: "%07x", Int.random(in: 0..<0xfffffff))]
            extra.forEach { result[$0.key] = $0.value }
            return result
        }
        func stageData(_ response: RawResponse, _ stage: String) throws -> [String: Any] {
            guard Self.int(response.json["status"]) == 1, let data = response.json["data"] as? [String: Any] else {
                throw ProviderRequestError.unknown("酷狗云盘上传失败：\(stage)（\(Self.int(response.json["error_code"])))")
            }
            return data
        }

        try Task.checkCancellation()
        let auth = try await request("/bsstrackercdngz/v1/upload/auth", baseURL: gateway, method: "GET",
            params: signed(["bucket": bucket, "filename": filename, "method": "POST", "loginType": "1",
                            "buVerifyCode": "\(appid)\(bucket)8ae10344e9738dcb".kgMD5Hex, "extranet": "1"]),
            body: nil, headers: headers())
        let authorization = Self.string(try stageData(auth, "获取上传授权")["authorization"])
        guard !authorization.isEmpty else { throw ProviderRequestError.unknown("酷狗云盘上传失败：获取上传授权") }

        try Task.checkCancellation()
        let initiate = try await request("/v2/multipart/initiate/music", baseURL: "http://bssulbig.kugou.com", method: "POST",
            params: signed(["bucket": bucket, "filename": filename, "ssl": "1", "extendname": file.ext, "authorization": authorization]),
            body: nil, headers: headers(["Authorization": authorization]))
        let initData = try stageData(initiate, "初始化上传")
        var storedHash = Self.string(initData["x-bss-filename"]).isEmpty ? filename : Self.string(initData["x-bss-filename"])
        let uploadID = Self.string(initData["upload_id"])
        if !uploadID.isEmpty {
            let host = Self.string(initData["external_host"])
            guard !host.isEmpty else { throw ProviderRequestError.unknown("酷狗云盘上传失败：缺少上传地址") }
            let base = host.lowercased().hasPrefix("http") ? host : "http://\(host)"
            let handle = try FileHandle(forReadingFrom: file.url)
            defer { try? handle.close() }
            var part = 0
            while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                part += 1
                let response = try await request("/v3/multipart/upload", baseURL: base, method: "POST",
                    params: signed(["bucket": bucket, "authorization": authorization, "filename": filename,
                                    "partnumber": String(part), "upload_id": uploadID, "body_empty": "1"]),
                    body: chunk, headers: headers(["Authorization": authorization, "Content-Type": "application/octet-stream"]))
                guard Self.int(response.json["status"]) == 1 else {
                    throw ProviderRequestError.unknown("酷狗云盘上传失败：第 \(part) 个分片（\(Self.int(response.json["error_code"])))")
                }
            }
            guard part > 0 else { throw ProviderRequestError.unknown("酷狗云盘上传失败：文件为空") }
            try Task.checkCancellation()
            let complete = try await request("/v3/multipart/complete", baseURL: base, method: "POST",
                params: signed(["bucket": bucket, "authorization": authorization, "filename": filename, "partnumber": String(part),
                                "upload_id": uploadID, "md5": filename, "if_id3": "1"]),
                body: nil, headers: headers(["Authorization": authorization]))
            let completed = try stageData(complete, "完成上传")
            if !Self.string(completed["x-bss-filename"]).isEmpty { storedHash = Self.string(completed["x-bss-filename"]) }
        }

        try Task.checkCancellation()
        // 没有歌手标签时不拼接占位歌手，云盘直接显示原文件名。
        let author = match.map(\.authorName).flatMap { $0.isEmpty ? nil : $0 } ?? file.artist ?? ""
        let title = match.map(\.audioName).flatMap { $0.isEmpty ? nil : $0 } ?? file.title
        let entry: [String: Any] = [
            "name": "\(author.isEmpty ? "" : "\(author) - ")\(title).\(file.ext)", "ext": file.ext, "author_name": author,
            "hash": storedHash, "hash_std": match.map(\.hashStd).flatMap { $0.isEmpty ? nil : $0 } ?? filename,
            "audio_id": match?.audioID ?? 0, "bitrate": 4, "album_audio_id": match?.albumAudioID ?? 0,
            "size": file.size, "timelen": file.durationMS]
        let json = try await cloudServiceRequest("/v1/add_files", payload: ["data": [entry], "list_ver": 0], uid: identity.uid, identity: identity)
        try Self.validateCloudChange(json, action: "上传")
    }

    static func mapAccountSong(_ raw: [String: Any]) -> ProviderSong? {
        var normalized = raw
        if raw["listen_count"] != nil, raw["songname"] == nil {
            let name = string(raw["name"]), artist = string(raw["singername"])
            let prefix = artist + " - "
            if !artist.isEmpty, name.hasPrefix(prefix) { normalized["songname"] = String(name.dropFirst(prefix.count)) }
        }
        if let album = raw["albuminfo"] as? [String: Any] { normalized["album_name"] = album["name"]; normalized["album_id"] = album["id"] }
        guard let song = mapTrack(normalized) else { return nil }
        let duration = (raw["duration"] ?? raw["timelen"]).map { double($0) / 1000 } ?? song.duration
        return ProviderSong(id: song.id, name: song.name, artists: song.artists, album: song.album, coverURL: song.coverURL,
            duration: duration, source: .kugou, kugouHash: song.kugouHash, kugouAlbumAudioId: song.kugouAlbumAudioId,
            kugouMixSongID: song.kugouMixSongID, kugouAlbumId: song.kugouAlbumId, kugouQualityHashes: song.kugouQualityHashes, fee: song.fee)
    }

    static func mapCloudSong(_ raw: [String: Any], ownerID: String) -> ProviderSong? {
        var row = raw
        let album = raw["album_info"] as? [String: Any] ?? [:]
        row["album_name"] = album["album_name"]; row["album_id"] = album["album_id"]
        row["sizable_cover"] = album["sizable_cover"]
        row["hash"] = raw["hash"] ?? raw["hash_std"]
        let name = string(raw["name"] ?? raw["audio_name"])
        let ext = (name as NSString).pathExtension.lowercased()
        row["name"] = ["mp3", "flac", "ape", "wav", "aac", "m4a", "ogg", "wma", "opus"].contains(ext) ? (name as NSString).deletingPathExtension : name
        if let authors = raw["authors"] as? [[String: Any]], !authors.isEmpty {
            row["singername"] = authors.map { string($0["author_name"]) }.filter { !$0.isEmpty }.joined(separator: " / ")
        }
        guard let song = mapAccountSong(row) else { return nil }
        return ProviderSong(id: song.id, name: song.name, artists: song.artists, album: song.album, coverURL: song.coverURL,
            duration: song.duration, source: .kugou, kugouHash: song.kugouHash, kugouAlbumAudioId: song.kugouAlbumAudioId,
            kugouAlbumId: song.kugouAlbumId, kugouCloud: .init(ownerID: ownerID, fileID: string(raw["kv_id"]),
                audioID: string(raw["audio_id"]), name: name, byteCount: Int64(string(raw["size"])) ?? 0))
    }

    func downloadResource(song: ProviderSong, track: Track, level: String, accountScope: String) async throws -> OfflineAudioResource {
        let identity = try libraryIdentity()
        guard song.kugouCloud == nil else { throw OfflineAudioError.unavailable }
        let requested = ProviderAudioQuality(rawValue: level) ?? .exhigh
        let metadata = Self.metadataQualities(song).contains(requested) && !Self.hasAliasedQualityHashes(song.kugouQualityHashes)
            ? song : await playbackMetadata(for: song)
        let hashes = Self.qualityHashCandidates(primary: metadata.kugouHash, qualityHashes: metadata.kugouQualityHashes, quality: requested)
        for hash in hashes {
            for profile in ["3116", "1005"] {
                try Task.checkCancellation()
                let params = Self.playbackParameters(hash: hash, albumAudioId: metadata.kugouAlbumAudioId, albumId: metadata.kugouAlbumId,
                    quality: requested, credentials: identity.credentials, timestamp: Int(Date().timeIntervalSince1970), clientAppID: profile)
                let response = try await request("/v5/url", baseURL: gateway, method: "GET", params: params, body: nil,
                    headers: ["x-router": "trackercdn.kugou.com", "User-Agent": androidUA,
                              "mid": params["mid"] ?? "-", "dfid": params["dfid"] ?? "-", "kg-rc": "1", "kg-thash": "5d816a0"])
                if let resource = try? Self.downloadResource(json: response.json, track: track, accountScope: accountScope) { return resource }
            }
        }
        throw OfflineAudioError.unavailable
    }

    static func downloadResource(json: [String: Any], track: Track, accountScope: String) throws -> OfflineAudioResource {
        let data = json["data"] as? [String: Any] ?? json
        guard int(json["status"] ?? data["status"]) == 1, int(json["error_code"] ?? 0) == 0,
              int(data["is_free_part"] ?? data["isFreePart"] ?? data["IsFreePart"] ?? 0) == 0,
              data["free_part"] == nil, data["freeTrialInfo"] == nil,
              let format = OfflineAudioFormat(rawValue: string(data["extName"] ?? data["extname"]).lowercased()),
              let quality = playbackQuality(in: json), track.platformSong?.source == .kugou,
              track.platformSong?.kugouCloud == nil,
              let url = URL(string: playbackURL(in: json)), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { throw OfflineAudioError.unavailable }
        let duration = double(data["timeLength"] ?? data["timelength"] ?? data["time_length"])
        guard duration > 0, track.duration > 0, abs(duration - track.duration) <= max(2, track.duration * 0.03) else { throw OfflineAudioError.invalidAudio }
        let md5 = string(data["fileHash"] ?? data["hash"]).lowercased()
        let descriptor = OfflineAudioDescriptor(identity: .init(accountScope: accountScope, trackID: track.id, source: "kugou",
            quality: quality.rawValue, format: format, contentMD5: md5),
            byteCount: Int64(string(data["fileSize"] ?? data["filesize"])) ?? 0, duration: duration)
        try descriptor.validate()
        return .init(descriptor: descriptor, url: url)
    }

    private static func rsaEncryptRaw(_ data: Data, publicKeyBase64: String) -> Data? {
        guard data.count <= 128, let keyData = Data(base64Encoded: publicKeyBase64),
              let key = SecKeyCreateWithData(keyData as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil) else { return nil }
        var padded = data; padded.append(Data(count: 128 - data.count))
        return SecKeyCreateEncryptedData(key, .rsaEncryptionRaw, padded as CFData, nil) as Data?
    }

    private enum SignType { case android, web }
    struct RawResponse { let json: [String: Any]; let rawData: Data }

    private func cloudlistRequest(_ path: String, params: [String: String], data: [String: Any]) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: data)
        return try await playlistRequest(path, params: params, dataRaw: body).json
    }

    // Account writes and device registration must use the token issuer's 3116 identity.
    // The signature includes the exact bytes sent, including base64 registration bodies.
    private func playlistRequest(_ path: String, baseURL: String? = nil, params: [String: String],
                                 dataRaw: Data, headers: [String: String] = [:]) async throws -> RawResponse {
        let auth = playlistIdentity
        var final = ["appid": appid, "clientver": clientver, "uuid": "-",
                     "clienttime": "\(Int(Date().timeIntervalSince1970))", "mid": auth.mid, "dfid": auth.dfid,
                     "userid": auth.userId, "token": auth.token]
        params.forEach { final[$0.key] = $0.value }
        final["signature"] = androidSignature(params: final, data: String(decoding: dataRaw, as: UTF8.self))
        var requestHeaders = ["User-Agent": androidUA, "x-router": "cloudlist.service.kugou.com",
            "kg-rc": "1", "kg-thash": "5d816a0", "kg-rec": "1", "kg-rf": "B9EDA08A64250DEFFBCADDEE00F8F25F",
            "dfid": auth.dfid, "mid": auth.mid, "clienttime": final["clienttime"] ?? "",
            "Content-Type": "application/json", "Cookie": auth.cookieHeader]
        headers.forEach { requestHeaders[$0.key] = $0.value }
        return try await request(path, baseURL: baseURL ?? gateway, method: "POST", params: final, body: dataRaw, headers: requestHeaders)
    }

    private func gatewayRequest(_ path: String, baseURL: String? = nil, method: String = "GET", signType: SignType = .android, params: [String: String] = [:], data: [String: Any]? = nil, dataRaw: Data? = nil, headers: [String: String] = [:], responseAsData: Bool = false) async throws -> RawResponse {
        var final = baseParams()
        params.forEach { final[$0.key] = $0.value }
        let body = try data.map { try JSONSerialization.data(withJSONObject: $0) } ?? dataRaw
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        final["signature"] = signType == .web ? webSignature(params: final) : androidSignature(params: final, data: bodyString)
        var requestHeaders = [
            "User-Agent": androidUA,
            "kg-rc": "1",
            "kg-thash": "5d816a0",
            "kg-rec": "1",
            "kg-rf": "B9EDA08A64250DEFFBCADDEE00F8F25F",
            "dfid": KugouMusicAuth.shared.dfid,
            "mid": KugouMusicAuth.shared.mid,
            "clienttime": final["clienttime"] ?? "",
        ]
        if !KugouMusicAuth.shared.cookieHeader.isEmpty { requestHeaders["Cookie"] = KugouMusicAuth.shared.cookieHeader }
        headers.forEach { requestHeaders[$0.key] = $0.value }
        let response = try await request(path, baseURL: baseURL ?? gateway, method: method, params: final, body: body, headers: requestHeaders)
        if responseAsData { return response }
        return response
    }

    /// KuGouMusicApi 的标准版请求封装。它与应用原先的 3116/11440
    /// 请求保持分开，避免不同客户端配置互相覆盖。
    func upstreamRequest(
        _ path: String,
        method: String = "GET",
        params: [String: String] = [:],
        data: [String: Any]? = nil,
        headers: [String: String] = [:],
        anonymous: Bool = false
    ) async throws -> RawResponse {
        let body = try data.map { try JSONSerialization.data(withJSONObject: $0) }
        var final = upstreamBaseParams()
        // 公开数据不带登录信息：部分接口一见 token 就会校验登录状态并拒绝。
        if anonymous { final["token"] = nil; final["userid"] = nil }
        params.forEach { final[$0.key] = $0.value }
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) } ?? ""
        final["signature"] = upstreamAndroidSignature(params: final, data: bodyString)
        var requestHeaders = upstreamHeaders(extra: headers)
        if anonymous { requestHeaders["Cookie"] = nil }
        if body != nil, requestHeaders["Content-Type"] == nil {
            requestHeaders["Content-Type"] = "application/json"
        }

        return try await request(
            path,
            baseURL: gateway,
            method: method,
            params: final,
            body: body,
            headers: requestHeaders
        )
    }

    private func upstreamBaseParams() -> [String: String] {
        let auth = KugouMusicAuth.shared
        var params: [String: String] = [
            "dfid": auth.dfid,
            "mid": auth.mid,
            "uuid": "-",
            "appid": upstreamAppID,
            "clientver": upstreamClientVersion,
            "clienttime": "\(Int(Date().timeIntervalSince1970))",
        ]
        if auth.isLoggedIn {
            params["token"] = auth.token
            params["userid"] = auth.userId
        }
        return params
    }

    func upstreamParamsKey(_ value: String) -> String {
        "\(upstreamAppID)\(upstreamSignSalt)\(upstreamClientVersion)\(value)".kgMD5Hex
    }

    private func upstreamHeaders(extra: [String: String] = [:]) -> [String: String] {
        let auth = KugouMusicAuth.shared
        var headers: [String: String] = [
            "User-Agent": androidUA,
            "kg-rc": "1",
            "kg-thash": "5d816a0",
            "kg-rec": "1",
            "kg-rf": "B9EDA08A64250DEFFBCADDEE00F8F25F",
            "dfid": auth.dfid,
            "mid": auth.mid,
        ]
        if !auth.cookieHeader.isEmpty {
            headers["Cookie"] = auth.cookieHeader
        }
        extra.forEach { headers[$0.key] = $0.value }
        return headers
    }

    private func request(_ path: String, baseURL: String, method: String, params: [String: String], body: Data?, headers: [String: String]) async throws -> RawResponse {
        guard var comps = URLComponents(string: baseURL + path) else { throw ProviderRequestError.network }
        comps.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        guard let url = comps.url else { throw ProviderRequestError.network }
        var request = URLRequest(url: url)
        request.httpMethod = method
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else { throw ProviderRequestError.network }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        return RawResponse(json: json, rawData: data)
    }

    private func baseParams() -> [String: String] {
        let auth = KugouMusicAuth.shared
        var p = [
            "dfid": auth.dfid,
            "mid": auth.mid,
            "uuid": "-",
            "appid": appid,
            "clientver": clientver,
            "clienttime": "\(Int(Date().timeIntervalSince1970))",
        ]
        if auth.isLoggedIn {
            p["token"] = auth.token
            p["userid"] = auth.userId
        }
        return p
    }

    private func androidSignature(params: [String: String], data: String) -> String {
        let body = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined()
        return "\(androidSignKey)\(body)\(data)\(androidSignKey)".kgMD5Hex
    }

    private func upstreamAndroidSignature(params: [String: String], data: String) -> String {
        let body = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined()
        return "\(upstreamSignSalt)\(body)\(data)\(upstreamSignSalt)".kgMD5Hex
    }

    private func webSignature(params: [String: String]) -> String {
        let body = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined()
        return "\(webSignKey)\(body)\(webSignKey)".kgMD5Hex
    }

    private func getJSON(_ url: URL, ua: String) async throws -> [String: Any] {
        try await getJSON(url, ua: ua, headers: [:])
    }

    private func getJSON(_ url: URL, ua: String, headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw ProviderRequestError.network }
        return obj
    }

    private func getString(_ url: URL, ua: String) async throws -> String {
        var request = URLRequest(url: url)
        request.setValue(ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://www.kugou.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let text = String(data: data, encoding: .utf8) else { throw ProviderRequestError.network }
        return text
    }

    private static func searchSignature(_ params: [String: String]) -> String {
        let body = params
            .filter { $0.key != "signature" }
            .keys
            .sorted()
            .map { "\($0)=\(params[$0] ?? "")" }
            .joined()
        return "y9tjae~n)k)vn[8\(body)y9tjae~n)k)vn[8".kgMD5Hex
    }

    private static func javascriptArray(named name: String, in html: String) -> [[String: Any]]? {
        javascriptJSON(named: name, in: html, opening: "[", closing: "]") as? [[String: Any]]
    }

    private static func javascriptJSON(named name: String, in html: String, opening: Character, closing: Character) -> Any? {
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: name) + "\\s*=\\s*" + NSRegularExpression.escapedPattern(for: String(opening))
        guard let startRange = html.range(of: pattern, options: .regularExpression),
              let openIndex = html[startRange.lowerBound..<startRange.upperBound].lastIndex(of: opening) else { return nil }
        var depth = 0
        var inString = false
        var escaped = false
        var endIndex: String.Index?
        var index = openIndex
        while index < html.endIndex {
            let char = html[index]
            if inString {
                if escaped {
                    escaped = false
                } else if char == "\\" {
                    escaped = true
                } else if char == "\"" {
                    inString = false
                }
            } else if char == "\"" {
                inString = true
            } else if char == opening {
                depth += 1
            } else if char == closing {
                depth -= 1
                if depth == 0 {
                    endIndex = html.index(after: index)
                    break
                }
            }
            index = html.index(after: index)
        }
        guard let endIndex else { return nil }
        let jsonText = String(html[openIndex..<endIndex])
        guard let data = jsonText.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func regexMatches(_ pattern: String, in text: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return [] }
        let nsrange = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: nsrange).map { match in
            (0..<match.numberOfRanges).map { index in
                guard let range = Range(match.range(at: index), in: text) else { return "" }
                return String(text[range])
            }
        }
    }

    private static func normalizeURL(_ value: String) -> String {
        if value.hasPrefix("//") { return "https:" + value }
        if value.hasPrefix("http://") { return "https://" + String(value.dropFirst("http://".count)) }
        return value
    }

    private static func htmlDecode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }

    // Cloud collections use `name` for the display filename ("artist - title"),
    // unlike search responses, where `name` can be the standalone song title.
    static func mapCloudPlaylistTrack(_ raw: [String: Any]) -> ProviderSong? {
        var normalized = raw
        func firstText(_ values: Any?...) -> String? {
            values.map { clean(string($0)) }.first { !$0.isEmpty }
        }
        normalized["filename"] = firstText(raw["filename"], raw["FileName"], raw["name"])
        normalized["songname"] = firstText(raw["songname"], raw["song_name"], raw["SongName"], raw["OriSongName"])
        let singers = raw["singerinfo"] as? [[String: Any]] ?? raw["authors"] as? [[String: Any]] ?? []
        let artistNames = singers.compactMap { firstText($0["name"], $0["author_name"], $0["singername"]) }
        normalized["singername"] = firstText(
            raw["singername"], raw["SingerName"], raw["singer_name"], raw["author_name"],
            raw["artist"], artistNames.joined(separator: " / ")
        )
        let albumInfo = raw["albuminfo"] as? [String: Any] ?? [:]
        normalized["album_name"] = firstText(raw["album_name"], raw["AlbumName"], raw["albumname"], albumInfo["name"], raw["album"])
        return mapCompleteTrack(normalized)
    }

    static func mapCompleteTrack(_ raw: [String: Any]) -> ProviderSong? {
        var normalized = raw
        if normalized["singername"] == nil,
           let authors = raw["authors"] as? [[String: Any]] {
            let names = authors.compactMap { author -> String? in
                let name = string(author["author_name"] ?? author["name"])
                return name.isEmpty ? nil : name
            }
            if !names.isEmpty { normalized["singername"] = names.joined(separator: " / ") }
        }
        normalized["songname"] = raw["SongName"] ?? raw["OriSongName"] ?? raw["songname"] ?? raw["FileName"]
        normalized["filename"] = raw["FileName"] ?? raw["SongName"] ?? raw["filename"]
        normalized["singername"] = raw["SingerName"] ?? raw["singername"] ?? normalized["singername"]
        normalized["album_name"] = raw["AlbumName"] ?? raw["album_name"]
        normalized["hash"] = raw["FileHash"] ?? raw["Hash"] ?? raw["hash"]
        normalized["album_audio_id"] = raw["AlbumAudioID"] ?? raw["MixSongID"] ?? raw["album_audio_id"] ?? raw["albumAudioId"]
        normalized["mixsongid"] = raw["MixSongID"] ?? raw["mixsongid"] ?? raw["mix_song_id"]
        normalized["audio_id"] = raw["audio_id"] ?? raw["Audioid"] ?? raw["audioid"] ?? raw["encrypt_id"]
        normalized["album_id"] = raw["AlbumID"] ?? raw["album_id"]
        normalized["duration"] = raw["Duration"] ?? raw["duration"] ?? raw["timeLen"] ?? raw["timelength"]
        normalized["album_sizable_cover"] = raw["Image"] ?? raw["ImageUrl"] ?? raw["AlbumImg"] ?? raw["album_sizable_cover"]
        normalized["pay_type"] = raw["PayType"] ?? raw["Privilege"] ?? raw["pay_type"]
        normalized["feetype"] = raw["FeeType"] ?? raw["feetype"]
        normalized["privilege"] = raw["Privilege"] ?? raw["privilege"]
        normalized["pay_type_320"] = raw["PayType320"] ?? raw["pay_type_320"]
        normalized["pay_type_sq"] = raw["PayTypeSQ"] ?? raw["pay_type_sq"]
        return mapTrack(normalized)
    }

    static func mapPlaylist(_ raw: [String: Any], accountUserID: String? = nil) -> ProviderPlaylist? {
        let id = int(raw["listid"] ?? raw["id"] ?? raw["global_collection_id"] ?? raw["specialid"])
        guard id > 0 else { return nil }
        let name = string(raw["name"] ?? raw["listname"] ?? raw["list_name"] ?? raw["specialname"] ?? raw["title"])
        let cover = string(raw["pic"] ?? raw["img"] ?? raw["cover"] ?? raw["sizable_cover"] ?? raw["list_pic"]).replacingOccurrences(of: "{size}", with: "240")
        let count = int(raw["count"] ?? raw["song_count"] ?? raw["total"] ?? raw["file_count"] ?? raw["songcount"])
        var item = ProviderPlaylist(id: id, name: name.isEmpty ? "酷狗歌单" : name, coverURL: URL(string: cover), trackCount: count, source: .kugou)
        item.kugouGlobalCollectionID = string(raw["global_collection_id"] ?? raw["collection_id"])
        item.kugouCreateUserID = string(raw["list_create_userid"] ?? raw["create_userid"] ?? raw["userid"])
        item.kugouCreateListID = string(raw["list_create_listid"] ?? raw["create_listid"])
        item.kugouCreateGID = string(raw["list_create_gid"] ?? raw["create_gid"])
        if item.kugouGlobalCollectionID?.isEmpty != false { item.kugouGlobalCollectionID = string(raw["gid"]) }
        item.kugouIntro = raw["intro"].map(string)
        item.kugouTags = (raw["tags"] as? String) ?? (raw["tags"] as? [Any])?.map { string(($0 as? [String: Any])?["tag_name"] ?? $0) }.joined(separator: ",")
        item.kugouSort = raw["sort"].map(int)
        if let accountUserID {
            item.ownerID = accountUserID
            item.isSubscribed = int(raw["type"]) == 1
            item.isOwned = item.isSubscribed != true
        }
        return item
    }

    private static func mapTrack(_ raw: [String: Any]) -> ProviderSong? {
        let trans = raw["trans_param"] as? [String: Any] ?? raw["transParam"] as? [String: Any] ?? [:]
        let qualityHashes = qualityHashes(raw: raw, trans: trans)
        let hash = string(raw["hash"] ?? raw["Hash"] ?? raw["file_hash"] ?? raw["FileHash"] ?? raw["audio_hash"] ?? qualityHashes["exhigh"] ?? qualityHashes["standard"] ?? qualityHashes["lossless"])
        let albumAudioId = string(raw["album_audio_id"] ?? raw["albumAudioId"] ?? raw["audio_id"] ?? raw["audioid"] ?? raw["mixsongid"] ?? raw["songid"] ?? raw["id"])
        let explicitMixID = string(raw["MixSongID"] ?? raw["mixsongid"] ?? raw["mix_song_id"])
        let inferredMixID = raw["AlbumAudioID"] == nil ? string(raw["album_audio_id"] ?? raw["albumAudioId"]) : ""
        let mixSongID = explicitMixID.isEmpty ? inferredMixID : explicitMixID
        let stable = (hash.isEmpty ? albumAudioId : hash).hashValue & Int.max
        var title = clean(string(raw["songname"] ?? raw["song_name"] ?? raw["name"] ?? raw["title"]))
        var artist = clean(string(raw["singername"] ?? raw["singer_name"] ?? raw["author_name"] ?? raw["singer"] ?? raw["artist"]))
        let filename = clean(string(raw["filename"] ?? raw["FileName"]))
        if !filename.isEmpty {
            let parts = filename.components(separatedBy: " - ")
            if parts.count >= 2 {
                if artist.isEmpty { artist = clean(parts[0]) }
                if title.isEmpty || title == filename { title = clean(parts.dropFirst().joined(separator: " - ")) }
            } else if title.isEmpty {
                title = filename
            }
        }
        guard !title.isEmpty, !hash.isEmpty || !albumAudioId.isEmpty else { return nil }
        let album = string(raw["album_name"] ?? raw["albumname"] ?? raw["album"] ?? (raw["albuminfo"] as? [String: Any])?["name"])
        let cover = normalizeURL(
            string(raw["pic"] ?? raw["img"] ?? raw["image"] ?? raw["cover"] ?? raw["album_sizable_cover"] ?? raw["sizable_cover"] ?? trans["union_cover"])
                .replacingOccurrences(of: "{size}", with: "300")
        )
        let durRaw = double(raw["timelength"] ?? raw["time_length"] ?? raw["timelen"] ?? raw["duration"] ?? raw["interval"])
        let seconds = durRaw > 1000 ? durRaw / 1000.0 : durRaw
        return ProviderSong(
            id: stable,
            name: title,
            artists: artist.isEmpty ? clean(string(raw["h5_author_name"] ?? raw["authors"])) : artist,
            album: album,
            coverURL: URL(string: cover),
            duration: seconds,
            source: .kugou,
            kugouHash: hash,
            kugouAlbumAudioId: albumAudioId,
            kugouMixSongID: mixSongID.isEmpty ? nil : mixSongID,
            kugouAlbumId: string(raw["album_id"] ?? raw["albumid"] ?? raw["AlbumID"] ?? raw["albumId"]),
            kugouQualityHashes: qualityHashes.isEmpty ? nil : qualityHashes,
            fee: kugouVIPFee(raw)
        )
    }

    private static func mergeRankCovers(primary: [ProviderSong], fallback: [ProviderSong]) -> [ProviderSong] {
        var byHash: [String: ProviderSong] = [:]
        var byAudioId: [String: ProviderSong] = [:]
        var byTitle: [String: ProviderSong] = [:]
        for song in fallback where song.coverURL != nil {
            if let hash = song.kugouHash?.lowercased(), !hash.isEmpty { byHash[hash] = song }
            if let audioId = song.kugouAlbumAudioId, !audioId.isEmpty { byAudioId[audioId] = song }
            byTitle[rankCoverMatchKey(song)] = song
        }
        return primary.map { song in
            guard song.coverURL == nil else { return song }
            let fallbackSong: ProviderSong?
            if let hash = song.kugouHash?.lowercased(), !hash.isEmpty, let hit = byHash[hash] {
                fallbackSong = hit
            } else if let audioId = song.kugouAlbumAudioId, !audioId.isEmpty, let hit = byAudioId[audioId] {
                fallbackSong = hit
            } else {
                fallbackSong = byTitle[rankCoverMatchKey(song)]
            }
            guard let coverURL = fallbackSong?.coverURL else { return song }
            return ProviderSong(
                id: song.id,
                name: song.name,
                artists: song.artists,
                album: song.album,
                coverURL: coverURL,
                duration: song.duration,
                source: song.source,
                qqMid: song.qqMid,
                qqMediaMid: song.qqMediaMid,
                kugouHash: song.kugouHash,
                kugouAlbumAudioId: song.kugouAlbumAudioId,
                kugouMixSongID: song.kugouMixSongID,
                kugouAlbumId: song.kugouAlbumId,
                kugouQualityHashes: song.kugouQualityHashes,
                fee: song.fee
            )
        }
    }

    private static func mergeRankSongs(primary: [ProviderSong], fallback: [ProviderSong], limit: Int) -> [ProviderSong] {
        let target = max(limit, 1)
        var result: [ProviderSong] = []
        var seenIdentity = Set<String>()
        var seenContent = Set<String>()

        for song in primary + fallback {
            let contentKey = rankSongContentKey(song)
            guard seenIdentity.insert(song.identityKey).inserted else { continue }
            if !contentKey.isEmpty, !seenContent.insert(contentKey).inserted { continue }
            result.append(song)
            if result.count >= target { break }
        }
        return result
    }

    private static func rankSongContentKey(_ song: ProviderSong) -> String {
        if let hash = song.kugouHash?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), !hash.isEmpty {
            return "hash:\(hash)"
        }
        if let audioID = song.kugouAlbumAudioId?.trimmingCharacters(in: .whitespacesAndNewlines), !audioID.isEmpty {
            return "audio:\(audioID)"
        }
        return "meta:\(song.name.lowercased())|\(song.artists.lowercased())|\(song.album.lowercased())|\(Int(song.duration))"
    }

    private static func rankCoverMatchKey(_ song: ProviderSong) -> String {
        "\(song.name)|\(song.artists)".lowercased()
    }

    private static func qualityHashes(raw: [String: Any], trans: [String: Any]) -> [String: String] {
        let values: [(String, String)] = [
            ("standard", string(raw["128hash"] ?? raw["hash"] ?? raw["Hash"] ?? raw["file_hash"] ?? raw["FileHash"] ?? trans["ogg_128_hash"])),
            ("exhigh", string(raw["320hash"] ?? raw["HQFileHash"] ?? raw["HQHash"] ?? trans["ogg_320_hash"])),
            ("lossless", string(raw["sqhash"] ?? raw["SQFileHash"] ?? raw["flac_hash"] ?? raw["SQHash"] ?? trans["sqhash"])),
            ("hires", string(raw["hrhash"] ?? raw["high_hash"] ?? raw["ResFileHash"] ?? raw["HiResHash"] ?? trans["high_hash"])),
        ]
        var result: [String: String] = [:]
        for (key, value) in values where !value.isEmpty {
            result[key] = value
        }
        return result
    }

    private static func qualityHashCandidates(primary: String?, qualityHashes: [String: String]?, quality requestedQuality: ProviderAudioQuality? = nil) -> [String] {
        let requested = requestedQuality ?? ProviderAudioQuality.current
        let order: [String]
        switch requested {
        case .hires:
            order = ["hires", "lossless", "exhigh", "standard"]
        case .lossless:
            order = ["lossless", "exhigh", "standard"]
        case .exhigh, .higher:
            order = ["exhigh", "standard"]
        case .standard:
            order = ["standard"]
        }
        var seen = Set<String>()
        var result: [String] = []
        func append(_ value: String?) {
            let hash = (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !hash.isEmpty, !seen.contains(hash) else { return }
            seen.insert(hash)
            result.append(hash)
        }
        for key in order { append(qualityHashes?[key]) }
        append(primary)
        ["hires", "lossless", "exhigh", "standard"].forEach { append(qualityHashes?[$0]) }
        return result
    }

    private static func vipTypeCandidates(_ vipType: Int) -> [Int] {
        let values = vipType > 0 ? [vipType, 0] : [0]
        var seen = Set<Int>()
        return values.filter { seen.insert($0).inserted }
    }

    private static func clean(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: #"\.(mp3|flac|m4a|aac|ogg|wav)$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func kugouVIPFee(_ raw: [String: Any]) -> Int {
        let explicitKeys: Set<String> = [
            "fee", "feetype", "fee_type", "pay_type", "paytype", "paytype320",
            "pay_type_320", "pay_type_sq", "media_pay_type", "needpay", "need_pay"
        ]
        let boolKeys: Set<String> = [
            "vip", "isvip", "is_vip", "onlyvipplayable", "only_vip_playable",
            "viprequired", "vip_required", "needvip", "need_vip"
        ]
        var explicit = 0
        var privilege = 0
        var flag = false
        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    let normalized = key
                        .replacingOccurrences(of: "_", with: "")
                        .replacingOccurrences(of: "-", with: "")
                        .lowercased()
                    let lower = key.lowercased()
                    if explicitKeys.contains(lower) || explicitKeys.contains(normalized) {
                        explicit = max(explicit, int(child))
                    }
                    if lower == "privilege" || lower == "media_privilege" || lower == "320privilege" || lower == "sqprivilege" {
                        privilege = max(privilege, int(child))
                    }
                    if boolKeys.contains(lower) || boolKeys.contains(normalized) {
                        if let bool = child as? Bool, bool { flag = true }
                        if int(child) > 0 { flag = true }
                        let text = string(child).lowercased()
                        if text == "true" || text.contains("vip") || text.contains("会员") { flag = true }
                    }
                    walk(child)
                }
            } else if let array = value as? [Any] {
                array.forEach(walk)
            }
        }
        walk(raw)
        if explicit > 0 { return explicit }
        if privilege >= 9 { return 1 }
        if flag { return 1 }
        return 0
    }

    private static func deepString(_ obj: Any, names: [String]) -> String {
        if let value = deepValue(obj, names: names), let array = value as? [Any] {
            return array.first.map { string($0) } ?? ""
        }
        return string(deepValue(obj, names: names))
    }

    private static func deepInt(_ obj: Any, names: [String]) -> Int { int(deepValue(obj, names: names)) }

    private static func deepArrays(_ obj: Any, names: [String]) -> [[String: Any]] {
        var best: [[String: Any]] = []
        func walk(_ value: Any) {
            if let array = value as? [[String: Any]], array.count > best.count {
                best = array
            } else if let dict = value as? [String: Any] {
                for (key, child) in dict {
                    if names.contains(where: { $0.lowercased() == key.lowercased() }) {
                        walk(child)
                    }
                }
                if best.isEmpty {
                    dict.values.forEach(walk)
                }
            } else if let array = value as? [Any] {
                for child in array { walk(child) }
            }
        }
        walk(obj)
        return best
    }

    private static func deepValue(_ obj: Any, names: [String]) -> Any? {
        let wanted = Set(names.map { $0.lowercased() })
        func walk(_ value: Any) -> Any? {
            if let dict = value as? [String: Any] {
                for (key, child) in dict where wanted.contains(key.lowercased()) {
                    return child
                }
                for child in dict.values {
                    if let found = walk(child) { return found }
                }
            } else if let array = value as? [Any] {
                for child in array {
                    if let found = walk(child) { return found }
                }
            }
            return nil
        }
        return walk(obj)
    }

    private static func string(_ value: Any?) -> String {
        if let s = value as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
        if let n = value as? NSNumber { return n.stringValue }
        return ""
    }

    private static func int(_ value: Any?) -> Int {
        if let i = value as? Int { return i }
        if let n = value as? NSNumber { return n.intValue }
        if let s = value as? String { return Int(s) ?? 0 }
        return 0
    }

    private static func double(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    private static func urlEncode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? text
    }

    private static var browserUA: String {
        "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148"
    }

    private static func randomLower(_ length: Int) -> String? {
        let chars = Array("1234567890abcdefghijklmnopqrstuvwxyz")
        return String((0..<length).map { _ in chars[Int.random(in: 0..<chars.count)] })
    }

    private static func aesCBCEncrypt(_ data: Data, password: String) -> Data? {
        let digest = password.kgMD5Hex
        return crypt(data, op: CCOperation(kCCEncrypt), key: Data(digest.prefix(16).utf8), iv: Data(digest.suffix(16).utf8))
    }

    private static func aesCBCDecrypt(_ data: Data, password: String) -> Data? {
        let digest = password.kgMD5Hex
        return crypt(data, op: CCOperation(kCCDecrypt), key: Data(digest.prefix(16).utf8), iv: Data(digest.suffix(16).utf8))
    }

    private static func crypt(_ data: Data, op: CCOperation, key: Data, iv: Data, keySize: Int = kCCKeySizeAES128) -> Data? {
        var out = Data(count: data.count + kCCBlockSizeAES128)
        let outputCapacity = out.count
        var outLen = 0
        let status = out.withUnsafeMutableBytes { outPtr in
            data.withUnsafeBytes { dataPtr in
                key.withUnsafeBytes { keyPtr in
                    iv.withUnsafeBytes { ivPtr in
                        CCCrypt(op, CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding), keyPtr.baseAddress, keySize, ivPtr.baseAddress, dataPtr.baseAddress, data.count, outPtr.baseAddress, outputCapacity, &outLen)
                    }
                }
            }
        }
        guard status == kCCSuccess else { return nil }
        out.removeSubrange(outLen..<outputCapacity)
        return out
    }

    private static func rsaEncryptPKCS1(_ data: Data, publicKeyBase64: String) -> Data? {
        guard let keyData = Data(base64Encoded: publicKeyBase64) else { return nil }
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits: 1024,
        ]
        guard let key = SecKeyCreateWithData(keyData as CFData, attrs as CFDictionary, nil) else { return nil }
        var error: Unmanaged<CFError>?
        guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, &error) else { return nil }
        return encrypted as Data
    }
}

// Protocol reference: MakcRe/KuGouMusicApi module/{playlist_tracks_del, playlist_update,
// artist_follow, artist_unfollow, user_follow, search_suggest, search}.js.
extension KugouMusicAPI {
    // MARK: Playlist edits

    /// Matches songs to the list-local `fileid` the delete endpoint requires.
    static func playlistFileIDs(rows: [[String: Any]], songs: [ProviderSong]) throws -> [Int] {
        try songs.map { song in
            let hash = (song.kugouHash ?? "").lowercased()
            let mixIDs = Set([song.kugouMixSongID, song.kugouAlbumAudioId].compactMap { $0 }.filter { !$0.isEmpty && $0 != "0" })
            let row = rows.first { row in
                let rowMix = [row["mixsongid"], row["album_audio_id"], row["MixSongID"]].map(string).filter { !$0.isEmpty && $0 != "0" }
                if rowMix.contains(where: mixIDs.contains) { return true }
                let rowHash = string(row["hash"] ?? row["FileHash"] ?? row["Hash"]).lowercased()
                return !hash.isEmpty && rowHash == hash
            }
            let fileID = int(row?["fileid"] ?? row?["file_id"] ?? row?["FileId"])
            guard fileID > 0 else { throw ProviderRequestError.unknown("未在歌单中找到这首歌，请刷新后重试") }
            return fileID
        }
    }

    func deleteSongs(listID: Int, songs: [ProviderSong]) async throws {
        try await preparePlaylistDevice()
        guard !songs.isEmpty else { return }
        let fileIDs = try Self.playlistFileIDs(rows: try await cloudPlaylistRows(listID: listID), songs: songs)
        let auth = playlistIdentity
        let json = try await cloudlistRequest("/v4/delete_songs", params: [:],
            data: ["listid": listID, "userid": Int(auth.userId) ?? 0, "token": auth.token, "type": 0, "list_ver": 0,
                   "data": fileIDs.map { ["fileid": $0] }])
        try Self.validatePlaylistMutation(json)
    }

    /// The cloud-list AES/RSA envelope that `v2/delete_list` already uses.
    private func encryptedCloudRequest(_ path: String, body: [String: Any]) async throws -> [String: Any] {
        try await preparePlaylistDevice()
        let auth = playlistIdentity
        guard let password = Self.randomLower(6) else { throw ProviderRequestError.network }
        let data = try JSONSerialization.data(withJSONObject: body)
        let credentials = try JSONSerialization.data(withJSONObject: ["aes": password, "uid": Int(auth.userId) ?? 0, "token": auth.token])
        guard let encrypted = Self.aesCBCEncrypt(data, password: password),
              let rsa = Self.rsaEncryptPKCS1(credentials, publicKeyBase64: rsaPublicKeyBase64) else { throw ProviderRequestError.network }
        let timestamp = "\(Int(Date().timeIntervalSince1970))"
        let response = try await playlistRequest(path,
            params: ["clienttime": timestamp, "key": "\(appid)\(androidSignKey)\(clientver)\(timestamp)".kgMD5Hex,
                     "last_area": "gztx", "last_time": timestamp, "p": rsa.kgHexString.uppercased()],
            dataRaw: Data(encrypted.base64EncodedString().utf8),
            headers: ["x-router": "cloudlist.service.kugou.com", "Content-Type": "application/json"])
        return Self.aesCBCDecrypt(response.rawData, password: password)
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? response.json
    }

    static func renameBody(playlist: ProviderPlaylist, name: String) -> [String: Any] {
        ["total_ver": 0, "listid": playlist.id, "type": 0, "sort": playlist.kugouSort ?? 0,
         "tags": playlist.kugouTags ?? "", "intro": playlist.kugouIntro ?? "", "name": name]
    }

    func renamePlaylist(_ playlist: ProviderPlaylist, name: String) async throws -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 50 else { throw ProviderRequestError.unknown("歌单名称需为 1–50 个字") }
        let json = try await encryptedCloudRequest("/v1/modify_list", body: Self.renameBody(playlist: playlist, name: name))
        try Self.validatePlaylistMutation(json)
        return name
    }

    // MARK: Followed singers

    /// `cryptoAesEncrypt`: key = MD5(random 16 lowercase), IV = key's last 16 chars, hex output.
    static func followEnvelope(_ object: [String: Any], tempKey: String) -> (params: String, key: String)? {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        let key = tempKey.kgMD5Hex
        guard let encrypted = crypt(data, op: CCOperation(kCCEncrypt), key: Data(key.utf8),
                                    iv: Data(key.suffix(16).utf8), keySize: kCCKeySizeAES256) else { return nil }
        return (encrypted.kgHexString, tempKey)
    }

    // Uses the account's 3116 identity, matching the RSA key the payload is encrypted with.
    func setFollowed(singerID: Int, follow: Bool) async throws {
        let identity = try libraryIdentity()
        guard singerID > 0, let tempKey = Self.randomLower(16),
              let envelope = Self.followEnvelope(["singerid": singerID, "token": identity.token], tempKey: tempKey) else {
            throw MusicProviderError.missingTrack
        }
        let clientTime = Int(Date().timeIntervalSince1970)
        let portrait = try JSONSerialization.data(withJSONObject: ["clienttime": clientTime, "key": envelope.key], options: [.sortedKeys])
        guard let rsa = Self.rsaEncryptPKCS1(portrait, publicKeyBase64: rsaPublicKeyBase64) else { throw ProviderRequestError.network }
        _ = try await libraryRequest("/followservice/v3/\(follow ? "follow_singer" : "unfollow_singer")",
            params: ["clienttime": String(clientTime)],
            data: ["plat": 0, "userid": Int(identity.uid) ?? 0, "singerid": singerID, "source": 7,
                   "p": rsa.kgHexString, "params": envelope.params], requiresData: false)
    }

    func followedSingers() async throws -> [ProviderArtist] {
        let identity = try libraryIdentity()
        let clientTime = Int(Date().timeIntervalSince1970)
        let message = try JSONSerialization.data(withJSONObject: ["clienttime": clientTime, "token": identity.token], options: [.sortedKeys])
        guard let encrypted = Self.rsaEncryptRaw(message, publicKeyBase64: rsaPublicKeyBase64) else { throw ProviderRequestError.network }
        let json = try await libraryRequest("/v4/follow_list", params: ["plat": "1", "clienttime": String(clientTime)],
            data: ["merge": 2, "need_iden_type": 1, "ext_params": "k_pic,jumptype,singerid,score", "userid": identity.uid,
                   "type": 0, "id_type": 0, "p": encrypted.kgHexString.uppercased()],
            requiresData: false, headers: ["x-router": "relationuser.kugou.com"])
        return Self.followedSingers(in: json)
    }

    static func followedSingers(in json: [String: Any]) -> [ProviderArtist] {
        var seen = Set<String>()
        return deepArrays(json, names: ["lists", "list", "info"]).compactMap { row in
            let id = string(row["singerid"] ?? row["singer_id"] ?? row["userid"])
            let name = clean(string(row["nickname"] ?? row["singername"] ?? row["name"]))
            guard !id.isEmpty, id != "0", !name.isEmpty, seen.insert(id).inserted else { return nil }
            let cover = string(row["k_pic"] ?? row["pic"] ?? row["avatar"]).replacingOccurrences(of: "{size}", with: "240")
            return ProviderArtist(id: id, name: name, coverURL: URL(string: cover), source: .kugou)
        }
    }

    // MARK: Search

    func searchSuggestions(keyword: String, limit: Int = 8) async throws -> [String] {
        let keyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return [] }
        let response = try await upstreamRequest("/v2/getSearchTip",
            params: ["keyword": keyword, "AlbumTipCount": "0", "CorrectTipCount": "10", "MVTipCount": "0",
                     "MusicTipCount": "10", "radiotip": "1"],
            headers: ["x-router": "searchtip.kugou.com"], anonymous: true)
        return Array(Self.searchTips(in: response.json, excluding: keyword).prefix(limit))
    }

    static func searchTips(in json: [String: Any], excluding keyword: String) -> [String] {
        var seen = Set<String>(), result: [String] = []
        // Tips are grouped (`data[].RecordDatas[]`); collect hints from every group.
        func walk(_ value: Any, depth: Int) {
            guard depth < 6 else { return }
            if let row = value as? [String: Any] {
                let text = clean(string(row["HintInfo"] ?? row["hintinfo"]))
                if !text.isEmpty {
                    if text != keyword, seen.insert(text).inserted { result.append(text) }
                    return
                }
                row.keys.sorted().forEach { walk(row[$0]!, depth: depth + 1) }
            } else if let list = value as? [Any] {
                list.forEach { walk($0, depth: depth + 1) }
            }
        }
        walk(json, depth: 0)
        return result
    }

    func searchPlaylists(keyword: String, page: Int = 1, limit: Int = 30) async throws -> [ProviderPlaylist] {
        let response = try await upstreamRequest("/v1/search/special",
            params: ["albumhide": "0", "iscorrection": "1", "keyword": keyword, "nocollect": "0",
                     "page": "\(max(page, 1))", "pagesize": "\(min(max(limit, 1), 30))", "platform": "AndroidFilter"],
            headers: ["x-router": "complexsearch.kugou.com"])
        var seen = Set<Int>()
        return Self.deepArrays(response.json, names: ["lists", "list", "info"]).compactMap { row in
            guard var playlist = Self.mapPlaylist(row), seen.insert(playlist.id).inserted else { return nil }
            playlist.ownerID = nil
            return playlist
        }
    }
}

private extension Data {
    var kgHexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}

private extension String {
    var kgMD5Hex: String { Data(utf8).md5Hex() }
}
