import XCTest

/// Real touches to the production Discover page. The fixture is a local data-URI book source,
/// not a mocked view: category parsing, caching, book links and native navigation all execute.
final class DiscoveryFiveCategoryUITests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("discovery-glass-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    @MainActor
    private func launch(bookCount: Int = 12) throws -> XCUIApplication {
        let names = ["巔峰", "榜單", "男頻", "女頻", "出版"]
        let categories: [[String: String]] = try names.enumerated().map { index, name in
            let answer: [String: Any] = ["books": (1...bookCount).map { number in
                ["name": "分類\(index)-作品\(number)", "author": "測試作者", "kind": "小說 · 連載中",
                 "cover": "", "url": "https://discovery.fixture/\(index)/\(number)"]
            }]
            let data = try JSONSerialization.data(withJSONObject: answer)
            return ["title": name, "url": "data:application/json;base64," + data.base64EncodedString()]
        }
        let filters: [[String: Any]] = [
            ["title": "性別", "type": "select", "chars": ["男頻", "女頻"], "default": "男頻"],
            ["title": "模式", "type": "select", "chars": ["小說", "漫畫"], "default": "小說"]
        ]
        let categoryData = try JSONSerialization.data(withJSONObject: categories.map { $0 as [String: Any] } + filters)
        let source: [String: Any] = [
            "id": "D413D0C1-0C00-4C00-8000-123456789012", "bookSourceName": "五分類離線測試",
            "bookSourceUrl": "https://discovery.fixture", "enabled": true, "enabledExplore": true,
            "bookSourceType": 0, "exploreUrl": String(decoding: categoryData, as: UTF8.self),
            "ruleExplore": ["bookList": "$.books[*]", "name": "$.name", "author": "$.author",
                            "bookUrl": "$.url", "coverUrl": "$.cover", "kind": "$.kind"]
        ]
        let sources = directory.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        try JSONSerialization.data(withJSONObject: [source]).write(to: sources.appendingPathComponent("book_sources.json"))
        let home = directory.appendingPathComponent("home.json")
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "sections": [], "configurations": []]).write(to: home)
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-onboarding.completed", "YES", "-yd_source_disclaimer_accepted", "YES",
            "-book-source-store-dir", sources.path, "-reset-explore-home",
            "-explore-home-file", home.path,
            "-explore.mode", "sources", "-yd_discovery_five_categories.v1", "",
            "-yd_root_tab_visible_ids", "(explore,bookshelf,settings,search)", "-yd_root_tab_order_ids", "()"]
        app.launch()
        return app
    }

    @MainActor
    func testSearchListDoesNotReturnToFirstBookAfterRepeatedUpwardScrolls() throws {
        let app = try launch(bookCount: 48)
        XCTAssertTrue(app.buttons["rootTab.search"].waitForExistence(timeout: 15), app.debugDescription)
        app.buttons["rootTab.search"].tap()
        let list = app.scrollViews["discovery.bookList"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 20), app.debugDescription)
        let first = app.buttons["discovery.book.0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), app.debugDescription)
        let filters = app.scrollViews["discovery.source.filters"].firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThanOrEqual(filters.frame.height, 64, "Horizontal filters must not absorb the feed height")
        XCTAssertLessThanOrEqual(first.frame.minY - filters.frame.maxY, 32,
                                 "No blank spacer band between filters and first book")
        XCTAssertLessThanOrEqual(first.frame.minY - list.frame.minY, 32,
                                 "Nested scroll content must not add a second top safe-area gap")
        // Exercise real native inertia/layout, without tapping categories or pulling down.
        // Page 2 repeats this fixture's page 1: deduplication must stop pagination normally.
        for _ in 0..<5 { list.swipeUp(velocity: .slow) }
        XCTAssertFalse(first.isHittable, "Upward scrolling must not bring page 1 back to the top")
        let reset = expectation(for: NSPredicate { _, _ in first.isHittable }, evaluatedWith: app)
        reset.isInverted = true
        wait(for: [reset], timeout: 3)
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "search-list-after-repeated-scroll-no-reset"
        shot.lifetime = .keepAlways
        add(shot)
    }

    @MainActor
    func testSearchFieldReplacesTopIconsAndSubmitsOriginalQuery() throws {
        let app = try launch()
        app.buttons["rootTab.search"].tap()
        let field = app.textFields["search.keywordField"]
        XCTAssertTrue(field.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.buttons["search.keywordEntry"].exists)
        XCTAssertFalse(app.buttons["search.allTypes"].exists, "Types belongs in More, not the top toolbar")
        XCTAssertTrue(app.buttons["discovery.category.change"].exists)
        XCTAssertGreaterThanOrEqual(app.buttons["discovery.category.change"].frame.width, 44)
        XCTAssertGreaterThanOrEqual(app.buttons["discovery.category.change"].frame.height, 44)
        let header = XCTAttachment(screenshot: app.screenshot())
        header.name = "search-field-and-compact-controls"
        header.lifetime = .keepAlways
        add(header)
        field.tap()
        field.typeText("  回滚测试  ")
        app.keyboards.buttons["搜索"].tap()
        let originalSearch = app.searchFields.firstMatch
        XCTAssertTrue(originalSearch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertEqual(originalSearch.value as? String, "回滚测试")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        XCTAssertTrue(field.waitForExistence(timeout: 10), app.debugDescription)
    }

    @MainActor
    func testFiveGlassCategoriesSwitchActualListsAndRestoreBottomSearch() throws {
        let app = try launch()
        XCTAssertTrue(app.buttons["explore.more"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["discovery.category.slot.0"].exists, "Discovery must keep its original HomePage")
        app.buttons["rootTab.search"].tap()
        for index in 0..<5 {
            let button = app.buttons["discovery.category.slot.\(index)"]
            XCTAssertTrue(button.waitForExistence(timeout: 20), app.debugDescription)
            button.tap()
            let row = app.buttons["discovery.book.0"].firstMatch
            XCTAssertTrue(row.waitForExistence(timeout: 20), app.debugDescription)
            let shown = NSPredicate(format: "label CONTAINS %@", "分類\(index)-作品1")
            expectation(for: shown, evaluatedWith: row)
            waitForExpectations(timeout: 10)
            XCTAssertTrue(button.isSelected)
            XCTAssertGreaterThanOrEqual(button.frame.width, 44)
            XCTAssertGreaterThanOrEqual(button.frame.height, 44)
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "discovery-five-glass-categories-native"
        shot.lifetime = .keepAlways
        add(shot)
        XCTAssertFalse(app.buttons["explore.search"].exists)
        XCTAssertTrue(app.buttons["discovery.category.change"].exists)
        app.buttons["discovery.source.more"].tap()
        app.buttons["search.allTypes"].tap()
        XCTAssertTrue(app.navigationBars["所有类型"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["genres.fiction"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["暂无栏目"].exists)
        app.buttons["rootTab.explore"].tap()
        XCTAssertTrue(app.buttons["explore.more"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["discovery.category.slot.0"].exists)
    }
}
