import Foundation
import Testing
@testable import CodaCore

/// Serves QQ's vkey, song detail and CDN answers. Each test uses its own songmids,
/// so the shared log stays readable while tests run in parallel.
private final class QQPlaybackFixture: URLProtocol, @unchecked Sendable {
    struct Song {
        var sizes: [String: Int]
        var mediaMid = "MEDIA"
        var playable: Set<String>
        /// Levels whose vkey link is handed out but every CDN refuses (QQ's fake links).
        var missingOnCDN: Set<String> = []
    }

    private static let lock = NSLock()
    private static var songs: [String: Song] = [:]
    private static var log: [String] = []

    static func register(_ songmid: String, _ song: Song) {
        lock.lock(); songs[songmid] = song; lock.unlock()
    }

    static func requests(containing marker: String) -> [String] {
        lock.lock(); defer { lock.unlock() }
        return log.filter { $0.contains(marker) }
    }

    private static func record(_ entry: String) {
        lock.lock(); log.append(entry); lock.unlock()
    }

    private static func song(inFilename name: String) -> Song? {
        lock.lock(); defer { lock.unlock() }
        return songs.first { name.contains($0.key) || name.contains($0.value.mediaMid) }?.value
    }

    private static func song(_ mid: String) -> Song? {
        lock.lock(); defer { lock.unlock() }
        return songs[mid]
    }

    static let flacHeader: Data = {
        var bytes: [UInt8] = Array("fLaC".utf8) + [0x00, 0x00, 0x00, 0x22]
        bytes += [UInt8](repeating: 0, count: 10)
        let info = (UInt64(44_100) << 44) | (UInt64(1) << 41) | (UInt64(15) << 36)
        bytes += (0..<8).map { UInt8((info >> (56 - 8 * UInt64($0))) & 0xff) }
        bytes += [UInt8](repeating: 0, count: 16)
        return Data(bytes)
    }()

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url!
        let host = url.host ?? ""
        if host == "u.y.qq.com" {
            if request.httpMethod == "POST" { return answerDetail() }
            return answerVkey(url)
        }
        // CDN probe: "good" hosts serve the file, everything else refuses it.
        let name = url.path.split(separator: "/").last.map(String.init) ?? ""
        Self.record("probe \(host) \(name)")
        // A host that accepts the connection and never answers.
        if host.hasPrefix("hang") { return }
        let missing = Self.song(inFilename: name)?.missingOnCDN.contains(String(name.prefix(4))) == true
        let ok = host.hasPrefix("good") && !missing
        let response = HTTPURLResponse(url: url, statusCode: ok ? 206 : 404, httpVersion: nil,
                                       headerFields: ["Content-Type": ok ? "audio/flac" : "text/plain"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: ok ? Self.flacHeader : Data())
        client?.urlProtocolDidFinishLoading(self)
    }

    private func body() -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func answerDetail() {
        let json = (try? JSONSerialization.jsonObject(with: body())) as? [String: Any]
        let info = (json?["songinfo"] as? [String: Any])?["param"] as? [String: Any]
        let mid = info?["song_mid"] as? String ?? ""
        Self.record("detail \(mid)")
        let song = Self.song(mid)
        var file: [String: Any] = ["media_mid": song?.mediaMid ?? ""]
        for (key, value) in song?.sizes ?? [:] { file[key] = value }
        respond(["songinfo": ["code": 0, "data": ["track_info": ["interval": 200, "file": file]]]])
    }

    private func answerVkey(_ url: URL) {
        let data = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "data" }?.value ?? ""
        let json = (try? JSONSerialization.jsonObject(with: Data(data.utf8))) as? [String: Any]
        let param = ((json?["req_0"] as? [String: Any])?["param"] as? [String: Any]) ?? [:]
        let filenames = param["filename"] as? [String] ?? []
        let mid = (param["songmid"] as? [String])?.first ?? ""
        let br = String(filenames.first?.prefix(4) ?? "")
        Self.record("vkey \(mid) \(br)")
        let song = Self.song(mid)
        let infos: [[String: Any]] = filenames.map { name in
            ["filename": name, "purl": song?.playable.contains(br) == true ? "\(name)?vkey=1" : ""]
        }
        respond(["req_0": ["code": 0, "data": [
            "midurlinfo": infos,
            "sip": ["http://hang.stream.qqmusic.qq.com/", "http://bad.stream.qqmusic.qq.com/", "http://good.stream.qqmusic.qq.com/"],
        ]]])
    }

    private func respond(_ object: [String: Any]) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: (try? JSONSerialization.data(withJSONObject: object)) ?? Data())
        client?.urlProtocolDidFinishLoading(self)
    }
}

private func fixtureAPI() -> QQMusicAPI {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [QQPlaybackFixture.self]
    return QQMusicAPI(configuration: configuration, authentication: QQMusicAuth(persistsSession: false))
}

@Suite struct QQMusicPlaybackTests {
    @Test func skipsLevelsTheDetailSaysAreMissingAndReusesTheResult() async throws {
        let mid = "SKIPHIRES0001"
        QQPlaybackFixture.register(mid, .init(sizes: ["size_hires": 0, "size_flac": 30_000_000, "size_320mp3": 8_000_000],
                                              playable: ["F000", "M800", "M500"]))
        let api = fixtureAPI()

        let first = try #require(try await api.songURLResult(songmid: mid, quality: .hires))
        #expect(first.br == "F000")
        #expect(first.quality == .lossless)
        #expect(first.attemptedBRs == ["F000"])
        #expect(QQPlaybackFixture.requests(containing: "vkey \(mid) RS01").isEmpty)
        #expect(first.url.contains("good.stream.qqmusic.qq.com"))

        // The quality menu asks again right away: no second vkey, no second detail.
        let again = try #require(try await api.songURLResult(songmid: mid, quality: .lossless))
        #expect(again.url == first.url)
        #expect(QQPlaybackFixture.requests(containing: "vkey \(mid) F000").count == 1)
        #expect(QQPlaybackFixture.requests(containing: "detail \(mid)").count == 1)
        let bitrates = try await api.averageBitrates(songmid: mid)
        #expect(bitrates["F000"] != nil)
        #expect(QQPlaybackFixture.requests(containing: "detail \(mid)").count == 1)
    }

    @Test func remembersTheCDNHostThatAnswered() async throws {
        let first = "HOSTMEMORY001", second = "HOSTMEMORY002"
        for mid in [first, second] {
            QQPlaybackFixture.register(mid, .init(sizes: ["size_flac": 1], playable: ["F000"]))
        }
        let api = fixtureAPI()
        _ = try #require(try await api.songURLResult(songmid: first, mediaMid: "MEDIA", quality: .lossless))
        // Every candidate host was probed at once for the first song.
        #expect(QQPlaybackFixture.requests(containing: "probe").filter { $0.contains(first) }.count > 1)

        let result = try #require(try await api.songURLResult(songmid: second, mediaMid: "MEDIA", quality: .lossless))
        #expect(result.url.contains("good.stream.qqmusic.qq.com"))
        let probes = QQPlaybackFixture.requests(containing: "probe").filter { $0.contains(second) }
        // Only the remembered host is asked, once per filename QQ offered.
        #expect(!probes.isEmpty)
        #expect(probes.allSatisfy { $0.hasPrefix("probe good.stream.qqmusic.qq.com ") })
    }

    @Test func fakeLinksAndAHangingHostDoNotStallTheFallback() async throws {
        let first = "FAKELINK00001", second = "FAKELINK00002"
        for mid in [first, second] {
            QQPlaybackFixture.register(mid, .init(sizes: [:], mediaMid: "M\(mid)", playable: ["RS01", "F000"], missingOnCDN: ["RS01"]))
        }
        let api = fixtureAPI()
        let started = Date()
        let result = try #require(try await api.songURLResult(songmid: first, mediaMid: "M\(first)", quality: .hires))
        // Every RS01 file was refused, so the hanging host is not waited out for each
        // filename (that took 4 × 6 s = 24 s). Loose bound: the full suite runs under load.
        #expect(Date().timeIntervalSince(started) < 10)
        #expect(result.br == "F000")
        #expect(result.url.contains("good.stream.qqmusic.qq.com"))

        // The host that hung is left out for the next song.
        _ = try #require(try await api.songURLResult(songmid: second, mediaMid: "M\(second)", quality: .hires))
        #expect(QQPlaybackFixture.requests(containing: "probe hang").filter { $0.contains(second) }.isEmpty)
    }

    @Test func fallsBackThroughLevelsWhenTheDetailIsSilent() async throws {
        let mid = "NODETAILS0001"
        QQPlaybackFixture.register(mid, .init(sizes: [:], playable: ["M500"]))
        let result = try #require(try await fixtureAPI().songURLResult(songmid: mid, mediaMid: "MEDIA", quality: .hires))
        #expect(result.br == "M500")
        #expect(result.attemptedBRs == ["RS01", "F000", "M800", "M500"])
    }

    @Test func detailOnlySkipsHigherLevelsItReportsAsEmpty() {
        let detail = QQSongPlaybackDetail(fileSizes: ["size_hires": 0, "size_flac": 10, "size_128mp3": 0])
        #expect(detail.definitelyLacks(br: "RS01"))
        #expect(!detail.definitelyLacks(br: "F000"))
        #expect(!detail.definitelyLacks(br: "M800"))
        #expect(!detail.definitelyLacks(br: "M500"))
        #expect(QQMusicAPI.fallbackBRs(preferred: "F000") == ["F000", "M800", "M500", "C400"])
    }

    @Test func cacheSharesOneLoadAndHonoursLifetimes() async throws {
        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func next() -> Int { lock.lock(); defer { lock.unlock() }; value += 1; return value }
        }
        let loads = Counter()
        let cache = QQMusicPlaybackCache<Int>()
        async let a = cache.value(for: "k", ttl: { _ in 60 }) {
            try await Task.sleep(nanoseconds: 50_000_000)
            return loads.next()
        }
        async let b = cache.value(for: "k", ttl: { _ in 60 }) { loads.next() }
        let values = try await [a, b]
        #expect(values == [1, 1])
        #expect(try await cache.value(for: "k", ttl: { _ in 60 }) { loads.next() } == 1)

        let uncached = try await cache.value(for: "n", ttl: { _ in nil }) { loads.next() }
        #expect(try await cache.value(for: "n", ttl: { _ in nil }) { loads.next() } == uncached + 1)
    }
}
