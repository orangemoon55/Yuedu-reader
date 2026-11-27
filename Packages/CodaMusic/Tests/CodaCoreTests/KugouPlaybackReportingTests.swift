import Foundation
import Testing
import zlib
@testable import CodaCore

private final class KugouReportProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var recorded: [URLRequest] = []
    nonisolated(unsafe) private static var failPost = false
    static func prepare(failPost: Bool = false) { lock.withLock { recorded = []; self.failPost = failPost } }
    static var requests: [URLRequest] { lock.withLock { recorded } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            var request = request
            if request.httpBody == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var bytes = Data(), buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }; bytes.append(contentsOf: buffer.prefix(n))
                }
                request.httpBody = bytes
            }
            Self.lock.withLock { Self.recorded.append(request) }
            let path = request.url!.path
            if path == "/v2/post", Self.lock.withLock({ Self.failPost }) {
                client?.urlProtocol(self, didFailWithError: URLError(.networkConnectionLost)); return
            }
            let result: [String: Any]
            switch path {
            case "/v3/qrydid": result = ["status": 1, "data": ["deviceid": "fixture-device"]]
            case "/v2/gen":
                let session: [String: Any] = ["cookie": "fixture-cookie", "clienttime": 1700000000, "serverstr": "fixture-server"]
                let encrypted = try KugouPlaybackLogClient.aes(JSONSerialization.data(withJSONObject: session),
                    key: String(repeating: "a", count: 32), iv: "0123456789abcdef")
                result = ["status": 1, "data": encrypted.base64EncodedString()]
            case "/v2/post": result = ["errcode": 0]
            case "/playhistory/v1/upload_songs": result = ["status": 1, "error_code": 0]
            default: throw URLError(.unsupportedURL)
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: result))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@Suite(.serialized) struct KugouPlaybackProtocolTests {
    private let credentials = ["userid": "12345", "token": "fixture-only", "KUGOU_API_GUID": "0123456789abcdef0123456789abcdef", "KUGOU_API_MID": "fixture-mid"]
    private let device = KugouPlaybackLogClient.Device(model: "Fixture Mac", system: "15.0", width: 1440, height: 900)
    private func config() -> URLSessionConfiguration {
        let c = URLSessionConfiguration.ephemeral; c.protocolClasses = [KugouReportProtocol.self]; return c
    }
    private func client() throws -> KugouPlaybackLogClient {
        try .init(credentials: credentials, device: device, configuration: config(), randomField: { String(repeating: "a", count: 32) })
    }
    private func query(_ request: URLRequest) -> [String: String] {
        Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
    }
    private func expand(_ data: Data) throws -> Data {
        var size: uLongf = 262144, output = Data(count: Int(size))
        let status = output.withUnsafeMutableBytes { dst in data.withUnsafeBytes { src in
            uncompress(dst.bindMemory(to: Bytef.self).baseAddress!, &size, src.bindMemory(to: Bytef.self).baseAddress!, uLong(data.count))
        } }
        #expect(status == Z_OK); output.count = Int(size); return output
    }

    @Test func binaryPacketMatchesIndependentNodeZlibAndCryptoReference() throws {
        let file = try #require(Bundle.module.url(forResource: "kugou-cscc-reference", withExtension: "json", subdirectory: "Fixtures"))
        let reference = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        let event = try #require(Data(base64Encoded: reference["event"] as! String))
        let packet = try KugouPlaybackLogClient.packet(eventData: event, uuid: credentials["KUGOU_API_GUID"]!, mid: credentials["KUGOU_API_MID"]!,
            userID: "12345", device: .init(model: "Mac", system: "15.0", width: 1440, height: 900),
            session: .init(cookie: "reference-cookie", clienttime: "1700000000", serverstr: "reference-server", field2: "abcdef0123456789abcdef0123456789", expires: .distantFuture),
            now: Date(timeIntervalSince1970: 1700000000))
        let key = KugouPlaybackLogClient.md5(Data("0123456789abcdef0123456789abcdef1700000000abcdef0123456789abcdef0123456789reference-server".utf8))
        let compressedReference = try #require(Data(base64Encoded: reference["compressedPlain"] as! String))
        #expect(try KugouPlaybackLogClient.aes(compressedReference, key: key, iv: "0123456789abcdef").base64EncodedString() == reference["packet"] as? String)
        // System and Node zlib versions can choose different valid Huffman
        // blocks. Check both decoded layers and framing rather than pinning
        // compressed byte choices from a different zlib release.
        let plain = try expand(KugouPlaybackLogClient.aes(packet.body, key: key, iv: "0123456789abcdef", decrypt: true))
        let refPlain = try expand(compressedReference)
        func headerAndEvent(_ bytes: Data) throws -> (Data, Data) {
            let first = try #require(bytes.range(of: Data("\r\n".utf8)))
            let second = try #require(bytes.range(of: Data("\r\n".utf8), in: first.upperBound..<bytes.endIndex))
            return (Data(bytes[..<second.upperBound]), try expand(Data(bytes[second.upperBound...])))
        }
        let actual = try headerAndEvent(plain), expected = try headerAndEvent(refPlain)
        #expect(actual.0 == expected.0)
        #expect(actual.1 == event && actual.1 == expected.1)
        #expect(packet.query["length"] == String(plain.count))
    }

    @Test func handshakeIsReusedAndEndCarriesActualDurationAndState() async throws {
        KugouReportProtocol.prepare()
        let client = try client()
        try await client.report(event: .start, songID: "32232422")
        try await client.report(event: .end, songID: "32232422", durationMS: 14500, completed: false)
        let requests = KugouReportProtocol.requests
        #expect(requests.map { $0.url!.path } == ["/v3/qrydid", "/v2/gen", "/v2/post", "/v2/post"])
        let first = requests[0], firstQuery = query(first)
        let sign = KugouPlaybackLogClient.md5(Data("_t\(firstQuery["_t"]!)appidand02pbKC7zn{4U*ydo2M1Rir".utf8) + (first.httpBody ?? Data()))
        #expect(firstQuery["sign"] == sign)
        for request in requests {
            #expect(query(request)["token"] == nil)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
        }
        let end = requests[3]
        var params = query(end)
        let signature = params.removeValue(forKey: "sign")
        let text = params.keys.sorted().map { $0 + params[$0]! }.joined() + "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
        #expect(signature == KugouPlaybackLogClient.md5(Data(text.utf8) + end.httpBody!))
        let key = KugouPlaybackLogClient.md5(Data("0123456789abcdef0123456789abcdef1700000000\(String(repeating: "a", count: 32))fixture-server".utf8))
        let plain = try expand(KugouPlaybackLogClient.aes(end.httpBody!, key: key, iv: "0123456789abcdef", decrypt: true))
        #expect(params["length"] == String(plain.count))
        let firstBreak = try #require(plain.range(of: Data("\r\n".utf8)))
        let secondBreak = try #require(plain.range(of: Data("\r\n".utf8), in: firstBreak.upperBound..<plain.endIndex))
        let event = String(decoding: try expand(Data(plain[secondBreak.upperBound...])), as: UTF8.self)
        #expect(event.contains("duration=14500"))
        #expect(event.contains("state=中断播放"))
        #expect(event.contains("mixsongid=32232422"))
        #expect(event.contains("fo=Coda"))
        #expect(!event.contains("fixture-only"))
    }

    @Test func ambiguousPostFailureIsNotRetried() async throws {
        KugouReportProtocol.prepare(failPost: true)
        let client = try client()
        await #expect(throws: KugouPlaybackLogClient.Failure.self) { try await client.report(event: .start, songID: "32232422") }
        #expect(KugouReportProtocol.requests.filter { $0.url?.path == "/v2/post" }.count == 1)
    }

    @Test func historyWritesOneDeltaWithActualStartTimestampAndChecksAcknowledgement() async throws {
        KugouReportProtocol.prepare()
        let api = KugouMusicAPI(configuration: config(), playlistCredentials: credentials)
        try await api.uploadPlayHistory(songID: "32232422", playedAt: Date(timeIntervalSince1970: 1700000000))
        let request = try #require(KugouReportProtocol.requests.first)
        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody!) as? [String: Any])
        let songs = try #require(body["songs"] as? [[String: Any]])
        #expect(songs.count == 1)
        #expect((songs[0]["mxid"] as? NSNumber)?.intValue == 32232422)
        #expect((songs[0]["ot"] as? NSNumber)?.intValue == 1700000000)
        #expect((songs[0]["pc"] as? NSNumber)?.intValue == 1)
        #expect(query(request)["plat"] == "3")
        #expect(throws: (any Error).self) { try KugouMusicAPI.validateLibraryResponse(["status": 0], requiresData: false) }
    }
}

@Suite @MainActor struct KugouPlaybackReporterTests {
    private var song: KugouPlaybackReporter.Song { .init(trackID: -1, mixSongID: "32232422", hash: "fixture") }

    @Test func resourceIDAndReportingMixSongIDStaySeparateThroughEnrichmentAndPersistence() async throws {
        let metadata = try #require(KugouMusicAPI.mapCompleteTrack([
            "FileHash": String(repeating: "a", count: 32), "SongName": "Song", "SingerName": "Singer",
            "AlbumAudioID": "1105012556", "MixSongID": "855701644", "Duration": 202
        ]))
        #expect(metadata.kugouAlbumAudioId == "1105012556")
        #expect(metadata.kugouMixSongID == "855701644")
        let restored = try JSONDecoder().decode(ProviderSong.self, from: JSONEncoder().encode(metadata))
        #expect(restored.kugouMixSongID == "855701644")
        let platformSong = try JSONSerialization.jsonObject(with: JSONEncoder().encode(restored))
        let track = try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: [
            "id": -123, "name": "Song", "dt": 202000, "platformSong": platformSong
        ]))
        var identifiers: [String] = [], time = 0.0
        let transport = KugouPlaybackReporter.Transport(baseline: { _ in nil }, start: { identifiers.append($0) },
            history: { id, _ in identifiers.append(id) }, end: { id, _, _ in identifiers.append(id) }, confirm: { _, _, _ in .init() })
        let reporter = KugouPlaybackReporter(binding: { "account" }, clock: { time }, transport: { transport }, accepted: {}, reconciliationDelays: [])
        reporter.begin(track: track, position: 0)
        time = 2; reporter.sample(position: 2, advancing: true)
        reporter.finish(position: 2, completed: false)
        await reporter.waitForPendingSubmissions()
        #expect(identifiers == ["855701644", "855701644", "855701644"])
        let rank = KugouMusicAPI.mapAccountSong(["hash": "fixture", "id": 1105012556, "album_audio_id": 855701644,
            "name": "Singer - Song", "singername": "Singer", "listen_count": 2])
        #expect(rank?.kugouMixSongID == "855701644")
        #expect(rank?.name == "Song")
    }

    @Test func actualProgressExcludesPausesBufferingAndSeekAndDoesNotReplaceTimeOnCompletion() async {
        var time = 0.0, events: [String] = [], duration = 0, binding: String? = "first"
        let transport = KugouPlaybackReporter.Transport(baseline: { _ in events.append("baseline"); return 1 },
            start: { _ in events.append("start") }, history: { _, _ in events.append("history") },
            end: { _, ms, completed in duration = ms; events.append("end"); #expect(completed) },
            confirm: { _, _, _ in .init() })
        let reporter = KugouPlaybackReporter(binding: { binding }, clock: { time }, transport: { transport }, accepted: {}, reconciliationDelays: [])
        reporter.begin(song: song, position: 0)
        time = 10; reporter.sample(position: 10, advancing: true)
        time = 12; reporter.sample(position: 12, advancing: false)
        time = 100; reporter.sample(position: 12, advancing: false)
        reporter.willSeek(position: 12)
        time = 101; reporter.sample(position: 100, advancing: true)
        reporter.begin(song: song, position: 100) // resume / quality replacement
        time = 103; reporter.sample(position: 102, advancing: true)
        time = 103.5; reporter.finish(position: 102.5, completed: true)
        reporter.finish(position: 200, completed: true)
        await reporter.waitForPendingSubmissions()
        #expect(events == ["baseline", "start", "history", "end"])
        #expect(duration == 14500)
        binding = nil
    }

    @Test func noAudioOrInvalidEnginePositionsDoNotReport() async {
        var events = 0, time = 0.0
        let t = KugouPlaybackReporter.Transport(baseline: { _ in events += 1; return nil }, start: { _ in events += 1 },
            history: { _, _ in events += 1 }, end: { _, _, _ in events += 1 }, confirm: { _, _, _ in .init() })
        let r = KugouPlaybackReporter(binding: { "account" }, clock: { time }, transport: { t }, accepted: {}, reconciliationDelays: [])
        r.begin(song: song, position: 0)
        time = 100; r.sample(position: 0, advancing: true)
        time = 101; r.sample(position: .nan, advancing: true)
        r.finish(position: 0, completed: true)
        await r.waitForPendingSubmissions()
        #expect(events == 0)
    }

    @Test func changedAccountDropsOldQueuedEvents() async {
        var identity: String? = "old", time = 0.0, events = 0
        let t = KugouPlaybackReporter.Transport(baseline: { _ in events += 1; return nil }, start: { _ in events += 1 },
            history: { _, _ in events += 1 }, end: { _, _, _ in events += 1 }, confirm: { _, _, _ in .init() })
        let r = KugouPlaybackReporter(binding: { identity }, clock: { time }, transport: { t }, accepted: {}, reconciliationDelays: [])
        r.begin(song: song, position: 0)
        time = 2; r.sample(position: 2, advancing: true)
        r.finish(position: 2, completed: false)
        identity = "new"
        await r.waitForPendingSubmissions()
        #expect(events == 0)
    }

    @Test func failedPlaybackEventStillAttemptsIndependentHistoryOnce() async {
        var time = 0.0, starts = 0, history = 0, ends = 0
        let t = KugouPlaybackReporter.Transport(baseline: { _ in 1 }, start: { _ in starts += 1; throw URLError(.networkConnectionLost) },
            history: { _, _ in history += 1 }, end: { _, _, _ in ends += 1; throw URLError(.networkConnectionLost) }, confirm: { _, _, _ in .init() })
        let r = KugouPlaybackReporter(binding: { "account" }, clock: { time }, transport: { t }, accepted: {}, reconciliationDelays: [])
        r.begin(song: song, position: 0)
        time = 2; r.sample(position: 2, advancing: true)
        r.finish(position: 2, completed: false)
        await r.waitForPendingSubmissions()
        #expect(starts == 1 && history == 1 && ends == 1)
    }
}
