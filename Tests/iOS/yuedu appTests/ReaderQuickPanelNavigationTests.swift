import Foundation
import Testing
@testable import yuedu_app

@Suite("Reader quick-panel iOS 17 navigation handoff")
@MainActor
struct ReaderQuickPanelNavigationTests {
    @Test("All detailed settings on iOS 17 defer to the parent without pushing or changing detents")
    func legacyRoutes() {
        let routes: [ReaderQuickPanelRoute] = [.settings, .display, .spacing, .headerFooter,
                                              .decoration, .chapterTitleStyle, .commentBubble]
        for route in routes {
            let navigation = ReaderQuickPanelNavigation(osMajorVersion: 17)
            var next = DismissalSequencedPresentation<ReaderQuickPanelRoute>()
            var shown: ReaderQuickPanelRoute?
            navigation.select(route) { next.select($0) }
            #expect(navigation.settingsDestination == nil)
            #expect(navigation.isHandingOff)
            #expect(next.pendingRoute == route)
            #expect(shown == nil)
            shown = next.consumeAfterDismissal()
            #expect(shown == route)
            #expect(next.consumeAfterDismissal() == nil)
        }
    }

    @Test("Modern systems retain their existing in-sheet navigation for settings")
    func modernRoutes() {
        let navigation = ReaderQuickPanelNavigation(osMajorVersion: 18)
        var handoffs: [ReaderQuickPanelRoute] = []
        navigation.select(.headerFooter) { handoffs.append($0) }
        #expect(navigation.settingsDestination == .headerFooter)
        #expect(handoffs.isEmpty && !navigation.isHandingOff)
        navigation.settingsDestination = nil
        navigation.select(.chapterTitleStyle) { handoffs.append($0) }
        #expect(navigation.settingsDestination == .chapterTitleStyle)
        #expect(handoffs.isEmpty)
    }

    @Test("A rapid second tap cannot overwrite the pending destination; reopening permits a new request")
    func repeatedTapAndReopen() {
        let navigation = ReaderQuickPanelNavigation(osMajorVersion: 17)
        var handoffs: [ReaderQuickPanelRoute] = []
        navigation.select(.headerFooter) { handoffs.append($0) }
        navigation.select(.autoRead) { handoffs.append($0) }
        #expect(handoffs == [.headerFooter])
        navigation.appeared()
        navigation.select(.spacing) { handoffs.append($0) }
        #expect(handoffs == [.headerFooter, .spacing])
    }

    @Test("Modal tools still hand off on both legacy and modern systems")
    func externalRoutes() {
        for os in [17, 18, 27] {
            for route: ReaderQuickPanelRoute in [.tableOfContents, .bookmarks, .readingAloud, .autoRead,
                                                 .touchZoneEditor, .styleImporter(.chapterTitleStyle)] {
                let navigation = ReaderQuickPanelNavigation(osMajorVersion: os)
                var received: ReaderQuickPanelRoute?
                navigation.select(route) { received = $0 }
                #expect(received == route && navigation.settingsDestination == nil)
            }
        }
    }

    @Test("Geometry rejects invalid values and sub-point jitter; navigation never remeasures")
    func heightUpdates() {
        for bad: CGFloat in [.nan, .infinity, -.infinity, -1] {
            #expect(ReaderQuickPanelHeightPolicy.measurement(bad, replacing: 500, isRoot: true) == nil)
        }
        for next: CGFloat in [499.6, 500, 500.4] {
            #expect(ReaderQuickPanelHeightPolicy.measurement(next, replacing: 500, isRoot: true) == nil)
        }
        #expect(ReaderQuickPanelHeightPolicy.measurement(520.1, replacing: 500, isRoot: true) == 520)
        #expect(ReaderQuickPanelHeightPolicy.measurement(0, replacing: 500, isRoot: true, minimum: 1) == nil)
        #expect(ReaderQuickPanelHeightPolicy.measurement(0, replacing: 34, isRoot: true) == 0)
        #expect(ReaderQuickPanelHeightPolicy.measurement(800, replacing: 500, isRoot: false) == nil)
    }
}
