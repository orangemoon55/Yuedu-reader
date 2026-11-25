import UIKit
import XCTest

/// Run on a full-width iPad simulator on iPadOS 17 and a newer OS with top tabs.
/// This checks a visible native Menu, not an unsupported top-tab long-press gesture.
final class MediaTabToolbarUITests: XCTestCase {
    @MainActor
    func testWideLayoutOffersHomeAndLibraryMediaMenusWithoutReplacingRoots() throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Requires a full-width iPad window")
        continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let device = XCUIDevice.shared
        let previousOrientation = device.orientation
        device.orientation = .landscapeLeft
        defer { device.orientation = previousOrientation }
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-debug-force-pro",
                               "-yd_root_tab_visible_ids", "(explore, bookshelf, library, settings, search)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }

        let homeMenu = app.buttons["rootTabMediaMenu.explore"].firstMatch
        XCTAssertTrue(homeMenu.waitForExistence(timeout: 20), "Home toolbar menu is missing: \(app.debugDescription)")
        XCTAssertTrue(homeMenu.isHittable)
        homeMenu.tap()
        let video = app.buttons["rootTabMedia.explore.video"].firstMatch
        XCTAssertTrue(video.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rootTabMedia.explore.music"].exists)
        XCTAssertTrue(app.buttons["rootTabMedia.explore.drama"].exists)
        video.tap()
        let close = app.buttons["mediaHub.close"].firstMatch
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Video menu did not route to the media hub")
        close.tap()
        XCTAssertTrue(homeMenu.waitForExistence(timeout: 10))
        XCTAssertFalse(close.exists, "Closing media must restore the existing home, not leave a media replacement")

        let shelfTab = app.tabBars.buttons["书架"].firstMatch
        if shelfTab.exists { shelfTab.tap() }
        else { app.buttons["书架"].firstMatch.tap() }
        XCTAssertTrue(app.buttons["home_options_menu"].firstMatch.waitForExistence(timeout: 10), "Original shelf is missing")
        let shelfMenu = app.buttons["rootTabMediaMenu.bookshelf"].firstMatch
        XCTAssertTrue(shelfMenu.waitForExistence(timeout: 10), "Shelf toolbar menu is missing")
        XCTAssertFalse(homeMenu.exists, "An inactive tab must not add its toolbar menu")
        shelfMenu.tap()
        let library = app.buttons["rootTabMedia.bookshelf.video"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["rootTabMedia.bookshelf.music"].exists)
        XCTAssertFalse(app.buttons["rootTabMedia.bookshelf.drama"].exists)
        library.tap()
        XCTAssertTrue(close.waitForExistence(timeout: 10), "Library menu did not route to the media library")
        close.tap()
        XCTAssertTrue(app.buttons["home_options_menu"].firstMatch.waitForExistence(timeout: 10), "Original shelf did not return")
    }
}
