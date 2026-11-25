import AVFoundation
import MediaPlayer
import XCTest
@testable import yuedu_app

@MainActor
final class MusicPlayerPlaybackTests: XCTestCase {
    func testQueueBoundaryPolicyLoopsOnlyCurrentItem() {
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: true, repeatsCurrent: true, hasNext: true), .repeatCurrent)
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: true, repeatsCurrent: false, hasNext: true), .advance)
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: true, repeatsCurrent: false, hasNext: false), .finish)
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: false, repeatsCurrent: true, hasNext: true), .ignore)
        XCTAssertNil(MusicQueuePlaybackPolicy.nextIndex(after: 1, itemCount: 2))
    }

    func testNativeQueuePausesAtItemBoundary() {
        let queue = AVQueuePlayer()
        let player = MusicPlayer(queuePlayer: queue)
        XCTAssertEqual(queue.actionAtItemEnd, .pause)
        player.stop()
    }

    func testRepeatedRemoteSetupAndStopCanReinstall() {
        let player = MusicPlayer(queuePlayer: AVQueuePlayer())
        player.configureRemoteCommandsIfNeeded()
        player.configureRemoteCommandsIfNeeded()
        player.stop()
        XCTAssertFalse(MPRemoteCommandCenter.shared().playCommand.isEnabled)
        player.configureRemoteCommandsIfNeeded()
        player.stop()
        XCTAssertFalse(MPRemoteCommandCenter.shared().nextTrackCommand.isEnabled)
    }

    func testTTSHubTakeoverClearsMusicAndStaleDetachDoesNotClearTTS() {
        let hub = NowPlayingHub.shared
        let player = MusicPlayer(queuePlayer: AVQueuePlayer())
        hub.attachMusic(player)
        let coordinator = TTSCoordinator()
        hub.attach(coordinator)
        XCTAssertEqual(hub.source, .tts)
        XCTAssertNil(player.currentTrack)
        hub.detachMusic(player)
        XCTAssertEqual(hub.source, .tts)
        hub.detach(coordinator)
    }
}
