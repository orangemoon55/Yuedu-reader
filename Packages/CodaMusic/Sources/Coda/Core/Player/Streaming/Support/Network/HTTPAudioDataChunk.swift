#if os(iOS) || CODA_STREAMING_TESTS
// Kumone addition (MIT): observe original HTTP bytes before MP4 restructuring
// or decoding, without issuing requests or changing the playback timeline.
import Foundation

public struct HTTPAudioDataChunk: Sendable {
    public let data: Data
    public let offset: Int64
    public let totalLength: Int64
    public let contentType: String?
    public let validator: String?

    public init(data: Data, offset: Int64, totalLength: Int64,
                contentType: String? = nil, validator: String? = nil) {
        self.data = data
        self.offset = offset
        self.totalLength = totalLength
        self.contentType = contentType
        self.validator = validator
    }
}

/// Per-request offsets remain independent when seeks cancel and replace a
/// request. Only identity-encoded, bounded 200/206 audio bodies are cacheable.
struct HTTPAudioDataRange {
    private var invalid = false
    private var offset: Int64
    private let end: Int64
    private let totalLength: Int64
    private let contentType: String?
    private let validator: String?

    init?(response: HTTPURLResponse) {
        let encoding = response.value(forHTTPHeaderField: "Content-Encoding")?.lowercased()
        guard encoding == nil || encoding == "identity" else { return nil }
        let type = response.mimeType?.lowercased()
        guard type?.hasPrefix("text/") != true, type != "application/json" else { return nil }
        switch response.statusCode {
        case 200:
            guard response.value(forHTTPHeaderField: "Content-Range") == nil,
                  response.expectedContentLength > 0 else { return nil }
            offset = 0
            end = response.expectedContentLength
            totalLength = end
        case 206:
            guard let header = response.value(forHTTPHeaderField: "Content-Range"),
                  header.lowercased().hasPrefix("bytes ") else { return nil }
            let parts = header.dropFirst(6).split(separator: "/", omittingEmptySubsequences: false)
            guard parts.count == 2, let total = Int64(parts[1]), total > 0 else { return nil }
            let bounds = parts[0].split(separator: "-", omittingEmptySubsequences: false)
            guard bounds.count == 2, let start = Int64(bounds[0]), let last = Int64(bounds[1]),
                  start >= 0, last >= start, last < total,
                  response.expectedContentLength <= 0 || response.expectedContentLength == last - start + 1 else { return nil }
            offset = start
            end = last + 1
            totalLength = total
        default:
            return nil
        }
        contentType = type
        validator = response.value(forHTTPHeaderField: "ETag")
            ?? response.value(forHTTPHeaderField: "Last-Modified")
    }

    mutating func consume(_ data: Data) -> HTTPAudioDataChunk? {
        guard !invalid else { return nil }
        guard !data.isEmpty, Int64(data.count) <= end - offset else {
            invalid = true
            return nil
        }
        let chunk = HTTPAudioDataChunk(data: data, offset: offset, totalLength: totalLength,
                                      contentType: contentType, validator: validator)
        offset += Int64(data.count)
        return chunk
    }
}
#endif
