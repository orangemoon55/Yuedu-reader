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
    private func launch(bookCount: Int = 12, alternate: Bool = false) throws -> XCUIApplication {
        let names = ["月票榜單", "榜單", "男頻", "女頻", "出版"]
        let categories: [[String: String]] = try names.enumerated().map { index, name in
            let answer: [String: Any] = ["books": (1...bookCount).map { number in
                ["name": "分類\(index)-作品\(number)", "author": "測試作者", "kind": "小說 · 連載中",
                 "intro": "測試簡介：這一行應在作者下方。", "cover": "", "url": "https://discovery.fixture/\(index)/\(number)"]
            }]
            let data = try JSONSerialization.data(withJSONObject: answer)
            return ["title": name, "url": "data:application/json;base64," + data.base64EncodedString()]
        }
        let filters: [[String: Any]] = [
            ["title": "性別", "type": "select", "chars": ["男頻", "女頻"], "default": "男頻"],
            ["title": "模式", "type": "select", "chars": ["小說", "漫畫"], "default": "小說"],
            ["title": "段評圖標", "type": "select", "chars": ["開啟", "關閉"], "default": "開啟"]
        ]
        let categoryData = try JSONSerialization.data(withJSONObject: categories.map { $0 as [String: Any] } + filters)
        let searchRules = ["bookList": "$.books[*]", "name": "$.name", "author": "$.author", "bookUrl": "$.url"]
        func offlineSearch(_ host: String, title: String) throws -> String {
            let body = ["books": [["name": title, "author": "Test author", "url": "\(host)/matched"]]]
            return "data:application/json;base64," + (try JSONSerialization.data(withJSONObject: body)).base64EncodedString()
        }
        let source: [String: Any] = [
            "id": "D413D0C1-0C00-4C00-8000-123456789012", "bookSourceName": "五分類離線測試",
            "bookSourceUrl": "https://discovery.fixture", "enabled": true, "enabledExplore": true,
            "bookSourceType": 0, "loginUrl": "https://discovery.fixture/login",
            "searchUrl": try offlineSearch("https://discovery.fixture", title: "Witness A"), "ruleSearch": searchRules,
            "exploreUrl": String(decoding: categoryData, as: UTF8.self),
            "ruleExplore": ["bookList": "$.books[*]", "name": "$.name", "author": "$.author",
                            "bookUrl": "$.url", "coverUrl": "$.cover", "kind": "$.kind", "intro": "$.intro"]
        ]
        let sources = directory.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let alternateCategories = try ["B-Short", "B-Wuxia"].map { title in
            let feed = ["books": [["name": "\(title)-book", "author": "B author", "kind": "小說",
                                   "cover": "", "url": "https://other.fixture/\(title)"]]]
            let data = try JSONSerialization.data(withJSONObject: feed)
            return ["title": title, "url": "data:application/json;base64," + data.base64EncodedString()]
        }
        let alternateData = try JSONSerialization.data(withJSONObject: alternateCategories)
        let other: [String: Any] = [
            "id": "D413D0C1-0C00-4C00-8000-123456789013", "bookSourceName": "另一來源",
            "bookSourceUrl": "https://other.fixture", "enabled": true, "enabledExplore": alternate, "bookSourceType": 0,
            "exploreUrl": String(decoding: alternateData, as: UTF8.self),
            "searchUrl": try offlineSearch("https://other.fixture", title: "Witness B"), "ruleSearch": searchRules,
            "ruleExplore": source["ruleExplore"]!
        ]
        try JSONSerialization.data(withJSONObject: [source, other]).write(to: sources.appendingPathComponent("book_sources.json"))
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
    private func openSearch(_ app: XCUIApplication) {
        // The iOS 27.3 tree exposes the grouped floating-tab identifier on its
        // container; its actual Button still exposes the localized title.
        let tab = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "rootTab.search", "搜索"
        )).firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 20), app.debugDescription)
        tab.tap()
    }

    @MainActor
    func testSearchFeedUsesCompactRankRows() throws {
        let app = try launch()
        openSearch(app)
        let first = app.buttons["discovery.book.0"].firstMatch
        let second = app.buttons["discovery.book.1"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(second.waitForExistence(timeout: 10), app.debugDescription)
        let stride = second.frame.minY - first.frame.minY
        XCTAssertGreaterThan(stride, 90, "Keep space for the 78pt cover and vertical padding")
        XCTAssertLessThan(stride, 104, "Do not use the old 108pt cover plus row padding")
        XCTAssertTrue(first.label.contains("測試簡介"), first.label)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "native-search-compact-rank-rows"
        image.lifetime = .keepAlways
        add(image)
    }

    @MainActor
    func testSearchListDoesNotReturnToFirstBookAfterRepeatedUpwardScrolls() throws {
        let app = try launch(bookCount: 48)
        openSearch(app)
        let list = app.scrollViews["discovery.bookList"].firstMatch
        XCTAssertTrue(list.waitForExistence(timeout: 20), app.debugDescription)
        let first = app.buttons["discovery.book.0"].firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 20), app.debugDescription)
        let filters = app.scrollViews["discovery.source.filters"].firstMatch
        XCTAssertTrue(filters.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThanOrEqual(filters.frame.height, 64, "Horizontal filters must not absorb the feed height")
        for id in ["discovery.source.more", "discovery.category.change"] {
            let control = app.buttons[id].firstMatch
            XCTAssertTrue(control.exists, app.debugDescription)
            XCTAssertLessThanOrEqual(control.frame.maxY, filters.frame.minY + 1,
                                     "The filter row must not overlap \(id)")
        }
        let firstCategory = app.buttons["discovery.category.slot.0"].firstMatch
        XCTAssertTrue(firstCategory.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThanOrEqual(app.buttons["discovery.category.change"].frame.maxY, firstCategory.frame.minY + 1)
        XCTAssertLessThanOrEqual(firstCategory.frame.maxY, filters.frame.minY + 1)
        assertActualFilterBounds(app)
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

    /// Compare the real menu targets with the category, not only the scroll view's outer frame.
    @MainActor
    private func assertActualFilterBounds(_ app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        let category = app.buttons["discovery.category.slot.0"].firstMatch
        let viewport = app.scrollViews["discovery.source.filters"].firstMatch
        XCTAssertTrue(category.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        XCTAssertTrue(viewport.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
        for id in ["性別", "模式"] {
            let chip = app.descendants(matching: .any)["discovery.source.filter.\(id)"].firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 10), app.debugDescription, file: file, line: line)
            let actual = chip.frame
            XCTAssertGreaterThan(actual.height, 16, "The chip must be visible, not just clipped away", file: file, line: line)
            XCTAssertGreaterThanOrEqual(actual.minY, category.frame.maxY + 1, "\(id) overlaps the category", file: file, line: line)
            XCTAssertGreaterThanOrEqual(actual.minY + 1, viewport.frame.minY, file: file, line: line)
            XCTAssertLessThanOrEqual(actual.maxY, viewport.frame.maxY + 1, file: file, line: line)
        }
    }

    @MainActor
    func testAggregateFiltersStayBelowCategoriesWithAndWithoutKeyboard() throws {
        let app = try launch()
        openSearch(app)
        assertActualFilterBounds(app)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "native-aggregate-category-filter-spacing"
        attachment.lifetime = .keepAlways
        add(attachment)
        let entry = app.textFields["search.keywordField"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 10), app.debugDescription)
        entry.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        assertActualFilterBounds(app)
    }

    @MainActor
    func testTopFieldSubmitsCurrentSourceQueryWithoutSecondEntry() throws {
        let app = try launch(alternate: true)
        openSearch(app)
        let switcher = app.buttons["discovery.category.change"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 20), app.debugDescription)
        switcher.tap()
        let source = app.buttons["discovery.source.choose.https://other.fixture"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 10), app.debugDescription)
        source.tap()

        let entry = app.textFields["search.keywordField"].firstMatch
        XCTAssertTrue(entry.waitForExistence(timeout: 20), app.debugDescription)
        let ready = expectation(for: NSPredicate(format: "enabled == true"), evaluatedWith: entry)
        wait(for: [ready], timeout: 10)
        entry.tap()
        entry.typeText("  Witness  ")
        XCTAssertTrue(entry.exists, "Tapping the field must not navigate to a second empty search form")
        XCTAssertFalse(app.searchFields.firstMatch.exists)
        let keyboardSearch = app.keyboards.buttons["搜索"].firstMatch
        if keyboardSearch.exists { keyboardSearch.tap() } else { entry.typeText("\n") }

        let result = app.staticTexts["Witness B"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertFalse(app.staticTexts["Witness A"].exists, "Do not query the other imported source")
        XCTAssertEqual(app.searchFields.firstMatch.value as? String, "Witness")
        let scope = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "已选 1 个来源配置")).firstMatch
        XCTAssertTrue(scope.exists, app.debugDescription)
    }

    @MainActor
    func testSwitchSourceReplacesEntireCategoryRowAndRestoresSelection() throws {
        let app = try launch(alternate: true)
        openSearch(app)
        let switcher = app.buttons["discovery.category.change"].firstMatch
        XCTAssertTrue(switcher.waitForExistence(timeout: 20), app.debugDescription)
        func pick(_ url: String) {
            switcher.tap()
            let bar = app.navigationBars["来源配置"].firstMatch
            XCTAssertTrue(bar.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertFalse(bar.buttons["设置五个分类"].exists)
            let source = app.buttons["discovery.source.choose.\(url)"].firstMatch
            XCTAssertTrue(source.waitForExistence(timeout: 10), app.debugDescription)
            source.tap()
        }
        func expectBook(_ title: String) {
            let first = app.buttons["discovery.book.0"].firstMatch
            wait(for: [expectation(for: NSPredicate(format: "label CONTAINS %@", title), evaluatedWith: first)], timeout: 20)
        }
        let firstCategory = app.buttons["discovery.category.slot.0"].firstMatch
        let thirdCategory = app.buttons["discovery.category.slot.2"].firstMatch
        pick("https://discovery.fixture")
        XCTAssertTrue(thirdCategory.waitForExistence(timeout: 20), app.debugDescription)
        thirdCategory.tap()
        expectBook("分類2-作品1")

        pick("https://other.fixture")
        expectBook("B-Short-book")
        XCTAssertEqual(firstCategory.label, "B-Short")
        XCTAssertEqual(app.buttons["discovery.category.slot.1"].firstMatch.label, "B-Wuxia")
        XCTAssertFalse(thirdCategory.exists, "The old source must not fill empty slots")
        XCTAssertLessThanOrEqual(switcher.frame.maxY, firstCategory.frame.minY + 1)
        app.buttons["discovery.category.slot.1"].firstMatch.tap()
        expectBook("B-Wuxia-book")

        pick("https://discovery.fixture")
        expectBook("分類2-作品1")
        XCTAssertTrue(thirdCategory.isSelected)
    }

    @MainActor
    func testFiveGlassCategoriesSwitchActualListsAndRestoreBottomSearch() throws {
        let app = try launch()
        XCTAssertTrue(app.buttons["explore.more"].waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertFalse(app.buttons["discovery.category.slot.0"].exists, "Discovery must keep its original HomePage")
        openSearch(app)
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
        XCTAssertTrue(app.buttons["发现页设置"].waitForExistence(timeout: 5), app.debugDescription)
        XCTAssertTrue(app.buttons["登录"].exists, app.debugDescription)
        XCTAssertFalse(app.buttons["所有类型"].exists)
        XCTAssertFalse(app.buttons["源内搜索"].exists)
        app.buttons["发现页设置"].tap()
        let settings = app.navigationBars["发现页设置"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 10), app.debugDescription)
        settings.buttons["关闭"].firstMatch.tap()
        app.buttons["rootTab.explore"].tap()
        XCTAssertTrue(app.buttons["explore.more"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["discovery.category.slot.0"].exists)
    }
}
