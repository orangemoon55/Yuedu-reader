import AVFoundation
import Foundation
import XCTest
@testable import yuedu_app

@MainActor
final class YingxiaMusicQueueTests: XCTestCase {
    func testEmptyAndClampedQueueBoundaries() {
        var empty = YingxiaMusicQueue<Int>(tracks: [], start: 99)
        XCTAssertEqual(empty.index, 0)
        XCTAssertNil(empty.current)
        XCTAssertFalse(empty.hasNext)
        XCTAssertFalse(empty.hasPrevious)
        XCTAssertNil(empty.advance())
        XCTAssertNil(empty.back())
        XCTAssertNil(empty.jump(to: 0))
        XCTAssertEqual(YingxiaMusicQueue(tracks: [1, 2], start: -10).current, 1)
        XCTAssertEqual(YingxiaMusicQueue(tracks: [1, 2], start: Int.max).current, 2)
        XCTAssertNil(MusicQueuePlaybackPolicy.nextIndex(after: Int.max, itemCount: Int.max))
        XCTAssertNil(MusicQueuePlaybackPolicy.nextIndex(after: -1, itemCount: 2))
        XCTAssertNil(MusicQueuePlaybackPolicy.nextIndex(after: 0, itemCount: 0))
    }

    func testAdvanceBackAndJumpNeverTruncateFullHistory() {
        let tracks = ["a", "b", "c", "d"]
        var queue = YingxiaMusicQueue(tracks: tracks, start: 1)
        XCTAssertEqual(queue.advance(), "c")
        XCTAssertEqual(queue.advance(), "d")
        XCTAssertNil(queue.advance())
        XCTAssertEqual(queue.back(), "c")
        XCTAssertEqual(queue.back(), "b")
        XCTAssertEqual(queue.back(), "a")
        XCTAssertNil(queue.back())
        XCTAssertEqual(queue.jump(to: 3), "d")
        XCTAssertNil(queue.jump(to: -1))
        XCTAssertNil(queue.jump(to: 4))
        XCTAssertEqual(queue.index, 3)
        XCTAssertEqual(queue.tracks, tracks)
    }

    func testUpstreamThreeFailureBoundAndNoAccidentalWrap() {
        var queue = YingxiaMusicQueue(tracks: [1, 2, 3, 4])
        XCTAssertTrue(queue.skipsAfterFailure(consecutive: 1))
        queue.advance()
        XCTAssertTrue(queue.skipsAfterFailure(consecutive: 2))
        queue.advance()
        XCTAssertFalse(queue.skipsAfterFailure(consecutive: 3))
        queue.advance()
        XCTAssertFalse(queue.skipsAfterFailure(consecutive: 1))
        XCTAssertTrue(queue.skipsAfterFailure(consecutive: 1, wraps: true))
        XCTAssertFalse(queue.skipsAfterFailure(consecutive: 3, wraps: true))
        XCTAssertFalse(YingxiaMusicQueue(tracks: [1]).skipsAfterFailure(consecutive: 1, wraps: true))
        XCTAssertFalse(YingxiaMusicQueue<Int>(tracks: []).skipsAfterFailure(consecutive: 1))
    }

    func testPreviousRestartsOnlyAfterThreeSecondsOrAtFirstTrack() {
        XCTAssertEqual(MusicQueuePlaybackPolicy.previousAction(elapsed: 0, hasPrevious: true), .back)
        XCTAssertEqual(MusicQueuePlaybackPolicy.previousAction(elapsed: 3, hasPrevious: true), .back)
        XCTAssertEqual(MusicQueuePlaybackPolicy.previousAction(elapsed: 3.001, hasPrevious: true), .restart)
        XCTAssertEqual(MusicQueuePlaybackPolicy.previousAction(elapsed: 0, hasPrevious: false), .restart)
    }

    func testEventGenerationRejectsStaleIdentityAndDeduplicatesEOFAndFailure() {
        var events = MusicQueuePlaybackPolicy.ItemEvents()
        let oldGeneration = events.generation
        XCTAssertFalse(events.consumeTerminalEvent(oldGeneration, isCurrentItem: false))
        XCTAssertTrue(events.consumeTerminalEvent(oldGeneration, isCurrentItem: true))
        // Notification + poll (or duplicate EOF) must not advance twice.
        XCTAssertFalse(events.consumeTerminalEvent(oldGeneration, isCurrentItem: true))
        events.invalidate()
        XCTAssertFalse(events.accepts(oldGeneration, isCurrentItem: true))
        XCTAssertFalse(events.consumeTerminalEvent(oldGeneration, isCurrentItem: true))
        XCTAssertTrue(events.consumeTerminalEvent(events.generation, isCurrentItem: true))
        events.invalidate() // Stop/replacement/seek invalidates even the same AVPlayerItem identity.
        XCTAssertTrue(events.accepts(events.generation, isCurrentItem: true))
    }

    func testEOFPolicyIgnoresStaleAndKeepsRepeatOnCurrent() {
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: false, repeatsCurrent: true, hasNext: true), .ignore)
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: true, repeatsCurrent: true, hasNext: true), .repeatCurrent)
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: true, repeatsCurrent: false, hasNext: true), .advance)
        XCTAssertEqual(MusicQueuePlaybackPolicy.endAction(isCurrentItem: true, repeatsCurrent: false, hasNext: false), .finish)
    }

    func testProductionStartsInMiddleAndPreviousRetainsAllTracks() throws {
        let fixture = try PlaybackFixture(count: 4)
        defer { fixture.cleanup() }
        let player = fixture.player
        player.play(fixture.tracks[1], queue: fixture.tracks)
        let originalItem = fixture.native.currentItem
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertEqual(fixture.native.items().count, 1)
        XCTAssertEqual(fixture.native.actionAtItemEnd, .pause)
        player.next()
        XCTAssertEqual(player.currentTrack, fixture.tracks[2])
        player.previous()
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertFalse(fixture.native.currentItem === originalItem)
        player.previous()
        XCTAssertEqual(player.currentTrack, fixture.tracks[0])
        player.next()
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertEqual(player.queue, fixture.tracks)
    }

    func testProductionPreviousRestartAndExactThreshold() throws {
        let fixture = try PlaybackFixture(count: 3)
        defer { fixture.cleanup() }
        let player = fixture.player
        player.play(fixture.tracks[1], queue: fixture.tracks)
        player.pause()
        player.seek(to: 3.001)
        player.previous()
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertFalse(player.isPlaying)
        player.seek(to: 3)
        player.previous()
        XCTAssertEqual(player.currentTrack, fixture.tracks[0])
        XCTAssertEqual(player.queue, fixture.tracks)
    }

    func testProductionEOFAdvancesAndFinishesWithFullHistoryIntact() async throws {
        let fixture = try PlaybackFixture(count: 2)
        let defaults = UserDefaults.standard
        let loopKey = MediaPreferences.musicLoopCurrentKey
        let oldLoop = defaults.object(forKey: loopKey)
        MediaPreferences.musicLoopCurrent = false
        defer {
            if let oldLoop { defaults.set(oldLoop, forKey: loopKey) }
            else { defaults.removeObject(forKey: loopKey) }
            fixture.cleanup()
        }
        let player = fixture.player
        player.play(fixture.tracks[0], queue: fixture.tracks)
        player.pause() // Notification handling must not silently undo a user pause.
        let first = try XCTUnwrap(fixture.native.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: first)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: first)
        await drainEvents()
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertFalse(player.isPlaying)
        let last = try XCTUnwrap(fixture.native.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: last)
        await drainEvents()
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.queue, fixture.tracks)
        player.seek(to: 0) // EOF is past the restart threshold; explicitly select backward history.
        player.previous()
        XCTAssertEqual(player.currentTrack, fixture.tracks[0])
    }

    func testProductionRejectsAlreadyEnqueuedEventsAfterSeekReplacementAndStop() async throws {
        let fixture = try PlaybackFixture(count: 3)
        defer { fixture.cleanup() }
        let player = fixture.player
        player.play(fixture.tracks[0], queue: fixture.tracks)
        player.pause()
        let first = try XCTUnwrap(fixture.native.currentItem)
        // Same identity, different generation: queued EOF must not undo this explicit seek.
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: first)
        player.seek(to: 1)
        await drainEvents()
        XCTAssertEqual(player.currentTrack, fixture.tracks[0])
        XCTAssertFalse(player.isPlaying)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: first)
        player.next() // The queued failure must not advance the replacement item again.
        player.pause()
        await drainEvents()
        XCTAssertEqual(player.currentTrack, fixture.tracks[1])
        XCTAssertNil(player.errorMessage)
        let second = try XCTUnwrap(fixture.native.currentItem)
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: second)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: second)
        player.stopForTakeover()
        await drainEvents()
        // Also outlive the cancelled status poll's first sleep; no stale task may resurrect it.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNil(player.currentTrack)
        XCTAssertTrue(player.queue.isEmpty)
        XCTAssertNil(fixture.native.currentItem)
        XCTAssertFalse(player.isPlaying)
        XCTAssertNil(player.errorMessage)
        player.play(fixture.tracks[2], queue: fixture.tracks)
        player.pause()
        NotificationCenter.default.post(name: .AVPlayerItemDidPlayToEndTime, object: first)
        NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: second)
        await drainEvents()
        XCTAssertEqual(player.currentTrack, fixture.tracks[2])
        XCTAssertEqual(player.queue, fixture.tracks)
        XCTAssertNil(player.errorMessage)
    }

    func testProductionSkipsOnlyTwoConsecutiveFailuresAndDeduplicatesNotifications() async throws {
        let fixture = try PlaybackFixture(count: 4)
        defer { fixture.cleanup() }
        let player = fixture.player
        player.play(fixture.tracks[0], queue: fixture.tracks)
        player.pause() // Never reaches .playing, so the consecutive-failure budget cannot reset.
        for failedIndex in 0..<3 {
            let failed = try XCTUnwrap(fixture.native.currentItem)
            NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: failed)
            NotificationCenter.default.post(name: .AVPlayerItemFailedToPlayToEndTime, object: failed)
            await drainEvents()
            XCTAssertEqual(player.currentTrack, fixture.tracks[min(failedIndex + 1, 2)])
        }
        XCTAssertNotNil(player.errorMessage)
        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.queue, fixture.tracks)
        // User navigation explicitly starts a fresh bounded attempt; the fourth track still exists.
        player.next()
        XCTAssertEqual(player.currentTrack, fixture.tracks[3])
        XCTAssertNil(player.errorMessage)
    }

    private func drainEvents() async {
        for _ in 0..<8 { await Task.yield() }
    }
}

/// Real, app-owned local PCM fixture. No remote endpoints, imported scripts or provider stubs.
@MainActor
private struct PlaybackFixture {
    let native: AVQueuePlayer
    let player: MusicPlayer
    let tracks: [MediaHubLibraryItem]
    let file: URL

    init(count: Int) throws {
        let name = "yingxia-queue-test-\(UUID().uuidString).wav"
        file = MusicStorage.directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: MusicStorage.directory, withIntermediateDirectories: true)
        // Eight seconds of mono 8 kHz / 16-bit silence keep EOF under explicit test control.
        let pcmBytes: UInt32 = 8 * 8_000 * 2
        var wave = Data("RIFF".utf8)
        func integer<T: FixedWidthInteger>(_ value: T) -> Data {
            var little = value.littleEndian
            return withUnsafeBytes(of: &little) { Data($0) }
        }
        wave.append(integer(pcmBytes + 36))
        wave.append(Data("WAVEfmt ".utf8))
        wave.append(integer(UInt32(16)))
        wave.append(integer(UInt16(1)))
        wave.append(integer(UInt16(1)))
        wave.append(integer(UInt32(8_000)))
        wave.append(integer(UInt32(16_000)))
        wave.append(integer(UInt16(2)))
        wave.append(integer(UInt16(16)))
        wave.append(Data("data".utf8))
        wave.append(integer(pcmBytes))
        wave.append(Data(repeating: 0, count: Int(pcmBytes)))
        try wave.write(to: file, options: .atomic)
        tracks = (0..<count).map { index in
            MusicTrackDescriptor(title: "Queue \(index)", artist: "", album: "", urlString: "local:\(name)", headers: [:]).libraryItem()
        }
        native = AVQueuePlayer()
        player = MusicPlayer(queuePlayer: native)
    }

    func cleanup() {
        player.stop()
        try? FileManager.default.removeItem(at: file)
    }
}
