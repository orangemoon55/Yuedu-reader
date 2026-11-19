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
    private func launch() throws -> XCUIApplication {
        let names = ["巔峰", "榜單", "男頻", "女頻", "出版"]
        let categories: [[String: String]] = try names.enumerated().map { index, name in
            let answer: [String: Any] = ["books": (1...12).map { number in
                ["name": "分類\(index)-作品\(number)", "author": "測試作者", "kind": "小說 · 連載中",
                 "cover": "", "url": "https://discovery.fixture/\(index)/\(number)"]
            }]
            let data = try JSONSerialization.data(withJSONObject: answer)
            return ["title": name, "url": "data:application/json;base64," + data.base64EncodedString()]
        }
        let categoryData = try JSONSerialization.data(withJSONObject: categories)
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
        app.buttons["search.allTypes"].tap()
        XCTAssertTrue(app.navigationBars["所有类型"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(app.buttons["genres.fiction"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.staticTexts["暂无栏目"].exists)
        app.buttons["rootTab.explore"].tap()
        XCTAssertTrue(app.buttons["explore.more"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["discovery.category.slot.0"].exists)
    }
}
