import AVFoundation
import KSPlayer
import Testing
@testable import yuedu_app

/// Run on a real iOS Simulator/device. A passing AV fallback cannot satisfy these tests.
@Suite("Readcc native KSPlayer playback", .serialized)
@MainActor
struct NativeKSVideoKernelTests {
    private func waitUntil(_ predicate: () -> Bool) async throws -> Bool {
        for _ in 0..<300 {
            if predicate() { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return predicate()
    }

    @Test("headers reach FFmpeg and CRLF injection is refused")
    func headerOptions() {
        let options = NativeKSVideoKernel.options(headers: [
            "User-Agent": "Readcc Fixture", "Referer": "https://fixture.invalid/",
            "X-Injected": "unsafe\r\nOther: header", "Bad Header": "discard",
            "Bad:Name": "discard", "Bad\nName": "discard", "": "discard"
        ])
        let raw = options.formatContextOptions["headers"] as? String ?? ""
        #expect(raw.contains("User-Agent:Readcc Fixture\r\n"))
        #expect(raw.contains("Referer:https://fixture.invalid/\r\n"))
        #expect(!raw.contains("Other:") && !raw.contains("Bad Header"))
        #expect(!raw.contains("Bad:Name") && !raw.contains("Bad\nName"))
        #expect(!raw.contains("discard"))
        #expect(options.formatContextOptions["rw_timeout"] as? Int == 20_000_000)
    }

    @Test("default production controller uses KSMEPlayer, decodes a frame, seeks and releases the kernel")
    func decodesAndAdvancesWithoutAVFallback() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VideoStill/video-still-landscape.mp4")
        try #require(FileManager.default.fileExists(atPath: fixture.path))
        let defaults = UserDefaults.standard
        let oldResume = defaults.object(forKey: MediaPreferences.videoResumeEnabledKey)
        let oldRate = defaults.object(forKey: MediaPreferences.videoDefaultRateKey)
        defaults.set(false, forKey: MediaPreferences.videoResumeEnabledKey)
        defaults.set(1.0, forKey: MediaPreferences.videoDefaultRateKey)
        defer {
            defaults.set(oldResume, forKey: MediaPreferences.videoResumeEnabledKey)
            defaults.set(oldRate, forKey: MediaPreferences.videoDefaultRateKey)
        }
        let controller = VideoPlaybackController(link: VideoStream(url: fixture, headers: [:]), title: "KS offline fixture")
        defer { controller.close() }
        controller.start()
        let started = try await waitUntil {
            controller.usesKSPlayer && controller.phase == .playing && controller.currentTime > 0.2
        }
        try #require(started, "KSPlayer failed to advance; AV fallback does not count")
        let engine = try #require(controller.ksKernel.engine)
        #expect(controller.player.currentItem == nil)
        #expect(controller.kernelName == "KSPlayer · FFmpeg")
        #expect(abs(controller.duration - 10) < 0.5)
        let decodedFrame = await engine.thumbnailImageAtCurrentTime()
        let frame = try #require(decodedFrame, "No decoded video frame")
        #expect(frame.width > frame.height)
        controller.pause()
        #expect(!engine.isPlaying && controller.phase == .paused)
        controller.seek(to: 4)
        let sought = try await waitUntil { abs(engine.currentPlaybackTime - 4) < 0.25 }
        try #require(sought, "Native seek did not land")
        #expect(!engine.isPlaying)
        controller.setRate(1.5)
        controller.resume()
        let resumed = try await waitUntil { engine.currentPlaybackTime > 4.2 }
        #expect(resumed && engine.playbackRate == 1.5)
        controller.close()
        #expect(controller.ksKernel.engine == nil)
        #expect(controller.player.currentItem == nil)
    }

    @Test("invalid media fails through the production controller instead of reporting success")
    func invalidMediaFails() async throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try Data("not a media file".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let controller = VideoPlaybackController(link: VideoStream(url: file, headers: [:]), title: "Invalid offline fixture")
        defer { controller.close() }
        controller.start()
        let failed = try await waitUntil {
            if case .failed = controller.phase { return true }
            return false
        }
        #expect(failed)
        #expect(!controller.usesKSPlayer, "The invalid media should also exercise the real AV fallback")
        #expect(controller.phase != .playing)
    }
}
