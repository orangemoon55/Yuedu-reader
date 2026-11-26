import Foundation
import Testing
@testable import yuedu_app

struct MusicOnlineLyricsTests {
    private func json(_ object: [String: Any]) throws -> Data { try JSONSerialization.data(withJSONObject: object) }
    private func track(_ provider: String = "wy", _ id: String = "123") throws -> MediaHubLibraryItem {
        let info = provider == "wy" ? ["id": id] : ["songmid": id]
        let data = try JSONSerialization.data(withJSONObject: info, options: [.sortedKeys])
        return try MusicJSSong(sourceID: "readcc.music.js.fixture", provider: provider, title: "Fixture",
            artist: "Artist", album: "", poster: "", musicInfoJSON: String(decoding: data, as: UTF8.self)).savedItem(sourceName: "Fixture")
    }
    private var fixtureLyrics: YingxiaMusicLyrics { YingxiaMusicLyrics.parse("[00:01.00]Original\n[00:03.00]Second")! }

    @Test func neteaseDecodesTimedTranslationAndExplicitNoLyrics() throws {
        let data = try json(["code": 200, "lrc": ["lyric": "[00:01.00]Original\n[00:02.00]Second"],
                             "tlyric": ["lyric": "[00:01.00]翻譯"]])
        guard case .lyrics(let lyrics) = try MusicLyricsService.decode(data, provider: "wy") else {
            Issue.record("Expected timed lyrics"); return
        }
        #expect(lyrics.synced)
        #expect(lyrics.lines.first?.translation == "翻譯")
        #expect(lyrics.index(at: 0.5) == nil)
        #expect(lyrics.index(at: 1.5) == 0)
        #expect(try MusicLyricsService.decode(json(["code": 200, "nolyric": true]), provider: "wy") == .instrumental)
        #expect(try MusicLyricsService.decode(json(["nolyric": "true"]), provider: "wy") == .instrumental)
        #expect(try MusicLyricsService.decode(json(["uncollected": true]), provider: "wy") == .unavailable)
        #expect(try MusicLyricsService.decode(json(["lrc": ["lyric": ""]]), provider: "wy") == .unavailable)
    }

    @Test func qqDecodesEntitiesPlainAndCanonicalBase64() throws {
        let plain = try json(["code": 0, "retcode": 0, "lyric": "First &amp; second\n&#x4e2d;&#25991;"])
        guard case .lyrics(let lyrics) = try MusicLyricsService.decode(plain, provider: "tx") else { Issue.record("Missing plain lyrics"); return }
        #expect(!lyrics.synced)
        #expect(lyrics.lines.map(\.text) == ["First & second", "中文"])
        let encoded = try json(["retcode": 0, "lyric": Data("[00:01.00]Original".utf8).base64EncodedString(),
                                "trans": Data("[00:01.00]譯文".utf8).base64EncodedString()])
        guard case .lyrics(let timed) = try MusicLyricsService.decode(encoded, provider: "tx") else { Issue.record("Missing base64 lyrics"); return }
        #expect(timed.synced)
        #expect(timed.lines.first?.translation == "譯文")
        #expect(try MusicLyricsService.decode(json(["code": 0, "lyric": ""]), provider: "tx") == .unavailable)
    }

    @Test func rejectsJSONBase64AndResponseBoundaries() throws {
        for body in ["[]", "null", "callback({\"lyric\":\"text\"})", "{", "\"text\""] {
            #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(Data(body.utf8), provider: "tx") }
        }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(Data([0xff]), provider: "wy") }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(Data(repeating: 32, count: MusicLyricsService.maximumResponseBytes + 1), provider: "wy") }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(json(["code": 0, "lyric": 12]), provider: "tx") }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(json(["code": 0, "lyric": "/w=="]), provider: "tx") }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(json(["code": 0, "lyric": "AA=="]), provider: "tx") }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(json(["code": 200, "retcode": 0, "lyric": "text"]), provider: "tx") }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(json(["code": true]), provider: "wy") }
        #expect(throws: MusicOnlineLyricsError.self) { try MusicLyricsService.decode(json(["code": 403]), provider: "wy") }
    }

    @Test func identityNeverUsesTitlesOrOtherProviderIDs() throws {
        let wy = try #require(MusicLyricsIdentity.from(track("wy", "123")))
        #expect(wy.provider == "wy" && wy.songID == "123")
        let tx = try #require(MusicLyricsIdentity.from(track("tx", "003AbC9")))
        #expect(tx.provider == "tx" && tx.songID == "003AbC9")
        #expect(MusicLyricsIdentity.from(trackID: "a", provider: "tx", musicInfoJSON: "{\"songId\":123,\"title\":\"Guess\"}") == nil)
        #expect(MusicLyricsIdentity.from(trackID: "a", provider: "wy", musicInfoJSON: "{\"id\":true}") == nil)
        #expect(MusicLyricsIdentity.from(trackID: "a", provider: "wy", musicInfoJSON: "[]") == nil)
        #expect(MusicLyricsIdentity.from(trackID: "a", provider: "kg", musicInfoJSON: "{\"id\":123}") == nil)
        #expect(!MusicLyricsIdentity.validID("1&cookie=x", provider: "wy"))
        #expect(!MusicLyricsIdentity.validID("https://example.com", provider: "tx"))
        #expect(!MusicLyricsIdentity.validID("18446744073709551616", provider: "wy"))
    }

    @Test func requestsAreCredentialFreeAndRejectCrossHostRedirects() throws {
        for (provider, id, host) in [("wy", "123", "music.163.com"), ("tx", "003AbC9", "c.y.qq.com")] {
            let request = try MusicLyricsService.request(for: .init(trackID: "fixture", provider: provider, songID: id))
            #expect(request.url?.host == host)
            #expect(request.httpShouldHandleCookies == false)
            #expect(request.value(forHTTPHeaderField: "Cookie") == nil)
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.timeoutInterval == 10)
            #expect(MusicLyricsService.allows(request.url, host: host))
            #expect(!MusicLyricsService.allows(URL(string: "https://evil.invalid/lyric"), host: host))
            #expect(!MusicLyricsService.allows(URL(string: "http://\(host)/lyric"), host: host))
            #expect(!MusicLyricsService.allows(URL(string: "https://user:pass@\(host)/lyric"), host: host))
            #expect(!MusicLyricsService.allows(URL(string: "https://\(host):8443/lyric"), host: host))
        }
    }

    @MainActor @Test func sharedModelIsIdempotentAndImportsTakePriority() async throws {
        let counter = LyricsFixtureCounter(result: .lyrics(fixtureLyrics))
        let model = MusicLyricsModel(loader: { try await counter.load($0) })
        let item = try track()
        await model.load(for: item)
        #expect(model.state == .ready)
        #expect(model.trackID == item.id)
        #expect(model.currentLine(at: 1.5)?.text == "Original")
        #expect(model.currentLine(at: .nan) == nil)
        await model.load(for: item)
        #expect(await counter.count == 1)
        let imported = try #require(YingxiaMusicLyrics.parse("Imported local text"))
        let token = model.generation
        #expect(model.importLyrics(imported, trackID: item.id, generation: token))
        #expect(!model.importLyrics(fixtureLyrics, trackID: item.id, generation: token))
        await model.retry()
        #expect(model.lyrics == imported)
        #expect(await counter.count == 1)
        await model.load(for: nil)
        #expect(model.state == .idle && model.lyrics == nil && model.trackID == nil)
        await model.load(for: item)
        #expect(model.lyrics == imported)
        #expect(await counter.count == 1)
    }

    @MainActor @Test func staleCompletionStopAndImportOwnershipAreGenerationGuarded() async throws {
        let gate = LyricsFixtureGate()
        let model = MusicLyricsModel(loader: { try await gate.load($0) })
        let first = try track("wy", "101"), second = try track("wy", "202")
        let old = Task { await model.load(for: first) }
        #expect(await gate.waitFor("101"))
        let firstGeneration = model.generation
        #expect(model.state == .loading)
        let newer = Task { await model.load(for: second) }
        #expect(await gate.waitFor("202"))
        #expect(model.lyrics == nil && model.trackID == second.id)
        #expect(!model.importLyrics(fixtureLyrics, trackID: first.id, generation: firstGeneration))
        await gate.finish("101", result: .lyrics(fixtureLyrics))
        await old.value
        #expect(model.state == .loading && model.lyrics == nil)
        let secondGeneration = model.generation
        #expect(model.importLyrics(fixtureLyrics, trackID: second.id, generation: secondGeneration))
        await gate.finish("202", result: .instrumental)
        await newer.value
        #expect(model.state == .ready && model.lyrics == fixtureLyrics)
        let pending = Task { await model.load(for: first) }
        #expect(await gate.waitFor("101"))
        await model.load(for: nil)
        await gate.finish("101", result: .lyrics(fixtureLyrics))
        await pending.value
        #expect(model.state == .idle && model.lyrics == nil)
        #expect(!model.importLyrics(fixtureLyrics, trackID: second.id, generation: secondGeneration))
    }

    @MainActor @Test func failureNoLyricsUnsupportedAndRetryStates() async throws {
        let item = try track()
        let model = MusicLyricsModel(loader: { _ in throw MusicOnlineLyricsError.httpStatus })
        await model.load(for: item)
        guard case .failed = model.state else { Issue.record("Expected error state"); return }
        await model.retry()
        guard case .failed = model.state else { Issue.record("Expected retry error state"); return }
        for (result, expected) in [(MusicLyricsResult.instrumental, MusicLyricsModel.State.instrumental), (.unavailable, .unavailable)] {
            let empty = MusicLyricsModel(loader: { _ in result })
            await empty.load(for: item)
            #expect(empty.state == expected && empty.lyrics == nil)
        }
        let unsupported = MusicLyricsModel(loader: { _ in Issue.record("Unsupported provider must not request"); return .unavailable })
        await unsupported.load(for: try track("kg", "123"))
        #expect(unsupported.state == .unsupported && unsupported.lyrics == nil)
    }
}

private actor LyricsFixtureCounter {
    private(set) var count = 0
    let result: MusicLyricsResult
    init(result: MusicLyricsResult) { self.result = result }
    func load(_ identity: MusicLyricsIdentity) throws -> MusicLyricsResult { count += 1; return result }
}

private actor LyricsFixtureGate {
    private var pending: [String: CheckedContinuation<MusicLyricsResult, any Error>] = [:]
    func load(_ identity: MusicLyricsIdentity) async throws -> MusicLyricsResult {
        try await withCheckedThrowingContinuation { pending[identity.songID] = $0 }
    }
    func waitFor(_ id: String) async -> Bool {
        for _ in 0..<10_000 {
            if pending[id] != nil { return true }
            await Task.yield()
        }
        return false
    }
    func finish(_ id: String, result: MusicLyricsResult) { pending.removeValue(forKey: id)?.resume(returning: result) }
}
