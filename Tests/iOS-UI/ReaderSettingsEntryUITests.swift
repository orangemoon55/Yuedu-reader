import XCTest

/// Local TXT fixture: no book-source login, networking, or remote cover is needed.
final class ReaderSettingsEntryUITests: XCTestCase {
    private var directory: URL!
    private let title = "设置入口回归"

    override func setUpWithError() throws {
        continueAfterFailure = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReaderSettingsEntry-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let text = "第一章 测试\n\n" + String(repeating: "这是设置入口测试正文，用来确认进入页眉页脚页面后仍能返回阅读。\n", count: 80)
        try Data(text.utf8).write(to: directory.appendingPathComponent("\(title).txt"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        // The current floating bar exposes its ancestor identifier on child buttons;
        // prefer the stable identifier, then the actual localized button label.
        if id == "rootTab.bookshelf" {
            return app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, "书架")).firstMatch
        }
        if id == "rootTab.settings" {
            return app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", id, "设置")).firstMatch
        }
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    func testHeaderFooterAndFloatingNavigationStayResponsive() throws {
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        app.launchArguments = [
            "-no-official-modules", "-onboarding.completed", "YES", "-yd_source_disclaimer_accepted", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-auto-import-epub", directory.appendingPathComponent("\(title).txt").path,
            "-auto-import-title", title, "-book-source-store-dir", directory.appendingPathComponent("sources").path,
            "-bookLayoutIsGrid", "NO", "-bookshelfRingMode", "NO", "-qingyunRingDefaultBuild10", "YES",
            "-yd_scroll_mode", "NO", "-yd_page_turn_style", "滑動"
        ]
        app.launch()
        let shelf = element("rootTab.bookshelf", in: app)
        XCTAssertTrue(shelf.waitForExistence(timeout: 30), app.debugDescription)
        shelf.tap()
        let book = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title + "，")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30), app.debugDescription)
        book.tap()
        let content = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "这是设置入口测试正文")).firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 30), app.debugDescription)
        let floatingBar = element("rootTab.floatingBar", in: app)
        XCTAssertTrue(floatingBar.waitForNonExistence(timeout: 10), "Floating navigation must hide on the reader page")

        for cycle in 0..<3 {
            let settings = app.buttons["reader_tool_settings"].firstMatch
            if !settings.exists || !settings.isHittable {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
            settings.tap()
            let headerFooter = element("reader.quickTool.headerFooter", in: app)
            if !headerFooter.waitForExistence(timeout: 5) { app.swipeUp() }
            XCTAssertTrue(headerFooter.waitForExistence(timeout: 10), app.debugDescription)
            headerFooter.tap()
            let editor = element("reader.settings.headerFooter.editor", in: app)
            XCTAssertTrue(editor.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertTrue(editor.isHittable)
            let done = element("reader.settings.done", in: app)
            XCTAssertTrue(done.waitForExistence(timeout: 5), app.debugDescription)
            if cycle == 0 {
                let image = XCTAttachment(screenshot: app.screenshot())
                image.name = "header-footer-entry-responsive"
                image.lifetime = .keepAlways
                add(image)
            }
            done.tap()
            XCTAssertTrue(editor.waitForNonExistence(timeout: 10), "Completion must actually leave the settings page")
            // iOS 18+ returns to the quick panel; iOS 17 returns directly to reader.
            if headerFooter.exists { app.swipeDown() }
            XCTAssertTrue(headerFooter.waitForNonExistence(timeout: 10), app.debugDescription)
        }
        let back = app.buttons["reader_back_button"]
        if !back.exists || !back.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(back.waitForExistence(timeout: 5), app.debugDescription)
        back.tap()
        XCTAssertTrue(floatingBar.waitForExistence(timeout: 15), "Floating navigation must return after leaving reader")
        XCTAssertTrue(floatingBar.isHittable)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "floating-tabs-after-reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        let settingsTab = element("rootTab.settings", in: app)
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()
        XCTAssertTrue(settingsTab.isSelected)
        shelf.tap()
        XCTAssertTrue(book.waitForExistence(timeout: 10), "Switching tabs must keep the existing shelf and reader ownership")
    }
    @MainActor
    func testParagraphAlignmentBelowBottomAndPersists() throws {
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        app.launchArguments = [
            "-no-official-modules", "-onboarding.completed", "YES", "-yd_source_disclaimer_accepted", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-auto-import-epub", directory.appendingPathComponent("\(title).txt").path,
            "-auto-import-title", title, "-book-source-store-dir", directory.appendingPathComponent("sources").path,
            "-bookLayoutIsGrid", "NO", "-bookshelfRingMode", "NO", "-qingyunRingDefaultBuild10", "YES",
            "-yd_scroll_mode", "NO", "-yd_page_turn_style", "滑動"
        ]
        app.launch()
        let shelf = element("rootTab.bookshelf", in: app)
        XCTAssertTrue(shelf.waitForExistence(timeout: 30), app.debugDescription)
        shelf.tap()
        let book = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", title + "，")).firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 30), app.debugDescription)
        book.tap()
        let readerSettings = app.buttons["reader_tool_settings"].firstMatch
        if !readerSettings.waitForExistence(timeout: 10) || !readerSettings.isHittable {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(readerSettings.waitForExistence(timeout: 15), app.debugDescription)
        readerSettings.tap()
        let spacing = element("reader.quickTool.spacing", in: app)
        for _ in 0..<5 where !spacing.isHittable { app.swipeUp() }
        XCTAssertTrue(spacing.waitForExistence(timeout: 10), app.debugDescription)
        spacing.tap()
        let picker = app.segmentedControls["reader.textAlignment"].firstMatch
        for _ in 0..<8 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(picker.waitForExistence(timeout: 10), app.debugDescription)
        let bottom = element("reader.bottomJustify", in: app)
        XCTAssertTrue(bottom.exists, app.debugDescription)
        XCTAssertGreaterThan(picker.frame.minY, bottom.frame.minY)
        let natural = picker.buttons["自然对齐"].firstMatch
        let justified = picker.buttons["两端对齐"].firstMatch
        XCTAssertTrue(natural.exists && justified.exists, app.debugDescription)
        natural.tap()
        XCTAssertTrue(natural.isSelected)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "paragraph-alignment-below-bottom-natural"
        shot.lifetime = .keepAlways
        add(shot)
        justified.tap()
        XCTAssertTrue(justified.isSelected)
        natural.tap()
        element("reader.settings.done", in: app).tap()
        // Enter the same page again: the setting is not a local preview-only value.
        if !spacing.waitForExistence(timeout: 3) {
            if !readerSettings.isHittable {
                app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            readerSettings.tap()
        }
        for _ in 0..<5 where !spacing.isHittable { app.swipeUp() }
        spacing.tap()
        for _ in 0..<8 where !picker.isHittable { app.swipeUp() }
        XCTAssertTrue(natural.isSelected, app.debugDescription)
    }

}
