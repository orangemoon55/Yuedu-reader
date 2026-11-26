import Foundation
import Testing
@testable import yuedu_app

/// Offline request+parser coverage for all seven metadata identities.
/// No test calls the live network. Live availability is recorded in MUSIC_RESULT.md.
struct MusicSevenPlatformCatalogTests {
    private func json(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value) }
    @Test func sevenPlatformsExposeExplicitCapabilities() {
        #expect(MusicCatalogPlatform.allCases.map(\.rawValue) == ["wy", "tx", "kg", "kw", "mg", "sd", "apple"])
        #expect(MusicCatalogPlatform.kg.searchKinds == [.song])
        #expect(MusicCatalogPlatform.kw.searchKinds == [.song])
        #expect(MusicCatalogPlatform.mg.searchKinds == [.song])
        #expect(MusicCatalogPlatform.sd.searchKinds == [.song])
        #expect(MusicCatalogPlatform.apple.searchKinds == [.song, .album, .artist])
        #expect(!MusicCatalogPlatform.apple.hasResolverMapping)
        #expect(!MusicCatalogPlatform.sd.hasResolverMapping)
    }
    @Test func kugouRequestAndFixtureParser() throws {
        let request = try MusicKugouCatalog.makeRequest(" hello ")
        #expect(request.url?.host == "songsearch.kugou.com")
        #expect(request.url?.path == "/song_search_v2")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        let body = try json(["status": 1, "error_code": 0, "data": ["lists": [[
            "FileHash": "1F62C7D9B83059CC879DA895E0AD64CF", "SongName": "Hello",
            "SingerName": "Adele", "AlbumName": "Hello", "Duration": 295,
            "Image": "http://imge.kugou.com/stdmusic/150/fixture.jpg", "Url": "https://evil.invalid/audio"
        ]]]])
        let result = try MusicKugouCatalog.parse(body)
        #expect(result.first?.id == "kg:song:1F62C7D9B83059CC879DA895E0AD64CF")
        #expect(result.first?.track?.durationMilliseconds == 295_000)
        #expect(result.first?.track?.poster.hasPrefix("https://") == true)
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicKugouCatalog.parse(Data(#"{"status":1,"error_code":0,"data":{}}"#.utf8)) }
    }
    @Test func kuwoRequestAndFixtureParser() throws {
        let request = try MusicKuwoCatalog.makeRequest("fixture")
        #expect(request.url?.host == "search.kuwo.cn")
        #expect(request.url?.path == "/r.s")
        let body = Data("{'TOTAL':'1','abslist':[{'MUSICRID':'MUSIC_12345','SONGNAME':'Song','ARTIST':'Singer&A','ALBUM':'Record','DURATION':'92','web_albumpic_short':'120/fixture.jpg'}]}".utf8)
        let result = try MusicKuwoCatalog.parse(body)
        #expect(result.first?.id == "kw:song:12345")
        #expect(result.first?.track?.artist == "Singer&A")
        #expect(result.first?.track?.durationMilliseconds == 92_000)
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicKuwoCatalog.parse(Data("{'TOTAL':'1','abslist':[]}".utf8)) }
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicKuwoCatalog.parse(Data("{'TOTAL':'1','abslist':[{'MUSICRID':'MUSIC_1','SONGNAME':'unterminated}".utf8)) }
    }
    @Test func miguRequestAndFixtureParserRequiresTwoIDs() throws {
        let request = try MusicMiguCatalog.makeRequest(" fixture ")
        #expect(request.url?.host == "jadeite.migu.cn")
        #expect(request.url?.path == "/music_search/v3/search/searchAll")
        #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        let body = try json(["code": "000000", "songResultData": ["resultList": [[
            ["contentId": "123", "copyrightId": "CP9", "name": "Migu Song", "duration": "91",
             "singerList": [["name": "Singer"]], "album": "Album", "img3": "/cover.jpg"]
        ]]]])
        let result = try MusicMiguCatalog.parse(body)
        #expect(result.first?.id == "mg:song:123_CP9")
        #expect(result.first?.track?.durationMilliseconds == 91_000)
        #expect(MusicMiguCatalog.ids("123_CP9")?.copyright == "CP9")
        #expect(MusicMiguCatalog.ids("123") == nil)
        #expect(throws: MusicCatalogError.rejected(40020)) { try MusicMiguCatalog.parse(Data(#"{"code":"040020","songResultData":{}}"#.utf8)) }
    }
    @Test func sodaLookupUsesObservedTrackSchemaAndRejectsAudio() throws {
        let request = try MusicSodaCatalog.makeRequest("7634441185327745025")
        #expect(request.url?.host == "api.qishui.com")
        #expect(request.url?.path == "/luna/h5/track_v2")
        #expect(request.url?.query?.contains("track_id=7634441185327745025") == true)
        let body = try json(["status_info": ["now": 1795706046], "risk_result": 0,
            "track": ["id": "7634441185327745025", "name": "Fixture Soda", "duration": 243133,
                      "artists": [["name": "Artist"]], "album": ["name": "Album"],
                      "track_player": ["url": "https://evil.invalid/audio"]]])
        let result = try MusicSodaCatalog.parse(body, expectedID: "7634441185327745025")
        #expect(result.first?.id == "sd:song:7634441185327745025")
        #expect(result.first?.track?.poster == "")
        #expect(result.first?.track?.durationMilliseconds == 243_133)
        #expect(throws: MusicCatalogError.invalidSongLookup) { try MusicSodaCatalog.makeRequest("hello") }
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicSodaCatalog.parse(body, expectedID: "7") }
    }
    @Test func appleSearchAndDetailFixtureParsersNeverExposePreview() throws {
        let request = try MusicAppleCatalog.makeRequest("fixture", kind: .song)
        #expect(request.url?.host == "itunes.apple.com")
        #expect(request.url?.path == "/search")
        #expect(request.url?.query?.contains("entity=song") == true)
        let song: [String: Any] = ["wrapperType": "track", "kind": "song", "trackId": 123,
            "trackName": "Apple Song", "artistName": "Artist", "collectionName": "Album",
            "trackTimeMillis": 1000, "artworkUrl100": "http://is1-ssl.mzstatic.com/image.jpg",
            "previewUrl": "https://evil.invalid/preview.m4a"]
        let result = try MusicAppleCatalog.parse(try json(["resultCount": 1, "results": [song]]), kind: .song)
        #expect(result.first?.id == "apple:song:123")
        #expect(result.first?.track?.poster.hasPrefix("https://") == true)
        let album = MusicCatalogEntry(identifier: "99", kind: .album, title: "Album", subtitle: "Artist", poster: "", track: nil, platform: .apple)
        let detail = try json(["resultCount": 2, "results": [
            ["wrapperType": "collection", "collectionId": 99, "collectionName": "Album", "artistName": "Artist"], song.merging(["collectionId": 99], uniquingKeysWith: { _, newer in newer })
        ]])
        #expect(try MusicAppleCatalog.parseDetail(detail, entry: album).first?.track?.title == "Apple Song")
        #expect(throws: MusicCatalogError.unsupportedCapability) { try MusicAppleCatalog.makeRequest("fixture", kind: .playlist) }
    }
    @Test func serviceDenialsAndMalformedEnvelopesNeverBecomeSuccess() throws {
        let album = MusicCatalogEntry(identifier: "99", kind: .album, title: "Album", subtitle: "Artist", poster: "", track: nil, platform: .apple)
        let denied = try json(["errorCode": 403, "errorMessage": "denied", "resultCount": 1,
            "results": [["wrapperType": "collection", "collectionId": 99]]])
        #expect(throws: MusicCatalogError.rejected(-1)) { try MusicAppleCatalog.parseDetail(denied, entry: album) }
        let track: [String: Any] = ["id": "7", "name": "Fixture", "duration": 1000, "artists": []]
        let missingStatus = try json(["status_info": [String: Int](), "risk_result": 0, "track": track])
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicSodaCatalog.parse(missingStatus, expectedID: "7") }
        let failedStatus = try json(["status_info": ["status_code": 403], "risk_result": 0, "track": track])
        #expect(throws: MusicCatalogError.rejected(403)) { try MusicSodaCatalog.parse(failedStatus, expectedID: "7") }
        #expect(!MusicAnonymousCatalogHTTP.allows(URL(string: "https://itunes.apple.com.evil.invalid/search"), host: "itunes.apple.com"))
        #expect(!MusicAnonymousCatalogHTTP.allows(URL(string: "http://itunes.apple.com/search"), host: "itunes.apple.com"))
        #expect(!MusicAnonymousCatalogHTTP.allows(URL(string: "https://user:secret@itunes.apple.com/search"), host: "itunes.apple.com"))
        #expect(!MusicAnonymousCatalogHTTP.allows(URL(string: "https://api.qishui.com/luna/search/track"), host: "api.qishui.com"))
        #expect(throws: MusicCatalogError.invalidResponse) { try MusicAdditionalCatalogParser.object(Data(repeating: 32, count: MusicCatalogParser.bodyLimit + 1)) }
    }
    @Test func identityNeverCrossesNewPlatformsOrResolver() throws {
        let kgEntries = try MusicKugouCatalog.parse(try json(["status": 1, "error_code": 0, "data": ["lists": [["FileHash": "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA", "SongName": "K", "Duration": 1]]]]))
        let kg = try #require(kgEntries.first?.track)
        let source = MusicJSSource(id: "fixture", name: "Fixture", version: "1", providers: [MusicJSProvider(id: "kg", name: "KG", actions: ["musicUrl"], qualities: ["128k"])])
        #expect(try MusicCatalogResolverMapping.song(kg, source: source, providerID: "kg").provider == "kg")
        let apple = try #require(MusicAppleCatalog.parse(try json(["resultCount": 1, "results": [["wrapperType": "track", "kind": "song", "trackId": 1, "trackName": "A"]]]), kind: .song).first?.track)
        #expect(throws: MusicCatalogError.unsupportedResolver) { try MusicCatalogResolverMapping.song(apple, source: source, providerID: "kg") }
    }
}
