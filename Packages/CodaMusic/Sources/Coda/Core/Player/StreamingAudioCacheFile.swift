#if os(iOS) || CODA_STREAMING_TESTS
import Foundation

/// Receives only bytes already fetched for playback. Disk work stays off both
/// the decoder and the audio render thread. Offsets refer to the original file,
/// including the MP4 atoms before the streaming parser rearranges them.
final class StreamingAudioCacheFile: @unchecked Sendable {
    struct Completed: Sendable {
        let byteCount: Int64
        let contentType: String?
    }

    private let queue = DispatchQueue(label: "coda.streaming-cache.write", qos: .utility)
    private let handle: FileHandle
    private let maximumBytes: Int64
    private let completion: @Sendable (Result<Completed, Error>) -> Void
    private var ranges = ByteRangePlanner()
    private var totalLength: Int64?
    private var validator: String?
    private var contentType: String?
    private var finished = false

    init(fileURL: URL, maximumBytes: Int64,
         completion: @escaping @Sendable (Result<Completed, Error>) -> Void) throws {
        handle = try FileHandle(forUpdating: fileURL)
        self.maximumBytes = maximumBytes
        self.completion = completion
    }

    func receive(_ chunk: HTTPAudioDataChunk) {
        queue.async { self.write(chunk) }
    }

    func cancel() {
        queue.async { self.finish(.failure(CancellationError())) }
    }

    private func write(_ chunk: HTTPAudioDataChunk) {
        guard !finished else { return }
        guard chunk.totalLength > 0, chunk.totalLength <= maximumBytes,
              chunk.offset >= 0, chunk.offset <= chunk.totalLength,
              !chunk.data.isEmpty, Int64(chunk.data.count) <= chunk.totalLength - chunk.offset,
              chunk.contentType?.hasPrefix("text/") != true,
              chunk.contentType != "application/json" else {
            finish(.failure(URLError(.cannotDecodeContentData)))
            return
        }
        if let totalLength {
            guard totalLength == chunk.totalLength, validator == chunk.validator else {
                finish(.failure(URLError(.resourceUnavailable)))
                return
            }
        } else {
            totalLength = chunk.totalLength
            validator = chunk.validator
            contentType = chunk.contentType
        }
        do {
            try handle.seek(toOffset: UInt64(chunk.offset))
            try handle.write(contentsOf: chunk.data)
            ranges.recordCached(chunk.offset..<(chunk.offset + Int64(chunk.data.count)))
            if ranges.isComplete(contentLength: chunk.totalLength) {
                try handle.synchronize()
                finish(.success(Completed(byteCount: chunk.totalLength, contentType: contentType)))
            }
        } catch {
            finish(.failure(error))
        }
    }

    private func finish(_ result: Result<Completed, Error>) {
        guard !finished else { return }
        finished = true
        try? handle.close()
        completion(result)
    }
}
#endif
