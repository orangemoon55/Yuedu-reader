import Foundation
import Testing
@testable import CodaCore

@Suite("Soft mist player poster geometry")
struct NowPlayingPosterLayoutTests {
    @Test(arguments: [CGSize(width: 272, height: 506), CGSize(width: 329, height: 717),
                      CGSize(width: 366, height: 810), CGSize(width: 960, height: 1024),
                      CGSize(width: 500, height: 320)])
    func reservesLiveControlsAndKeepsCoverInsideColumn(size: CGSize) {
        let layout = NowPlayingPosterLayout(width: size.width, height: size.height, controlsHeight: 250)
        #expect(layout.viewportHeight == max(0, size.height - 250))
        #expect(layout.coverSide.isFinite)
        #expect(layout.coverSide >= min(136, layout.contentWidth))
        #expect(layout.coverSide <= layout.contentWidth)
        #expect(layout.contentWidth <= 440)
    }

    @Test func shortViewportScrollsInsteadOfCollapsingArtwork() {
        let layout = NowPlayingPosterLayout(width: 272, height: 380, controlsHeight: 250)
        #expect(layout.coverSide == 136)
        #expect(layout.viewportHeight == 130)
        // The SwiftUI ScrollView owns overflow; the controls keep their height.
        #expect(layout.coverSide > layout.viewportHeight)
    }

    @Test func largeTypeLeavesRoomForReadableMetadata() {
        let layout = NowPlayingPosterLayout(width: 440, height: 1024, controlsHeight: 250,
                                            accessibilityText: true)
        #expect(layout.coverSide <= 192)
        #expect(layout.viewportHeight == 774)
    }

    @Test(arguments: [CGFloat.nan, CGFloat.infinity, -CGFloat.infinity, -100, 0])
    func transientInvalidSizesNeverLeakIntoSwiftUI(value: CGFloat) {
        let layout = NowPlayingPosterLayout(width: value, height: value, controlsHeight: value)
        #expect(layout.viewportHeight == 0)
        #expect(layout.coverSide == 0)
        #expect(layout.contentWidth == 0)
    }

    @Test func rightSwipeOpensAndLeftSwipeClosesOnly() {
        #expect(NowPlayingPortraitLyricsSwipe.targetVisibility(
            translation: CGSize(width: 56, height: 4), expanded: false) == true)
        #expect(NowPlayingPortraitLyricsSwipe.targetVisibility(
            translation: CGSize(width: -56, height: 4), expanded: true) == false)
        #expect(NowPlayingPortraitLyricsSwipe.targetVisibility(
            translation: CGSize(width: -100, height: 0), expanded: false) == nil)
        #expect(NowPlayingPortraitLyricsSwipe.targetVisibility(
            translation: CGSize(width: 100, height: 0), expanded: true) == nil)
    }

    @Test(arguments: [CGSize(width: 55, height: 0), CGSize(width: 0, height: 120),
                      CGSize(width: 70, height: 60), CGSize(width: 72, height: 40),
                      CGSize(width: .nan, height: 0), CGSize(width: 100, height: .infinity)])
    func shortVerticalDiagonalAndInvalidDragsDoNotToggle(translation: CGSize) {
        #expect(NowPlayingPortraitLyricsSwipe.targetVisibility(translation: translation, expanded: false) == nil)
        #expect(NowPlayingPortraitLyricsSwipe.targetVisibility(translation: translation, expanded: true) == nil)
    }

    @Test func previewIsBoundedButFullLyricsRetainEveryLine() {
        #expect(NowPlayingPortraitLyricWindow.indices(count: 0, focus: nil, expanded: false).isEmpty)
        #expect(NowPlayingPortraitLyricWindow.indices(count: 2, focus: -9, expanded: false) == 0..<2)
        #expect(NowPlayingPortraitLyricWindow.indices(count: 20, focus: 10, expanded: false) == 9..<13)
        #expect(NowPlayingPortraitLyricWindow.indices(count: 20, focus: 99, expanded: false) == 16..<20)
        #expect(NowPlayingPortraitLyricWindow.indices(count: 20, focus: 10, expanded: true) == 0..<20)
    }

    @Test(arguments: [CGSize(width: 272, height: 506), CGSize(width: 345, height: 759),
                      CGSize(width: 382, height: 844)])
    func persistentPosterControlsReserveTheSameSpaceAtLargeType(size: CGSize) {
        let standard = NowPlayingPosterLayout(width: size.width, height: size.height, controlsHeight: 250)
        let largeType = NowPlayingPosterLayout(width: size.width, height: size.height, controlsHeight: 250,
                                               accessibilityText: true)
        #expect(standard.viewportHeight == largeType.viewportHeight)
        #expect(largeType.viewportHeight >= 0)
    }

    @Test func oversizedControlsLeaveANonnegativeScrollViewport() {
        let layout = NowPlayingPosterLayout(width: 320, height: 100, controlsHeight: 500)
        #expect(layout.viewportHeight == 0)
        #expect(layout.coverSide == 136)
    }
}
