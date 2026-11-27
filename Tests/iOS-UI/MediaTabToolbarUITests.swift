import UIKit
import XCTest

/// Visible toolbar fallback on wide iPads, plus the separate iPadOS 18+ sidebar gesture.
final class MediaTabToolbarUITests: XCTestCase {
    @MainActor private var notificationInterruptionCount = 0

    @MainActor
    func testWideLayoutOffersHomeAndLibraryMediaMenusWithoutReplacingRoots() throws {
        try withWideApp { app in
            choose("music", for: "explore", in: app)
            assertVisible("mediaHub.musicHome", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertReadingHome(in: app)
            assertGone("mediaHub.close", in: app)

            selectTab("bookshelf", in: app)
            assertVisible("home_options_menu", in: app)
            choose("music", for: "bookshelf", in: app)
            assertVisible("mediaHub.musicLibrary", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertVisible("home_options_menu", in: app)
            assertGone("mediaHub.close", in: app)
        }
    }

    @MainActor
    func testNativeSidebarLongPressOffersOnlyMusicAndReading() throws {
        try XCTSkipIf(ProcessInfo.processInfo.operatingSystemVersion.majorVersion < 18,
                      "Native Tab context menus require iPadOS 18")
        try withWideApp { app in
            sidebarTab("explore", in: app).press(forDuration: 1.0)
            let exploreMenu = try nativeSidebarMenu(for: "explore", in: app)
            try XCTUnwrap(exploreMenu["音乐"]).tap()
            assertVisible("mediaHub.musicHome", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertReadingHome(in: app)

            selectTab("bookshelf", in: app)
            assertVisible("home_options_menu", in: app)
            sidebarTab("bookshelf", in: app).press(forDuration: 1.0)
            let bookshelfMenu = try nativeSidebarMenu(for: "bookshelf", in: app)
            try XCTUnwrap(bookshelfMenu["音乐库"]).tap()
            assertVisible("mediaHub.musicLibrary", in: app)
            app.buttons["mediaHub.close"].firstMatch.tap()
            assertVisible("home_options_menu", in: app)
        }
    }

    @MainActor
    func testMediaChoicesStayInMemoryAcrossTabsButResetOnRelaunch() throws {
        try withWideApp { app in
            choose("music", for: "explore", in: app)
            assertVisible("mediaHub.musicHome", in: app)
            selectTab("settings", in: app)
            assertVisible("settings.form", in: app)
            selectTab("explore", in: app)
            assertVisible("mediaHub.musicHome", in: app)

            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5) || app.state == .runningBackgroundSuspended)
            app.activate()
            XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
            assertVisible("mediaHub.musicHome", in: app)

            // The roots keep independent in-memory routes, never saved preferences.
            selectTab("bookshelf", in: app)
            choose("music", for: "bookshelf", in: app)
            assertVisible("mediaHub.musicLibrary", in: app)
            selectTab("explore", in: app)
            assertVisible("mediaHub.musicHome", in: app)
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
            choose("music", for: "explore", in: app)
            assertVisible("mediaHub.musicHome", in: app)
            choose("reading", for: "explore", in: app)
            assertReadingHome(in: app)
            assertGone("mediaHub.musicHome", in: app)
            assertGone("mediaHub.close", in: app)
            selectTab("bookshelf", in: app)
            choose("music", for: "bookshelf", in: app)
            assertVisible("mediaHub.musicLibrary", in: app)
            choose("reading", for: "bookshelf", in: app)
            assertVisible("home_options_menu", in: app)
            assertGone("mediaHub.musicLibrary", in: app)
            assertGone("mediaHub.close", in: app)
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
        notificationInterruptionCount = 0
        let notificationMonitor = addUIInterruptionMonitor(withDescription: "Readcc notification permission") { alert in
            self.handleNotificationPrompt(alert)
        }
        defer { removeUIInterruptionMonitor(notificationMonitor) }
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
        dismissPendingNotificationPrompt()
        // Start both in-memory routes in reading through the same UI used by the scenario;
        // never reset them between terminate/launch assertions.
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
        // A permission prompt can invalidate an already-open menu's activation point.
        // Retry only after our narrowly matched notification handler actually ran;
        // never retry an application failure or infer success from a hidden toolbar.
        for _ in 0..<2 {
            dismissPendingNotificationPrompt()
            let interruptionsBeforeTap = notificationInterruptionCount
            let action = app.buttons["rootTabMedia.\(tab).\(kind)"].firstMatch
            if !action.exists || !action.isHittable {
                let menu = app.buttons["rootTabMediaMenu.\(tab)"].firstMatch
                XCTAssertTrue(menu.waitForExistence(timeout: 20), "Missing visible \(tab) toolbar menu: \(app.debugDescription)")
                XCTAssertTrue(menu.isHittable)
                menu.tap()
            }
            dismissPendingNotificationPrompt()
            if notificationInterruptionCount != interruptionsBeforeTap { continue }
            assertMenu(for: tab, in: app)
            // Requery after interruption handling instead of reusing a pre-alert element.
            app.buttons["rootTabMedia.\(tab).\(kind)"].firstMatch.tap()
            dismissPendingNotificationPrompt()
            if notificationInterruptionCount == interruptionsBeforeTap { return }
        }
        XCTFail("Notification permission repeatedly interrupted \(tab)/\(kind): \(app.debugDescription)")
    }

    @MainActor
    @discardableResult
    private func handleNotificationPrompt(_ alert: XCUIElement) -> Bool {
        guard alert.exists else { return false }
        let title = alert.label.lowercased()
        guard title.contains("readcc"), title.contains("notification") || title.contains("通知") else { return false }
        let allow = alert.buttons.matching(NSPredicate(format: "label IN %@", ["Allow", "允许", "允許"])).firstMatch
        guard allow.exists, allow.isHittable else { return false }
        allow.tap()
        notificationInterruptionCount += 1
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: alert)
        let dismissed = XCTWaiter.wait(for: [gone], timeout: 5) == .completed
        XCTAssertTrue(dismissed, "Notification alert did not dismiss")
        return dismissed
    }

    @MainActor
    private func dismissPendingNotificationPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        _ = handleNotificationPrompt(springboard.alerts.firstMatch)
    }

    @MainActor
    private func nativeSidebarMenu(for tab: String, in app: XCUIApplication) throws -> [String: XCUIElement] {
        let expectedLabels: [String]
        switch tab {
        case "explore": expectedLabels = ["音乐", "阅读首页"]
        case "bookshelf": expectedLabels = ["音乐库", "阅读书架"]
        default:
            XCTFail("Unexpected native media-menu root: \(tab)")
            return [:]
        }

        // Native Tab.contextMenu materializes as a sidebar CollectionView; its Button
        // accessibility identifiers are not surfaced by UIKit. Match the one container
        // whose complete descendant button-label set is exactly the two menu actions.
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

        // The exact two-label set excludes film, short drama and cross-root menu entries.
        XCTAssertFalse(container.buttons["影视"].exists)
        XCTAssertFalse(container.buttons["影视库"].exists)
        XCTAssertFalse(container.buttons["短剧"].exists)
        XCTAssertFalse(container.buttons["短剧库"].exists)
        let otherRoot = tab == "explore" ? "bookshelf" : "explore"
        XCTAssertFalse(app.buttons["rootTabMedia.\(otherRoot).music"].exists,
                       "Inactive root media items leaked into the native menu")
        return items
    }

    @MainActor
    private func assertMenu(for tab: String, in app: XCUIApplication) {
        for kind in ["music", "reading"] {
            XCTAssertTrue(app.buttons["rootTabMedia.\(tab).\(kind)"].firstMatch.waitForExistence(timeout: 5))
        }
        XCTAssertFalse(app.buttons["rootTabMedia.\(tab).video"].exists)
        XCTAssertFalse(app.buttons["rootTabMedia.\(tab).drama"].exists)
        let other = tab == "explore" ? "bookshelf" : "explore"
        XCTAssertFalse(app.buttons["rootTabMedia.\(other).music"].exists, "Inactive root leaked menu items")
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
        guard XCTWaiter.wait(for: [gone], timeout: 10) == .completed else {
            let matches = app.descendants(matching: .any).matching(identifier: identifier).allElementsBoundByIndex
            let residue = matches.map { "exists=\($0.exists), hittable=\($0.isHittable), frame=\($0.frame)" }
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "reading-\(identifier)-residue"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            let hierarchy = XCTAttachment(string: "state=\(app.state), notificationsHandled=\(notificationInterruptionCount), matches=\(residue)\n\(app.debugDescription)\nSpringBoard alerts:\n\(XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.debugDescription)")
            hierarchy.name = "reading-\(identifier)-AX-residue"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            XCTFail("\(identifier) remained after returning to reading (must not exist): \(residue)")
            return
        }
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
        dismissPendingNotificationPrompt()
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
