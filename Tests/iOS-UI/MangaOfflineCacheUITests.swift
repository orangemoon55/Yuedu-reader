import XCTest

/// Real app touches, localhost JSON and colored PNGs only. Never a live book-source account.
final class MangaOfflineCacheUITests: XCTestCase {
    private var folder: URL!
    override func setUpWithError() throws {
        continueAfterFailure = false
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("manga-cache-ui-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: folder) }

    @MainActor
    func testCacheButtonOpensSelectionAndDownloadsSyntheticPages() throws {
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let host = "http://localhost:18779"
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let title = "Offline cache " + token
        let sources = folder.appendingPathComponent("sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let body: [String: Any] = ["books": [["name": title, "author": "Synthetic author", "url": host + "/book?t=" + token]]]
        let feed = "data:application/json;base64," + (try JSONSerialization.data(withJSONObject: body)).base64EncodedString()
        let categories = try JSONSerialization.data(withJSONObject: [["title": "离线漫画测试", "url": feed]])
        let source: [String: Any] = [
            "id": "81D72BDD-D2AD-4E00-A111-123456789001", "bookSourceName": "Offline Manga Fixture",
            "bookSourceUrl": host, "bookSourceType": 2, "enabled": true, "enabledExplore": true,
            "exploreUrl": String(decoding: categories, as: UTF8.self),
            "ruleExplore": ["bookList": "$.books[*]", "name": "$.name", "author": "$.author", "bookUrl": "$.url"],
            "ruleBookInfo": ["name": "$.name", "author": "$.author", "coverUrl": "$.cover", "tocUrl": "$.toc"],
            "ruleToc": ["chapterList": "$.chapters[*]", "chapterName": "$.title", "chapterUrl": "$.url"],
            "ruleContent": ["content": "$.content", "title": "$.title"],
            "lastUpdateTime": Int(Date().timeIntervalSince1970*1000)
        ]
        try JSONSerialization.data(withJSONObject: [source]).write(to: sources.appendingPathComponent("book_sources.json"))
        let home = folder.appendingPathComponent("home.json")
        try JSONSerialization.data(withJSONObject: ["schemaVersion": 3, "sections": [], "configurations": []]).write(to: home)
        let app = XCUIApplication()
        app.launchArguments = ["-no-official-modules", "-onboarding.completed", "YES", "-yd_source_disclaimer_accepted", "YES",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN", "-book-source-store-dir", sources.path,
            "-reset-explore-home", "-explore-home-file", home.path, "-reset-reading-settings",
            "-yd_discovery_five_categories.v1", "", "-yd_root_tab_visible_ids", "(explore,bookshelf,settings,search)"]
        app.launch()
        let search = app.buttons.matching(NSPredicate(format: "identifier == %@ OR label == %@", "rootTab.search", "搜索")).firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 25), app.debugDescription)
        search.tap()
        let row = app.buttons["discovery.book.0"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 25), app.debugDescription)
        row.tap()
        let addShelfButton = app.buttons["加入书架"].firstMatch
        XCTAssertTrue(addShelfButton.waitForExistence(timeout: 25), app.debugDescription)
        addShelfButton.tap()
        let shelved = app.buttons["从书架移除"].firstMatch
        XCTAssertTrue(shelved.waitForExistence(timeout: 20), app.debugDescription)
        let read = app.buttons.matching(NSPredicate(format: "label IN %@", ["继续阅读", "立即阅读"])).firstMatch
        XCTAssertTrue(read.waitForExistence(timeout: 15), app.debugDescription)
        read.tap()
        let cache = app.buttons["manga.offlineCache"].firstMatch
        if !cache.waitForExistence(timeout: 10) {
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        }
        XCTAssertTrue(cache.waitForExistence(timeout: 20), app.debugDescription)
        XCTAssertTrue(cache.isEnabled, app.debugDescription)
        cache.tap()
        let bar = app.navigationBars["下载章节"].firstMatch
        XCTAssertTrue(bar.waitForExistence(timeout: 15), app.debugDescription)
        let start = app.buttons["reader.offline.start"].firstMatch
        XCTAssertTrue(start.waitForExistence(timeout: 10), app.debugDescription)
        start.tap()
        XCTAssertTrue(app.staticTexts["下载完成"].firstMatch.waitForExistence(timeout: 35), app.debugDescription)
        XCTAssertTrue(app.staticTexts["2/2"].firstMatch.exists, app.debugDescription)
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "manga-offline-two-chapters-downloaded-through-real-toolbar"
        image.lifetime = .keepAlways
        self.add(image)
        app.buttons["reader.offline.close"].firstMatch.tap()
        XCTAssertTrue(cache.waitForExistence(timeout: 10), app.debugDescription)
    }
}
