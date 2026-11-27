import CryptoKit
import Foundation
import ImageIO
import SwiftUI

/// Two-tier (memory + disk) image cache with in-flight request coalescing.
actor ImageCache {
    static let shared = ImageCache()
    typealias CachedImageHandler = @MainActor @Sendable (PlatformImage) -> Void

    private final class Entry {
        let image: PlatformImage
        let fetchedAt: Date
        init(_ image: PlatformImage, fetchedAt: Date) { self.image = image; self.fetchedAt = fetchedAt }
    }
    private nonisolated(unsafe) let memory = NSCache<NSString, Entry>()
    private nonisolated let lifetime: TimeInterval
    private let maximumDiskBytes: Int64
    private nonisolated let now: @Sendable () -> Date
    private var diskBytes: Int64?
    nonisolated let directory: URL
    private let session: URLSession
    private let offlineArtwork: @Sendable (URL) async -> Data?
    private var generation: UInt64 = 0
    private struct Request {
        let generation: UInt64
        let task: Task<PlatformImage?, Never>
        var preview: PlatformImage?
    }
    private var inflight: [String: Request] = [:]

    init(directory: URL = CodaPaths.imageCache, session: URLSession = .shared,
         lifetime: TimeInterval = 30 * 86_400, maximumDiskBytes: Int64 = 256 * 1_024 * 1_024,
         now: @escaping @Sendable () -> Date = { Date() },
         offlineArtwork: @escaping @Sendable (URL) async -> Data? = { await ImageCache.loadOfflineArtwork(for: $0) }) {
        self.directory = directory
        self.session = session
        self.offlineArtwork = offlineArtwork
        self.lifetime = lifetime
        self.maximumDiskBytes = max(0, maximumDiskBytes)
        self.now = now
        #if os(macOS)
        // Small decoded covers for a large playlist can fit within the byte
        // budget; avoid evicting them after scrolling only a few hundred songs.
        memory.countLimit = 2_000
        #else
        memory.countLimit = 300
        #endif
        memory.totalCostLimit = 64 * 1024 * 1024
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func loadOfflineArtwork(for url: URL) async -> Data? {
        guard let scope = await MainActor.run(body: { AccountStore.shared.offlineScope }) else { return nil }
        return await OfflineMetadataStore.shared.artwork(url: url, scope: scope)
    }

    /// Surface local pixels before waiting for a larger version. The returned
    /// image still prefers the requested resolution, including after reconnect.
    func image(for url: URL, onCachedImage: CachedImageHandler? = nil) async -> PlatformImage? {
        if let cached = cachedImage(for: url) { return cached }
        guard !Task.isCancelled else { return nil }
        let key = url.absoluteString
        let sourceURL = url.imageSourceURL
        let requestGeneration = generation
        if let existing = inflight[key], existing.generation == requestGeneration {
            if let onCachedImage, let preview = existing.preview { await onCachedImage(preview) }
            return await existing.task.value
        }
        // Register the complete load before its first actor hop. Recycled rows
        // requesting the same cover share disk I/O and decoding as well as HTTP.
        let task = Task<PlatformImage?, Never> { [self] in
            if diskBytes == nil { try? trimDisk() }
            let resident = memory.object(forKey: url.absoluteString as NSString)
            let diskKey = Self.cacheKey(for: sourceURL)
            let exact = diskImage(for: diskKey, requestedURL: url)
            let fileURL = directory.appendingPathComponent(diskKey)
            let fetchedAt = (try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let exact, let fetchedAt, isFresh(fetchedAt) {
                touch(fileURL)
                store(exact, url: url, fetchedAt: fetchedAt, generation: requestGeneration)
                return exact
            }
            // Probe other sizes once per load; a failed network request can
            // reuse this decoded preview instead of repeating the disk probes.
            let preview = resident?.image ?? exact ?? cachedVariant(for: url)
            if inflight[key]?.generation == requestGeneration { inflight[key]?.preview = preview }
            if let onCachedImage, let preview { await onCachedImage(preview) }
            let offline = await offlineArtwork(sourceURL).flatMap { Self.decode($0, for: url) }
            if exact == nil, resident == nil, let offline {
                if Self.thumbnailLimit(for: url).map({ Self.longestPixelDimension(offline) >= $0 }) ?? true {
                    store(offline, url: url, fetchedAt: now(), generation: requestGeneration)
                    return offline
                }
                if inflight[key]?.generation == requestGeneration { inflight[key]?.preview = offline }
                if let onCachedImage { await onCachedImage(offline) }
                // Offline art may be a small retained thumbnail. Keep it as
                // fallback while fetching the actual requested CDN resource.
            }
            let stale = resident?.image ?? exact ?? offline ?? preview
            var request = URLRequest(url: sourceURL)
            if stale != nil { request.cachePolicy = .reloadIgnoringLocalCacheData }
            guard let (data, response) = try? await session.data(for: request),
                  (response as? HTTPURLResponse).map({ (200..<300).contains($0.statusCode) }) ?? true,
                  let image = Self.decode(data, for: url) else { return stale }
            if generation == requestGeneration {
                write(data, to: fileURL)
                store(image, url: url, fetchedAt: now(), generation: requestGeneration)
            }
            return image
        }
        inflight[key] = Request(generation: requestGeneration, task: task, preview: nil)
        let result = await task.value
        if inflight[key]?.generation == requestGeneration { inflight[key] = nil }
        // Smaller fallbacks must not prevent a later resolution upgrade.
        return result
    }

    private nonisolated func isFresh(_ fetchedAt: Date) -> Bool {
        let age = now().timeIntervalSince(fetchedAt)
        return age >= 0 && age < lifetime
    }

    private func store(_ image: PlatformImage, url: URL, fetchedAt: Date, generation: UInt64) {
        guard self.generation == generation else { return }
        memory.setObject(Entry(image, fetchedAt: fetchedAt), forKey: url.absoluteString as NSString,
                         cost: Int(image.size.width * image.size.height * 4))
    }

    private func touch(_ url: URL) {
        var values = URLResourceValues()
        values.contentAccessDate = now()
        var url = url
        try? url.setResourceValues(values)
    }

    private func write(_ data: Data, to url: URL) {
        do {
            let oldSize = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.modificationDate: now()], ofItemAtPath: url.path)
            touch(url)
            if let diskBytes { self.diskBytes = diskBytes - Int64(oldSize) + Int64(data.count) }
            if diskBytes.map({ $0 > maximumDiskBytes }) ?? true { try trimDisk() }
        } catch {
            // A failed disk write must not prevent displaying the fetched image.
            diskBytes = nil
        }
    }

    private func trimDisk() throws {
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isRegularFileKey])
        let entries = try files.compactMap { url -> (URL, Int64, Date)? in
            let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentAccessDateKey, .contentModificationDateKey, .isRegularFileKey])
            guard values.isRegularFile == true else { return nil }
            return (url, Int64(values.fileSize ?? 0), values.contentAccessDate ?? values.contentModificationDate ?? .distantPast)
        }
        var bytes = entries.reduce(Int64(0)) { $0 + $1.1 }
        for (url, size, _) in entries.sorted(by: { $0.2 < $1.2 }) where bytes > maximumDiskBytes {
            try FileManager.default.removeItem(at: url)
            bytes -= size
        }
        diskBytes = bytes
    }

    private func diskImage(for key: String, requestedURL: URL) -> PlatformImage? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(key)) else { return nil }
        return Self.decode(data, for: requestedURL)
    }

    private static func longestPixelDimension(_ image: PlatformImage) -> Int {
        #if os(macOS)
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return 0 }
        #else
        guard let pixels = image.cgImage else { return 0 }
        #endif
        return max(pixels.width, pixels.height)
    }

    private static func thumbnailLimit(for url: URL) -> Int? {
        if let limit = url.localImagePixelLimit { return limit }
        guard let value = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "param" })?.value else { return nil }
        let dimensions = value.split(separator: "y", omittingEmptySubsequences: false)
        guard dimensions.count == 2, let width = Int(dimensions[0]), let height = Int(dimensions[1]),
              width > 0, height > 0 else { return nil }
        return max(width, height)
    }

    /// A CDN size hint is not a decode limit: offline artwork and older cache
    /// variants can contain the original cover. Decode thumbnails on this
    /// actor before SwiftUI displays them, with a bounded pixel allocation.
    private static func decode(_ data: Data, for url: URL) -> PlatformImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, [
            kCGImageSourceShouldCache: false,
        ] as CFDictionary) else { return PlatformImage(data: data) }
        // Unbounded covers are decoded here too. `PlatformImage(data:)` defers
        // decoding to the first draw, which lands on the main thread while
        // the page is scrolling.
        var options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        if let limit = thumbnailLimit(for: url) {
            options[kCGImageSourceThumbnailMaxPixelSize] = limit
        } else if let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int {
            options[kCGImageSourceThumbnailMaxPixelSize] = max(width, height)
        } else {
            return PlatformImage(data: data)
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return thumbnailLimit(for: url) == nil ? PlatformImage(data: data) : nil
        }
        return platformImage(image)
    }

    private static func platformImage(_ image: CGImage) -> PlatformImage {
        #if os(macOS)
        return PlatformImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        #else
        return PlatformImage(cgImage: image)
        #endif
    }

    private static func preview(_ image: PlatformImage, for url: URL) -> PlatformImage? {
        guard let limit = thumbnailLimit(for: url) else { return image }
        #if os(macOS)
        guard let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        #else
        guard let pixels = image.cgImage else { return nil }
        #endif
        guard max(pixels.width, pixels.height) > limit else { return image }
        let scale = Double(limit) / Double(max(pixels.width, pixels.height))
        let width = max(1, Int(Double(pixels.width) * scale))
        let height = max(1, Int(Double(pixels.height) * scale))
        guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(pixels, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let thumbnail = context.makeImage() else { return nil }
        #if os(macOS)
        return platformImage(thumbnail)
        #else
        return PlatformImage(cgImage: thumbnail, scale: 1, orientation: image.imageOrientation)
        #endif
    }

    private func cachedVariant(for url: URL) -> PlatformImage? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "param" }) == true else { return nil }
        let otherItems = components.queryItems?.filter { $0.name != "param" } ?? []
        // Sizes used by app surfaces, including existing on-disk caches from
        // before cross-size fallback. Probe largest first without a disk scan.
        let sizes = [1024, 768, 640, 512, 384, 256, 160, 128, 120, 96, 80, 64, 48]
        for size in [nil] + sizes.map(Optional.some) {
            components.queryItems = otherItems + (size.map { [URLQueryItem(name: "param", value: "\($0)y\($0)")] } ?? [])
            if components.queryItems?.isEmpty == true { components.queryItems = nil }
            guard let candidate = components.url, candidate != url else { continue }
            if let entry = memory.object(forKey: candidate.absoluteString as NSString),
               let preview = Self.preview(entry.image, for: url) { return preview }
            let key = Self.cacheKey(for: candidate)
            if let image = diskImage(for: key, requestedURL: url) { return image }
        }
        return nil
    }

    func usage() throws -> CacheUsage {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
        let bytes = files.reduce(Int64(0)) { total, file in
            total + Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return CacheUsage(bytes: bytes)
    }

    /// Existing views may finish loading their image, but requests started
    /// before the clear cannot refill either disk or memory caches afterwards.
    func clear() throws {
        generation += 1
        diskBytes = 0
        memory.removeAllObjects()
        if FileManager.default.fileExists(atPath: directory.path) {
            let info = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard info.isDirectory == true, info.isSymbolicLink != true else { throw OfflineAudioError.invalidResource }
            try FileManager.default.removeItem(at: directory)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    /// Synchronous in-memory lookup — safe off the actor (`NSCache` is
    /// thread-safe). Returns nil unless the image is resident in memory; use
    /// `image(for:)` for disk/network loads.
    nonisolated func cachedImage(for url: URL) -> PlatformImage? {
        // Hashing is only necessary for disk filenames, not hot row lookups.
        guard let entry = memory.object(forKey: url.absoluteString as NSString), isFresh(entry.fetchedAt) else { return nil }
        return entry.image
    }

    private static func cacheKey(for url: URL) -> String {
        let digest = Insecure.MD5.hash(data: Data(url.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Keep pixels bound to their source, even while SwiftUI reuses a view for a
/// different URL or a cancelled request finishes after the next one starts.
struct CachedImageState {
    private(set) var url: URL?
    private var image: PlatformImage?

    init(url: URL? = nil, image: PlatformImage? = nil) {
        self.url = url
        self.image = image
    }

    func image(for url: URL?) -> PlatformImage? {
        guard let url, self.url == url else { return nil }
        return image
    }

    mutating func finish(_ image: PlatformImage?, for url: URL) {
        guard self.url == url else { return }
        self.image = image
    }
}

/// AsyncImage replacement backed by `ImageCache`, with a crossfade reveal.
struct CachedAsyncImage<Placeholder: View>: View {
    let url: URL?
    var animated: Bool = true
    @ViewBuilder var placeholder: () -> Placeholder

    @State private var imageState: CachedImageState

    init(url: URL?, animated: Bool = true,
         @ViewBuilder placeholder: @escaping () -> Placeholder) {
        self.url = url
        self.animated = animated
        self.placeholder = placeholder
        // Seed from the in-memory cache so a re-created view (e.g. the iOS 26
        // tab-bar accessory rebuilt on a tab switch, #46) shows already-decoded
        // artwork immediately instead of flashing the placeholder.
        let seeded = url.flatMap { ImageCache.shared.cachedImage(for: $0) }
        _imageState = State(initialValue: CachedImageState(url: url, image: seeded))
    }

    var body: some View {
        // A reused row keeps its State. Resolve an already decoded cover
        // synchronously when the URL changes, before the new task runs.
        let image = imageState.image(for: url) ?? url.flatMap({ ImageCache.shared.cachedImage(for: $0) })
        ZStack {
            // Without a crossfade the placeholder is fully covered once the
            // cover is present; skip drawing it under every scrolling row.
            if image == nil || animated {
                placeholder()
            }
            if let image {
                Image(platformImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .transition(animated ? .opacity.animation(.easeIn(duration: 0.22)) : .identity)
            }
        }
        .task(id: url) {
            guard let url else {
                imageState = CachedImageState()
                return
            }
            // Synchronous memory hit first — no actor hop, no placeholder frame.
            let memoryHit = ImageCache.shared.cachedImage(for: url)
            if imageState.url != url || memoryHit != nil {
                imageState = CachedImageState(url: url, image: memoryHit)
            }
            guard memoryHit == nil else { return }
            let cached = await ImageCache.shared.image(for: url) { preview in
                guard !Task.isCancelled else { return }
                imageState.finish(preview, for: url)
            }
            guard !Task.isCancelled, let cached else { return }
            imageState.finish(cached, for: url)
        }
    }
}

extension CachedAsyncImage where Placeholder == AnyView {
    /// Default placeholder: a quiet neutral fill with a music note.
    init(url: URL?, animated: Bool = true) {
        self.init(url: url, animated: animated) {
            AnyView(
                ZStack {
                    Rectangle().fill(.quaternary.opacity(0.5))
                    Image(systemName: "music.note")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.quaternary)
                }
            )
        }
    }
}
