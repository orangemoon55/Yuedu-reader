import AVFoundation
import XCTest
@testable import DeckHarness

/// Host-only integration tests of the iOS deck adapter, using muted playback.
/// The harness compiles the same sources; no iPad test runner is involved.
@MainActor
final class DeckTests: XCTestCase {
    func testMalformedStreamDurationDoesNotReplaceCatalogTimeline() {
        // Screenshot regression: 1:36 elapsed plus 1621:36 remaining.
        XCTAssertNil(AudioPlaybackDeck.validatedDuration(97_392, referenceDuration: 273))
        for invalid in [Double.nan, .infinity, -.infinity, 0, -1] {
            XCTAssertNil(AudioPlaybackDeck.validatedDuration(invalid, referenceDuration: 273))
        }
        XCTAssertEqual(AudioPlaybackDeck.validatedDuration(274.2, referenceDuration: 273), 274.2)
        XCTAssertEqual(AudioPlaybackDeck.validatedDuration(30, referenceDuration: 273), 30)
        XCTAssertEqual(AudioPlaybackDeck.validatedDuration(7_200, referenceDuration: 7_200), 7_200)
        XCTAssertEqual(AudioPlaybackDeck.validatedDuration(274, referenceDuration: 0), 274)
    }

    private func fixture(_ name: String, _ ext: String) -> URL {
        Bundle.module.url(forResource: name, withExtension: ext, subdirectory: "Fixtures")!
    }

    private func waitUntil(_ condition: () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }

    private func load(_ deck: AudioPlaybackDeck, at seconds: Double = 0) async -> Bool {
        var result: Bool?
        let task = Task { result = await deck.load(fixture("audio", "flac"), startAt: seconds) }
        let finished = await waitUntil { result != nil }
        if !finished { deck.clear() }
        await task.value
        return finished && result == true
    }

    func testPausedLoadAndSeekUseDecodedPosition() async {
        let deck = AudioPlaybackDeck()
        deck.volume = 0
        defer { deck.clear() }
        let loaded = await load(deck, at: 1.325)
        XCTAssertTrue(loaded)
        XCTAssertEqual(deck.state, .paused)
        XCTAssertEqual(deck.rate, 0)
        XCTAssertEqual(deck.currentPlaybackTime ?? -1, 1.325, accuracy: 0.03)
        var completed = false
        deck.onSeekCompleted = { completed = true }
        deck.seek(to: 4.125)
        XCTAssertNil(deck.currentPlaybackTime)
        let settled = await waitUntil { completed }
        XCTAssertTrue(settled)
        XCTAssertEqual(deck.state, .paused)
        XCTAssertEqual(deck.currentPlaybackTime ?? -1, 4.125, accuracy: 0.03)
    }

    func testRapidSeeksSettleOnLastTarget() async {
        let deck = AudioPlaybackDeck()
        deck.volume = 0
        defer { deck.clear() }
        let loaded = await load(deck)
        XCTAssertTrue(loaded)
        var completed = false
        deck.onSeekCompleted = { completed = true }
        for target in [4.125, 1.325, 5.425, 0, 2.437] { deck.seek(to: target) }
        let settled = await waitUntil { completed }
        XCTAssertTrue(settled)
        XCTAssertEqual(deck.currentPlaybackTime ?? -1, 2.437, accuracy: 0.03)
    }

    func testClearingDuringLoadDiscardsOldSource() async {
        let deck = AudioPlaybackDeck()
        deck.volume = 0
        defer { deck.clear() }
        let old = Task { await deck.load(fixture("vbr", "mp3"), startAt: 4) }
        await Task.yield()
        deck.clear()
        let loaded = await load(deck, at: 1.325)
        let discarded = await old.value
        XCTAssertFalse(discarded)
        XCTAssertTrue(loaded)
        XCTAssertEqual(deck.currentPlaybackTime ?? -1, 1.325, accuracy: 0.03)
    }

    /// Quick track changes: each load replaces the player while the old one
    /// may still be starting its output on a background queue.
    func testRapidTrackChangesReleasePlayersSafely() async {
        let deck = AudioPlaybackDeck()
        deck.volume = 0
        defer { deck.clear() }
        let sources = [fixture("audio", "flac"), fixture("cbr", "mp3"),
                       fixture("vbr", "mp3"), fixture("audio", "m4a")]
        var pending: [Task<Bool, Never>] = []
        for round in 0..<40 {
            let source = sources[round % sources.count]
            pending.append(Task { await deck.load(source, startAt: Double(round % 3), autoplay: true) })
            try? await Task.sleep(for: .milliseconds([0, 1, 5, 20, 60][round % 5]))
        }
        let loaded = await load(deck, at: 1)
        for task in pending { _ = await task.value }
        XCTAssertTrue(loaded)
        XCTAssertEqual(deck.currentPlaybackTime ?? -1, 1, accuracy: 0.03)
    }

    func testPauseFreezesClockAndResumeAdvancesIt() async {
        let deck = AudioPlaybackDeck()
        deck.volume = 0
        defer { deck.clear() }
        let loaded = await load(deck, at: 1)
        XCTAssertTrue(loaded)
        let paused = deck.currentPlaybackTime ?? -1
        try? await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(deck.currentPlaybackTime ?? -1, paused, accuracy: 0.001)
        deck.play()
        let advanced = await waitUntil { (deck.currentPlaybackTime ?? 0) > paused + 0.1 }
        XCTAssertTrue(advanced)
        deck.pause()
        XCTAssertEqual(deck.rate, 0)
    }
}
