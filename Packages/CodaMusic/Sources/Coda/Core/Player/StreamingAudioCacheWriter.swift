#if os(iOS)
import Foundation

@MainActor
final class StreamingAudioCacheWriter {
    private nonisolated let file: StreamingAudioCacheFile

    private init(file: StreamingAudioCacheFile) { self.file = file }

    static func make(url: URL, track: Track, requestedQuality: String, servedQuality: String?,
                     source: AudioCacheSource, servedBitrate: Int? = nil,
                     scope: String?) async -> StreamingAudioCacheWriter? {
        let cache = AudioCache.shared
        let limit = await SettingsManager.shared.effectiveAudioCacheSizeMB()
        guard SettingsManager.shared.enableAudioCache, limit > 0 else { return nil }
        do {
            // The response MIME type supplies an extension for opaque CDN URLs.
            let ext = CachingAudioResourceLoader.fileExtension(for: url, contentType: nil) ?? "audio"
            let session = try await cache.beginWrite(trackID: track.id, requestedQuality: requestedQuality,
                servedQuality: servedQuality, source: source, servedBitrate: servedBitrate,
                fileExtension: ext, maximumSizeMB: limit)
            do {
                let file = try StreamingAudioCacheFile(fileURL: session.partialFileURL,
                    maximumBytes: Int64(limit) * 1_000_000) { result in
                    Task { @MainActor in
                        do {
                            let completed = try result.get()
                            guard SettingsManager.shared.enableAudioCache,
                                  let ext = fileExtension(url: url, contentType: completed.contentType) else {
                                try? await cache.discard(session)
                                return
                            }
                            switch try await cache.commitAndRetain(session, byteCount: completed.byteCount,
                                contentType: completed.contentType, fileExtension: ext) {
                            case .retained(_, let lease):
                                try? await cache.release(lease)
                                await QueuePrefetcher.keepPlaybackData(track: track, scope: scope)
                            case .deferredDiscard, .rejectedForCurrentLimit:
                                try? await cache.discard(session)
                            }
                        } catch {
                            try? await cache.discard(session)
                        }
                    }
                }
                return StreamingAudioCacheWriter(file: file)
            } catch {
                try? await cache.discard(session)
                return nil
            }
        } catch {
            return nil
        }
    }

    private static func fileExtension(url: URL, contentType: String?) -> String? {
        if CachingAudioResourceLoader.resourceContentType(for: url.pathExtension) != nil {
            return url.pathExtension.lowercased()
        }
        return CachingAudioResourceLoader.fileExtension(for: URL(fileURLWithPath: "/audio"), contentType: contentType)
    }

    nonisolated func receive(_ chunk: HTTPAudioDataChunk) { file.receive(chunk) }
    func cancel() { file.cancel() }
    deinit { file.cancel() }
}
#endif
