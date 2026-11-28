import XCTest
import UIKit

/// Embedded chrome is intentionally custom even on iOS 26. Recommendation
/// long press presents a reading menu; only choosing 阅读 returns to Bookshelf.
/// Wide-iPad sidebar uses the same recommendation-only reading context menu.
final class CodaBottomBarUITests: XCTestCase {
    @MainActor func testHomeMusicOwnsItsTabBarAndReturnsToReading() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone coverage") }
        try CodaRecommendationFlow.verify(test: self, root: "explore", iPad: false)
    }
    @MainActor func testLibraryMusicOwnsItsTabBarAndReturnsToShelf() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else { throw XCTSkip("iPhone coverage") }
        try CodaRecommendationFlow.verify(test: self, root: "bookshelf", iPad: false)
    }
}

final class CodaIPadNavigationUITests: XCTestCase {
    @MainActor func testIPadHomeMusicSettingsSyncAndReturnToReadingThreeCycles() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad coverage") }
        try CodaRecommendationFlow.verify(test: self, root: "explore", iPad: true)
    }
    @MainActor func testIPadLibraryMusicSettingsSyncAndReturnToShelfThreeCycles() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else { throw XCTSkip("iPad coverage") }
        try CodaRecommendationFlow.verify(test: self, root: "bookshelf", iPad: true)
    }
}

@MainActor
private enum CodaRecommendationFlow {
    private static func assertHittable(_ element: XCUIElement, app: XCUIApplication,
                                       timeout: TimeInterval = 10,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let ready = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: timeout), .completed,
                       app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isHittable, app.debugDescription, file: file, line: line)
    }

    private static func assertSelected(_ element: XCUIElement, app: XCUIApplication,
                                       file: StaticString = #filePath, line: UInt = #line) {
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "selected == true"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                       app.debugDescription, file: file, line: line)
        XCTAssertTrue(element.isSelected, app.debugDescription, file: file, line: line)
    }

    private static func tapTab(_ tab: String, app: XCUIApplication) {
        let control = app.buttons["codaTab.\(tab)"].firstMatch
        assertHittable(control, app: app)
        control.tap()
        assertSelected(control, app: app)
        for other in ["home", "search", "library"] where other != tab {
            let sibling = app.buttons["codaTab.\(other)"].firstMatch
            assertHittable(sibling, app: app)
            XCTAssertFalse(sibling.isSelected, "Only the tapped Coda tab may be selected")
        }
    }

    private static func assertHostChromeHidden(_ app: XCUIApplication) {
        for id in ["rootTab.explore", "rootTab.bookshelf", "rootTab.settings", "rootTab.search"] {
            XCTAssertFalse(app.buttons[id].firstMatch.isHittable, "Host chrome overlaps Coda")
        }
    }

    private static func readingAction(_ app: XCUIApplication) -> XCUIElement {
        app.buttons["codaTab.reading"].firstMatch
    }

    private static func verifyBottomTabContacts(_ app: XCUIApplication) {
        let home = app.buttons["codaTab.home"].firstMatch
        let reading = readingAction(app)
        XCTAssertFalse(reading.exists, "An ordinary tab tap must not open the reading menu")
        for tab in ["search", "library", "home"] {
            tapTab(tab, app: app)
            XCTAssertFalse(reading.exists, "Ordinary taps select tabs, never the menu")
            assertHostChromeHidden(app)
        }

        // Neither non-recommendation item may show the menu or return to the host.
        for tab in ["search", "library"] {
            tapTab("home", app: app)
            let other = app.buttons["codaTab.\(tab)"].firstMatch
            assertHittable(other, app: app)
            other.press(forDuration: 0.85)
            XCTAssertFalse(reading.exists, "Only recommendation owns a reading context menu")
            assertHittable(home, app: app)
            assertHostChromeHidden(app)
            // A native Button may activate on release; the very next ordinary tap must work.
            tapTab(tab, app: app)
            tapTab("home", app: app)
        }

        // Long pressing an UNSELECTED recommendation must not select it or return.
        tapTab("search", app: app)
        home.press(forDuration: 0.85)
        assertHittable(reading, app: app)
        XCTAssertEqual(reading.label, "阅读")
        XCTAssertTrue(app.buttons["codaTab.search"].firstMatch.isSelected)
        XCTAssertFalse(home.isSelected, "Presenting the context menu must not activate recommendation")
        assertHostChromeHidden(app)
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        let dismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: reading)
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed,
                       "Tapping outside must dismiss the native menu without returning")
        assertHittable(home, app: app)
        XCTAssertTrue(app.buttons["codaTab.search"].firstMatch.isSelected)
        assertHostChromeHidden(app)
        // No timer or per-contact suppression may swallow any post-menu tap/reselection.
        for tab in ["home", "home", "library", "search", "home"] {
            tapTab(tab, app: app)
            XCTAssertFalse(reading.exists)
        }
    }

    static func verify(test: XCTestCase, root: String, iPad: Bool) throws {
        test.continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-no-official-modules",
            "-yd_source_disclaimer_accepted", "YES", "-debug-force-pro",
            "-disclaimer.acceptedVersion", "3",
            "-yd_root_tab_visible_ids", "(explore, bookshelf, settings, search)",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        for cycle in 0..<3 {
            let origin = app.buttons["rootTab.\(root)"].firstMatch
            XCTAssertTrue(origin.waitForExistence(timeout: 30), app.debugDescription)
            origin.tap()
            let nativeMenu = app.buttons["rootTabMediaMenu.\(root)"].firstMatch
            if iPad && nativeMenu.exists && nativeMenu.isHittable { nativeMenu.tap() }
            else { origin.press(forDuration: 1) }
            let music = app.buttons["rootTabMedia.\(root).music"].firstMatch
            XCTAssertTrue(music.waitForExistence(timeout: 5), app.debugDescription)
            music.tap()
            let home = app.buttons["codaTab.home"].firstMatch
            XCTAssertTrue(home.waitForExistence(timeout: 20), app.debugDescription)
            assertHittable(home, app: app)
            home.tap()
            if !iPad {
                assertSelected(home, app: app)
                verifyBottomTabContacts(app)
            }
            XCTAssertTrue(app.buttons["codaHost.providerSwitcher"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.buttons["codaHost.settings"].exists, "Home must not regain its settings button")
            if !iPad { XCTAssertEqual(app.tabBars.count, 0, "Embedded iPhone always uses the matching custom capsule") }
            for id in ["rootTab.explore", "rootTab.bookshelf", "rootTab.settings", "rootTab.search"] {
                XCTAssertFalse(app.buttons[id].firstMatch.isHittable, "Host chrome overlaps Coda")
            }

            // Settings remains reachable away from the recommendation header.
            let sidebarSettings = app.buttons["sidebarSettingsButton"].firstMatch
            if sidebarSettings.exists && sidebarSettings.isHittable {
                sidebarSettings.tap()
                XCTAssertTrue(app.descendants(matching: .any)["settingsForm"].firstMatch.waitForExistence(timeout: 10))
                XCTAssertTrue(app.switches["settings.showLoginRequiredRecommendations"].firstMatch.exists)
                home.tap()
            } else {
                let mine = app.buttons["codaTab.library"].firstMatch
                XCTAssertTrue(mine.waitForExistence(timeout: 10))
                assertHittable(mine, app: app)
                mine.press(forDuration: 0.85)
                assertHittable(home, app: app)
                XCTAssertFalse(readingAction(app).exists, "Holding a non-recommendation item must not offer reading")
                mine.tap()
                assertSelected(mine, app: app)
                let settings = app.navigationBars.buttons.matching(NSPredicate(format: "label == %@", "设置")).firstMatch
                XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
                settings.tap()
                let toggle = app.switches["settings.showLoginRequiredRecommendations"].firstMatch
                XCTAssertTrue(toggle.waitForExistence(timeout: 10))
                let initial = toggle.value as? String
                toggle.tap()
                XCTAssertNotEqual(toggle.value as? String, initial)
                app.buttons["完成"].firstMatch.tap()
                settings.tap()
                XCTAssertTrue(toggle.waitForExistence(timeout: 10))
                XCTAssertNotEqual(toggle.value as? String, initial, "Preference must survive settings recreation")
                toggle.tap() // Restore the original preference.
                app.buttons["完成"].firstMatch.tap()
                home.tap()
            }
            XCTAssertTrue(home.isHittable)
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "coda-recommendation-return-\(root)-\(cycle)"
            shot.lifetime = .keepAlways
            test.add(shot)
            home.press(forDuration: 0.85)
            let reading = readingAction(app)
            assertHittable(reading, app: app)
            XCTAssertEqual(reading.label, "阅读")
            assertHostChromeHidden(app)
            XCTAssertFalse(app.buttons["rootTab.bookshelf"].firstMatch.isHittable,
                           "Long press must present the menu, not immediately return")
            reading.tap()
            let shelf = app.buttons["rootTab.bookshelf"].firstMatch
            XCTAssertTrue(shelf.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(shelf.isHittable)
            let selected = XCTNSPredicateExpectation(predicate: NSPredicate(format: "selected == true"), object: shelf)
            XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed,
                           "Both music origins must return to Bookshelf")
            XCTAssertFalse(home.exists, "Dedicated return must clear the music route")
        }
    }
}
