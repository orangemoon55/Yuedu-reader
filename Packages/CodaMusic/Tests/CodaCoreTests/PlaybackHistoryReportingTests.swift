import CryptoKit
import Foundation
import Testing
@testable import CodaCore

private final class PlaybackLogProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var replies: [[String: Any]] = []
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    static func prepare(_ values: [[String: Any]] = []) { lock.withLock { replies = values; recorded = [] } }
    static var requests: [URLRequest] { lock.withLock { recorded } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        var normalized = request
        normalized.httpBody = Self.body(request)
        let text = String(decoding: normalized.httpBody ?? Data(), as: UTF8.self)
        let filename = text.components(separatedBy: "filename=\"").dropFirst().first?.components(separatedBy: "\"").first ?? "missing"
        let payload = Self.lock.withLock { () -> [String: Any] in
            Self.recorded.append(normalized)
            return Self.replies.isEmpty ? ["code": 200, "data": ["successfiles": [filename]]] : Self.replies.removeFirst()
        }
        if let code = payload["_networkError"] as? Int {
            client?.urlProtocol(self, didFailWithError: NSError(domain: NSURLErrorDomain, code: code))
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: payload))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private static func body(_ request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var output = Data(), buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            output.append(contentsOf: buffer.prefix(count))
        }
        return output
    }
}

@Suite(.serialized) @MainActor struct PlaybackHistoryReportingTests {
    private func client(authenticated: Bool = true) -> NeteaseClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [PlaybackLogProtocol.self]
        let client = NeteaseClient(configuration: configuration, persistsCookies: false)
        if authenticated { client.setCookies(["MUSIC_U": "test+account/only=", "__csrf": "test-csrf", "os": "ios", "appver": "9.0.90"]) }
        return client
    }
    private var song: NeteasePlaybackLog.Song {
        .init(id: 142930, sourceID: 22, duration: 180, quality: "lossless", fee: 0)
    }

    @Test func ncblPacketMatchesIndependentJavaScriptReference() throws {
        let url = try #require(Bundle.module.url(forResource: "ncbl-reference", withExtension: "json", subdirectory: "Fixtures"))
        let fixture = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let key = Data(0..<32), uuid = Data(0..<16)
        #expect(NeteasePlaybackLog.rsaWrap(key).map { String(format: "%02x", $0) }.joined() == fixture["rsa"] as? String)
        let high = NeteasePlaybackLog.rsaWrap(Data([0xa2] + [UInt8](repeating: 255, count: 31)))
        #expect(high.map { String(format: "%02x", $0) }.joined() == fixture["rsaHigh"] as? String)
        let metadata = Data("{\"MUSIC_U\":\"fixture-only\"}".utf8)
        let body = Data("1700000000\u{01}_plv\u{01}{\"id\":\"123\"}".utf8)
        let compressedBase64 = try #require(fixture["compressedBody"] as? String)
        let compressedReference = try #require(Data(base64Encoded: compressedBase64))
        let packet = try NeteasePlaybackLog.encode(metadata: metadata, body: body, key: key, uuid: uuid,
            sequence: 100, compressedBody: compressedReference)
        #expect(packet.base64EncodedString() == fixture["packet"] as? String)
        var state: UInt32 = 0x12345678
        let large = Data((0..<70000).map { _ -> UInt8 in
            state ^= state << 13; state ^= state >> 17; state ^= state << 5
            return UInt8(truncatingIfNeeded: state)
        })
        let framed = try NeteasePlaybackLog.encode(metadata: metadata, body: large, key: key, uuid: uuid, sequence: 65535)
        #expect(SHA256.hash(data: large).map { String(format: "%02x", $0) }.joined() == fixture["largeBodySHA256"] as? String)
        // Validate packet framing separately from entropy compression choices.
        let headerLength = Int(framed[8]) | Int(framed[9]) << 8
        #expect(NeteasePlaybackLog.little32(framed, 58) == 65535)
        #expect(NeteasePlaybackLog.little32(framed, 62) == 65537)
        #expect(NeteasePlaybackLog.little32(framed, 66) == UInt32(framed.count - headerLength))
        var compressed = Data(), offset = headerLength
        var sequence: UInt32 = 65535
        while offset < framed.count {
            let size = Int(framed[offset]) | Int(framed[offset + 1]) << 8
            #expect(size <= 0x8000)
            #expect(NeteasePlaybackLog.little32(framed, offset + 2) == sequence)
            compressed.append(NeteasePlaybackLog.chacha20(Data(framed[(offset + 6)..<(offset + 6 + size)]),
                key: key, nonce: Data(uuid.prefix(12)), counter: NeteasePlaybackLog.little32(uuid, 12) >> 2))
            offset += size + 6; sequence += 1
        }
        #expect(compressed.prefix(5) == Data([0x28, 0xb5, 0x2f, 0xfd, 0xa0]))
        #expect(NeteasePlaybackLog.little32(compressed, 5) == UInt32(large.count))
        let block = UInt32(compressed[9]) | UInt32(compressed[10]) << 8 | UInt32(compressed[11]) << 16
        #expect(block & 7 == 1) // final raw block
        #expect(block >> 3 == UInt32(large.count))
        #expect(Data(compressed.dropFirst(12)) == large)
    }

    @Test func zstdRawBlocksHandleEmptyAndMultiBlockRecords() {
        for length in [0, 1, 131072, 131073, 300000] {
            let input = Data((0..<length).map { UInt8(truncatingIfNeeded: $0 * 31 + 7) })
            let frame = NeteasePlaybackLog.zstdFrame(input)
            #expect(frame.prefix(5) == Data([0x28, 0xb5, 0x2f, 0xfd, 0xa0]))
            #expect(NeteasePlaybackLog.little32(frame, 5) == UInt32(length))
            var offset = 9, decoded = Data()
            while offset < frame.count {
                let block = UInt32(frame[offset]) | UInt32(frame[offset + 1]) << 8 | UInt32(frame[offset + 2]) << 16
                let size = Int(block >> 3)
                #expect(size <= 131072 && block & 6 == 0)
                decoded.append(frame[(offset + 3)..<(offset + 3 + size)])
                offset += size + 3
                #expect((block & 1 != 0) == (offset == frame.count))
            }
            #expect(decoded == input)
        }
    }

    @Test func chachaMatchesRFC8439BlockVector() {
        var nonce = Data(repeating: 0, count: 12)
        nonce[3] = 9; nonce[7] = 0x4a
        let result = NeteasePlaybackLog.chacha20(Data(repeating: 0, count: 64), key: Data(0..<32), nonce: nonce, counter: 1)
        #expect(result.map { String(format: "%02x", $0) }.joined() ==
            "10f1e7e4d13b5915500fdd1fa32071c4c7d1f4c733c068030422aa9ac3d46c4e" +
            "d2826446079faa0914c2d705d98b02a2b5129cd1de164eb9cbd083e8a2503c4e")
    }

    @Test func uploadUsesConsistentClientProfileAndKeepsCookieTokenLiteral() async throws {
        PlaybackLogProtocol.prepare()
        try await client().uploadPlaybackLog(song: song, event: .start)
        let request = try #require(PlaybackLogProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://clientlog3.music.163.com/api/clientlog/encrypt/upload?multiupload=true")
        #expect(request.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") == true)
        let cookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
        #expect(cookie.contains("MUSIC_U=test+account/only="))
        #expect(cookie.contains("os=pc"))
        #expect(!cookie.contains("os=ios"))
        #expect(!cookie.contains("appver=9.0.90"))
        let body = try #require(request.httpBody)
        let marker = try #require(body.range(of: Data("\r\n\r\n".utf8)))
        let packet = Data(body[marker.upperBound...])
        #expect(packet.prefix(4) == Data("NCBL".utf8))
        let length = Int(packet[8]) | Int(packet[9]) << 8
        let decrypted = NeteasePlaybackLog.chacha20(Data(packet[74..<length]), key: Data(packet[26..<58]),
            nonce: Data(packet[10..<22]), counter: NeteasePlaybackLog.little32(packet, 22) >> 2)
        let metadata = try #require(JSONSerialization.jsonObject(with: decrypted) as? [String: String])
        #expect(metadata["MUSIC_U"] == "test+account/only=")
        #expect(metadata["__csrf"] == "test-csrf")
        for (name, value) in metadata { #expect(cookie.contains("\(name)=\(value)")) }
    }

    @Test func genericSuccessOrWrongFilenameCannotMasqueradeAsAcceptedUpload() async throws {
        PlaybackLogProtocol.prepare([["code": 200], ["code": 200, "data": ["successfiles": ["another-file"], "rate": 10000]]])
        let api = client()
        for _ in 0..<2 {
            do { try await api.uploadPlaybackLog(song: song, event: .start); Issue.record("A filename acknowledgement is required") }
            catch NeteaseAPIError.business(let code, _) { #expect(code == -1) }
        }
        #expect(PlaybackLogProtocol.requests.count == 2)
    }

    @Test func tlsFailureUsesOfficialFallbackWithTheSameAuthenticatedPacket() async throws {
        PlaybackLogProtocol.prepare([["_networkError": URLError.secureConnectionFailed.rawValue]])
        try await client().uploadPlaybackLog(song: song, event: .start)
        let requests = PlaybackLogProtocol.requests
        #expect(requests.count == 2)
        #expect(requests.first?.url?.host == "clientlog3.music.163.com")
        #expect(requests.last?.url?.host == "music.163.com")
        #expect(requests.last?.url?.scheme == "https")
        #expect(requests.first?.httpBody == requests.last?.httpBody)
        #expect(requests.first?.value(forHTTPHeaderField: "Cookie") == requests.last?.value(forHTTPHeaderField: "Cookie"))
    }

    @Test func lostConnectionDoesNotReplayAnUploadThatMightHaveReachedTheServer() async throws {
        PlaybackLogProtocol.prepare([["_networkError": URLError.networkConnectionLost.rawValue]])
        do { try await client().uploadPlaybackLog(song: song, event: .start); Issue.record("Expected failure") }
        catch let error as URLError { #expect(error.code == .networkConnectionLost) }
        #expect(PlaybackLogProtocol.requests.count == 1)
    }

    @Test func authAndBusinessRejectionsRemainFailures() async throws {
        PlaybackLogProtocol.prepare([["code": 301], ["code": 500, "message": "rejected"]])
        let api = client()
        do { try await api.uploadPlaybackLog(song: song, event: .start); Issue.record("Expected login failure") }
        catch NeteaseAPIError.needLogin {}
        do { try await api.uploadPlaybackLog(song: song, event: .finish, seconds: 30); Issue.record("Expected rejection") }
        catch NeteaseAPIError.business(let code, _) { #expect(code == 500) }
    }

    @Test func logContainsActualTimeAndNoInventedReferrals() throws {
        let data = try NeteasePlaybackLog.record(song: song, event: .finish, seconds: 999, completed: false, now: Date(timeIntervalSince1970: 100))
        let parts = String(decoding: data, as: UTF8.self).components(separatedBy: "\u{01}")
        #expect(parts[0] == "100"); #expect(parts[1] == "_pld")
        let fields = try #require(JSONSerialization.jsonObject(with: Data(parts[2].utf8)) as? [String: Any])
        #expect(fields["time"] as? Int == 180)
        #expect(fields["resource_time"] as? Int == 180)
        #expect(fields["fee"] as? Int == 0)
        #expect(fields["sourceId"] as? String == "22")
        #expect(fields["bitrate_level"] as? String == "lossless")
        #expect(fields["end"] as? String == "interrupt")
        #expect(fields["_addrefer"] == nil && fields["_multirefers"] == nil)
    }

    @Test func durationLogIncludesOnlyKnownStreamBitrate() throws {
        var actual = song
        actual.bitrate = 987
        for event in [NeteasePlaybackLog.Event.start, .finish] {
            let record = try NeteasePlaybackLog.record(song: actual, event: event, seconds: 180,
                                                       completed: true, now: .now)
            let json = record.split(separator: 1, maxSplits: 2)[2]
            let fields = try #require(JSONSerialization.jsonObject(with: Data(json)) as? [String: Any])
            #expect(fields["bitrate"] as? Int == 987)
        }
        let unknown = try NeteasePlaybackLog.record(song: song, event: .finish, seconds: 180,
                                                    completed: true, now: .now)
        let fields = try #require(JSONSerialization.jsonObject(with: Data(unknown.split(separator: 1, maxSplits: 2)[2])) as? [String: Any])
        #expect(fields["bitrate"] == nil)
    }

    @Test func submissionsKeepSessionsOrderedAndDoNotReportTheSameFinishTwice() async throws {
        var events: [(Int, String, Int, Bool)] = []
        let reporter = PlaybackHistoryReporter(client: client(), upload: { song, event, seconds, completed in
            events.append((song.id, event.rawValue, seconds, completed))
        })
        let first = try #require(reporter.start(trackID: 1, sourceID: 10, duration: 180))
        reporter.finish(first, playbackTime: 31.7, duration: 180, completed: false)
        reporter.finish(first, playbackTime: 70, duration: 180, completed: false)
        let second = try #require(reporter.start(trackID: 2, sourceID: 20, duration: 180))
        reporter.finish(second, playbackTime: 179.6, duration: 180, completed: true)
        await reporter.waitForPendingSubmissions()
        #expect(events.map { $0.0 } == [1, 1, 2, 2])
        #expect(events.map { $0.1 } == ["_plv", "_pld", "_plv", "_pld"])
        #expect(events.map { $0.2 } == [0, 31, 0, 180])
        #expect(events[3].3)
    }

    @Test func switchedAccountsDiscardQueuedEventsAndAnonymousPlaybackDoesNotReport() async throws {
        PlaybackLogProtocol.prepare()
        let api = client(), reporter = PlaybackHistoryReporter(client: client(authenticated: false))
        #expect(reporter.start(trackID: 1, sourceID: 10) == nil)
        let authenticated = PlaybackHistoryReporter(client: api)
        let session = try #require(authenticated.start(trackID: 1, sourceID: 10))
        authenticated.finish(session, playbackTime: 30, duration: 180, completed: false)
        api.setCookies(["MUSIC_U": "different-account"])
        await authenticated.waitForPendingSubmissions()
        #expect(PlaybackLogProtocol.requests.isEmpty)
        do { try await client(authenticated: false).uploadPlaybackLog(song: song, event: .start); Issue.record("Expected login failure") }
        catch NeteaseAPIError.needLogin {}
        #expect(PlaybackLogProtocol.requests.isEmpty)
    }

    @Test func zeroOrInvalidListeningTimeDoesNotProduceDurationEvents() async throws {
        var events: [NeteasePlaybackLog.Event] = []
        let reporter = PlaybackHistoryReporter(client: client(), upload: { _, event, _, _ in events.append(event) })
        let first = try #require(reporter.start(trackID: 1, sourceID: 10))
        reporter.finish(first, playbackTime: .nan, duration: .infinity, completed: false)
        let second = try #require(reporter.start(trackID: 2, sourceID: 10))
        reporter.finish(second, playbackTime: -8, duration: 180, completed: false)
        await reporter.waitForPendingSubmissions()
        #expect(events == [.start, .start])
    }
}
