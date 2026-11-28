import XCTest
import UIKit

/// Embedded chrome is intentionally custom even on iOS 26. The dedicated
/// recommendation hold returns to Bookshelf regardless of the entry root.
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
            home.tap()
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
                mine.press(forDuration: 0.85)
                XCTAssertTrue(home.exists, "Holding a non-recommendation item must not dismiss Coda")
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
