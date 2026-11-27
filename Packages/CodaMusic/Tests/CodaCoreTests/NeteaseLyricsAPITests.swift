import CommonCrypto
import Foundation
import Testing
@testable import CodaCore

private final class LyricEndpointProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [[String: Any]] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func prepare(_ values: [[String: Any]]) {
        lock.withLock { replies = values; recorded = [] }
    }

    static var requests: [URLRequest] { lock.withLock { recorded } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let payload = Self.lock.withLock { () -> [String: Any] in
            Self.recorded.append(request)
            return Self.replies.isEmpty ? ["code": 500] : Self.replies.removeFirst()
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct NeteaseLyricsAPITests {
    private func client() -> NeteaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [LyricEndpointProtocol.self]
        return NeteaseClient(configuration: configuration, persistsCookies: false)
    }

    /// Independently decrypt the wire request to verify the endpoint contract,
    /// rather than asserting against the production payload-building helper.
    private func requestBody(_ request: URLRequest) throws -> String {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        return try #require(String(data: body, encoding: .utf8))
    }

    private func payload(_ request: URLRequest) throws -> (path: String, data: [String: Any]) {
        let form = try requestBody(request)
        let field = try #require(form.split(separator: "&").first { $0.hasPrefix("params=") })
        let hex = String(field.dropFirst(7)).removingPercentEncoding ?? ""
        let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { offset -> UInt8? in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            let end = hex.index(start, offsetBy: 2)
            return UInt8(hex[start..<end], radix: 16)
        }
        let encrypted = Data(bytes)
        let key = Array("e82ckenh8dichen8".utf8)
        var output = [UInt8](repeating: 0, count: bytes.count + kCCBlockSizeAES128)
        var written = 0
        let capacity = output.count
        let status = encrypted.withUnsafeBytes { input in
            key.withUnsafeBytes { keyBytes in
                output.withUnsafeMutableBytes { destination in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding),
                        keyBytes.baseAddress, kCCKeySizeAES128, nil,
                        input.baseAddress, encrypted.count, destination.baseAddress, capacity, &written)
                }
            }
        }
        #expect(status == kCCSuccess)
        let text = try #require(String(bytes: output.prefix(written), encoding: .utf8))
        let parts = text.components(separatedBy: "-36cd479b6b5-")
        #expect(parts.count == 3)
        let data = try #require(parts[1].data(using: .utf8))
        return (parts[0], try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]))
    }

    @Test func desktopProfileReplacesImportedCookiesAndMatchesEncryptedHeader() async throws {
        LyricEndpointProtocol.prepare([["code": 200], ["code": 200]])
        let transport = client()
        transport.setCookies(["os": "ios", "appver": "old", "deviceId": "old-device", "MUSIC_U": "synthetic", "__csrf": "csrf"])
        _ = try await transport.eapi("/v3/song/detail", ["c": "[]"])
        _ = try await transport.eapi("/v3/song/detail", ["c": "[]"])
        var identity: String?
        for request in LyricEndpointProtocol.requests {
            let (path, body) = try payload(request)
            #expect(path == "/api/v3/song/detail")
            #expect(body["e_r"] as? Bool == false)
            let header = try #require(body["header"] as? [String: String])
            let device = try #require(header["deviceId"])
            #expect(device.count == 52 && device != "old-device")
            if let identity { #expect(device == identity) }
            identity = device
            #expect(header["os"] == "pc")
            #expect(header["MUSIC_U"] == "synthetic")
            let cookieFields = Set((request.value(forHTTPHeaderField: "Cookie") ?? "").components(separatedBy: "; "))
            for (key, value) in header { #expect(cookieFields.contains("\(key)=\(value)")) }
        }
        #expect(transport.cookie(named: "os") == "ios")
        #expect(transport.cookie(named: "deviceId") == "old-device")
    }

    @Test func recentPlaybackUsesEAPIAndKeepsServerTimestamps() async throws {
        LyricEndpointProtocol.prepare([["code": 200, "data": ["list": [
            ["data": ["id": 1, "name": "Earlier"], "playTime": 1_700_000_000_000],
            ["data": ["id": 2, "name": "Later"], "playTime": 1_700_000_060_000]
        ]]]])
        let records = try await NeteaseAPI.recentSongs(limit: 20, using: client())
        #expect(records.map(\.song.id) == [2, 1])
        #expect(records.first?.playedAt.timeIntervalSince1970 == 1_700_000_060)
        let request = try #require(LyricEndpointProtocol.requests.first)
        #expect(request.url?.path == "/eapi/play-record/song/list")
        let (_, body) = try payload(request)
        #expect(body["limit"] as? Int == 20)
    }

    @Test func dailyManualRefreshRequestsANewBatchWhileOrdinaryLoadDoesNot() async throws {
        LyricEndpointProtocol.prepare([
            ["code": 200, "data": ["dailySongs": []]],
            ["code": 200, "data": ["dailySongs": []]],
        ])
        let transport = client()
        _ = try await NeteaseAPI.dailyRecommendSongs(using: transport)
        _ = try await NeteaseAPI.dailyRecommendSongs(afresh: true, using: transport)
        let requests = LyricEndpointProtocol.requests
        #expect(requests.count == 2)
        for (index, request) in requests.enumerated() {
            #expect(request.url?.path == "/eapi/v3/discovery/recommend/songs")
            let (_, payload) = try self.payload(request)
            if index == 0 { #expect(payload["afresh"] == nil) }
            else { #expect(payload["afresh"] as? Bool == true) }
        }
    }

    @Test func usesMobileEAPIAndRequestsEveryWordLyricField() async throws {
        LyricEndpointProtocol.prepare([["code": 200, "lrc": ["lyric": "[00:10.00]歌词"],
            "yrc": ["lyric": "[10000,1000](10000,1000,0)歌词"],
            "ytlrc": ["lyric": "[00:10.00]译文"], "yromalrc": ["lyric": "[00:10.00]reading"]]])
        let response = try await NeteaseAPI.lyric(id: 142930, using: client())
        let requests = LyricEndpointProtocol.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url?.absoluteString == "https://interface.music.163.com/eapi/song/lyric/v1")
        let decoded = try payload(request)
        #expect(decoded.path == "/api/song/lyric/v1")
        #expect(decoded.data["id"] as? Int == 142930)
        #expect(decoded.data["cp"] as? Bool == false)
        #expect(decoded.data["e_r"] as? Bool == false)
        for key in ["tv", "lv", "rv", "kv", "yv", "ytv", "yrv"] {
            #expect(decoded.data[key] as? Int == 0)
        }
        let header = try #require(decoded.data["header"] as? [String: String])
        #expect(header["os"] == "ios")
        #expect(header["appver"] == "9.0.90")
        #expect(response.yrc?.lyric?.isEmpty == false)
        #expect(response.ytlrc?.lyric?.isEmpty == false)
        #expect(response.yromalrc?.lyric?.isEmpty == false)
    }

    @Test func legacyFallbackKeepsEAPIAndLyricParameters() async throws {
        LyricEndpointProtocol.prepare([["code": 500], ["code": 200, "lrc": ["lyric": "[00:10.00]歌词"]]])
        let response = try await NeteaseAPI.lyric(id: 142930, using: client())
        #expect(response.lrc?.lyric == "[00:10.00]歌词")
        let requests = LyricEndpointProtocol.requests
        #expect(requests.count == 2)
        let last = try #require(requests.last)
        #expect(last.url?.path == "/eapi/song/lyric")
        let decoded = try payload(last)
        #expect(decoded.path == "/api/song/lyric")
        #expect(decoded.data["_nmclfl"] as? Int == 1)
        for key in ["tv", "lv", "rv", "kv"] { #expect(decoded.data[key] as? Int == -1) }
    }

    @Test func successfulPureMusicDoesNotTriggerLegacyRequest() async throws {
        LyricEndpointProtocol.prepare([["code": 200, "pureMusic": true]])
        let response = try await NeteaseAPI.lyric(id: 142930, using: client())
        #expect(response.pureMusic == true)
        #expect(LyricsParser.parse(response).isInstrumental)
        #expect(LyricEndpointProtocol.requests.count == 1)
    }

    @Test func cancellationNeverFallsBack() async throws {
        LyricEndpointProtocol.prepare([])
        let isolated = client()
        let gate = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate.stream { break }
            return try await NeteaseAPI.lyric(id: 142930, using: isolated)
        }
        task.cancel()
        gate.continuation.finish()
        do { _ = try await task.value; Issue.record("Cancelled lyric lookup completed") }
        catch is CancellationError { }
        #expect(LyricEndpointProtocol.requests.isEmpty)
    }
}
