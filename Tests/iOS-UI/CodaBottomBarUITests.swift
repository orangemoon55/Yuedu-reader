import XCTest
import UIKit

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
            XCTAssertFalse(app.buttons["codaHost.legacySources"].exists)
            // The home owns settings/sync, the library keeps its original initial route.
            app.buttons.matching(NSPredicate(format: "label == %@", "推荐")).firstMatch.tap()
            let settings = app.buttons["codaHost.settings"].firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 10))
            settings.tap()
            XCTAssertTrue(app.descendants(matching: .any)["settingsForm"].firstMatch.waitForExistence(timeout: 10))
            XCTAssertFalse(app.staticTexts["同步"].exists, "Sync must be a separate native destination")
            XCTAssertFalse(app.staticTexts["关于"].exists, "Embedded settings must be simplified")
            app.buttons["完成"].firstMatch.tap()
            let sync = app.buttons["codaHost.sync"].firstMatch
            XCTAssertTrue(sync.waitForExistence(timeout: 10))
            sync.tap()
            XCTAssertTrue(app.navigationBars["同步"].waitForExistence(timeout: 10))
            app.buttons["完成"].firstMatch.tap()
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


/// Native iPad split-view coverage. The iPhone-only bottom-bar assertions above
/// intentionally remain separate: iPad Coda uses its own sidebar and detail toolbar.
final class CodaIPadNavigationUITests: XCTestCase {
    @MainActor
    func testIPadHomeMusicSettingsSyncAndReturnToReadingThreeCycles() throws {
        try verifyIPadMusicRoute(root: "explore", libraryRoot: false)
    }

    @MainActor
    func testIPadLibraryMusicSettingsSyncAndReturnToShelfThreeCycles() throws {
        try verifyIPadMusicRoute(root: "bookshelf", libraryRoot: true)
    }

    @MainActor
    private func verifyIPadMusicRoute(root: String, libraryRoot: Bool) throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This suite targets the native iPad sidebar/split view")
        }
        continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-no-official-modules",
            "-yd_source_disclaimer_accepted", "YES", "-debug-force-pro",
            "-disclaimer.acceptedVersion", "3",
            "-yd_root_tab_visible_ids", "(explore, bookshelf, settings, search)",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }

        let hostTab = app.descendants(matching: .any)["rootTab.\(root)"].firstMatch
        XCTAssertTrue(hostTab.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(hostTab.isHittable, "Readcc native iPad tab is unavailable")
        hostTab.tap()

        let hostMenu = app.buttons["rootTabMediaMenu.\(root)"].firstMatch
        for cycle in 0..<3 {
            XCTAssertTrue(hostTab.isHittable, "Readcc root unavailable before cycle \(cycle)")
            // Native TabContent context menus exist only when Readcc's sidebar is
            // expanded. The original toolbar Menu also works in native top-tab mode.
            XCTAssertTrue(hostMenu.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(hostMenu.isHittable, "Wrong Readcc root is active")
            hostMenu.tap()
            let music = app.buttons["rootTabMedia.\(root).music"].firstMatch
            XCTAssertTrue(music.waitForExistence(timeout: 5), app.debugDescription)
            music.tap()

            let close = app.buttons["mediaHub.close"].firstMatch
            XCTAssertTrue(close.waitForExistence(timeout: 20), app.debugDescription)
            XCTAssertTrue(close.isHittable, "Coda native return action is not reachable")
            for label in ["推荐", "探索", "账户"] {
                let sidebarItem = app.buttons.matching(NSPredicate(format: "label == %@", label)).firstMatch
                XCTAssertTrue(sidebarItem.waitForExistence(timeout: 10),
                              "Coda native sidebar item missing: \(label); \(app.debugDescription)")
                XCTAssertTrue(sidebarItem.isHittable, app.debugDescription)
            }
            XCTAssertFalse(app.buttons["codaHost.legacySources"].exists,
                           "Legacy host/JS header must not return")
            for id in ["rootTab.explore", "rootTab.bookshelf", "rootTab.settings", "rootTab.search"] {
                let hostItem = app.descendants(matching: .any)[id].firstMatch
                XCTAssertFalse(hostItem.isHittable,
                               "Readcc chrome overlaps Coda on iPad cycle \(cycle): \(app.debugDescription)")
            }

            // LibraryView keeps Coda's existing gear; HOME uses the explicit host
            // settings action owned by MainWindow's native iPad detail toolbar.
            let settings: XCUIElement
            if libraryRoot {
                settings = app.navigationBars.buttons.matching(
                    NSPredicate(format: "label == %@", "设置")
                ).firstMatch
            } else {
                settings = app.buttons["codaHost.settings"].firstMatch
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(settings.isHittable, app.debugDescription)
            settings.tap()
            XCTAssertTrue(app.descendants(matching: .any)["settingsForm"].firstMatch
                .waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(app.staticTexts["同步"].exists,
                           "Sync must be a separate native destination")
            XCTAssertFalse(app.staticTexts["关于"].exists,
                           "Embedded settings must omit About")
            app.buttons["完成"].firstMatch.tap()

            let sync = app.buttons["codaHost.sync"].firstMatch
            XCTAssertTrue(sync.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(sync.isHittable, app.debugDescription)
            sync.tap()
            XCTAssertTrue(app.navigationBars["同步"].waitForExistence(timeout: 10),
                          app.debugDescription)
            app.buttons["完成"].firstMatch.tap()
            let syncDismissed = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "exists == false"),
                object: app.navigationBars["同步"]
            )
            XCTAssertEqual(XCTWaiter.wait(for: [syncDismissed], timeout: 10), .completed,
                           "Native sync sheet must dismiss before inspecting Coda")
            XCTAssertTrue(close.isHittable, "Return action vanished after native sheets")
            let shot = XCTAttachment(screenshot: app.screenshot())
            shot.name = "coda-ipad-native-\(root)-\(cycle)"
            shot.lifetime = .keepAlways
            add(shot)

            close.tap()
            XCTAssertTrue(hostTab.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(hostTab.isHittable,
                          libraryRoot ? "Coda did not return to the Readcc shelf" :
                                        "Coda did not return to Readcc reading")
            XCTAssertFalse(close.exists, "Music route must close before the next cycle")
            XCTAssertTrue(hostMenu.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(hostMenu.isHittable, "Coda restored a different Readcc root")
            XCTAssertEqual(app.state, .runningForeground)
        }

        app.terminate()
        app.launch()
        let readingRoot = app.descendants(matching: .any)["rootTab.explore"].firstMatch
        XCTAssertTrue(readingRoot.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertTrue(readingRoot.isHittable, "Readcc root did not return after relaunch")
        XCTAssertFalse(app.buttons["mediaHub.close"].firstMatch.exists,
                       "Music presentation must remain transient after relaunch")
    }
}
