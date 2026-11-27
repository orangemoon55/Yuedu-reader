import CryptoKit
import Foundation
import ImageIO
import Testing
@testable import CodaCore

private final class ThumbnailFailureProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}

private final class ThumbnailUpgradeProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var payload = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Image thumbnails")
struct ImageThumbnailTests {
    private let cover = "https://example.test/large-cover.jpg"

    @Test func resizingReplacesAnExistingSizeAndPreservesOtherParameters() throws {
        let url = try #require("http://example.test/cover.jpg?param=2048y2048&version=2".resizedImageURL(96))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        #expect(components.scheme == "https")
        #expect(components.queryItems?.filter { $0.name == "param" }.map(\.value) == ["96y96"])
        #expect(components.queryItems?.first { $0.name == "version" }?.value == "2")
    }

    @Test func kugouResizingUpdatesResourcePathInsteadOfOnlyAddingNeteaseParameter() throws {
        let url = try #require("https://imge.kugou.com/stdmusic/300/20230910/cover.jpg".resizedImageURL(1536))
        #expect(url.path == "/stdmusic/1536/20230910/cover.jpg")
    }

    @Test func resizingPreservesNeteaseImageProcessingPipeline() throws {
        let pipeline = "imageView=1&thumbnail=800y800&enlarge=1%7CimageView=1&watermark&type=1&image=abc==&dx=0&dy=0%7CimageView=1&thumbnail=140y140&"
        let source = "http://p1.music.126.net/cover.jpg?\(pipeline)"
        let url = try #require(source.resizedImageURL(384))
        #expect(url.absoluteString == "https://p1.music.126.net/cover.jpg?\(pipeline)&param=384y384")
        #expect(url.absoluteString.resizedImageURL(96)?.absoluteString ==
                "https://p1.music.126.net/cover.jpg?\(pipeline)&param=96y96")
    }

    @Test func qqCoverResizingFetchesOriginalResource() throws {
        let url = try #require("https://y.gtimg.cn/music/photo_new/T002R300x300M000fixture.jpg".resizedImageURL(1536))
        #expect(url.path == "/music/photo_new/T002M000fixture.jpg")
    }

    #if os(macOS)
    @Test func qishuiThumbnailsReuseOriginalDiskCacheWithoutChangingTheCDNRequest() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let cover = "https://p3-luna.douyinpic.com/img/cover~tplv-example-resize:960:960.png?token=abc%2B123&size=960"
        let original = try #require(URL(string: cover))
        let row = try #require(cover.resizedImageURL(96))
        let detail = try #require(cover.resizedImageURL(768))
        #expect(row.imageSourceURL.absoluteString == cover)
        #expect(detail.imageSourceURL.absoluteString == cover)
        try seed(largeCover(), url: original, root: root)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThumbnailFailureProtocol.self]
        let cache = ImageCache(directory: root, session: URLSession(configuration: config), offlineArtwork: { _ in nil })

        let rowImage = try #require(await cache.image(for: row))
        let detailImage = try #require(await cache.image(for: detail))
        #expect(try cgImage(rowImage).width == 96)
        #expect(try cgImage(detailImage).width == 768)
        #expect(cache.cachedImage(for: row) === rowImage)
        #expect(cache.cachedImage(for: detail) === detailImage)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }
    #endif

    @Test func offlineThumbnailDoesNotPreventNetworkResolutionUpgrade() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        ThumbnailUpgradeProtocol.payload = try largeCover()
        let thumbnail = try largeCover(width: 160, height: 160)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ThumbnailUpgradeProtocol.self]
        let cache = ImageCache(directory: root, session: URLSession(configuration: configuration), offlineArtwork: { _ in thumbnail })
        let url = try #require(cover.resizedImageURL(1536))
        let image = try #require(await cache.image(for: url))
        #expect(try cgImage(image).width == 1536)
        #expect(try cgImage(#require(cache.cachedImage(for: url))).width == 1536)
    }

    @Test(arguments: [false, true])
    func originalArtworkIsDecodedAtTheRequestedSize(fromDisk: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try largeCover()
        let url = try #require(cover.resizedImageURL(96))
        if fromDisk { try seed(data, url: url, root: root) }
        let cache = ImageCache(directory: root, offlineArtwork: { _ in data })

        let image = try #require(await cache.image(for: url))
        let pixels = try cgImage(image)
        #expect(pixels.width == 96 && pixels.height == 48)
        #expect(pixels.bytesPerRow * pixels.height <= 96 * 48 * 8)
        #expect(try cgImage(#require(cache.cachedImage(for: url))).width == 96)

        // A row thumbnail must not replace the larger detail rendition.
        let detailURL = try #require(cover.resizedImageURL(768))
        let detail = try #require(await cache.image(for: detailURL))
        #expect(try cgImage(detail).width == 768)
        #expect(try cgImage(#require(cache.cachedImage(for: url))).width == 96)
    }

    @Test(arguments: [false, true])
    func largerFallbackIsBoundedWithoutBeingCachedAsAnExactAnswer(warmMemory: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let largeURL = try #require(cover.resizedImageURL(768))
        try seed(largeCover(), url: largeURL, root: root)
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ThumbnailFailureProtocol.self]
        let cache = ImageCache(directory: root, session: URLSession(configuration: config), offlineArtwork: { _ in nil })
        if warmMemory { _ = await cache.image(for: largeURL) }
        let smallURL = try #require(cover.resizedImageURL(96))
        let image = try #require(await cache.image(for: smallURL, onCachedImage: { preview in
            #expect(preview.size.width == 96 && preview.size.height == 48)
        }))
        #expect(try cgImage(image).width == 96)
        #expect(cache.cachedImage(for: smallURL) == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).count == 1)
    }

    @Test func concurrentColdDiskLoadsShareDecodedPixels() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try #require(cover.resizedImageURL(96))
        try seed(largeCover(), url: url, root: root)
        let cache = ImageCache(directory: root, offlineArtwork: { _ in nil })
        let images = await withTaskGroup(of: PlatformImage?.self) { group in
            for _ in 0..<16 {
                group.addTask { await cache.image(for: url, onCachedImage: { _ in }) }
            }
            var images: [PlatformImage] = []
            for await image in group { if let image { images.append(image) } }
            return images
        }
        #expect(images.count == 16)
        let first = try #require(images.first)
        // Sharing HTTP alone is insufficient: simultaneous disk hits must not
        // allocate and decode a separate bitmap for each card or recycled row.
        #expect(images.allSatisfy { $0 === first })
        #expect(try cgImage(first).width == 96)
    }

    @Test func smallOriginalIsNotUpscaled() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let data = try largeCover(width: 32, height: 16)
        let cache = ImageCache(directory: root, offlineArtwork: { _ in data })
        let url = try #require(cover.resizedImageURL(96))
        let image = try #require(await cache.image(for: url))
        #expect(try cgImage(image).width == 32)
    }

    private func largeCover(width: Int = 2_048, height: Int = 1_024) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, "public.jpeg" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, try #require(context.makeImage()), nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func seed(_ data: Data, url: URL, root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let key = Insecure.MD5.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
        try data.write(to: root.appendingPathComponent(key))
    }

    private func cgImage(_ image: PlatformImage) throws -> CGImage {
        #if os(macOS)
        return try #require(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        #else
        return try #require(image.cgImage)
        #endif
    }
}
