import XCTest

/// Run on an iPhone: Coda's three destinations own the full-screen music UI.
/// The reading root must return unchanged, rather than leaving a second tab bar.
final class CodaBottomBarUITests: XCTestCase {
    @MainActor
    func testHomeMusicOwnsItsTabBarAndReturnsToReading() throws {
        try verifyMusicPresentation(from: "explore")
    }

    @MainActor
    func testLibraryMusicOwnsItsTabBarAndReturnsToShelf() throws {
        try verifyMusicPresentation(from: "bookshelf")
    }

    @MainActor
    private func verifyMusicPresentation(from root: String) throws {
        continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        // Fixture state only: do not alter production consent or account behavior.
        app.launchArguments = ["-onboarding.completed", "YES", "-no-official-modules",
            "-yd_source_disclaimer_accepted", "YES", "-debug-force-pro",
            "-disclaimer.acceptedVersion", "3",
            "-yd_root_tab_visible_ids", "(explore, bookshelf, settings, search)",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let hostTab = app.buttons["rootTab.\(root)"].firstMatch
        XCTAssertTrue(hostTab.waitForExistence(timeout: 30), app.debugDescription)
        hostTab.tap()

        for cycle in 0..<3 {
            XCTAssertTrue(hostTab.isHittable, "Reading root unavailable before cycle \(cycle)")
            hostTab.press(forDuration: 1)
            let music = app.buttons["rootTabMedia.\(root).music"].firstMatch
            XCTAssertTrue(music.waitForExistence(timeout: 5), app.debugDescription)
            music.tap()
            let close = app.buttons["mediaHub.close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
            for title in ["推荐", "探索", "我的"] {
                let tab = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
                XCTAssertTrue(tab.waitForExistence(timeout: 10), "Missing Coda \(title)")
                XCTAssertTrue(tab.isHittable, app.debugDescription)
            }
            for id in ["rootTab.explore", "rootTab.bookshelf", "rootTab.settings", "rootTab.search"] {
                XCTAssertFalse(app.buttons[id].firstMatch.isHittable,
                               "Readcc chrome overlaps Coda at cycle \(cycle): \(app.debugDescription)")
            }
            if #available(iOS 26.0, *) {
                XCTAssertEqual(app.tabBars.count, 1, "Only Coda's native tab bar may be exposed")
                XCTAssertEqual(app.tabBars.buttons.count, 3, "Readcc's items leaked into Coda")
            } else {
                XCTAssertEqual(app.tabBars.count, 0, "Coda's legacy bar must not expose Readcc's native bar")
            }
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "coda-single-bottom-bar-\(root)-\(cycle)"
            shot.lifetime = .keepAlways
            add(shot)
            close.tap()
            XCTAssertTrue(hostTab.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(hostTab.isHittable, "Returning from Coda did not restore reading")
            XCTAssertFalse(close.exists)
            XCTAssertEqual(app.state, .runningForeground)
        }
        app.terminate()
        app.launch()
        XCTAssertTrue(hostTab.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(hostTab.isHittable)
        XCTAssertFalse(app.buttons["mediaHub.close"].firstMatch.exists,
                       "Music presentation must remain transient after relaunch")
    }
}
