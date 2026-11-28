import Foundation
import Testing
@testable import CodaCore

@Suite("Embedded recommendation chrome regressions")
struct CodaEmbeddedUIRegressionTests {
    @Test func embeddedPhoneUsesCustomChromeEvenWhenNativeTabsAreAvailable() {
        for native in [false, true] {
            #expect(!CodaEmbeddedUIPolicy.usesNativePhoneTabs(embedded: true, nativeAvailable: native))
            #expect(CodaEmbeddedUIPolicy.usesNativePhoneTabs(embedded: false, nativeAvailable: native) == native)
        }
    }
    @Test func returnRequiresEmbeddedRecommendationAndDedicatedAction() {
        for embedded in [false, true] {
            for home in [false, true] {
                for action in [false, true] {
                    #expect(CodaEmbeddedUIPolicy.canReturnToBookshelf(embedded: embedded,
                        recommendation: home, hasAction: action) == (embedded && home && action))
                }
            }
        }
    }
    @Test func preferenceHidesOnlyGuestLikedSection() {
        for login in [false, true] {
            for show in [false, true] {
                #expect(CodaEmbeddedUIPolicy.showsLikedRecommendations(
                    loggedIn: login, showLoginRequired: show) == (login || show))
            }
        }
    }
    @Test func defaultHostMetricsImplementActualFourPointIncrease() {
        let metrics = ReadccTabBarMetrics()
        #expect(metrics.iconSize == 24)
        #expect(metrics.contentHeight == 52)
        #expect(metrics.height == 60)
        #expect(metrics.height - 56 == 4)
        #expect(ReadccTabBarMetrics(showsLabels: false).height == 60)
    }
    @Test func metricsPreserveCustomIconsAndScaledTwoLineText() {
        for icon: CGFloat in [20, 24, 28, 36] {
            for line: CGFloat in [15, 22, 36] {
                for accessibility in [false, true] {
                    let metrics = ReadccTabBarMetrics(iconSize: icon, labelLineHeight: line,
                                                     accessibilityText: accessibility)
                    #expect(metrics.iconSize == icon)
                    #expect(metrics.height == max(52, icon + line * (accessibility ? 2 : 1) + 6) + 8)
                }
            }
        }
        #expect(ReadccTabBarMetrics(iconSize: .nan, labelLineHeight: .infinity).height == 60)
    }
    @Test func stationaryHoldReturnsOnceAndNeverBecomesTapOrDrag() {
        var touch = CodaTabBarInteraction()
        touch.begin(index: 0)
        #expect(touch.recognizeHold(allowed: true))
        #expect(!touch.recognizeHold(allowed: true))
        touch.move(horizontal: 150, vertical: 0)
        #expect(!touch.isDragging)
        #expect(touch.finish(index: 1, inside: true) == .none)
        #expect(touch.startIndex == nil)
    }
    @Test func slowNineToSeventeenPointDragCanNeverReturnOrTap() {
        for distance: CGFloat in [8, 9, 12, 17] {
            var touch = CodaTabBarInteraction()
            touch.begin(index: 0)
            touch.move(horizontal: distance, vertical: 0)
            #expect(!touch.recognizeHold(allowed: true))
            #expect(touch.finish(index: 1, inside: true) == .drag(1))
        }
    }
    @Test func cancellationDoesNotSwallowTheNextTap() {
        var touch = CodaTabBarInteraction()
        touch.begin(index: 0)
        #expect(touch.recognizeHold(allowed: true))
        touch.cancel()
        touch.begin(index: 2)
        #expect(touch.finish(index: 2, inside: true) == .tap(2))
    }
    @Test func outsideAndVerticalMovementDoNotTapOrReturn() {
        var touch = CodaTabBarInteraction()
        touch.begin(index: 0)
        #expect(touch.finish(index: 0, inside: false) == .none)
        touch.begin(index: 0)
        touch.move(horizontal: 0, vertical: 9)
        #expect(!touch.recognizeHold(allowed: true))
        #expect(touch.finish(index: 0, inside: true) == .none)
        touch.begin(index: 1)
        #expect(!touch.recognizeHold(allowed: false))
        #expect(touch.finish(index: 1, inside: true) == .tap(1))
    }
}
