import Foundation
import Testing
@testable import CodaCore

private final class DeferredImageProtocol: URLProtocol, @unchecked Sendable {
    final class State: @unchecked Sendable {
        private let lock = NSLock()
        private var pending: DeferredImageProtocol?
        func set(_ value: DeferredImageProtocol?) { lock.lock(); pending = value; lock.unlock() }
        func get() -> DeferredImageProtocol? { lock.lock(); defer { lock.unlock() }; return pending }
    }
    static let state = State()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { Self.state.set(self) }
    override func stopLoading() {}
    func finish(_ data: Data) {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "image/png"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
        Self.state.set(nil)
    }
    func fail() {
        client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
        Self.state.set(nil)
    }
}

private final class ImageCacheClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value = Date()
    func now() -> Date { lock.withLock { value } }
    func advance(_ interval: TimeInterval) { lock.withLock { value.addTimeInterval(interval) } }
}

@Suite("Image cache clearing", .serialized)
struct ImageCacheClearTests {
    private let png = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a5XkAAAAASUVORK5CYII=")!

    private func pendingRequest() async throws -> DeferredImageProtocol {
        for _ in 0..<200 where DeferredImageProtocol.state.get() == nil { try await Task.sleep(for: .milliseconds(5)) }
        return try #require(DeferredImageProtocol.state.get())
    }

    @Test func lateRequestDoesNotRepopulateClearedDiskOrMemory() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coda-image-clear-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeferredImageProtocol.self]
        let cache = ImageCache(directory: root, session: URLSession(configuration: config), offlineArtwork: { _ in nil })
        let url = URL(string: "https://example.test/image.png")!
        let first = Task { await cache.image(for: url) }
        let pending = try await pendingRequest()
        try await cache.clear()
        pending.finish(png)
        #expect(await first.value != nil)
        #expect(cache.cachedImage(for: url) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)

        let second = Task { await cache.image(for: url) }
        try await pendingRequest().finish(png)
        #expect(await second.value != nil)
        #expect(cache.cachedImage(for: url) != nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }

    @Test func offlineArtworkSurvivesClearingOrdinaryImages() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coda-protected-art-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let metadata = OfflineMetadataStore(directory: root.appendingPathComponent("offline"))
        let url = URL(string: "https://example.test/cover.png")!
        try await metadata.saveArtwork(png, url: url, scope: "a")
        let cache = ImageCache(directory: root.appendingPathComponent("images"), offlineArtwork: { url in
            await metadata.artwork(url: url, scope: "a")
        })
        #expect(await cache.image(for: url) != nil)
        try await cache.clear()
        #expect(cache.cachedImage(for: url) == nil)
        #expect(await metadata.artwork(url: url, scope: "a") == png)
        #expect(await cache.image(for: url) != nil)
    }

    @Test func expiredMemoryAndDiskRevalidateButRemainUsableOffline() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coda-image-expiry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeferredImageProtocol.self]
        let clock = ImageCacheClock()
        let session = URLSession(configuration: config)
        let cache = ImageCache(directory: root, session: session, lifetime: 60, now: { clock.now() }, offlineArtwork: { _ in nil })
        let url = URL(string: "https://example.test/expiry.png")!
        let first = Task { await cache.image(for: url) }
        try await pendingRequest().finish(png)
        #expect(await first.value != nil)
        #expect(await cache.image(for: url) != nil)
        #expect(DeferredImageProtocol.state.get() == nil)

        clock.advance(61)
        #expect(cache.cachedImage(for: url) == nil)
        let expired = Task { await cache.image(for: url) }
        let failed = try await pendingRequest()
        #expect(failed.request.cachePolicy == .reloadIgnoringLocalCacheData)
        failed.fail()
        #expect(await expired.value != nil)
        // Failure must not renew freshness and suppress a subsequent retry.
        #expect(cache.cachedImage(for: url) == nil)

        // A new cache instance must also respect the on-disk fetch timestamp.
        let reopened = ImageCache(directory: root, session: session, lifetime: 60, now: { clock.now() }, offlineArtwork: { _ in nil })
        let retry = Task { await reopened.image(for: url) }
        try await pendingRequest().finish(png)
        #expect(await retry.value != nil)
        #expect(reopened.cachedImage(for: url) != nil)
    }

    @Test func diskBudgetEvictsLeastRecentlyUsedCover() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("coda-image-budget-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [DeferredImageProtocol.self]
        let session = URLSession(configuration: config)
        let clock = ImageCacheClock()
        func cache() -> ImageCache {
            ImageCache(directory: root, session: session, maximumDiskBytes: Int64(png.count * 2),
                       now: { clock.now() }, offlineArtwork: { _ in nil })
        }
        let firstCache = cache()
        let urls = ["a", "b", "c"].map { URL(string: "https://example.test/\($0).png")! }
        for url in urls.prefix(2) {
            let task = Task { await firstCache.image(for: url) }
            try await pendingRequest().finish(png)
            #expect(await task.value != nil)
            clock.advance(10)
        }
        let reopened = cache()
        #expect(await reopened.image(for: urls[0]) != nil) // Touch A after B.
        clock.advance(10)
        let third = Task { await reopened.image(for: urls[2]) }
        try await pendingRequest().finish(png)
        #expect(await third.value != nil)
        #expect(try await reopened.usage().bytes <= Int64(png.count * 2))
        let lastCache = cache()
        #expect(await lastCache.image(for: urls[0]) != nil)
        #expect(await lastCache.image(for: urls[2]) != nil)
        let evicted = Task { await lastCache.image(for: urls[1]) }
        try await pendingRequest().finish(png)
        #expect(await evicted.value != nil)
    }
}
