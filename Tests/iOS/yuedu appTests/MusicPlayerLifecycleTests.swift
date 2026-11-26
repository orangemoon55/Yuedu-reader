import AVFoundation
import Combine
import MediaPlayer
import XCTest
@testable import yuedu_app

/// Adds to the already selected XCTest class, so the media51 CI scope executes these tests.
extension MusicPlayerPlaybackTests {
    @MainActor
    func testDefaultStatusBridgeDeliversRealAVFoundationFailureOnMainActor() async throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("music-kvo-invalid-\(UUID().uuidString).wav")
        try Data("Deliberately invalid local audio, no remote source".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let item = AVPlayerItem(asset: AVURLAsset(url: file))
        let native = AVQueuePlayer()
        let received = RealStatusRecorder()
        // The production bridge, not MusicStatusProbe; no failed-notification listener is
        // installed here, so only actual status KVO can satisfy this assertion.
        let observation = yuedu_app.MusicPlayer.observeStatus(of: item) { status in
            received.values.append(status.rawValue)
        }
        defer { observation.cancel(); native.pause(); native.removeAllItems() }
        native.insert(item, after: nil)
        native.play()
        let deadline = Date().addingTimeInterval(10)
        while !received.values.contains(AVPlayerItem.Status.failed.rawValue), Date() < deadline {
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(received.values.contains(AVPlayerItem.Status.failed.rawValue),
                      "Default KVO bridge failed to deliver real AVPlayerItem failure: \(received.values)")
        XCTAssertEqual(item.status, .failed)
    }

    @MainActor
    func testStatusObservationSurvivesReadyAndHandlesLaterFailureOnlyOnce() throws {
        let probe = MusicStatusProbe()
        let fixture = try LifecycleAudioFixture(probe: probe)
        defer { fixture.cleanup() }
        let player = fixture.player
        player.play(fixture.tracks[0], queue: fixture.tracks)
        player.pause() // deterministic failure budget; readiness is not successful playback
        XCTAssertEqual(probe.callbacks.count, 1)
        probe.deliver(0, .readyToPlay)
        XCTAssertFalse(probe.cancelled.contains(0), "Readiness must not end failure observation")
        probe.deliver(0, .failed)
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertTrue(probe.cancelled.contains(0))
        XCTAssertEqual(probe.callbacks.count, 2)
        probe.deliver(0, .failed) // an already queued old KVO callback is harmless
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertNil(player.errorMessage)
        probe.deliver(1, .readyToPlay)
        probe.deliver(1, .failed)
        XCTAssertEqual(player.currentTrack, fixture.tracks[2])
        probe.deliver(2, .failed) // third consecutive failure stops instead of looping forever
        XCTAssertNotNil(player.errorMessage)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.queue, fixture.tracks)
    }

    @MainActor
    func testSeekCancelsOldStatusObservationEvenForSameNativeItem() throws {
        let probe = MusicStatusProbe()
        let fixture = try LifecycleAudioFixture(probe: probe)
        defer { fixture.cleanup() }
        let player = fixture.player
        player.play(fixture.tracks[0], queue: fixture.tracks)
        player.pause()
        let sameItem = try XCTUnwrap(fixture.native.currentItem)
        player.seek(to: 1)
        XCTAssertTrue(fixture.native.currentItem === sameItem)
        XCTAssertEqual(probe.callbacks.count, 2)
        XCTAssertTrue(probe.cancelled.contains(0))
        probe.deliver(0, .failed)
        XCTAssertEqual(player.currentTrack, fixture.tracks[0])
        XCTAssertNil(player.errorMessage)
        probe.deliver(1, .readyToPlay)
        probe.deliver(1, .failed)
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
    }

    @MainActor
    func testTakeoverCancelsStatusObserverAndRejectsEnqueuedFailure() throws {
        let probe = MusicStatusProbe()
        let fixture = try LifecycleAudioFixture(probe: probe)
        defer { fixture.cleanup() }
        fixture.player.play(fixture.tracks[0], queue: fixture.tracks)
        fixture.player.stopForTakeover()
        XCTAssertTrue(probe.cancelled.contains(0))
        probe.deliver(0, .failed)
        XCTAssertNil(fixture.player.currentTrack)
        XCTAssertTrue(fixture.player.queue.isEmpty)
        XCTAssertNil(fixture.native.currentItem)
        XCTAssertNil(fixture.player.errorMessage)
        XCTAssertFalse(fixture.player.isPlaying)
    }

    @MainActor
    func testReleasedPlayerRemovesOnlyItsSixTargetsWithoutClearingNewOwner() {
        let center = MPRemoteCommandCenter.shared()
        let info = MPNowPlayingInfoCenter.default()
        let oldInfo = info.nowPlayingInfo
        let oldState = info.playbackState
        let oldPlay = center.playCommand.isEnabled
        let oldNext = center.nextTrackCommand.isEnabled
        defer {
            info.nowPlayingInfo = oldInfo; info.playbackState = oldState
            center.playCommand.isEnabled = oldPlay; center.nextTrackCommand.isEnabled = oldNext
        }
        var removed: [ObjectIdentifier] = []
        var player: yuedu_app.MusicPlayer? = yuedu_app.MusicPlayer(
            queuePlayer: AVQueuePlayer(), removeCommandTarget: { command, token in
                removed.append(ObjectIdentifier(command))
                command.removeTarget(token)
            })
        weak var released = player
        player?.configureRemoteCommandsIfNeeded()
        player?.configureRemoteCommandsIfNeeded()
        let expected = [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand,
                        center.changePlaybackPositionCommand].map { ObjectIdentifier($0) }
        // A subsequent owner can have its own targets, flags and metadata on the same center.
        let newerToken = center.playCommand.addTarget { _ in .commandFailed }
        defer { center.playCommand.removeTarget(newerToken) }
        center.playCommand.isEnabled = true
        center.nextTrackCommand.isEnabled = true
        info.nowPlayingInfo = [MPMediaItemPropertyTitle: "Other audio owner"]
        info.playbackState = .playing
        player = nil
        XCTAssertNil(released)
        XCTAssertEqual(removed, expected)
        XCTAssertTrue(center.playCommand.isEnabled)
        XCTAssertTrue(center.nextTrackCommand.isEnabled)
        XCTAssertEqual(info.nowPlayingInfo?[MPMediaItemPropertyTitle] as? String, "Other audio owner")
        XCTAssertEqual(info.playbackState, .playing)
    }

    @MainActor
    func testStoppedPlayerDoesNotRemoveRemoteTargetsTwiceOnRelease() {
        var removals = 0
        var player: yuedu_app.MusicPlayer? = yuedu_app.MusicPlayer(
            queuePlayer: AVQueuePlayer(), removeCommandTarget: { command, token in
                removals += 1; command.removeTarget(token)
            })
        player?.configureRemoteCommandsIfNeeded()
        player?.stop()
        XCTAssertEqual(removals, 6)
        player?.configureRemoteCommandsIfNeeded()
        weak var released = player
        player = nil
        XCTAssertNil(released)
        XCTAssertEqual(removals, 12, "Exactly the newly installed six targets must be removed")
    }
}

@MainActor
private final class RealStatusRecorder {
    var values: [Int] = []
}

@MainActor
private final class MusicStatusProbe {
    var callbacks: [@MainActor @Sendable (AVPlayerItem.Status) -> Void] = []
    var cancelled: Set<Int> = []

    func install(_ item: AVPlayerItem,
                 deliver: @escaping @MainActor @Sendable (AVPlayerItem.Status) -> Void) -> AnyCancellable {
        let index = callbacks.count
        callbacks.append(deliver)
        return AnyCancellable { [weak self] in
            MainActor.assumeIsolated { _ = self?.cancelled.insert(index) }
        }
    }

    func deliver(_ index: Int, _ status: AVPlayerItem.Status) { callbacks[index](status) }
}

@MainActor
private struct LifecycleAudioFixture {
    let native: AVQueuePlayer
    let player: yuedu_app.MusicPlayer
    let tracks: [MediaHubLibraryItem]
    let file: URL

    init(probe: MusicStatusProbe) throws {
        let name = "music-lifecycle-\(UUID().uuidString).wav"
        file = MusicStorage.directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: MusicStorage.directory, withIntermediateDirectories: true)
        let pcmBytes: UInt32 = 8 * 8_000 * 2
        func bytes<T: FixedWidthInteger>(_ value: T) -> Data {
            var little = value.littleEndian
            return withUnsafeBytes(of: &little) { Data($0) }
        }
        var wave = Data("RIFF".utf8)
        wave.append(bytes(pcmBytes + 36)); wave.append(Data("WAVEfmt ".utf8))
        wave.append(bytes(UInt32(16))); wave.append(bytes(UInt16(1))); wave.append(bytes(UInt16(1)))
        wave.append(bytes(UInt32(8_000))); wave.append(bytes(UInt32(16_000)))
        wave.append(bytes(UInt16(2))); wave.append(bytes(UInt16(16)))
        wave.append(Data("data".utf8)); wave.append(bytes(pcmBytes))
        wave.append(Data(repeating: 0, count: Int(pcmBytes)))
        try wave.write(to: file, options: .atomic)
        tracks = (0..<4).map { index in
            MusicTrackDescriptor(title: "Lifecycle \(index)", artist: "", album: "",
                                 urlString: "local:\(name)", headers: [:]).libraryItem()
        }
        native = AVQueuePlayer()
        player = yuedu_app.MusicPlayer(queuePlayer: native, statusObserver: probe.install)
    }

    func cleanup() {
        player.stop()
        try? FileManager.default.removeItem(at: file)
    }
}
