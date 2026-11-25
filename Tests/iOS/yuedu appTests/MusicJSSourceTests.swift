import Foundation
import Testing
@testable import yuedu_app

@Suite("Native LX JavaScript source import", .serialized)
@MainActor
struct MusicJSSourceTests {
    private let script = #"""
/*! @name Offline LX Fixture
 * @version 1.0
 */
const { EVENT_NAMES, on, send } = globalThis.lx;
on(EVENT_NAMES.request, async ({action, info}) => {
  if (action === 'search') return [{name:'Fixture Song',singer:'Fixture Artist',albumName:'Fixture Album',id:7,meta:{wy:{id:7}}}];
  if (action === 'musicUrl') return info.musicInfo.bad ? 'file:///not-allowed.mp3' : 'https://fixture.invalid/audio.mp3';
  throw Error('unsupported');
});
send(EVENT_NAMES.inited,{sources:{wy:{name:'Fixture',type:'music',actions:['search','musicUrl'],qualitys:['128k','320k']},
 tx:{name:'Resolver Only',type:'music',actions:['musicUrl'],qualitys:['128k']}}});
"""#

    @Test("imports only JS, recognizes capabilities, persists, searches and resolves at play time")
    func importSearchResolve() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.js")
        try script.write(to: file, atomically: true, encoding: .utf8)
        let store = MusicJSSourceStore(directory: root.appendingPathComponent("store"))
        let source = try await store.importFile(file)
        #expect(source.name == "Offline LX Fixture")
        #expect(source.version == "1.0")
        #expect(source.providers.count == 2)
        #expect(source.providers.first { $0.id == "wy" }?.canSearch == true)
        #expect(source.providers.first { $0.id == "tx" }?.canSearch == false)
        let songs = try await store.search(sourceID: source.id, provider: "wy", query: "Fixture")
        let song = try #require(songs.first)
        #expect(song.title == "Fixture Song" && song.artist == "Fixture Artist")
        let saved = try song.savedItem(sourceName: source.name)
        #expect(saved.musicURL == nil && saved.musicHeaders == nil)
        #expect(MusicJSSong.from(saved) == song)
        let playable = try await store.resolve(song, quality: "128k")
        #expect(playable.id == saved.id)
        #expect(playable.musicURL == "https://fixture.invalid/audio.mp3")
        #expect(MusicTrackDescriptor.from(playable)?.resolvedURL()?.scheme == "https")
        let reopened = MusicJSSourceStore(directory: root.appendingPathComponent("store"))
        #expect(reopened.sources == [source])
        let again = try await reopened.resolve(song, quality: "320k")
        #expect(again.id == saved.id)
        // No URLSession/player opens the .invalid address: these are real WebKit protocol tests.
        let m3u = root.appendingPathComponent("playlist.m3u")
        try "#EXTM3U\nhttps://fixture.invalid/one.mp3".write(to: m3u, atomically: true, encoding: .utf8)
        await #expect(throws: MusicJSError.self) { try await store.importFile(m3u) }
        #expect(store.sources == [source])
        try store.remove(source)
        #expect(store.sources.isEmpty)
        await #expect(throws: MusicJSError.self) { try await store.resolve(song, quality: "128k") }
    }

    @Test("invalid JS cannot replace an already installed source")
    func badSourceIsRejected() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("bad.js")
        try "throw new Error('synthetic failure')".write(to: file, atomically: true, encoding: .utf8)
        let store = MusicJSSourceStore(directory: root.appendingPathComponent("store"))
        await #expect(throws: MusicJSError.self) { try await store.importFile(file) }
        #expect(store.sources.isEmpty)
    }

    @Test("rejects secret bookmarks without redacting resolver input; import reads are bounded")
    func persistenceAndReadBounds() throws {
        let raw = #"{"id":7,"meta":{"access_token":"synthetic-only"}}"#
        let song = MusicJSSong(sourceID: "readcc.music.js.fixture", provider: "wy", title: "Fixture",
            artist: "", album: "", poster: "", musicInfoJSON: raw)
        #expect(!MusicJSSong.canPersistMusicInfo(raw))
        #expect(throws: MusicJSError.self) { try song.savedItem(sourceName: "Fixture") }
        #expect(song.musicInfoJSON == raw)
        #expect(song.playbackItem(sourceName: "Fixture").videoID.hasPrefix("lx-volatile:"))
        #expect(MusicJSSong.canPersistMusicInfo(#"{"id":7,"meta":{"wy":{"id":7}}}"#))
        #expect(!MusicJSSong.canPersistMusicInfo(#"{"picture":"https://fixture.invalid/a?token=synthetic"}"#))
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: file) }
        try Data(repeating: 32, count: 512 * 1024 + 1).write(to: file)
        #expect(throws: MusicJSError.self) { try MusicJSSourceStore.readScript(file) }
    }

    @Test("a ready announcement cannot hide a later evaluation error")
    func earlyInitializationThenThrowIsRejected() async {
        await #expect(throws: MusicJSError.self) {
            try await MusicJSRuntime.load(script: script + "\nthrow Error('synthetic trailing failure');")
        }
    }

    @Test("cancellation closes a runtime rather than preserving its pending callbacks")
    func cancelledRuntimeIsUnusable() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MusicJSFixtureURLProtocol.self]
        let hanging = script.replacingOccurrences(of: "if (action === 'search')", with:
            "if (action === 'search') return new Promise((resolve, reject) => lx.request('https://fixture.invalid/stall', {}, (err) => err ? reject(err) : resolve([]))); if (false)")
        let runtime = try await MusicJSRuntime.load(script: hanging, networkConfiguration: config)
        defer { runtime.close() }
        let pending = Task { try await runtime.invoke(action: "search", provider: "wy", infoJSON: "{}") }
        for _ in 0..<100 {
            if runtime.activeHTTPCount > 0 { break }
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(runtime.activeHTTPCount == 1)
        pending.cancel()
        _ = try? await pending.value
        #expect(!runtime.isUsable)
        #expect(runtime.activeHTTPCount == 0)
    }

    @Test("a cancelled store action can reload its closed cached runtime")
    func cancelledCacheCanReload() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("fixture.js")
        let hanging = script.replacingOccurrences(of: "if (action === 'search')", with:
            "if (action === 'search' && info.keyword === 'hang') return new Promise(() => {}); if (action === 'search')")
        try hanging.write(to: file, atomically: true, encoding: .utf8)
        let store = MusicJSSourceStore(directory: root.appendingPathComponent("store"))
        let source = try await store.importFile(file)
        let pending = Task { try await store.search(sourceID: source.id, provider: "wy", query: "hang") }
        try await Task.sleep(for: .milliseconds(200))
        pending.cancel()
        _ = try? await pending.value
        let songs = try await store.search(sourceID: source.id, provider: "wy", query: "Fixture")
        #expect(songs.first?.title == "Fixture Song")
    }

    @Test("same-song fresh URL or headers replace a stale AV item")
    func freshResolutionReplacesPlayback() {
        let old = MediaHubLibraryItem(sourceID: "fixture", siteKey: "wy", videoID: "7", title: "Fixture",
            poster: "", kind: .music, siteName: "Fixture", musicURL: "https://fixture.invalid/old")
        var fresh = old
        fresh.musicURL = "https://fixture.invalid/new"
        #expect(fresh.id == old.id)
        #expect(MusicPlayerView.shouldReplace(current: old, with: fresh, hasError: false))
        fresh = old; fresh.musicHeaders = ["X-Fixture": "synthetic"]
        #expect(MusicPlayerView.shouldReplace(current: old, with: fresh, hasError: false))
        #expect(!MusicPlayerView.shouldReplace(current: old, with: old, hasError: false))
        #expect(MusicPlayerView.shouldReplace(current: old, with: old, hasError: true))
    }

    @Test("custom credential headers never cross origins")
    func redirectCredentials() throws {
        let origin = try #require(URL(string: "https://fixture.invalid/start"))
        var request = URLRequest(url: try #require(URL(string: "https://other.invalid/end")))
        for header in ["Cookie", "Authorization", "X-API-Key", "X-Source-Credential", "Referer", "Origin"] {
            request.setValue("synthetic-only", forHTTPHeaderField: header)
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let redirected = try #require(MusicJSRuntime.redirectedRequest(request, from: origin))
        #expect(redirected.allHTTPHeaderFields?.isEmpty != false)
        #expect(redirected.value(forHTTPHeaderField: "Accept") == nil)
        let sameOrigin = MusicJSRuntime.redirectedRequest(request, from: request.url)
        #expect(sameOrigin?.value(forHTTPHeaderField: "X-API-Key") == "synthetic-only")
        request.httpMethod = "POST"; request.httpBody = Data("synthetic-only".utf8)
        #expect(MusicJSRuntime.redirectedRequest(request, from: origin) == nil)
    }

    @Test("incremental transport rejects oversized bodies even without Content-Length")
    func boundedHTTPTransport() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MusicJSFixtureURLProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var small = URLRequest(url: try #require(URL(string: "https://fixture.invalid/small")))
        small.setValue("synthetic", forHTTPHeaderField: "X-Fixture")
        let response = try await MusicJSHTTPTransport.shared.perform(small, session: session)
        #expect(response.statusCode == 200 && response.body == "{\"code\":200}")
        let large = URLRequest(url: try #require(URL(string: "https://fixture.invalid/large")))
        await #expect(throws: MusicJSError.self) {
            try await MusicJSHTTPTransport.shared.perform(large, session: session)
        }
    }

    @Test("native bridge denies files, private loopback and control headers")
    func nativeBridgeBoundaries() throws {
        for address in ["file:///tmp/key", "http://127.0.0.1:80/config", "http://localhost/", "http://192.168.1.1/", "http://169.254.169.254/"] {
            #expect(!MusicJSRuntime.allowedRemoteURL(try #require(URL(string: address))))
        }
        #expect(MusicJSRuntime.allowedRemoteURL(try #require(URL(string: "https://fixture.invalid/api"))))
        #expect(!MusicJSRuntime.safeHeader("x-readcc-token", "synthetic"))
        #expect(!MusicJSRuntime.safeHeader("Referer", "bad\r\nInjected: true"))
        #expect(MusicJSRuntime.safeHeader("User-Agent", "Offline Fixture"))
    }
}

/// URLProtocol fixture only: no DNS, network, external services or real credentials.
private final class MusicJSFixtureURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url,
              let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]) else { return }
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if url.path == "/stall" { return }
        if url.path == "/large" {
            let chunk = Data(repeating: 120, count: 64 * 1024)
            for _ in 0..<33 { client?.urlProtocol(self, didLoad: chunk) }
        } else {
            let code = request.value(forHTTPHeaderField: "X-Fixture") == "synthetic" ? 200 : 403
            client?.urlProtocol(self, didLoad: Data("{\"code\":\(code)}".utf8))
        }
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
