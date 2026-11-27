import Testing
@testable import CodaCore

@MainActor
@Suite struct KaraokeGlyphVisualStateTests {
    private func timing(_ text: String = "字", duration: Double = 2) -> LyricTimingTextAttribute {
        TimedLyricTextBuilder.attributes(from: [
            LyricSyllable(text: text, startTime: 10, endTime: 10 + duration)
        ])[0]
    }

    @Test func noEarlyLightAndNoLingeringGlowAfterTheTail() {
        let word = timing()
        let before = KaraokeGlyphVisualState.state(timing: word, at: 9.9)
        #expect(before.reveal == 0)
        #expect(before.lift == 0)
        #expect(before.emphasis == 0)
        #expect(before.glow == 0)
        let finished = KaraokeGlyphVisualState.state(timing: word, at: 14)
        #expect(abs(finished.reveal - 1) < 0.000001)
        #expect(finished.lift == 1)
        #expect(finished.emphasis == 0)
        #expect(finished.glow == 0)
    }

    @Test func longNotesSwellAndShortNotesOnlyLift() {
        let long = KaraokeGlyphVisualState.state(timing: timing(), at: 11)
        #expect(long.emphasis > 0.5)
        #expect(long.glow > 0)
        #expect(long.lift > 0 && long.lift < 1)
        let short = KaraokeGlyphVisualState.state(timing: timing(duration: 0.3), at: 10.15)
        #expect(short.emphasis == 0)
        #expect(short.lift > 0)
        #expect(short.glow > 0)
    }

    @Test func backwardsSeekRestoresTheExactEarlierState() {
        let word = timing()
        let first = KaraokeGlyphVisualState.state(timing: word, at: 10.4)
        _ = KaraokeGlyphVisualState.state(timing: word, at: 11.8)
        let restored = KaraokeGlyphVisualState.state(timing: word, at: 10.4)
        #expect(first.reveal == restored.reveal)
        #expect(first.lift == restored.lift)
        #expect(first.emphasis == restored.emphasis)
        #expect(first.glow == restored.glow)
    }

    @Test func whitespaceDoesNotExpandOrGlow() {
        let state = KaraokeGlyphVisualState.state(timing: timing(" "), at: 11)
        #expect(state.emphasis == 0)
        #expect(state.glow == 0)
        #expect(state.lift == 0)
    }
}
