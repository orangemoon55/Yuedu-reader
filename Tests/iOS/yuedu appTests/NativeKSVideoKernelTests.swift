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
            "X-Injected": "unsafe\r\nOther: header", "X-Bare-CR": "bare\r", "X-Bare-LF": "bare\n",
            "Bad Header": "discard", "Bad:Name": "discard", "Bad\nName": "discard", "": "discard"
        ])
        let raw = options.formatContextOptions["headers"] as? String ?? ""
        #expect(raw.contains("User-Agent:Readcc Fixture\r\n"))
        #expect(raw.contains("Referer:https://fixture.invalid/\r\n"))
        #expect(!raw.contains("Other:") && !raw.contains("Bad Header"))
        #expect(!raw.contains("bare\r") && !raw.contains("bare\n"))
        #expect(!raw.contains("Bad:Name") && !raw.contains("Bad\nName"))
        #expect(!raw.contains("discard"))
        #expect(options.formatContextOptions["rw_timeout"] as? Int == 20_000_000)
    }

    @Test("automatic production controller uses KSMEPlayer, decodes a frame, seeks and releases the kernel")
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
        let controller = VideoPlaybackController(link: VideoStream(url: fixture, headers: [:]),
                                                 title: "KS offline fixture", prefersKSPlayer: true)
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
        let controller = VideoPlaybackController(link: VideoStream(url: file, headers: [:]),
                                                 title: "Invalid offline fixture", prefersKSPlayer: true)
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

    @Test("adapter drops retired engine events, delivers terminal once and clears callbacks on stop")
    func adapterTerminalLifecycle() throws {
        // Delegate-contract test only: engines are real but intentionally not prepared/decoded.
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VideoStill/video-still-landscape.mp4")
        let kernel = NativeKSVideoKernel()
        defer { kernel.stop() }
        let stream = VideoStream(url: fixture, headers: [:])
        kernel.open(stream, prepareImmediately: false)
        let retired = try #require(kernel.engine)
        var finishes = 0
        kernel.onReady = {}
        kernel.onTick = { _, _, _, _ in }
        kernel.onFinish = { _ in finishes += 1 }
        let error = NSError(domain: "Readcc.LifecycleTest", code: 1)
        kernel.finish(player: retired, error: error)
        kernel.finish(player: retired, error: error)
        #expect(finishes == 1)
        kernel.stop()
        #expect(kernel.engine == nil)
        #expect(kernel.onReady == nil && kernel.onTick == nil && kernel.onFinish == nil)
        kernel.open(stream, prepareImmediately: false)
        let current = try #require(kernel.engine)
        kernel.onFinish = { _ in finishes += 1 }
        kernel.finish(player: retired, error: error)
        #expect(finishes == 1)
        kernel.finish(player: current, error: error)
        kernel.finish(player: current, error: error)
        #expect(finishes == 2)
    }

    @Test("queued controller callbacks cannot alter a replacement load or revive close")
    func controllerRetiredCallbacks() throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VideoStill/video-still-landscape.mp4")
        let controller = VideoPlaybackController(link: VideoStream(url: fixture, headers: [:]),
                                                 title: "Lifecycle fixture", prefersKSPlayer: true)
        defer { controller.close() }
        controller.start()
        let oldReady = try #require(controller.ksKernel.onReady)
        let oldFinish = try #require(controller.ksKernel.onFinish)
        controller.play(chapterIndex: 0)
        let current = try #require(controller.ksKernel.engine)
        let currentReady = try #require(controller.ksKernel.onReady)
        let currentFinish = try #require(controller.ksKernel.onFinish)
        let phase = controller.phase
        oldReady()
        oldFinish(NSError(domain: "Readcc.LifecycleTest", code: 2))
        #expect(controller.ksKernel.engine === current && controller.usesKSPlayer)
        #expect(controller.phase == phase)
        controller.close()
        currentReady()
        currentFinish(NSError(domain: "Readcc.LifecycleTest", code: 3))
        #expect(controller.ksKernel.engine == nil && controller.player.currentItem == nil)
        #expect(controller.phase == .paused)
    }

    @Test("pause during real fixture preparation stays paused on ready and keeps desired rate")
    func pausedPreparationStaysPaused() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VideoStill/video-still-landscape.mp4")
        let controller = VideoPlaybackController(link: VideoStream(url: fixture, headers: [:]),
                                                 title: "Paused preparation fixture", prefersKSPlayer: true)
        defer { controller.close() }
        controller.start()
        controller.setRate(1.5)
        controller.pause()
        let ready = try await waitUntil { controller.phase != .loading }
        try #require(ready)
        #expect(controller.usesKSPlayer && controller.phase == .paused)
        let engine = try #require(controller.ksKernel.engine)
        #expect(!engine.isPlaying)
        #expect(controller.rate == 1.5)
        controller.resume()
        #expect(controller.phase == .playing && engine.playbackRate == 1.5)
    }
}
