import Foundation
import Testing
@testable import CodaCore

@Suite("Music provider isolation")
struct MusicProviderTests {
    @Test func accountSwitchInvalidatesInFlightResponsesEvenWhenReturningToSameProvider() throws {
        let name = "MusicProviderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let context = MusicProviderContext(provider: .netease, defaults: defaults)
        let initial = context.ticket
        context.activate(.qq)
        #expect(throws: CancellationError.self) { try context.check(initial) }
        #expect(throws: MusicProviderError.self) { try context.requireNetease() }
        let qq = context.ticket
        context.activate(.netease)
        #expect(throws: CancellationError.self) { try context.check(qq) }
        #expect(throws: CancellationError.self) { try context.check(initial) }
        try context.requireNetease()
        #expect(defaults.string(forKey: "music.provider") == "netease")
    }

    @MainActor @Test func platformIdentifiersSeparateServicesAndEntityKinds() {
        let qq = PlatformMusicAPI.identifier(provider: .qq, kind: "song", value: "123")
        let kugou = PlatformMusicAPI.identifier(provider: .kugou, kind: "song", value: "123")
        let playlist = PlatformMusicAPI.identifier(provider: .qq, kind: "playlist", value: "123")
        #expect(qq < 0 && kugou < 0 && playlist < 0)
        #expect(Set([qq, kugou, playlist, 123]).count == 4)
        #expect(qq == PlatformMusicAPI.identifier(provider: .qq, kind: "song", value: "123"))
    }

    @MainActor @Test func cachedTracksPreservePlatformHandlesAndShareLinks() throws {
        let song = ProviderSong(id: 123, name: "Fixture", artists: "Artist", album: "Album", coverURL: nil,
                             duration: 123, source: .qq, qqMid: "fixture-mid", qqMediaMid: "fixture-media", fee: 1)
        let bytes = try JSONEncoder().encode(song)
        let object: [String: Any] = ["id": -123, "name": "Fixture", "dt": 123000,
                                   "platformSong": try JSONSerialization.jsonObject(with: bytes)]
        let track = try PlatformMusicAPI.decode(Track.self, object)
        let restored = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(track))
        #expect(restored.platformSong == song)
        #expect(restored.id == -123)
        #expect(restored.musicShareURL?.absoluteString == "https://y.qq.com/n/ryqq/songDetail/fixture-mid")
        #expect(restored.playability(privilege: nil, isLoggedIn: true, vipType: 0) == .playable)
    }

    @MainActor @Test func legacyNetEaseTrackRemainsCompatible() throws {
        let track = try PlatformMusicAPI.decode(Track.self, ["id": 123, "name": "Legacy", "fee": 1])
        #expect(track.platformSong == nil)
        #expect(track.musicShareURL?.absoluteString == "https://music.163.com/#/song?id=123")
        #expect(track.playability(privilege: nil, isLoggedIn: false, vipType: 0) == .vipOnly)
    }

    @Test func capabilitiesPreventUnsupportedMutations() {
        #expect(MusicProvider.qq.supportsFavoriteChanges)
        #expect(MusicProvider.kugou.supportsFavoriteChanges)
        #expect(!MusicProvider.qq.supportsDownloads)
        #expect(MusicProvider.kugou.supportsDownloads)
        #expect(MusicProvider.netease.supportsDownloads)
    }

    @Test func qqCredentialValidationRequiresIdentityAndMusicSession() {
        #expect(QQMusicAuth.loginValidationMessage(["uin": "1234"]) != nil)
        #expect(QQMusicAuth.loginValidationMessage(["qqmusic_key": "fixture"]) != nil)
        #expect(QQMusicAuth.loginValidationMessage(["uin": "1234", "qqmusic_key": "fixture"]) == nil)
        let parsed = QQMusicAuth.parseCookieHeader("uin=1234; qqmusic_key=fixture=a=b")
        #expect(parsed["qqmusic_key"] == "fixture=a=b")
    }
}

private final class PlatformSearchFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let qq = request.url?.host == "c.y.qq.com"
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!
        let body: String
        if qq {
            #expect(request.value(forHTTPHeaderField: "Referer") == "https://y.qq.com/portal/player.html")
            body = #"callback({"code":0,"data":{"song":{"list":[{"songid":77,"songmid":"qq-mid","songname":"QQ fixture","singer":[{"name":"Singer"}],"albumname":"Album","albummid":"album-mid","interval":200,"file":{"media_mid":"media-mid"}}]}}});"#
        } else {
            #expect(request.url?.host == "gateway.kugou.com")
            #expect(request.value(forHTTPHeaderField: "x-router") == "complexsearch.kugou.com")
            #expect(request.url?.path == "/v2/search/song")
            let query = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains { $0.name == "signature" && $0.value?.count == 32 })
            body = #"{"status":1,"data":{"lists":[{"Hash":"00112233445566778899AABBCCDDEEFF","SongName":"Kugou fixture","SingerName":"Singer","AlbumName":"Album","Duration":200,"AlbumAudioID":1234,"AlbumID":5678}]}}"#
        }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

extension MusicProviderTests {
    @Test func qqSearchMapsJSONPAndMediaHandle() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlatformSearchFixture.self]
        let songs = try await QQMusicAPI(configuration: configuration).searchSongs(keyword: "Fixture", limit: 1)
        let song = try #require(songs.first)
        #expect(song.id == 77 && song.source == .qq)
        #expect(song.qqMid == "qq-mid" && song.qqMediaMid == "media-mid")
        #expect(song.artists == "Singer" && song.duration == 200)
    }

    @Test func kugouSearchUsesSignedGatewayAndKeepsPlaybackHandles() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlatformSearchFixture.self]
        let songs = try await KugouMusicAPI(configuration: configuration).searchSongs(keyword: "Fixture", limit: 1)
        let song = try #require(songs.first)
        #expect(song.source == .kugou)
        #expect(song.kugouHash?.lowercased() == "00112233445566778899aabbccddeeff")
        #expect(song.kugouAlbumAudioId == "1234")
    }
}
