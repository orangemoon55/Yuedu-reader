import AVFoundation
import Foundation
import Testing
@testable import CodaCore

/// FLAC seeks start at the stream's own seek table instead of byte 0.
///
/// `afconvert` writes FLAC without a SEEKTABLE, so the fixture gets one added
/// here by walking the frame headers — the same table `flac` and QQ's files carry.
@Suite("FLAC seek table", .serialized)
struct FLACSeekTableTests {
    static let sampleRate = 44_100.0
    static let seconds = 30.0

    /// Mono noise from a fixed seed: unlike a sine, a seek that lands on the
    /// wrong sample cannot line up with the reference by accident.
    static let fixture: (flac: URL, reference: [Float]) = {
        let frames = Int(sampleRate * seconds)
        var state: UInt32 = 0x1234_5678
        var samples = [Float](repeating: 0, count: frames)
        for index in 0..<frames {
            state = state &* 1_664_525 &+ 1_013_904_223
            // Quantised to 16 bits so the lossless round trip is exact.
            samples[index] = Float(Int16(truncatingIfNeeded: Int32(state >> 16) - 32768) / 4) / 32768
        }
        let caf = Fixtures.dir.appendingPathComponent("flac-seek-noise.caf")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 1, interleaved: false)!
        try? FileManager.default.removeItem(at: caf)
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                                       AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: true]
        let file = try! AVAudioFile(forWriting: caf, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        samples.withUnsafeBufferPointer { buffer.floatChannelData![0].update(from: $0.baseAddress!, count: frames) }
        try! file.write(from: buffer)
        let plain = try! ProgressiveLoaderFLACTests.flacFixture(from: caf, name: "flac-seek-noise-plain")
        let flac = Fixtures.dir.appendingPathComponent("flac-seek-noise.flac")
        try! addSeekTable(to: Data(contentsOf: plain), everySeconds: 5).write(to: flac)
        return (flac, samples)
    }()

    // MARK: Parsing

    @Test func readsTheTableAndPicksThePointBeforeTheTarget() throws {
        let data = try Data(contentsOf: Self.fixture.flac)
        guard case .table(let table) = FLACSeekTable.parse(data) else {
            Issue.record("no seek table parsed"); return
        }
        #expect(table.sampleRate == Self.sampleRate)
        #expect(table.points.count >= 5)
        let point = try #require(table.point(atOrBefore: 17.3))
        #expect(table.time(of: point) <= 17.3)
        #expect(table.time(of: point) > 17.3 - 6)
        #expect(table.point(atOrBefore: 0.5) == nil, "the first point is byte 0: nothing to gain")

        // Needs the whole header before answering; a stream without one is refused.
        #expect(FLACSeekTable.parse(data.prefix(20)) == .needMore)
        let plain = try Data(contentsOf: Fixtures.dir.appendingPathComponent("flac-seek-noise-plain.flac"))
        #expect(FLACSeekTable.parse(plain) == .unavailable)
        #expect(FLACSeekTable.parse(Data(repeating: 0x41, count: 64)) == .unavailable)
    }

    @Test func collectorOnlyKeepsBytesFromTheStart() throws {
        let data = try Data(contentsOf: Self.fixture.flac)
        var collector = FLACSeekTableCollector()
        for start in stride(from: 0, to: 4096, by: 100) {
            collector.append(data.subdata(in: start..<min(start + 100, data.count)))
        }
        #expect(collector.table != nil)

        var abandoned = FLACSeekTableCollector()
        abandoned.append(data.prefix(10))
        abandoned.abandon()
        abandoned.append(data)
        #expect(abandoned.table == nil)
    }

    // MARK: Streaming seek (macOS ProgressiveLoader)

    /// The seek requests bytes from the table's frame before the target (not
    /// byte 0) and decodes exactly the samples that follow the target.
    @Test func streamSeekStartsAtTheTableAndLandsOnTheExactSample() throws {
        let payload = try Data(contentsOf: Self.fixture.flac)
        let server = try TestHTTPServer(serving: payload, pauseAfterBytes: nil, pauseDuration: 0)  // the server serves one connection at a time
        defer { server.stop() }
        let partURL = Fixtures.dir.appendingPathComponent("flac-seek.part")
        try? FileManager.default.removeItem(at: partURL)
        let output = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 2)!
        let engineQueue = DispatchQueue(label: "flac-seek.engine")
        let loader = ProgressiveLoader(remoteURL: server.url, formatHint: "flac",
                                       partURL: partURL, output: output, queue: engineQueue)
        final class Box: @unchecked Sendable {
            var seeked = false
            var afterSeek: [Float] = []
        }
        let box = Box()
        let firstBuffer = DispatchSemaphore(value: 0)
        let landed = DispatchSemaphore(value: 0)
        loader.onBuffer = { [weak loader] buffer in
            guard box.seeked else {
                loader?.setDownloadSuspended(true)
                firstBuffer.signal()
                return
            }
            let channel = buffer.floatChannelData![0]
            box.afterSeek += (0..<Int(buffer.frameLength)).map { channel[$0] }
            if box.afterSeek.count >= 4096 {
                loader?.setDownloadSuspended(true)
                landed.signal()
            }
        }
        loader.start()
        defer { loader.cancel() }
        #expect(firstBuffer.wait(timeout: .now() + 10) == .success)

        let target = 25.0
        let started = Date()
        engineQueue.sync {
            box.seeked = true
            loader.seek(to: target)
        }
        #expect(landed.wait(timeout: .now() + 10) == .success)
        let elapsed = Date().timeIntervalSince(started)
        #expect(elapsed < 5, "seek took \(elapsed)s")
        guard case .table(let table) = FLACSeekTable.parse(payload),
              let point = table.point(atOrBefore: target) else { Issue.record("fixture has no table"); return }
        #expect(loader.requestOffsetForTesting == table.byteOffset(of: point),
                "the seek should request from the seek point, not byte 0")

        engineQueue.sync {}
        let start = Int(target * Self.sampleRate)
        let expected = Array(Self.fixture.reference[start..<(start + 2048)])
        let actual = Array(box.afterSeek.prefix(2048))
        let worst = zip(expected, actual).map { abs($0 - $1) }.max() ?? 1
        #expect(actual.count == 2048)
        #expect(worst < 1e-4, "post-seek audio differs from the source by \(worst)")
    }

    // MARK: Fixture helper

    /// Inserts a SEEKTABLE after STREAMINFO with a point at the first frame
    /// at or after every `everySeconds`. Frames are found by their sync code
    /// and confirmed by the header CRC-8.
    static func addSeekTable(to file: Data, everySeconds: Double) throws -> Data {
        let bytes = [UInt8](file)
        precondition(bytes.starts(with: Array("fLaC".utf8)))
        var index = 4
        var streamInfoEnd = 0
        var lastFlagIndex = 0
        while true {
            let header = bytes[index]
            let length = (Int(bytes[index + 1]) << 16) | (Int(bytes[index + 2]) << 8) | Int(bytes[index + 3])
            if header & 0x7f == 0 { streamInfoEnd = index + 4 + length }
            lastFlagIndex = index
            index += 4 + length
            if header & 0x80 != 0 { break }
        }
        let audioStart = index
        let info = bytes[8 + 10..<8 + 18].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let rate = Double(info >> 44)
        let blockSize = (Int(bytes[8]) << 8) | Int(bytes[9])

        var frames: [(sample: UInt64, offset: Int)] = []
        var cursor = audioStart
        while cursor + 16 < bytes.count {
            if bytes[cursor] == 0xff, bytes[cursor + 1] == 0xf8,
               let number = frameNumber(bytes, at: cursor) {
                frames.append((UInt64(number) * UInt64(blockSize), cursor - audioStart))
            }
            cursor += 1
        }
        var points: [(UInt64, Int)] = []
        var next = 0.0
        for frame in frames where Double(frame.sample) / rate >= next {
            points.append((frame.sample, frame.offset))
            next += everySeconds
        }
        var table: [UInt8] = []
        func put(_ value: UInt64, _ count: Int) {
            for shift in stride(from: (count - 1) * 8, through: 0, by: -8) { table.append(UInt8((value >> UInt64(shift)) & 0xff)) }
        }
        for (sample, offset) in points {
            put(sample, 8); put(UInt64(offset), 8); put(UInt64(blockSize), 2)
        }
        var out = Array(bytes[0..<streamInfoEnd])
        out[4] &= 0x7f
        // The new block is last only if STREAMINFO was.
        let isLast: UInt8 = lastFlagIndex == 4 ? 0x80 : 0
        out += [isLast | 3, UInt8(table.count >> 16), UInt8((table.count >> 8) & 0xff), UInt8(table.count & 0xff)] + table
        out += bytes[streamInfoEnd..<bytes.count]
        return Data(out)
    }

    /// The frame number of a fixed-blocksize frame header at `at`, if its CRC-8 checks out.
    private static func frameNumber(_ bytes: [UInt8], at start: Int) -> Int? {
        var cursor = start + 4
        let first = bytes[cursor]
        var count = 0
        var value: Int
        if first & 0x80 == 0 { value = Int(first) }
        else if first & 0xe0 == 0xc0 { value = Int(first & 0x1f); count = 1 }
        else if first & 0xf0 == 0xe0 { value = Int(first & 0x0f); count = 2 }
        else if first & 0xf8 == 0xf0 { value = Int(first & 0x07); count = 3 }
        else { return nil }
        cursor += 1
        for _ in 0..<count {
            guard bytes[cursor] & 0xc0 == 0x80 else { return nil }
            value = (value << 6) | Int(bytes[cursor] & 0x3f)
            cursor += 1
        }
        let blockCode = bytes[start + 2] >> 4
        if blockCode == 6 { cursor += 1 } else if blockCode == 7 { cursor += 2 }
        let rateCode = bytes[start + 2] & 0x0f
        if rateCode == 12 { cursor += 1 } else if rateCode == 13 || rateCode == 14 { cursor += 2 }
        var crc: UInt8 = 0
        for byte in bytes[start..<cursor] {
            crc ^= byte
            for _ in 0..<8 { crc = crc & 0x80 != 0 ? (crc << 1) ^ 0x07 : crc << 1 }
        }
        return crc == bytes[cursor] ? value : nil
    }
}
