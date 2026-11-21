import AVFoundation
import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

/// Only the existing synthetic ten-second MP4 is played. No source script or remote stream.
@Suite("Video fifteen-second transport", .serialized)
@MainActor
struct VideoTransportTests {
    @Test("transport directions name and deliver minus/plus fifteen seconds")
    func directions() {
        #expect(VideoSkipButton.Direction.backward.seconds == -15)
        #expect(VideoSkipButton.Direction.forward.seconds == 15)
        #expect(VideoSkipButton.Direction.backward.symbol == "gobackward.15")
        #expect(VideoSkipButton.Direction.forward.symbol == "goforward.15")
        #expect(VideoSkipButton.Direction.backward.label == localized("快退15秒"))
        #expect(VideoSkipButton.Direction.forward.label == localized("快进15秒"))
        #expect(VideoSkipButton.Direction.backward.identifier == "video.seekBackward15")
        #expect(VideoSkipButton.Direction.forward.identifier == "video.seekForward15")
    }

    @Test("glass transport buttons expose stable IDs, exact labels and at least 44-point targets")
    func accessibleButtons() async throws {
        var skips: [Double] = []
        let buttons = HStack {
            VideoSkipButton(direction: .backward) { skips.append($0) }
            VideoSkipButton(direction: .forward) { skips.append($0) }
        }
        try await withAccessibilityHost(in: buttons) { host in
            let found = await eventually(host) {
                accessibilityElements(in: host).filter { $0.accessibilityTraits.contains(.button) }.count == 2
            }
            #expect(found)
            for direction in [VideoSkipButton.Direction.backward, .forward] {
                let button = try #require(accessibilityElements(in: host).first {
                    ($0 as? UIAccessibilityIdentification)?.accessibilityIdentifier == direction.identifier
                })
                #expect(button.accessibilityLabel == direction.label)
                #expect(button.accessibilityFrame.width >= 44)
                #expect(button.accessibilityFrame.height >= 44)
                #expect(button.accessibilityActivate())
            }
            #expect(skips == [-15, 15])
        }
    }

    @Test("a disabled transport button cannot issue a seek")
    func disabledButton() async throws {
        var skips: [Double] = []
        try await withAccessibilityHost(in: VideoSkipButton(direction: .forward) { skips.append($0) }.disabled(true)) { host in
            let found = await eventually(host) {
                accessibilityElements(in: host).contains { $0.accessibilityLabel == localized("快进15秒") }
            }
            #expect(found)
            let button = try #require(accessibilityElements(in: host).first {
                $0.accessibilityLabel == localized("快进15秒")
            })
            #expect(button.accessibilityTraits.contains(.notEnabled))
            _ = button.accessibilityActivate()
            #expect(skips.isEmpty)
        }
    }

    private func withLocalPlayer(_ body: (VideoPlaybackController) async throws -> Void) async throws {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VideoStill/video-still-landscape.mp4")
        let saved = VideoLinkPositions.time(for: file)
        VideoLinkPositions.save(0, for: file)
        let controller = VideoPlaybackController(link: VideoStream(url: file, headers: [:]), title: "Synthetic transport")
        defer {
            controller.close()
            VideoLinkPositions.save(saved ?? 0, for: file)
        }
        controller.start()
        let deadline = ContinuousClock.now + .seconds(8)
        while controller.phase == .loading, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(controller.phase == .playing)
        #expect(abs(controller.duration - 10) < 0.5)
        controller.pause()
        try await body(controller)
    }

    @Test("unknown/loading transport is a no-op without opening any media")
    func loadingIsSafe() {
        let file = URL(fileURLWithPath: "/synthetic-not-opened.mp4")
        let controller = VideoPlaybackController(link: VideoStream(url: file, headers: [:]), title: "Not opened")
        #expect(!controller.canSkip)
        controller.skip(by: -15)
        controller.skip(by: 15)
        #expect(controller.phase == .loading)
        #expect(controller.currentTime == 0)
        #expect(controller.player.currentItem == nil)
    }

    @Test("native seek and repeated transport clamp without replacing the item or chapter")
    func nativeSeekClamps() async throws {
        try await withLocalPlayer { controller in
            let item = try #require(controller.player.currentItem)
            let chapter = controller.chapterIndex
            controller.seek(to: 6)
            controller.skip(by: -15)
            #expect(controller.currentTime == 0)
            controller.skip(by: 15)
            controller.skip(by: 15)
            #expect(controller.currentTime == controller.duration)
            #expect(controller.phase == .paused)
            let deadline = ContinuousClock.now + .seconds(5)
            while abs(controller.player.currentTime().seconds - controller.duration) > 0.1,
                  ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(abs(controller.player.currentTime().seconds - controller.duration) <= 0.1)
            controller.seek(to: .nan)
            #expect(controller.currentTime == controller.duration)
            controller.skip(by: -15)
            #expect(controller.currentTime == 0)
            #expect(controller.phase == .paused)
            #expect(controller.player.currentItem === item)
            #expect(controller.chapterIndex == chapter)
        }
    }

    @Test("forward to the finite end cannot auto-advance, and central play replays this item")
    func endStaysInEpisode() async throws {
        try await withLocalPlayer { controller in
            let item = try #require(controller.player.currentItem)
            let chapter = controller.chapterIndex
            controller.seek(to: 6)
            controller.resume()
            controller.skip(by: 15)
            #expect(controller.phase == .paused)
            #expect(controller.currentTime == controller.duration)
            // AVPlayer can emit this for an explicit seek, not only for natural playback end.
            NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            #expect(controller.phase == .paused)
            #expect(controller.chapterIndex == chapter)
            #expect(controller.player.currentItem === item)
            controller.togglePlayPause()
            let deadline = ContinuousClock.now + .seconds(5)
            while controller.phase == .paused, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(controller.phase == .playing)
            #expect(controller.currentTime < controller.duration)
            #expect(controller.player.currentItem === item)
            #expect(controller.chapterIndex == chapter)
            controller.togglePlayPause()
            #expect(controller.phase == .paused)
        }
    }

    @Test("natural end retains the existing replay action and disables relative transport")
    func naturalEndRetainsReplay() async throws {
        try await withLocalPlayer { controller in
            let item = try #require(controller.player.currentItem)
            let chapter = controller.chapterIndex
            controller.resume()
            NotificationCenter.default.post(name: AVPlayerItem.didPlayToEndTimeNotification, object: item)
            #expect(controller.phase == .ended)
            #expect(!controller.canSkip)
            controller.skip(by: -15)
            controller.skip(by: 15)
            #expect(controller.phase == .ended)
            #expect(controller.currentTime == 0)
            controller.togglePlayPause()
            let deadline = ContinuousClock.now + .seconds(8)
            while controller.phase == .loading, ContinuousClock.now < deadline {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(controller.phase == .playing)
            #expect(controller.chapterIndex == chapter)
        }
    }
}
