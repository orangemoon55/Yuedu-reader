import Foundation
import Testing
@testable import yuedu_app

struct MusicPlatformCatalogTests {
    private static var qqSong: [String: Any] { ["mid": "003FixtureMid", "id": 123,
        "title": "QQ Fixture", "interval": 92, "singer": [["name": "Singer"]],
        "album": ["mid": "002Album", "name": "Album"], "file": ["media_mid": "004MediaMid"],
        "url": "https://untrusted.invalid/audio.mp3", "fee": 1] }
    private func envelope(_ data: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["code": 0, "req": ["code": 0, "data": data]])
    }
    private func requestBody(_ operation: MusicQQCatalog.Operation) throws -> [String: Any] {
        let request = try MusicQQCatalog.makeRequest(operation)
        #expect(request.url?.absoluteString == "https://u.y.qq.com/cgi-bin/musicu.fcg")
        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == 15)
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let root = try #require(JSONSerialization.jsonObject(with: #require(request.httpBody)) as? [String: Any])
        let comm = try #require(root["comm"] as? [String: Any])
        #expect(comm["uin"] as? String == "0")
        return try #require(root["req"] as? [String: Any])
    }
    @Test func qqHomeRequestsAndBothShelvesUseRealSchemas() throws {
        let chartsRequest = try requestBody(.charts)
        #expect(chartsRequest["module"] as? String == "musicToplist.ToplistInfoServer")
        #expect(chartsRequest["method"] as? String == "GetAll")
        let charts = try MusicQQCatalogParser.charts(envelope(["group": [["groupId": 0, "toplist": [
            ["topId": 4, "title": "Chart", "mbFrontPicUrl": "https://y.gtimg.cn/chart.jpg"]]]]]))
        #expect(charts.first?.platform == .tx)
        #expect(charts.first?.identifier == "toplist:4")
        let playlistsRequest = try requestBody(.playlists)
        #expect(playlistsRequest["module"] as? String == "playlist.PlayListPlazaServer")
        #expect(playlistsRequest["method"] as? String == "get_playlist_by_tag")
        let lists = try MusicQQCatalogParser.playlists(envelope(["v_playlist": [
            ["tid": "7", "title": "Public list", "creator_info": ["nick": "Creator"],
             "cover_url_medium": "http://qpic.y.qq.com/list.jpg"]]]))
        #expect(lists.first?.id == "tx:playlist:7")
        #expect(lists.first?.subtitle == "Creator")
        #expect(lists.first?.poster == "https://qpic.y.qq.com/list.jpg")
    }
    @Test func qqSupportedSearchKindsBuildAndParse() throws {
        for (kind, type) in [(MusicCatalogKind.song, 0), (.album, 2), (.playlist, 3)] {
            let request = try requestBody(.search(" fixture ", kind))
            #expect(request["module"] as? String == "music.search.SearchCgiService")
            #expect(request["method"] as? String == "DoSearchForQQMusicMobile")
            let param = try #require(request["param"] as? [String: Any])
            #expect(param["search_type"] as? Int == type)
            #expect(param["query"] as? String == "fixture")
            #expect(!(param["searchid"] as? String ?? "").isEmpty)
        }
        let songs = try MusicQQCatalogParser.search(envelope(["body": ["item_song": [Self.qqSong]]]), kind: .song)
        #expect(songs.first?.track?.identifier == "003FixtureMid")
        #expect(songs.first?.track?.durationMilliseconds == 92_000)
        #expect(songs.first?.track?.numericSongID == "123")
        #expect(songs.first?.track?.mediaMid == "004MediaMid")
        let legacy = try MusicQQCatalogParser.search(envelope(["body": ["song": ["list": [Self.qqSong]]]]), kind: .song)
        #expect(songs == legacy)
        let albums = try MusicQQCatalogParser.search(envelope(["body": ["item_album": [
            ["albumMID": "002Album", "albumName": "Album", "singer_list": [["name": "Singer"]]]]]]), kind: .album)
        #expect(albums.first?.identifier == "002Album")
        let lists = try MusicQQCatalogParser.search(envelope(["body": ["item_songlist": [["dissid": 7, "dissname": "List"]]]]), kind: .playlist)
        #expect(lists.first?.identifier == "7")
        #expect(!MusicCatalogPlatform.tx.searchKinds.contains(.artist))
        #expect(throws: MusicCatalogError.unsupportedCapability) { try MusicQQCatalog.makeRequest(.search("fixture", .artist)) }
        #expect(throws: MusicCatalogError.unsupportedCapability) { try MusicQQCatalogParser.search(envelope([:]), kind: .artist) }
    }
    @Test func qqChartPlaylistAlbumDetailsBuildAndParse() throws {
        for (id, kind, module, method, responseKey) in [
            ("toplist:4", MusicCatalogKind.playlist, "musicToplist.ToplistInfoServer", "GetDetail", "songInfoList"),
            ("7", .playlist, "music.srfDissInfo.aiDissInfo", "uniform_get_Dissinfo", "songlist"),
            ("002Album", .album, "music.musichallAlbum.AlbumSongList", "GetAlbumSongList", "songList")
        ] {
            let entry = MusicCatalogEntry(identifier: id, kind: kind, title: "Fixture", subtitle: "", poster: "", track: nil, platform: .tx)
            let req = try requestBody(.tracks(entry))
            #expect(req["module"] as? String == module)
            #expect(req["method"] as? String == method)
            let item = kind == .album ? ["songInfo": Self.qqSong] as [String: Any] : Self.qqSong
            let songs = try MusicQQCatalogParser.tracks(envelope([responseKey: [item]]), entry: entry)
            #expect(songs.first?.track?.platform == .tx)
            #expect(songs.first?.track?.identifier == "003FixtureMid")
            #expect(songs.first?.id == "tx:song:003FixtureMid")
        }
    }
    @Test func platformIdentityAndResolverMappingNeverCrossPlatforms() throws {
        let qq = try #require(MusicQQCatalogParser.track(Self.qqSong))
        let source = MusicJSSource(id: "fixture", name: "Fixture", version: "1", providers: [
            MusicJSProvider(id: "wy", name: "WY", actions: ["musicUrl"], qualities: ["128k"]),
            MusicJSProvider(id: "tx", name: "QQ", actions: ["musicUrl"], qualities: ["128k"])
        ])
        let mapped = try MusicCatalogResolverMapping.song(qq, source: source, providerID: "tx")
        let info = try #require(JSONSerialization.jsonObject(with: Data(mapped.musicInfoJSON.utf8)) as? [String: Any])
        #expect(mapped.provider == "tx")
        #expect(info["source"] as? String == "tx")
        #expect(info["songmid"] as? String == "123")
        #expect(info["mid"] as? String == "003FixtureMid")
        #expect(info["strMediaMid"] as? String == "004MediaMid")
        #expect(info["url"] == nil && info["fee"] == nil)
        #expect(throws: MusicCatalogError.unsupportedResolver) { try MusicCatalogResolverMapping.song(qq, source: source, providerID: "wy") }
        let wy = try #require(MusicCatalogParser.track(["id": 123, "name": "WY"]))
        #expect(wy.platform == .wy)
        #expect(try MusicCatalogResolverMapping.song(wy, source: source, providerID: "wy").provider == "wy")
        #expect(throws: MusicCatalogError.unsupportedResolver) { try MusicCatalogResolverMapping.song(wy, source: source, providerID: "tx") }
        let txSameID = MusicCatalogTrack(identifier: "123", title: "QQ", artist: "", album: "", poster: "", durationMilliseconds: 0, platform: .tx)
        #expect(wy.id != txSameID.id)
        let a = MusicCatalogEntry(identifier: "7", kind: .playlist, title: "WY", subtitle: "", poster: "", track: nil)
        let b = MusicCatalogEntry(identifier: "7", kind: .playlist, title: "QQ", subtitle: "", poster: "", track: nil, platform: .tx)
        #expect(a.id != b.id)
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicQQCatalog.makeRequest(.tracks(a)) }
        #expect(MusicHomePresentation.catalogCaption(for: b, showingOrigin: true) == localized("QQ 音樂"))
    }
    @Test func invalidIDsURLsMissingSchemasAndServiceFailuresAreNotEmptySuccess() throws {
        for value in ["", "../escape", "id?token=secret", "a/b", String(repeating: "x", count: 65)] {
            #expect(MusicQQCatalogParser.mid(value) == nil)
        }
        #expect(MusicCatalogParser.identifier(true) == nil)
        #expect(MusicQQCatalogParser.track(["id": 123, "title": "No mid"]) == nil)
        for value in ["https://user:pass@y.gtimg.cn/a.jpg", "https://y.gtimg.cn/a?token=1",
                      "https://y.gtimg.cn.evil.invalid/a", "https://127.0.0.1/a", "file:///a"] {
            #expect(MusicQQCatalogParser.artwork(value).isEmpty)
        }
        for value in ["http://u.y.qq.com/cgi-bin/musicu.fcg", "https://u.y.qq.com/login",
                      "https://user:pass@u.y.qq.com/cgi-bin/musicu.fcg", "https://u.y.qq.com/cgi-bin/musicu.fcg?token=1",
                      "https://u.y.qq.com.evil.invalid/cgi-bin/musicu.fcg"] {
            #expect(!MusicQQCatalog.allowedURL(try #require(URL(string: value))))
        }
        #expect(throws: MusicCatalogError.invalidQuery) { try MusicQQCatalog.makeRequest(.search(" ", .song)) }
        #expect(throws: MusicCatalogError.invalidQuery) { try MusicQQCatalog.makeRequest(.search(String(repeating: "x", count: 301), .song)) }
        #expect(throws: MusicCatalogError.self) { try MusicQQCatalogParser.data(Data(repeating: 0, count: MusicCatalogParser.bodyLimit + 1)) }
        #expect(throws: MusicCatalogError.rejected(2001)) { try MusicQQCatalogParser.data(Data(#"{"code":0,"req":{"code":2001,"data":{}}}"#.utf8)) }
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicQQCatalogParser.search(envelope(["body": [:]]), kind: .song) }
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicQQCatalogParser.playlists(envelope([:])) }
        #expect(try MusicQQCatalogParser.search(envelope(["body": ["item_song": []]]), kind: .song).isEmpty)
        #expect(try MusicQQCatalogParser.songs(Array(repeating: Self.qqSong, count: 110)).count == 1)
    }
    @MainActor @Test(arguments: [false, true]) func oldHomepageCannotReplaceNewPlatform(cancelOld: Bool) async {
        let gate = SlowCatalogGate()
        let model = MusicHomeCatalogModel(chartLoader: { platform in
            if platform == .wy { await gate.wait() }
            return [MusicCatalogEntry(identifier: "7", kind: .playlist, title: platform.title, subtitle: "", poster: "", track: nil, platform: platform)]
        }, playlistLoader: { _ in [] })
        let first = Task { await model.load(platform: .wy) }
        while !(await gate.started) { await Task.yield() }
        if cancelOld { first.cancel() }
        model.reset()
        #expect(model.charts.isEmpty && model.playlists.isEmpty)
        await model.load(platform: .tx)
        await gate.release()
        await first.value
        #expect(model.charts.first?.platform == .tx)
        #expect(!model.chartsLoading && !model.playlistsLoading)
    }
}

private actor SlowCatalogGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var started = false
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation; started = true
        }
    }
    func release() { continuation?.resume(); continuation = nil }
}
