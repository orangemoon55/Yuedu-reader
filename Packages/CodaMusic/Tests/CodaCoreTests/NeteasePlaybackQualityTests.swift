import Foundation
import Testing
@testable import CodaCore

private final class NeteasePlaybackFixture: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [[String: Any]] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func prepare(_ responses: [[String: Any]]) -> NeteaseClient {
        lock.withLock { self.responses = responses; recorded = [] }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [Self.self]
        return NeteaseClient(configuration: configuration, persistsCookies: false)
    }

    static var requests: [URLRequest] { lock.withLock { recorded } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        if request.value(forHTTPHeaderField: "Range") == "bytes=0-41" {
            let hiRes = request.url?.path == "/song.flac"
            let header = KugouAuthorizationTests.flacHeader(sampleRate: hiRes ? 96_000 : 44_100, bitDepth: hiRes ? 24 : 16)
            let response = HTTPURLResponse(url: request.url!, statusCode: 206, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: header)
            client?.urlProtocolDidFinishLoading(self)
            return
        }
        let payload = Self.lock.withLock {
            Self.recorded.append(request)
            return Self.responses.isEmpty ? ["code": 500] : Self.responses.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized)
struct NeteasePlaybackQualityTests {
    private func stream(_ level: String?, br: Int = 0, type: String = "mp3", trial: Bool = false) -> [String: Any] {
        let name = level == "hires" ? "song" : "cd"
        var item: [String: Any] = ["id": 42, "code": 200, "url": "https://m1.music.126.net/\(name).\(type)", "type": type, "br": br]
        item["level"] = level
        if trial { item["freeTrialInfo"] = ["start": 0, "end": 30] }
        return ["code": 200, "data": [item]]
    }

    @Test func retriesRejectedRequestBeforeDroppingToALowerTier() async throws {
        let client = NeteasePlaybackFixture.prepare([["code": -460], stream("hires", type: "flac")])
        let result = try await NeteaseAPI.preferredSongURL(id: 42, quality: .exhigh, alwaysHighest: true, using: client)
        let requests = NeteasePlaybackFixture.requests
        #expect(result?.resolvedAudioQuality == .hires)
        #expect(requests.map { $0.url?.path } == Array(repeating: "/eapi/song/enhance/player/url/v1", count: 2))
        #expect(requests.first?.value(forHTTPHeaderField: "Cookie")?.contains("os=ios") == true)
        #expect(requests.last?.value(forHTTPHeaderField: "Cookie")?.contains("os=pc") == true)
    }

    @Test func alwaysHighestUsesMeasuredQualityBeforeRanking() async throws {
        var cdStream = stream("hires", br: 900_000, type: "flac")
        cdStream["data"] = [["id": 42, "code": 200, "url": "https://m1.music.126.net/cd.flac",
                            "type": "flac", "br": 900_000, "level": "hires"]]
        let client = NeteasePlaybackFixture.prepare([stream("hires", br: 320_000, type: "aac"), cdStream])
        let result = try await NeteaseAPI.preferredSongURL(id: 42, quality: .hires, alwaysHighest: true, using: client)
        #expect(result?.resolvedAudioQuality == .lossless)
        #expect(result?.url?.hasSuffix("/cd.flac") == true)
        #expect(NeteasePlaybackFixture.requests.count == 2)
    }

    @Test func downgradedFixedTierChecksIntermediateFullStreams() async throws {
        let client = NeteasePlaybackFixture.prepare([stream("standard", trial: true), stream(nil, br: 852061, type: "flac")])
        let result = try await NeteaseAPI.preferredSongURL(id: 42, quality: .hires, alwaysHighest: false, using: client)
        #expect(result?.resolvedAudioQuality == .lossless)
        #expect(result?.freeTrialInfo == nil)
        #expect(NeteasePlaybackFixture.requests.count == 2)
    }

    @Test func successfulServerDowngradeIsKeptIfIntermediateRequestFails() async throws {
        let client = NeteasePlaybackFixture.prepare([stream("exhigh", br: 320000), ["code": -460], ["code": -460]])
        let result = try await NeteaseAPI.preferredSongURL(id: 42, quality: .standard, alwaysHighest: true, using: client)
        #expect(result?.resolvedAudioQuality == .exhigh)
        #expect(NeteasePlaybackFixture.requests.count == 3)
    }
}
