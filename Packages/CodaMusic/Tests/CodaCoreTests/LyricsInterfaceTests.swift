import CoreGraphics
import Testing
@testable import CodaCore

@Suite("Lyrics interface scrolling")
struct LyricsInterfaceTests {
    @Test func forwardBrowsingHidesAt200PointsAndReverseImmediatelyReveals() {
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: 120, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: 79, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: 1, hideThreshold: 200) == false)
        #expect(tracker.update(offsetDelta: 50, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: -0.5, hideThreshold: 200) == true)
    }

    @Test func changingDirectionResetsAccumulatedDistance() {
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: 150, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: -20, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: 150, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: 50, hideThreshold: 200) == false)
    }

    @Test func newGestureDoesNotInheritPreviousGestureDistance() {
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: 180, hideThreshold: 200) == nil)
        tracker.end()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: 30, hideThreshold: 200) == nil)
    }

    @Test func reverseScrollRestoresAnAutomaticallyHiddenInterface() {
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        tracker.begin(isInterfaceVisible: false)
        #expect(tracker.update(offsetDelta: 50, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: -1, hideThreshold: 200) == true)
        #expect(tracker.update(offsetDelta: -1, hideThreshold: 200) == nil)
    }

    @Test func invalidOrStationaryOffsetsDoNotChangeVisibility() {
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        tracker.begin(isInterfaceVisible: true)
        #expect(tracker.update(offsetDelta: .nan, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: .infinity, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: 0, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: 200, hideThreshold: .nan) == nil)
        #expect(tracker.update(offsetDelta: 199, hideThreshold: 200) == nil)
        #expect(tracker.update(offsetDelta: 1, hideThreshold: 200) == false)
    }
}
