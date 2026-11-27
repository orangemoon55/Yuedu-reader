import AVFoundation
import Foundation
import Testing
@testable import CodaCore

@Suite("Mac lyrics engine synchronization", .serialized)
struct MacLyricsEngineSyncTests {
    @Test(arguments: ["flac", "aac"])
    func seekMatchesTheActualDecodedSourceFrames(format: String) throws {
        // A ramp encodes source position in every sample, so a guessed byte
        // offset cannot pass by returning the right duration but the wrong audio.
        let source = try Fixtures.writeRampCAF(seconds: 6, name: "lyrics-seek-ramp")
        let encoded: URL
        if format == "flac" {
            encoded = try ProgressiveLoaderFLACTests.flacFixture(from: source, name: "lyrics-seek-ramp")
        } else {
            encoded = try Fixtures.writeSineADTS(seconds: 6, name: "lyrics-seek-aac")
        }
        let server = try TestHTTPServer(serving: Data(contentsOf: encoded))
        defer { server.stop() }
        let queue = DispatchQueue(label: "lyrics.seek.test")
        let output = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        let loader = ProgressiveLoader(remoteURL: server.url, formatHint: format,
            partURL: Fixtures.dir.appendingPathComponent("lyrics-seek-\(format).part"), output: output, queue: queue)
        final class Capture: @unchecked Sendable {
            var samples: [Float] = []
            var error: Error?
        }
        let capture = Capture()
        let done = DispatchSemaphore(value: 0)
        loader.onBuffer = { buffer in
            capture.samples.append(contentsOf: UnsafeBufferPointer(
                start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
        }
        loader.onCompleted = { done.signal() }
        loader.onError = { capture.error = $0; done.signal() }
        defer { loader.cancel() }
        func waitForDecode() throws -> [Float] {
            try #require(done.wait(timeout: .now() + 15) == .success, "decoder did not finish")
            return try queue.sync {
                if let error = capture.error { throw error }
                return capture.samples
            }
        }
        loader.start()
        let baseline = try waitForDecode()
        // The converter can omit its partial tail block; the test pins the
        // actual samples, rather than assuming a codec-specific tail length.
        try #require(baseline.count > 5 * 44_100)
        if format == "flac" {
            #expect(abs(baseline[44_100] - Float(44_101) * 1e-7) < 0.000001)
        }
        for target in [2.317, 0, 4.91] {
            queue.sync { capture.samples = []; capture.error = nil }
            loader.seek(to: target)
            let actual = try waitForDecode()
            let targetFrame = Int((target * output.sampleRate).rounded())
            let expected = Array(baseline.dropFirst(targetFrame))
            #expect(actual.count == expected.count, "target \(target): wrong frame count")
            let error = zip(actual, expected).map { abs($0 - $1) }.max() ?? .infinity
            #expect(error < 0.000001, "target \(target): PCM content is off its reported timeline: \(error)")
        }
        queue.sync { capture.samples = []; capture.error = nil }
        // Older requests must never leak buffers or completion into the last seek.
        loader.seek(to: 4)
        loader.seek(to: 1.25)
        let actual = try waitForDecode()
        let expected = Array(baseline.dropFirst(55_125))
        #expect(actual.count == expected.count)
        #expect(zip(actual, expected).allSatisfy { abs($0 - $1) < 0.000001 })
    }

    @Test func renderedSegmentClockUsesSourceRateRatherThanUnity() {
        let points: [OfflineTransitionRenderer.TimelinePoint] = [
            .init(offset: 0, source: 10), .init(offset: 2, source: 11.6),
            .init(offset: 4, source: 14)
        ]
        #expect(abs(TransitionSegment.sourceRate(in: points, at: 1) - 0.8) < 0.000001)
        #expect(abs(TransitionSegment.sourceRate(in: points, at: 2) - 1.2) < 0.000001)
        #expect(TransitionSegment.sourceRate(in: points, at: 4) == 0)
        #expect(TransitionSegment.sourceRate(in: [], at: 0) == 0)
    }
}
