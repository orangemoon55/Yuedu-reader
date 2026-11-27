import CryptoKit
import Foundation
import Testing
@testable import CodaCore

private final class KugouPlaybackFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        var body: Data
        if url.path != "/v5/url", url.host != "audio.example" {
            // Metadata enrichment can precede URL resolution. An empty search
            // leaves the supplied recording unchanged; v5 assertions below
            // apply only to actual playback requests.
            body = try! JSONSerialization.data(withJSONObject: ["status": 1, "data": ["lists": []]])
        } else if url.host == "audio.example" {
            body = KugouAuthorizationTests.flacHeader(sampleRate: 48000, bitDepth: 24)
        } else {
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
            var params = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
            let signature = params.removeValue(forKey: "signature")
            let concept = params["appid"] == "3116"
            let salt = concept ? "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA" : "OIlwieks28dk2k092lksi2UIkp"
            let text = salt + params.keys.sorted().map { "\($0)=\(params[$0]!)" }.joined() + salt
            let expected = Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
            #expect(signature == expected)
            #expect(url.path == "/v5/url")
            #expect(params["IsFreePart"] == "0")
            #expect(params["pid"] == (concept ? "411" : "2"))
            #expect(params["clientver"] == "11430")
            let high = params["quality"] == "high" && !(concept && params["hash"] == "fallback")
            body = try! JSONSerialization.data(withJSONObject: ["status": 1, "url": ["https://audio.example/song"], "extName": high ? "flac" : "mp3", "bitRate": high ? 1608000 : 320000])
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 206, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Kugou signed playback")
struct KugouAuthorizationTests {
    static func flacHeader(sampleRate: UInt64, bitDepth: UInt64) -> Data {
        var bytes = [UInt8](repeating: 0, count: 42)
        bytes.replaceSubrange(0..<4, with: "fLaC".utf8)
        bytes[7] = 34
        let info = (sampleRate << 44) | ((bitDepth - 1) << 36)
        for i in 0..<8 { bytes[18+i] = UInt8(truncatingIfNeeded: info >> ((7-i)*8)) }
        return Data(bytes)
    }

    @Test func membershipTokenKeepsConceptClientIdentityAndBothSignatures() {
        let params = KugouMusicAPI.playbackParameters(hash: "ABCDEF", albumAudioId: "324003078", albumId: "46062560",
            quality: .lossless, credentials: ["userid": "12345", "token": "fixture-token", "KUGOU_API_MID": "777"], timestamp: 123)
        #expect(params["appid"] == "3116")
        #expect(params["pid"] == "411")
        #expect(params["token"] == "fixture-token")
        #expect(params["quality"] == "flac")
        let expectedKey = Insecure.MD5.hash(data: Data("abcdef185672dd44712f60bb1736df5a377e82311677712345".utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(params["key"] == expectedKey)
        var unsigned = params
        unsigned.removeValue(forKey: "signature")
        let salt = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
        let text = salt + unsigned.keys.sorted().map { "\($0)=\(unsigned[$0]!)" }.joined() + salt
        let expectedSignature = Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
        #expect(params["signature"] == expectedSignature)
    }

    @Test func validatesFlacEncodingWithoutTrustingRequestedQuality() {
        #expect(KugouMusicAPI.flacQuality(header: Self.flacHeader(sampleRate: 44100, bitDepth: 16)) == .lossless)
        #expect(KugouMusicAPI.flacQuality(header: Self.flacHeader(sampleRate: 48000, bitDepth: 24)) == .hires)
        #expect(KugouMusicAPI.flacQuality(header: Self.flacHeader(sampleRate: 96000, bitDepth: 16)) == .hires)
        #expect(KugouMusicAPI.flacQuality(header: Data("invalid".utf8)) == nil)
    }

    @Test func lowerQualityFromFirstClientStillTriesOtherSignedClient() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KugouPlaybackFixture.self]
        let api = KugouMusicAPI(configuration: configuration,
            playbackCredentials: ["userid": "12345", "token": "fixture", "KUGOU_API_MID": "777"])
        let song = ProviderSong(id: 1, name: "Fixture", artists: "Singer", album: "", coverURL: nil,
                             duration: 192, source: .kugou, kugouHash: "fallback")
        let result = try await api.songURLResult(song: song, quality: .hires)
        #expect(result?.quality == .hires)
    }

    @Test func signedRequestResolvesAndSwitchesQualityFromSameRecording() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KugouPlaybackFixture.self]
        let api = KugouMusicAPI(configuration: configuration)
        let song = ProviderSong(id: 1, name: "Fixture", artists: "Singer", album: "Album", coverURL: nil,
                             duration: 192, source: .kugou, kugouHash: "ABCDEF", kugouAlbumAudioId: "324003078")
        let high = try await api.songURLResult(song: song, quality: .hires)
        #expect(high?.quality == .hires)
        let mp3 = try await api.songURLResult(song: song, quality: .exhigh)
        #expect(mp3?.quality == .exhigh)
    }
}
