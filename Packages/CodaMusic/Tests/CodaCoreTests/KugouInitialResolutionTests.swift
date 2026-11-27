import Foundation
import Testing
@testable import CodaCore

private final class InitialKugouFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        if request.value(forHTTPHeaderField: "Range") == "bytes=0-41" {
            #expect(url.host == "audio.example")
            let header = KugouAuthorizationTests.flacHeader(sampleRate: 44_100, bitDepth: 16)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 206, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: header)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let body: [String: Any]
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if query.first(where: { $0.name == "hash" })?.value?.uppercased() == "LOW" {
            body = ["status": 1, "url": ["https://audio.example/standard"], "extName": "mp3", "bitRate": 128000]
        } else if url.path == "/v2/search/song" {
            body = ["status": 1, "data": ["lists": [["FileHash": "primary", "HQFileHash": "hq", "SQFileHash": "lossless", "ResFileHash": "hires", "MixSongID": "773529640", "AlbumID": "154407186", "SongName": "跃", "SingerName": "薛之谦", "Duration": 351]]]]
        } else {
            #expect(url.path == "/v5/url")
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            #expect(q.first { $0.name == "album_audio_id" }?.value == "773529640")
            #expect(q.first { $0.name == "hash" }?.value == "lossless")
            body = ["status": 1, "url": ["https://audio.example/song"], "extName": "flac", "bitRate": 905000]
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Kugou first resolution after track change")
struct KugouInitialResolutionTests {
    static let stale = ProviderSong(id: 1, name: "跃", artists: "薛之谦", album: "跃", coverURL: nil, duration: 351.373, source: .kugou,
        kugouHash: "primary", kugouAlbumAudioId: "475737829", kugouAlbumId: "154407186", kugouQualityHashes: ["standard": "primary", "exhigh": "old-hq"])

    @MainActor @Test func trackLinksSurviveCachedZeroReferences() throws {
        let song = Self.stale
        let track = try PlatformMusicAPI.decode(Track.self, [
            "id": -123, "name": song.name,
            "ar": [["id": 0, "name": song.artists]],
            "al": ["id": 0, "name": song.album],
            "platformSong": try JSONSerialization.jsonObject(with: JSONEncoder().encode(song))
        ])
        #expect(track.artists.first?.name == song.artists)
        #expect((track.artists.first?.id ?? 0) < 0)
        #expect(track.album.id < 0)
        #expect(track.album.id == PlatformMusicAPI.kugouReferences(song).1.id)
        let registered = try PlatformMusicAPI.shared.register(song)
        #expect(registered.artists == track.artists)
        #expect(registered.album == track.album)
    }

    @Test func firstLosslessRequestRefreshesIncompleteQueueMetadataBeforeResolving() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InitialKugouFixture.self]
        let api = KugouMusicAPI(configuration: configuration, playbackCredentials: ["userid": "123", "token": "fixture", "KUGOU_API_MID": "777"])
        let result = try await api.songURLResult(song: Self.stale, quality: .lossless)
        #expect(result?.quality == .lossless)
    }

    @Test func firstLosslessRequestRefreshesHashOnlyPlaylistMetadata() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InitialKugouFixture.self]
        let api = KugouMusicAPI(configuration: configuration, playbackCredentials: ["userid": "123", "token": "fixture", "KUGOU_API_MID": "777"])
        let song = ProviderSong(id: 1, name: "跃", artists: "薛之谦", album: "跃", coverURL: nil, duration: 351, source: .kugou, kugouHash: "primary")
        let result = try await api.songURLResult(song: song, quality: .lossless)
        #expect(result?.quality == .lossless)
    }

    @Test func lowerQualityFirstHashDoesNotHideLaterLosslessSource() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [InitialKugouFixture.self]
        let api = KugouMusicAPI(configuration: configuration, playbackCredentials: ["userid": "123", "token": "fixture", "KUGOU_API_MID": "777"])
        let song = ProviderSong(id: 1, name: "跃", artists: "薛之谦", album: "跃", coverURL: nil, duration: 351, source: .kugou, kugouHash: "low", kugouAlbumAudioId: "773529640", kugouQualityHashes: ["lossless": "low", "exhigh": "lossless"])
        let result = try await api.songURLResult(song: song, quality: .lossless)
        #expect(result?.quality == .lossless)
        #expect(result?.url == "https://audio.example/song")
    }

    @MainActor @Test func restoringOldQueueDoesNotOverwriteCompletedMetadata() {
        let fresh = ProviderSong(id: 1, name: "跃", artists: "薛之谦", album: "跃", coverURL: nil, duration: 351, source: .kugou,
            kugouHash: "primary", kugouAlbumAudioId: "773529640", kugouAlbumId: "154407186",
            kugouQualityHashes: ["standard": "primary", "exhigh": "hq", "lossless": "lossless", "hires": "hires"])
        #expect(PlatformMusicAPI.preferredPlaybackMetadata(cached: fresh, incoming: Self.stale).kugouAlbumAudioId == "773529640")
        #expect(PlatformMusicAPI.preferredPlaybackMetadata(cached: Self.stale, incoming: fresh) == fresh)
    }
}
