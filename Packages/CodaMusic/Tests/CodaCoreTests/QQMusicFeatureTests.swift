import CryptoKit
import Foundation
import Testing
@testable import CodaCore

private final class QQMusicFeatureFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var states: [String: Set<String>] = [:]

    private func saved(_ key: String, set value: Bool? = nil) -> Bool {
        Self.lock.lock()
        defer { Self.lock.unlock() }
        let fixture = request.value(forHTTPHeaderField: "X-Fixture-ID") ?? ""
        if let value {
            if value { Self.states[fixture, default: []].insert(key) }
            else { Self.states[fixture]?.remove(key) }
        }
        return Self.states[fixture]?.contains(key) == true
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var object: [String: Any] = [:]
        let rejected = request.value(forHTTPHeaderField: "X-Fixture-Reject") == "yes"
        let unconfirmed = request.value(forHTTPHeaderField: "X-Fixture-Unconfirmed") == "yes"
        let expiring = request.value(forHTTPHeaderField: "X-Fixture-Expiring") == "yes"
        let web = request.url!.host == "u6.y.qq.com"
        if request.url!.host == "api.tencentmusic.com" {
            #expect(request.value(forHTTPHeaderField: "method") == "GetQimei")
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            object = ["code": 0, "data": ["code": 0, "data": ["q16": "fixture-q16", "q36": "fixture-q36"]]]
        } else if request.url!.host == "u.y.qq.com" || web {
            var body = Self.body(request)
            if web {
                #expect(request.url?.query?.contains("encoding=ag-1") == true)
                #expect(request.url?.query?.contains("sign=zzc") == true)
                #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("tmeLoginType=2") == true)
                let key = SymmetricKey(data: Data([189, 48, 95, 16, 208, 255, 116, 182, 239, 84, 218, 184, 53, 181, 225, 207]))
                if let encrypted = Data(base64Encoded: body),
                   let decoded = try? AES.GCM.open(.init(combined: encrypted), using: key) { body = decoded }
            }
            let payload = (try? JSONSerialization.jsonObject(with: body)) as? [String: Any] ?? [:]
            let modern = payload["req_0"] != nil
            let key = modern ? "req_0" : "req_1"
            let operation = payload[key] as? [String: Any] ?? [:]
            let method = operation["method"] as? String ?? ""
            let params = operation["param"] as? [String: Any] ?? [:]
            if modern && !web {
                let comm = payload["comm"] as? [String: Any]
                #expect(request.value(forHTTPHeaderField: "User-Agent") == "QQMusic 14090008(android 10)")
                #expect(comm?["ct"] as? Int == 11)
                #expect(comm?["QIMEI36"] as? String == "fixture-q36")
                if method != "GetSession" {
                    #expect(comm?["qq"] as? String == "12345")
                    #expect(comm?["tmeLoginType"] as? Int == 2)
                    if !expiring { #expect(comm?["authst"] as? String == "fixture-key") }
                    #expect(comm?["sid"] as? String == "fixture-sid")
                    #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("qqmusic_uin=12345") == true)
                }
            }
            var data: [String: Any] = [:]
            let authst = (payload["comm"] as? [String: Any])?["authst"] as? String
            var expired = false
            switch method {
            case "Login" where expiring:
                #expect(params["refresh_token"] as? String == "fixture-refresh-token")
                // QQ (ptlogin) logins carry an empty refresh_key and renew with openid + refresh_token.
                #expect(["fixture-refresh-key", ""].contains(params["refresh_key"] as? String))
                #expect(params["openid"] as? String == "fixture-openid")
                #expect(params["loginMode"] as? Int == 2)
                data = ["musickey": "renewed-key", "str_musicid": "12345", "loginType": 2]
            case "GetRank":
                expired = expiring && authst != "renewed-key"
                data = ["rank": [["listenCnt": 7, "track": ["id": 42, "mid": "song-mid", "name": "Song",
                                                            "singer": [["mid": "fixture-singer", "name": "Singer"]]]]]]
            case "GetSession":
                data = ["session": ["uid": 123, "sid": "fixture-sid"]]
            case "get_song_detail_yqq":
                #expect(params["song_type"] as? Int == 0)
                #expect(params["song_mid"] as? String == "song-mid")
                data = ["track_info": ["id": 42, "mid": "song-mid", "type": 1]]
            case "IsSongFanByMid":
                #expect(params["v_songMid"] as? [String] == ["song-mid"])
                data = ["m_fan": ["song-mid": saved("song")]]
            case "AddSonglist", "DelSonglist":
                #expect(operation["module"] as? String == "music.musicasset.PlaylistDetailWrite")
                #expect((params["v_songInfo"] as? [[String: Int]]) == [["songId": 42, "songType": 0]])
                if params["dirId"] as? Int == 51 {
                    #expect(saved("created"))
                    data = ["retCode": 0, "result": ["dirId": 51, "tid": "987654321"]]
                } else {
                    #expect(params["dirId"] as? Int == 201)
                    if !unconfirmed { _ = saved("song", set: method == "AddSonglist") }
                    // A real upstream can commit the change and return an incomplete acknowledgment.
                    data = method == "AddSonglist" ? ["retCode": 0] : ["retCode": 0, "result": ["dirId": 201, "tid": "8888"]]
                }
            case "IsPlaylistFan":
                #expect(params["v_tid"] as? [Int] == [987654321])
                data = ["m_fan": ["987654321": saved("playlist")]]
            case "FavPlaylist", "CancelFavPlaylist":
                #expect(params["uin"] as? String == "12345")
                #expect(params["v_playlistId"] as? [Int] == [987654321])
                _ = saved("playlist", set: method == "FavPlaylist")
                data = ["result": 0, "v_failedPlaylistId": []]
            case "IsAlbumFan":
                #expect(params["uin"] as? Int == 12345)
                #expect(params["v_albumMid"] as? [String] == ["album-mid"])
                data = ["m_fan": ["album-mid": saved("album")]]
            case "FavAlbum", "CancelFavAlbum":
                #expect(params["uin"] as? String == "12345")
                #expect(params["v_albumMid"] as? [String] == ["album-mid"])
                _ = saved("album", set: method == "FavAlbum")
                data = ["result": 0, "v_failedAlbumId": [], "v_failedAlbumMid": []]
            case "cgi_qry_concern_status":
                #expect(web)
                #expect(params["encrypt_singerid"] as? Int == 1)
                data = ["map_singer_status": ["fixture-singer": saved("singer") ? 1 : 0]]
            case "cgi_concern_user_v2":
                #expect(web)
                #expect(params["encrypt_singerid"] as? Int == 1)
                let user = params["userinfo"] as? [String: Any]
                #expect(user?["usertype"] as? Int == 1)
                #expect(user?["userid"] as? String == "fixture-singer")
                _ = saved("singer", set: params["opertype"] as? Int == 0)
            case "GetFollowSingerList":
                let items = saved("singer") ? [["MID": "fixture-singer", "Name": "Singer"]] : []
                data = ["List": items, "HasMore": false]
            case "GetPlaylistByUin":
                #expect(params["uin"] as? String == "12345")
                var rows: [[String: Any]] = [["tid": 31, "dirId": 12, "dirName": "Created", "songNum": 4]]
                if saved("created"), !unconfirmed {
                    rows.append(["tid": "987654321", "dirId": 51, "dirName": "A&B + 测试", "dirShow": saved("private") ? 2 : 1])
                }
                data = ["v_playlist": rows]
            case "uniform_get_Dissinfo":
                #expect(params["dirid"] as? Int == 51)
                data = ["dirinfo": ["dirid": 51, "title": saved("renamed") ? "Renamed" : "A&B + 测试",
                                    "desc": "Keep", "picurl": "https://y.gtimg.cn/cover.jpg", "picurl2": "",
                                    "tag": [["id": 11, "name": "Tag"]], "dir_show": 2]]
            case "EditPlaylist":
                #expect(params["dirId"] as? Int == 51)
                #expect(params["dirNewName"] as? String == "Renamed")
                #expect(params["dirNewDesc"] as? String == "Keep")
                #expect(params["dirNewPicUrl"] as? String == "https://y.gtimg.cn/cover.jpg")
                #expect(params["dirNewtaglist"] as? String == "11")
                #expect(params["dirShow"] as? Int == 2)
                _ = saved("renamed", set: true)
                data = ["retCode": 0, "result": ["dirId": 51, "tid": "987654321"]]
            case "DelPlaylist":
                #expect(params["dirId"] as? Int == 51)
                #expect(saved("created"))
                _ = saved("created", set: false)
                data = ["retCode": 0, "result": ["dirId": 51, "tid": "987654321", "updateTime": 0]]
            case "CgiGetPlaylistFavInfo":
                #expect(params["uin"] as? String == "fixture-encrypted")
                data = ["v_list": [["tid": 987654321, "name": "Saved", "logo": "https://y.gtimg.cn/saved.jpg"]], "hasmore": 0]
            case "CgiGetDiss":
                #expect(params["disstid"] as? Int == 0)
                #expect(params["dirid"] as? Int == 201)
                #expect(params["enc_host_uin"] as? String == "fixture-encrypted")
                data = ["songlist": [["id": 42, "mid": "song-mid", "name": "Song"]], "hasmore": 0]
            case "GetDetail":
                #expect(params["topid"] as? Int == 26)
                data = ["data": ["song": [
                    ["songId": 43, "rank": 1, "rankType": 4, "rankValue": "0"],
                    ["songId": 42, "rank": 2, "rankType": 1, "rankValue": "3"]]],
                    "songInfoList": [["id": 42, "mid": "second", "name": "Second"],
                                     ["id": 43, "mid": "first", "name": "First"]]]
            case "GetSingerSongList":
                #expect(params["singerMid"] as? String == "fixture-singer")
                data["songList"] = [["songInfo": ["id": 42, "mid": "song-mid", "name": "Song", "interval": 120]]]
            case "GetAlbumList":
                #expect(params["singerMid"] as? String == "fixture-singer")
                data["albumList"] = [["albumMid": "album-mid", "albumName": "Album", "totalNum": 12],
                                     ["albumMid": "unknown-count", "albumName": "Unknown"]]
            case "GetAlbumSongList":
                #expect(params["albumMid"] as? String == "album-mid")
                data["songList"] = [["songInfo": ["id": 43, "mid": "album-song", "name": "Exact album track"]]]
            case "AddPlaylist":
                #expect(modern && !web)
                #expect(!saved("created"))
                let isPrivate = params["dirShow"] != nil
                #expect(params["dirName"] as? String == "A&B + 测试")
                #expect(isPrivate ? Set(params.keys) == ["dirName", "dirShow"] && params["dirShow"] as? Int == 2 : Set(params.keys) == ["dirName"])
                _ = saved("created", set: true)
                _ = saved("private", set: isPrivate)
                data = ["retCode": 0, "result": ["tid": "987654321", "dirId": 51, "dirName": "garbled acknowledgment"]]
            default: Issue.record("Unexpected RPC: \(method)")
            }
            object = ["code": 0, key: ["code": (rejected && method != "GetSession") || expired ? 1000 : 0, "data": data]]
        } else {
            #expect(request.value(forHTTPHeaderField: "Cookie")?.contains("qqmusic_key=fixture-key") == true)
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains { $0.name == "reqtype" && $0.value == "2" })
            #expect(query.contains { $0.name == "ein" && $0.value == "99" })
            object = ["code": 0, "data": ["totalalbum": 1, "albumlist": [
                ["albummid": "album-mid", "albumname": "Album", "singername": "Singer", "songnum": 8]
            ]]]
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        var bytes = try! JSONSerialization.data(withJSONObject: object)
        if web {
            let mask: [UInt8] = [122, 63, 140, 29, 94, 155, 47, 10, 108, 77, 126, 139, 31, 58, 92, 157, 14, 43, 111, 74, 129]
            bytes = Data(bytes.enumerated().map { $0.element ^ mask[$0.offset % mask.count] })
        }
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096), result = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            result.append(contentsOf: bytes.prefix(count))
        }
        return result
    }
}

@Suite("QQ collection and catalog operations")
struct QQMusicFeatureTests {
    private func api(reject: Bool = false, unconfirmed: Bool = false, expiring: Bool = false,
                     extra: [String: String] = [:], authentication: QQMusicAuth? = nil) -> QQMusicAPI {
        let auth = authentication ?? QQMusicAuth(persistsSession: false)
        var cookies = ["uin": "12345", "qqmusic_key": "fixture-key", "encryptUin": "fixture-encrypted"]
        if expiring {
            cookies.merge(["openid": "fixture-openid", "refresh_token": "fixture-refresh-token",
                           "refresh_key": "fixture-refresh-key"]) { _, new in new }
        }
        cookies.merge(extra) { _, new in new }
        auth.importCookies(cookies, nickname: "Fixture")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QQMusicFeatureFixture.self]
        config.httpAdditionalHeaders = ["X-Fixture-ID": UUID().uuidString, "X-Fixture-Reject": reject ? "yes" : "no",
                                        "X-Fixture-Unconfirmed": unconfirmed ? "yes" : "no", "X-Fixture-Expiring": expiring ? "yes" : "no"]
        return QQMusicAPI(configuration: config, authentication: auth)
    }
    @Test func singerSongsUseModernRPCAndUnwrapSongInfo() async throws {
        let songs = try await api().artistHotSongs(mid: "fixture-singer", name: "Singer")
        #expect(songs.count == 1 && songs.first?.qqMid == "song-mid")
    }
    @Test func artistAlbumsKeepRawMIDAndUnknownCount() async throws {
        let albums = try await api().artistAlbums(mid: "fixture-singer", name: "Singer")
        #expect(albums.map(\.id) == ["album-mid", "unknown-count"])
        #expect(albums.first?.trackCount == 12)
        #expect(albums.last?.trackCount == nil)
    }
    @Test func albumTracksUseTheAlbumMIDRatherThanSearchMatching() async throws {
        let songs = try await api().albumSongs(mid: "album-mid")
        #expect(songs.first?.qqMid == "album-song")
    }
    @Test(arguments: [false, true])
    func createPlaylistUsesOwnedReadbackForNameAndTID(isPrivate: Bool) async throws {
        let list = try await api().createPlaylist(name: "A&B + 测试", isPrivate: isPrivate)
        #expect(list.id == 987654321 && list.name == "A&B + 测试")
        #expect(list.isOwned == true && list.isSubscribed == false)
    }

    @Test func playlistWritesResolveDirectoryAndRejectUnownedTargets() async throws {
        let api = api()
        await #expect(throws: Error.self) { try await api.deletePlaylist(tid: 987654321) }
        let created = try await api.createPlaylist(name: "A&B + 测试", isPrivate: true)
        #expect(try await api.renamePlaylist(tid: created.id, name: "Renamed") == "Renamed")
        try await api.updatePlaylistTracks(tid: created.id, songIDs: [42], adding: true)
        try await api.updatePlaylistTracks(tid: created.id, songIDs: [42], adding: false)
        try await api.deletePlaylist(tid: created.id)
        await #expect(throws: Error.self) { try await api.updatePlaylistTracks(tid: created.id, songIDs: [42], adding: true) }
    }

    @Test func creationWithoutAnOwnedMatchDoesNotReportSuccessOrRepeatTheWrite() async {
        await #expect(throws: Error.self) {
            try await api(unconfirmed: true).createPlaylist(name: "A&B + 测试", isPrivate: false)
        }
    }
    @Test func subscribeAndUnsubscribeUseRemotePlaylistID() async throws {
        let api = api()
        try await api.subscribePlaylist(id: 987654321, subscribe: true)
        #expect(try await api.playlistSubscribed(id: 987654321))
        try await api.subscribePlaylist(id: 987654321, subscribe: false)
        #expect(try await !api.playlistSubscribed(id: 987654321))
    }
    @Test func followUnfollowAndReadFollowedSingers() async throws {
        let api = api()
        try await api.followArtist(mid: "fixture-singer", follow: true)
        #expect(try await api.followedArtists().first?.id == "fixture-singer")
        try await api.followArtist(mid: "fixture-singer", follow: false)
        #expect(try await !api.artistFollowed(mid: "fixture-singer"))
    }
    @Test func songHeartChecksTheRemoteIdentityAndConfirmsTheTarget() async throws {
        let api = api()
        await #expect(throws: Error.self) { try await api.like(songID: 999, songmid: "song-mid", liked: true) }
        try await api.like(songID: 42, songmid: "song-mid", liked: true)
        try await api.like(songID: 42, songmid: "song-mid", liked: false)
        let unconfirmed = self.api(unconfirmed: true)
        await #expect(throws: Error.self) { try await unconfirmed.like(songID: 42, songmid: "song-mid", liked: true) }
    }
    @Test func albumStatusAndLibraryKeepTheSearchMID() async throws {
        let api = api()
        try await api.subscribeAlbum(mid: "album-mid", subscribe: true)
        #expect(try await api.albumSubscribed(mid: "album-mid"))
        let albums = try await api.favoriteAlbums()
        #expect(albums.map(\.id) == ["album-mid"])
        #expect(albums.first?.artistName == "Singer")
        try await api.subscribeAlbum(mid: "album-mid", subscribe: false)
        #expect(try await !api.albumSubscribed(mid: "album-mid"))
    }
    @Test func libraryKeepsOwnershipAndTheFavoriteDirectorySeparate() async throws {
        let api = api()
        let lists = try await api.userPlaylists(uin: "12345")
        let created = lists.first { $0.id == 31 }
        #expect(created?.isOwned == true && created?.name == "Created" && created?.trackCount == 4)
        #expect(lists.first { $0.id == 987654321 }?.isSubscribed == true)
        #expect(lists.first { $0.id == QQMusicAPI.qqLikedPlaylistID }?.isOwned == true)
        #expect(try await api.favoriteSongs().map(\.qqMid) == ["song-mid"])
    }
    @Test func expiredLoginIsRenewedOnceAndTheRequestRepeated() async throws {
        let api = api(expiring: true)
        let rank = try await api.listeningRank(period: 1)
        #expect(rank.map(\.count) == [7])
        #expect(rank.first?.song.qqMid == "song-mid")
    }
    @Test @MainActor func qqScanLoginWithoutRefreshKeyRenewsAheadOfExpiry() async {
        let auth = QQMusicAuth(persistsSession: false)
        let created = Int(Date().timeIntervalSince1970) - 70 * 3600
        let api = api(expiring: true, extra: ["refresh_key": "", "musickeyCreateTime": "\(created)",
                                              "keyExpiresIn": "259200"], authentication: auth)
        #expect(auth.canRenewCredential)
        #expect(auth.nextRenewalCheckDelay() == 60)
        #expect(await auth.refreshCredentialIfNeeded(api: api))
        #expect(auth.collectionCredential?.key == "renewed-key")
        #expect(auth.exportedCredentials["refresh_token"] == "fixture-refresh-token")
        // The renewed key is dated from now, so the next check waits until its own renewal window.
        let delay = auth.nextRenewalCheckDelay() ?? 0
        #expect(delay == 3600)
        #expect(await auth.refreshCredentialIfNeeded(api: api) == false)
    }
    @Test @MainActor func freshKeyIsNotRenewedAndWebCookiesCannotRenew() async {
        let auth = QQMusicAuth(persistsSession: false)
        let api = api(expiring: true, extra: ["musickeyCreateTime": "\(Int(Date().timeIntervalSince1970))",
                                              "keyExpiresIn": "259200"], authentication: auth)
        #expect(await auth.refreshCredentialIfNeeded(api: api) == false)
        #expect(auth.collectionCredential?.key == "fixture-key")
        let web = QQMusicAuth(persistsSession: false)
        web.importCookies(["uin": "12345", "qqmusic_key": "fixture-key"], nickname: nil)
        #expect(web.canRenewCredential == false)
        #expect(web.nextRenewalCheckDelay() == nil)
    }
    @Test func expiredLoginWithoutRefreshTokenAsksForANewScan() async {
        let api = api(reject: true)
        await #expect(throws: QQMusicSessionError.self) { try await api.listeningRank(period: 1) }
    }
    @Test func credentialKeepsLongWeChatAccountIDsExact() {
        let auth = QQMusicAuth(persistsSession: false)
        let id = "1234567890123456789"
        auth.importCookies(["wxuin": "o" + id, "qqmusic_key": "fixture-key"], nickname: nil)
        #expect(auth.collectionCredential?.id == id)
        #expect(auth.collectionCredential?.albumStatusOwner as? String == id)
        #expect(auth.collectionCredential?.loginType == 1)
    }
    @Test func businessRejectionDoesNotBecomeEmptySongsOrSuccessfulMutation() async {
        let api = api(reject: true)
        await #expect(throws: Error.self) { try await api.artistHotSongs(mid: "fixture-singer", name: "Singer") }
        await #expect(throws: Error.self) { try await api.subscribePlaylist(id: 987654321, subscribe: true) }
        await #expect(throws: Error.self) { try await api.followArtist(mid: "fixture-singer", follow: true) }
    }
}

extension QQMusicFeatureTests {
    @MainActor @Test func newPlaylistRemainsVisibleUntilServerListsItAndDoesNotCrossAccounts() {
        var item = ProviderPlaylist(id: 10, name: "New", coverURL: nil, source: .qq)
        item.ownerID = "account-A"; item.isOwned = true
        let pending = [10: item]
        let delayed = PlatformMusicAPI.mergePendingPlaylists(remote: [], pending: pending, ownerID: "account-A")
        #expect(delayed.visible.map(\.id) == [10])
        let other = PlatformMusicAPI.mergePendingPlaylists(remote: [], pending: pending, ownerID: "account-B")
        #expect(other.visible.isEmpty && other.remaining.count == 1)
        let confirmed = PlatformMusicAPI.mergePendingPlaylists(remote: [item], pending: pending, ownerID: "account-A")
        #expect(confirmed.visible.count == 1 && confirmed.remaining.isEmpty)
    }
}

extension QQMusicFeatureTests {
    @MainActor @Test func releaseTypeWinsOverUnknownOrMisleadingTrackCounts() throws {
        let album = try PlatformMusicAPI.decode(AlbumSummary.self, ["id": -1, "name": "Album", "size": 0, "subType": "录音室专辑"])
        let ep = try PlatformMusicAPI.decode(AlbumSummary.self, ["id": -2, "name": "EP", "size": 6, "subType": "EP"])
        let unknown = try PlatformMusicAPI.decode(AlbumSummary.self, ["id": -3, "name": "Unknown", "size": 0])
        #expect(!album.isEPOrSingle && ep.isEPOrSingle && !unknown.isEPOrSingle)
    }
}

extension QQMusicFeatureTests {
    @Test func oldAlbumDisplayIdentifiersAreConvertedBackToRemoteMID() {
        #expect(QQMusicAPI.normalizedAlbumMID("qq-album-003RMaRI1iFoYd-Album-Name") == "003RMaRI1iFoYd")
        #expect(QQMusicAPI.normalizedAlbumMID("003RMaRI1iFoYd") == "003RMaRI1iFoYd")
    }
}

extension QQMusicFeatureTests {
    @Test func toplistJoinsMovementBySongIDInChartOrder() async throws {
        let entries = try await api().topListEntries(topid: 26, limit: 2)
        #expect(entries.map(\.song.qqMid) == ["first", "second"])
        #expect(entries.map(\.previousRank) == [0, 5])
    }

    @Test func toplistMovementPreservesQQSemantics() {
        func movement(_ type: Int, _ value: Any, rank: Int = 10) -> (previousRank: Int?, growthRatio: Double?) {
            QQMusicAPI.toplistMovement(["rank": rank, "rankType": type, "rankValue": value])
        }
        #expect(movement(1, "3").previousRank == 13)
        #expect(movement(2, "3").previousRank == 7)
        #expect(movement(3, "0").previousRank == 10)
        #expect(movement(4, "0").previousRank == 0)
        #expect(movement(6, "43%").growthRatio == 43)
        #expect(movement(6, "-2.5%").growthRatio == -2.5)
        #expect(movement(6, "NaN").growthRatio == nil)
        #expect(movement(1, "bad").previousRank == nil)
        #expect(movement(2, "20").previousRank == nil)
        #expect(movement(99, 0).previousRank == nil)
    }
}
