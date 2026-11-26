import UIKit
import XCTest

/// Visible toolbar fallback on wide iPads, plus the separate iPadOS 18+ sidebar gesture.
final class MediaTabToolbarUITests: XCTestCase {
    @MainActor
    func testWideLayoutOffersHomeAndLibraryMediaMenusWithoutReplacingRoots() throws {
        try withWideApp { app in
            choose("video", for: "explore", in: app)
            assertVisible("mediaHub.videoHome", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertReadingHome(in: app)
            assertGone("mediaHub.close", in: app)

            selectTab("bookshelf", in: app)
            assertVisible("home_options_menu", in: app)
            choose("video", for: "bookshelf", in: app)
            assertVisible("mediaHub.videoLibrary", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertVisible("home_options_menu", in: app)
            assertGone("mediaHub.close", in: app)
        }
    }

    @MainActor
    func testNativeSidebarLongPressOffersOnlyVideoMusicAndReading() throws {
        try XCTSkipIf(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 18,
                      "Native Tab context menus require iPadOS 18")
        try withWideApp { app in
            sidebarTab("explore", in: app).press(forDuration: 1.0)
            let exploreMenu = try nativeSidebarMenu(for: "explore", in: app)
            try XCTUnwrap(exploreMenu["影視"]).tap()
            assertVisible("mediaHub.videoHome", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertReadingHome(in: app)

            selectTab("bookshelf", in: app)
            assertVisible("home_options_menu", in: app)
            sidebarTab("bookshelf", in: app).press(forDuration: 1.0)
            let bookshelfMenu = try nativeSidebarMenu(for: "bookshelf", in: app)
            try XCTUnwrap(bookshelfMenu["音樂庫"]).tap()
            assertVisible("mediaHub.musicLibrary", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertVisible("home_options_menu", in: app)
        }
    }

    @MainActor
    func testMediaChoicesStayInMemoryAcrossTabsButResetOnRelaunch() throws {
        try withWideApp { app in
            choose("video", for: "explore", in: app)
            assertVisible("mediaHub.videoHome", in: app)
            selectTab("settings", in: app)
            assertVisible("settings.form", in: app)
            selectTab("explore", in: app)
            assertVisible("mediaHub.videoHome", in: app)

            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.state == .runningBackgroundSuspended)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            assertVisible("mediaHub.videoHome", in: app)

            // The roots keep independent in-memory routes, never saved preferences.
            selectTab("bookshelf", in: app)
            choose("music", for: "bookshelf", in: app)
            assertVisible("mediaHub.musicLibrary", in: app)
            selectTab("explore", in: app)
            assertVisible("mediaHub.videoHome", in: app)
            relaunch(app)
            assertReadingHome(in: app)
            assertGone("mediaHub.close", in: app)
            selectTab("bookshelf", in: app)
            assertVisible("home_options_menu", in: app)
            assertGone("mediaHub.musicLibrary", in: app)

            selectTab("explore", in: app)
            choose("music", for: "explore", in: app)
            assertVisible("mediaHub.musicHome", in: app)
            relaunch(app)
            assertReadingHome(in: app)
            assertGone("mediaHub.musicHome", in: app)
            choose("video", for: "explore", in: app)
            assertVisible("mediaHub.videoHome", in: app)
            choose("reading", for: "explore", in: app)
            assertReadingHome(in: app)
            assertGone("mediaHub.close", in: app)
            selectTab("bookshelf", in: app)
            choose("music", for: "bookshelf", in: app)
            assertVisible("mediaHub.musicLibrary", in: app)
            choose("reading", for: "bookshelf", in: app)
            assertVisible("home_options_menu", in: app)
            XCTAssertEqual(app.state, .runningForeground)
        }
    }

    @MainActor
    private func withWideApp(_ body: (XCUIApplication) throws -> Void) throws {
        try XCTSkipIf(UIDevice.current.userInterfaceIdiom != .pad, "Requires a wide iPad window")
        continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let device = XCUIDevice.shared
        let previousOrientation = device.orientation
        device.orientation = .landscapeLeft
        let app = XCUIApplication()
        // No media-content defaults arguments: those would mask the values under test.
        app.launchArguments = ["-onboarding.completed", "YES", "-debug-force-pro",
                               "-yd_root_tab_visible_ids", "(explore, bookshelf, library, settings, search)",
                               "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer {
            bestEffortRestoreReading(in: app)
            app.terminate()
            device.orientation = previousOrientation
        }
        // StoreKit reset does not clear UserDefaults. Reset both roots through actual UI once,
        // before the scenario, never between terminate/launch assertions.
        choose("reading", for: "explore", in: app)
        selectTab("bookshelf", in: app)
        choose("reading", for: "bookshelf", in: app)
        assertVisible("home_options_menu", in: app)
        selectTab("explore", in: app)
        assertReadingHome(in: app)
        try body(app)
    }

    private func tabMetadata(_ tab: String) -> (icon: String, title: String) {
        switch tab {
        case "explore": return ("safari.fill", "主页")
        case "bookshelf": return ("books.vertical.fill", "书架")
        case "settings": return ("gearshape.fill", "设置")
        default: preconditionFailure("Unexpected root tab: \(tab)")
        }
    }

    @MainActor
    private func sidebarTab(_ tab: String, in app: XCUIApplication) -> XCUIElement {
        let cell = app.cells.matching(identifier: tabMetadata(tab).icon).firstMatch
        if !cell.exists || !cell.isHittable {
            let toggle = app.buttons["ToggleSidebar"].firstMatch
            XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Missing native sidebar toggle: \(app.debugDescription)")
            XCTAssertTrue(toggle.isHittable)
            toggle.tap()
        }
        XCTAssertTrue(cell.waitForExistence(timeout: 20), "Missing sidebar Cell for \(tab): \(app.debugDescription)")
        XCTAssertTrue(cell.isHittable)
        return cell
    }

    @MainActor
    private func selectTab(_ tab: String, in app: XCUIApplication) {
        let nativeTab = app.tabBars.buttons[tabMetadata(tab).title].firstMatch
        if nativeTab.exists && nativeTab.isHittable { nativeTab.tap() }
        else { sidebarTab(tab, in: app).tap() }
    }

    @MainActor
    private func choose(_ kind: String, for tab: String, in app: XCUIApplication) {
        let menu = app.buttons["rootTabMediaMenu.\(tab)"].firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 20), "Missing visible \(tab) toolbar menu: \(app.debugDescription)")
        XCTAssertTrue(menu.isHittable)
        menu.tap()
        assertMenu(for: tab, in: app)
        app.buttons["rootTabMedia.\(tab).\(kind)"].firstMatch.tap()
    }

    @MainActor
    private func nativeSidebarMenu(for tab: String, in app: XCUIApplication) throws -> [String: XCUIElement] {
        let expectedLabels: [String]
        switch tab {
        case "explore": expectedLabels = ["影視", "音樂", "閱讀首頁"]
        case "bookshelf": expectedLabels = ["影視庫", "音樂庫", "閱讀書架"]
        default:
            XCTFail("Unexpected native media-menu root: \(tab)")
            return [:]
        }

        // Native Tab.contextMenu materializes as a sidebar CollectionView; its Button
        // accessibility identifiers are not surfaced by UIKit. Match the one container
        // whose complete descendant button-label set is exactly the three menu actions.
        let matches = app.collectionViews.allElementsBoundByIndex.filter { container in
            let buttons = container.buttons.allElementsBoundByIndex.filter { $0.exists }
            return buttons.count == expectedLabels.count
                && Set(buttons.map(\.label)) == Set(expectedLabels)
        }
        XCTAssertEqual(matches.count, 1,
                       "Expected one native sidebar menu collection with exactly \(expectedLabels): \(app.debugDescription)")
        let container = try XCTUnwrap(matches.first, "Native sidebar media-menu container was not unique")

        var items: [String: XCUIElement] = [:]
        for label in expectedLabels {
            let labeledButtons = container.buttons.matching(NSPredicate(format: "label == %@", label))
            XCTAssertEqual(labeledButtons.count, 1, "Expected one \(label) item in native menu")
            let button = labeledButtons.firstMatch
            XCTAssertTrue(button.exists, "Missing \(label) in native menu: \(container.debugDescription)")
            XCTAssertTrue(button.isHittable, "Native menu item \(label) is not hittable: \(container.debugDescription)")
            items[label] = button
        }

        // The exact three-label set excludes short drama and cross-root menu entries.
        XCTAssertFalse(container.buttons["短劇"].exists)
        XCTAssertFalse(container.buttons["短劇庫"].exists)
        let otherRoot = tab == "explore" ? "bookshelf" : "explore"
        XCTAssertFalse(app.buttons["rootTabMedia.\(otherRoot).video"].exists,
                       "Inactive root media items leaked into the native menu")
        return items
    }

    @MainActor
    private func assertMenu(for tab: String, in app: XCUIApplication) {
        for kind in ["video", "music", "reading"] {
            XCTAssertTrue(app.buttons["rootTabMedia.\(tab).\(kind)"].firstMatch.waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.buttons["rootTabMedia.\(tab).drama"].exists)
        let other = tab == "explore" ? "bookshelf" : "explore"
        XCTAssertFalse(app.buttons["rootTabMedia.\(other).video"].exists, "Inactive root leaked menu items")
    }

    @MainActor
    private func assertVisible(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let visible = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"), object: element)
        guard XCTWaiter.wait(for: [visible], timeout: 20) == .completed else {
            // Keep the exists+hittable assertion strict. Capture fresh AX state and a
            // screenshot so a later relaunch/menu obstruction can be distinguished from
            // a missing control without guessing at an application-side cause.
            let fresh = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
            let diagnostic = "state=\(app.state), exists=\(fresh.exists), hittable=\(fresh.isHittable), frame=\(fresh.frame), windows=\(app.windows.count)"
            let attachment = XCTAttachment(screenshot: app.screenshot())
            attachment.name = "visible-\(identifier)-timeout-diagnostic"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTFail("Missing visible \(identifier) (\(diagnostic)): \(app.debugDescription)")
            return
        }
    }

    @MainActor
    private func assertGone(_ identifier: String, in app: XCUIApplication) {
        let element = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 10), .completed,
                       "\(identifier) remained after returning to reading")
    }

    @MainActor
    private func assertReadingHome(in app: XCUIApplication) {
        assertVisible("explore.allTypes", in: app)
        assertVisible("explore.configurations", in: app)
    }

    @MainActor
    private func relaunch(_ app: XCUIApplication) {
        app.terminate()
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }

    /// Do not mask the original failure with teardown assertions; next setup also resets both.
    @MainActor
    private func bestEffortRestoreReading(in app: XCUIApplication) {
        guard app.state == .runningForeground else { return }
        for tab in ["explore", "bookshelf"] {
            let nativeTab = app.tabBars.buttons[tabMetadata(tab).title].firstMatch
            let cell = app.cells.matching(identifier: tabMetadata(tab).icon).firstMatch
            if nativeTab.exists && nativeTab.isHittable { nativeTab.tap() }
            else {
                if !cell.exists || !cell.isHittable {
                    let toggle = app.buttons["ToggleSidebar"].firstMatch
                    if toggle.exists && toggle.isHittable { toggle.tap() }
                }
                guard cell.exists && cell.isHittable else { continue }
                cell.tap()
            }
            let menu = app.buttons["rootTabMediaMenu.\(tab)"].firstMatch
            guard menu.waitForExistence(timeout: 3), menu.isHittable else { continue }
            menu.tap()
            let reading = app.buttons["rootTabMedia.\(tab).reading"].firstMatch
            if reading.waitForExistence(timeout: 3), reading.isHittable { reading.tap() }
        }
    }
}
