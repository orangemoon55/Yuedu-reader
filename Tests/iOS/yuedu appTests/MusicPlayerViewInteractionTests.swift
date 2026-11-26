import AVFoundation
import Foundation
import XCTest
@testable import yuedu_app

@MainActor
final class MusicPlayerViewInteractionTests: XCTestCase {
    func testDragOnlyPreviewsUntilFinishAndCanCommitOnlyOnce() {
        var scrub = MusicPlayerScrubState()
        scrub.begin(trackID: "A", time: 12, duration: 120)
        scrub.preview(20, trackID: "A", duration: 120)
        scrub.preview(45, trackID: "A", duration: 120)
        XCTAssertEqual(scrub.previewTime(for: "A"), 45)
        XCTAssertNil(scrub.previewTime(for: "B"))
        XCTAssertEqual(scrub.finish(trackID: "A", currentTrackID: "A", duration: 120), 45)
        XCTAssertNil(scrub.finish(trackID: "A", currentTrackID: "A", duration: 120))
    }

    func testScopeDistinguishesSameTrackInstancesAndRejectsTheirOldCallbacks() {
        let first = MusicPlayerScrubState.scope(trackID: "A:with:separators", instanceID: UUID())
        let second = MusicPlayerScrubState.scope(trackID: "A:with:separators", instanceID: UUID())
        XCTAssertNotEqual(first, second)
        var scrub = MusicPlayerScrubState()
        scrub.begin(trackID: first, time: 5, duration: 120)
        scrub.preview(80, trackID: first, duration: 120)
        XCTAssertNil(scrub.finish(trackID: first, currentTrackID: second, duration: 120))
        scrub.begin(trackID: second, time: 10, duration: 120)
        scrub.preview(40, trackID: second, duration: 120)
        scrub.preview(90, trackID: first, duration: 120)
        XCTAssertNil(scrub.finish(trackID: first, currentTrackID: second, duration: 120))
        XCTAssertEqual(scrub.finish(trackID: second, currentTrackID: second, duration: 120), 40)
    }

    func testPlayerABAAndSameIDReplacementInvalidateDragScope() throws {
        let name = "music-scrub-" + UUID().uuidString + ".wav"
        try FileManager.default.createDirectory(at: MusicStorage.directory, withIntermediateDirectories: true)
        let url = MusicStorage.directory.appendingPathComponent(name)
        // One second of local mono 8 kHz 16-bit PCM; no network or provider is contacted.
        let header: [UInt8] = [82,73,70,70,164,62,0,0,87,65,86,69,102,109,116,32,
            16,0,0,0,1,0,1,0,64,31,0,0,128,62,0,0,2,0,16,0,100,97,116,97,128,62,0,0]
        try (Data(header) + Data(repeating: 0, count: 16_000)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let player = yuedu_app.MusicPlayer(queuePlayer: AVQueuePlayer())
        defer { player.stop() }
        let a = MediaHubLibraryItem(sourceID: "fixture", siteKey: "music", videoID: "A",
            title: "测试 A", poster: "", kind: .music, siteName: "Fixture", musicURL: "local:\(name)")
        let b = MediaHubLibraryItem(sourceID: "fixture", siteKey: "music", videoID: "B",
            title: "测试 B", poster: "", kind: .music, siteName: "Fixture", musicURL: "local:\(name)")
        let descriptor = try XCTUnwrap(MusicTrackDescriptor.from(a))
        XCTAssertEqual(descriptor.resolvedURL(), url)
        player.play(a, queue: [a, b])
        XCTAssertEqual(player.currentTrack?.id, a.id)
        XCTAssertNil(player.errorMessage)
        let firstInstance = player.playbackInstanceID
        let first = MusicPlayerScrubState.scope(trackID: a.id, instanceID: firstInstance)
        var scrub = MusicPlayerScrubState()
        scrub.begin(trackID: first, time: 0, duration: 120)
        scrub.preview(80, trackID: first, duration: 120)
        player.pause()
        XCTAssertEqual(player.playbackInstanceID, firstInstance)
        player.next()
        player.previous()
        XCTAssertEqual(player.currentTrack?.id, a.id)
        XCTAssertNotEqual(player.playbackInstanceID, firstInstance)
        let returned = MusicPlayerScrubState.scope(trackID: a.id, instanceID: player.playbackInstanceID)
        XCTAssertNil(scrub.finish(trackID: first, currentTrackID: returned, duration: 120))
        var refreshed = a
        refreshed.musicQuality = "320k"
        player.play(refreshed)
        XCTAssertEqual(player.currentTrack?.id, a.id)
        let replaced = MusicPlayerScrubState.scope(trackID: a.id, instanceID: player.playbackInstanceID)
        XCTAssertNotEqual(returned, replaced)
        scrub.begin(trackID: returned, time: 0, duration: 120)
        XCTAssertNil(scrub.finish(trackID: returned, currentTrackID: replaced, duration: 120))
        let beforeStop = player.playbackInstanceID
        player.stop()
        XCTAssertNotEqual(player.playbackInstanceID, beforeStop)
        XCTAssertNil(player.currentTrack)
    }

    func testChangingTrackRejectsOldDragEvenBeforeViewCancellation() {
        var scrub = MusicPlayerScrubState()
        scrub.begin(trackID: "A", time: 0, duration: 120)
        scrub.preview(80, trackID: "A", duration: 120)
        XCTAssertNil(scrub.finish(trackID: "A", currentTrackID: "B", duration: 300))
        XCTAssertNil(scrub.previewTime(for: "A"))
    }

    func testStaleEndCannotCancelAnotherTracksPreview() {
        var scrub = MusicPlayerScrubState()
        scrub.begin(trackID: "A", time: 5, duration: 120)
        scrub.cancel()
        scrub.begin(trackID: "B", time: 10, duration: 300)
        scrub.preview(60, trackID: "B", duration: 300)
        scrub.preview(90, trackID: "A", duration: 120)
        XCTAssertNil(scrub.finish(trackID: "A", currentTrackID: "B", duration: 300))
        XCTAssertEqual(scrub.finish(trackID: "B", currentTrackID: "B", duration: 300), 60)
    }

    func testCancelledOrStoppedDragCannotSeek() {
        var scrub = MusicPlayerScrubState()
        scrub.preview(15, trackID: "A", duration: 60)
        XCTAssertNil(scrub.finish(trackID: "A", currentTrackID: "A", duration: 60))
        scrub.begin(trackID: "A", time: 10, duration: 60)
        scrub.cancel()
        XCTAssertNil(scrub.finish(trackID: "A", currentTrackID: "A", duration: 60))
        scrub.begin(trackID: "A", time: 10, duration: 60)
        XCTAssertNil(scrub.finish(trackID: "A", currentTrackID: nil, duration: 60))
    }

    func testFinalSeekUsesLatestDurationAndFiniteValues() {
        var scrub = MusicPlayerScrubState()
        scrub.begin(trackID: "A", time: 10, duration: 120)
        scrub.preview(100, trackID: "A", duration: 120)
        scrub.preview(.nan, trackID: "A", duration: 120)
        XCTAssertEqual(scrub.finish(trackID: "A", currentTrackID: "A", duration: 80), 80)
        scrub.begin(trackID: "A", time: 10, duration: 120)
        scrub.preview(-10, trackID: "A", duration: 120)
        XCTAssertEqual(scrub.finish(trackID: "A", currentTrackID: "A", duration: 120), 0)
        scrub.begin(trackID: "A", time: 10, duration: 120)
        XCTAssertNil(scrub.finish(trackID: "A", currentTrackID: "A", duration: .infinity))
    }

    func testUnknownDurationDoesNotBeginDragging() {
        var scrub = MusicPlayerScrubState()
        scrub.begin(trackID: "A", time: 10, duration: 0)
        XCTAssertNil(scrub.previewTime(for: "A"))
        scrub.begin(trackID: "A", time: 10, duration: .nan)
        XCTAssertNil(scrub.previewTime(for: "A"))
    }

    func testVoiceOverAdjustmentClampsAndDoesNotNeedEditingCallbacks() {
        XCTAssertEqual(MusicPlayerScrubState.accessibilityTarget(currentTime: 10, duration: 120, delta: 5), 15)
        XCTAssertEqual(MusicPlayerScrubState.accessibilityTarget(currentTime: 10, duration: 120, delta: -5), 5)
        XCTAssertEqual(MusicPlayerScrubState.accessibilityTarget(currentTime: 2, duration: 120, delta: -5), 0)
        XCTAssertEqual(MusicPlayerScrubState.accessibilityTarget(currentTime: 118, duration: 120, delta: 5), 120)
        XCTAssertNil(MusicPlayerScrubState.accessibilityTarget(currentTime: 0, duration: 0, delta: 5))
        XCTAssertNil(MusicPlayerScrubState.accessibilityTarget(currentTime: .nan, duration: 120, delta: 5))
        XCTAssertNil(MusicPlayerScrubState.accessibilityTarget(currentTime: 10, duration: .infinity, delta: 5))
    }

    func testPositiveOffsetAdvancesLyricsAndTapUsesInverseMapping() {
        let lyrics = YingxiaMusicLyrics(lines: [
            YingxiaLyricLine(time: 10, text: "第一行", translation: "First line"),
            YingxiaLyricLine(time: 20, text: "第二行", translation: nil)
        ], synced: true)
        XCTAssertNil(lyrics.index(at: MusicLyricsTiming.lyricTime(currentTime: 9, offset: 0)))
        XCTAssertEqual(lyrics.index(at: MusicLyricsTiming.lyricTime(currentTime: 9.5, offset: 0.5)), 0)
        XCTAssertEqual(MusicLyricsTiming.seekTime(lineTime: 10, offset: 0.5), 9.5)
        XCTAssertEqual(MusicLyricsTiming.seekTime(lineTime: 10, offset: -0.5), 10.5)
    }

    func testNegativeLyricClockDoesNotPrematurelyHighlightFirstLine() {
        let lyrics = YingxiaMusicLyrics(lines: [
            YingxiaLyricLine(time: 0, text: "第一行", translation: nil)
        ], synced: true)
        XCTAssertNil(lyrics.index(at: MusicLyricsTiming.lyricTime(currentTime: 0, offset: -0.5)))
        XCTAssertEqual(MusicLyricsTiming.seekTime(lineTime: 0, offset: 10), 0)
        XCTAssertEqual(MusicLyricsTiming.seekTime(lineTime: 0, offset: -10), 10)
        XCTAssertEqual(MusicLyricsTiming.offsetRange, -10.0...10.0)
        XCTAssertEqual(MusicLyricsTiming.offsetStep, 0.5)
    }

    func testQualityOnlyChangeRefreshesSameURLAndTrack() {
        var original = MediaHubLibraryItem(sourceID: "fixture", siteKey: "music", videoID: "1",
            title: "测试歌曲", poster: "", kind: .music, siteName: "Fixture",
            musicURL: "https://fixture.invalid/audio.mp3")
        original.musicQuality = "128k"
        var updated = original
        updated.musicQuality = "320k"
        XCTAssertTrue(MusicPlayerView.shouldReplace(current: original, with: updated, hasError: false))
        XCTAssertFalse(MusicPlayerView.shouldReplace(current: original, with: original, hasError: false))
        updated.musicQuality = nil
        XCTAssertTrue(MusicPlayerView.shouldReplace(current: original, with: updated, hasError: false))
    }
}
