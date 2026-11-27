import Foundation

/// The SEEKTABLE of a FLAC stream, read from the bytes at the start of the file.
///
/// AudioFileStream only *estimates* byte offsets for FLAC, so both stream
/// players used to seek by downloading from byte 0 and decoding everything
/// before the target — several seconds on a lossless file. A seek point is
/// exact (the sample number of a frame and that frame's byte offset), so a
/// seek can start at the nearest point before the target and decode at most
/// one point-interval (typically ~10 s) of audio to land on the exact sample.
struct FLACSeekTable: Equatable, Sendable {
    struct Point: Equatable, Sendable {
        /// First sample of the target frame.
        let sample: UInt64
        /// Byte offset of that frame from the first frame header.
        let offset: UInt64
    }

    enum ParseResult: Equatable {
        /// More header bytes are needed.
        case needMore
        /// Not FLAC, or FLAC without a usable SEEKTABLE.
        case unavailable
        case table(FLACSeekTable)
    }

    /// Byte offset of the first audio frame in the file.
    let audioStart: Int
    let sampleRate: Double
    let points: [Point]

    /// Header bytes beyond this are not kept waiting for a table: a large
    /// embedded picture is not worth holding in memory for a faster seek.
    static let maximumHeaderBytes = 8 * 1024 * 1024

    /// Parses `data`, which must start at byte 0 of the file.
    static func parse(_ data: Data) -> ParseResult {
        let bytes = [UInt8](data.prefix(maximumHeaderBytes))
        var index = 0
        // An ID3v2 tag may precede the stream marker.
        if bytes.count >= 3, bytes[0] == 0x49, bytes[1] == 0x44, bytes[2] == 0x33 {
            guard bytes.count >= 10 else { return .needMore }
            let size = (Int(bytes[6] & 0x7f) << 21) | (Int(bytes[7] & 0x7f) << 14)
                | (Int(bytes[8] & 0x7f) << 7) | Int(bytes[9] & 0x7f)
            let footer = bytes[5] & 0x10 != 0 ? 10 : 0
            index = 10 + size + footer
        }
        guard bytes.count >= index + 4 else {
            return bytes.count >= maximumHeaderBytes ? .unavailable : .needMore
        }
        guard bytes[index] == 0x66, bytes[index + 1] == 0x4c,
              bytes[index + 2] == 0x61, bytes[index + 3] == 0x43 else { return .unavailable }
        index += 4
        var sampleRate: Double?
        var points: [Point]?
        while true {
            guard bytes.count >= index + 4 else {
                return bytes.count >= maximumHeaderBytes ? .unavailable : .needMore
            }
            let header = bytes[index]
            let isLast = header & 0x80 != 0
            let type = header & 0x7f
            let length = (Int(bytes[index + 1]) << 16) | (Int(bytes[index + 2]) << 8) | Int(bytes[index + 3])
            let body = index + 4
            guard type != 127 else { return .unavailable }
            if type == 0 || type == 3 {
                guard bytes.count >= body + length else {
                    return bytes.count >= maximumHeaderBytes ? .unavailable : .needMore
                }
            }
            if type == 0 {
                guard length >= 18 else { return .unavailable }
                let rate = (Int(bytes[body + 10]) << 12) | (Int(bytes[body + 11]) << 4) | Int(bytes[body + 12] >> 4)
                guard rate > 0 else { return .unavailable }
                sampleRate = Double(rate)
            } else if type == 3 {
                points = seekPoints(bytes, from: body, length: length)
            }
            index = body + length
            if isLast { break }
        }
        guard let sampleRate, let points, !points.isEmpty else { return .unavailable }
        return .table(FLACSeekTable(audioStart: index, sampleRate: sampleRate, points: points))
    }

    private static func seekPoints(_ bytes: [UInt8], from start: Int, length: Int) -> [Point] {
        func integer(_ at: Int, _ count: Int) -> UInt64 {
            (0..<count).reduce(UInt64(0)) { ($0 << 8) | UInt64(bytes[at + $1]) }
        }
        var points: [Point] = []
        var cursor = start
        while cursor + 18 <= start + length {
            let sample = integer(cursor, 8)
            let offset = integer(cursor + 8, 8)
            let frameSamples = integer(cursor + 16, 2)
            cursor += 18
            // Placeholder points carry an all-ones sample number.
            guard sample != UInt64.max, frameSamples > 0 else { continue }
            // Points must ascend; a table that does not is not trusted past that point.
            if let last = points.last, sample <= last.sample || offset <= last.offset { break }
            points.append(Point(sample: sample, offset: offset))
        }
        return points
    }

    /// The last point at or before `seconds`, if it is past the start of the stream.
    func point(atOrBefore seconds: TimeInterval) -> Point? {
        guard seconds.isFinite, seconds > 0 else { return nil }
        let target = UInt64(seconds * sampleRate)
        guard let point = points.last(where: { $0.sample <= target }), point.sample > 0 else { return nil }
        return point
    }

    /// Absolute byte offset of `point` in the file.
    func byteOffset(of point: Point) -> Int64 {
        Int64(audioStart) + Int64(point.offset)
    }

    /// Time of the first sample of `point`.
    func time(of point: Point) -> TimeInterval {
        Double(point.sample) / sampleRate
    }
}

/// Collects the first bytes of a stream until its FLAC seek table can be read.
/// Only bytes that arrive in order from byte 0 are kept.
struct FLACSeekTableCollector {
    private var buffer = Data()
    private(set) var result: FLACSeekTable.ParseResult = .needMore

    var table: FLACSeekTable? {
        if case .table(let table) = result { return table }
        return nil
    }

    var isCollecting: Bool { result == .needMore }

    /// Feed the next chunk read from the stream's start.
    mutating func append(_ data: Data) {
        guard isCollecting, !data.isEmpty else { return }
        buffer.append(data)
        result = FLACSeekTable.parse(buffer)
        if !isCollecting { buffer = Data() }
    }

    /// The bytes stopped being contiguous from 0 before a table was found.
    mutating func abandon() {
        guard isCollecting else { return }
        result = .unavailable
        buffer = Data()
    }
}
