import XCTest
import UIKit

/// DEBUG-only, explicitly local layout fixtures. These tests never assert a
/// successful live provider request, login, playable URL or network result.
final class CodaProviderSearchUITests: XCTestCase {
    private let platforms = [
        (id: "netease", title: "网易云音乐"),
        (id: "qq", title: "QQ 音乐"),
        (id: "kugou", title: "酷狗音乐"),
        (id: "qishui", title: "汽水音乐")
    ]

    @MainActor
    func testFixedNativeHeaderAndFourPlatformChips() throws {
        let app = try launchMusicSearch()
        defer { app.terminate() }
        let field = app.textFields["codaSearch.keyword"].firstMatch
        let header = element("codaSearch.header", in: app)
        let results = element("codaSearch.resultsScroll", in: app)
        XCTAssertTrue(header.exists)
        XCTAssertTrue(app.navigationBars["搜索"].exists, app.debugDescription)
        XCTAssertTrue(app.buttons["codaSearch.settings"].isHittable)
        XCTAssertTrue(element("codaSearch.category", in: app).exists)
        XCTAssertTrue(app.buttons["codaSearch.scope.all"].exists)
        for platform in platforms {
            revealScope(platform.id, in: app)
            let chip = app.buttons["codaSearch.scope.\(platform.id)"].firstMatch
            XCTAssertEqual(chip.label, platform.title)
        }
        revealScope("all", in: app)
        app.buttons["codaSearch.scope.all"].tap()
        XCTAssertEqual(app.buttons["codaSearch.scope.all"].value as? String, "已选择")
        XCTAssertTrue(element("codaSearch.scopeExplanation", in: app).label.contains("仅搜索单曲"))
        XCTAssertFalse(results.descendants(matching: .any)["codaSearch.keyword"].exists,
                       "Keyword field must be outside the scrolling result body")

        field.tap()
        field.typeText("Coda local UI fixture\n")
        XCTAssertTrue(element("codaSearch.localFixture", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(element("codaSearch.localFixture", in: app).label.contains("非网络结果"))
        let before = field.frame
        results.swipeUp()
        results.swipeUp()
        XCTAssertTrue(field.isHittable, app.debugDescription)
        XCTAssertEqual(field.frame.minY, before.minY, accuracy: 2,
                       "Search field scrolled with results")
        XCTAssertEqual(field.frame.height, before.height, accuracy: 2)
        XCTAssertTrue(header.isHittable)
        XCTAssertTrue(app.buttons["codaSearch.settings"].isHittable)
        XCTAssertTrue(app.buttons["mediaHub.close"].isHittable)
        XCTAssertFalse(app.buttons["rootTab.explore"].isHittable,
                       "Reading chrome must not overlap Coda")
        XCTAssertFalse(app.buttons["codaHost.legacySources"].exists)
    }

    @MainActor
    func testEachScopeShowsOnlyItsLabeledNativeSongPanel() throws {
        let app = try launchMusicSearch()
        defer { app.terminate() }
        let field = app.textFields["codaSearch.keyword"].firstMatch
        field.tap()
        field.typeText("Coda local UI fixture\n")
        XCTAssertTrue(element("codaSearch.localFixture", in: app).waitForExistence(timeout: 10))
        for platform in platforms {
            revealScope(platform.id, in: app)
            let chip = app.buttons["codaSearch.scope.\(platform.id)"].firstMatch
            chip.tap()
            let label = app.staticTexts["codaSearch.providerLabel.\(platform.id)"].firstMatch
            XCTAssertTrue(label.waitForExistence(timeout: 10), app.debugDescription)
            XCTAssertEqual(label.label, platform.title)
            XCTAssertEqual(chip.value as? String, "已选择")
            let panel = element("codaSearch.results.\(platform.id)", in: app)
            XCTAssertTrue(panel.exists, app.debugDescription)
            let switchButton = app.buttons["codaSearch.switchProvider.\(platform.id)"].firstMatch
            if platform.id == "netease" {
                XCTAssertFalse(switchButton.exists, "Active fixture source has no switch action")
                XCTAssertFalse(panel.isHittable, "Fixture rows must never be playable")
            } else {
                XCTAssertTrue(switchButton.exists, "Foreign source must offer explicit user switch")
                XCTAssertFalse(switchButton.isEnabled, "Offline fixture cannot activate a platform")
                XCTAssertTrue(app.staticTexts["切换到此平台后播放、收藏和查看详情"].exists)
                XCTAssertFalse(panel.isHittable, "Foreign native row/menu actions must be disabled")
            }
            // This text is supplied via MusicTrackPanel's native trailingText
            // slot on the track rows, not just the scope chip or section title.
            XCTAssertGreaterThan(panel.staticTexts.matching(
                NSPredicate(format: "label == %@", platform.title)).count, 0,
                "Every native result panel must expose its track source")
            for other in platforms where other.id != platform.id {
                XCTAssertFalse(element("codaSearch.results.\(other.id)", in: app).exists,
                               "Another provider's results leaked into \(platform.id)")
            }
            XCTAssertFalse(element("codaSearch.failure", in: app).exists)
            XCTAssertFalse(app.buttons["codaSearch.loadMore"].exists,
                           "Local layout fixtures must not claim real pagination")
        }
    }

    @MainActor
    func testEntityMenuIsLimitedToCurrentSingleProvider() throws {
        let app = try launchMusicSearch()
        defer { app.terminate() }
        let field = app.textFields["codaSearch.keyword"].firstMatch
        field.tap()
        field.typeText("Coda local UI fixture\n")
        XCTAssertTrue(element("codaSearch.localFixture", in: app).waitForExistence(timeout: 10))
        let category = element("codaSearch.category", in: app)
        category.tap()
        for title in ["歌手", "专辑", "歌单"] {
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.exists,
                           "Aggregate mode must not offer cross-provider entity IDs")
        }
        app.buttons.matching(NSPredicate(format: "label == %@", "单曲")).firstMatch.tap()

        revealScope("netease", in: app)
        app.buttons["codaSearch.scope.netease"].tap()
        XCTAssertTrue(app.staticTexts["codaSearch.providerLabel.netease"].waitForExistence(timeout: 10))
        category.tap()
        for title in ["歌手", "专辑", "歌单"] {
            let option = app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch
            XCTAssertTrue(option.exists, "Current provider must retain native \(title) search")
            XCTAssertTrue(option.isEnabled)
        }
        // Keep the selection on songs: this is a UI-only fixture, not a live
        // non-song endpoint test.
        app.buttons.matching(NSPredicate(format: "label == %@", "单曲")).firstMatch.tap()

        revealScope("qq", in: app)
        app.buttons["codaSearch.scope.qq"].tap()
        XCTAssertTrue(app.staticTexts["codaSearch.providerLabel.qq"].waitForExistence(timeout: 10))
        XCTAssertTrue(element("codaSearch.scopeExplanation", in: app).label.contains("当前平台为网易云音乐"),
                      "Scope changes must not mutate the active provider")
        category.tap()
        for title in ["歌手", "专辑", "歌单"] {
            XCTAssertFalse(app.buttons.matching(NSPredicate(format: "label == %@", title)).firstMatch.exists)
        }
        app.buttons.matching(NSPredicate(format: "label == %@", "单曲")).firstMatch.tap()
    }

    @MainActor
    func testSearchSettingsUsesNativeSimplifiedDestination() throws {
        let app = try launchMusicSearch()
        defer { app.terminate() }
        app.buttons["codaSearch.settings"].tap()
        XCTAssertTrue(element("settingsForm", in: app).waitForExistence(timeout: 10))
        XCTAssertTrue(app.navigationBars["设置"].exists)
        XCTAssertFalse(app.staticTexts["同步"].exists, "Sync remains a standalone destination")
        XCTAssertFalse(app.staticTexts["关于"].exists, "Embedded settings stay simplified")
        app.buttons["完成"].firstMatch.tap()
        XCTAssertTrue(app.textFields["codaSearch.keyword"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.buttons["mediaHub.close"].isHittable)
    }

    @MainActor
    private func launchMusicSearch() throws -> XCUIApplication {
        continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-no-official-modules",
            "-yd_source_disclaimer_accepted", "YES", "-debug-force-pro",
            "-disclaimer.acceptedVersion", "3",
            "-yd_root_tab_visible_ids", "(explore, bookshelf, settings, search)",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN",
            "-music.provider", "netease", "-coda-provider-search-ui-fixture"]
        app.launch()
        let reading = element("rootTab.explore", in: app)
        XCTAssertTrue(reading.waitForExistence(timeout: 30), app.debugDescription)
        reading.tap()
        if UIDevice.current.userInterfaceIdiom == .pad {
            let menu = app.buttons["rootTabMediaMenu.explore"].firstMatch
            XCTAssertTrue(menu.waitForExistence(timeout: 10), app.debugDescription)
            menu.tap()
        } else {
            reading.press(forDuration: 1)
        }
        let music = app.buttons["rootTabMedia.explore.music"].firstMatch
        XCTAssertTrue(music.waitForExistence(timeout: 5), app.debugDescription)
        music.tap()
        XCTAssertTrue(app.buttons["mediaHub.close"].firstMatch.waitForExistence(timeout: 20))
        let explore = app.buttons.matching(NSPredicate(format: "label == %@", "探索")).firstMatch
        XCTAssertTrue(explore.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(explore.isHittable)
        explore.tap()
        XCTAssertTrue(app.textFields["codaSearch.keyword"].firstMatch.waitForExistence(timeout: 10),
                      app.debugDescription)
        return app
    }

    @MainActor
    private func element(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)[id].firstMatch
    }

    @MainActor
    private func revealScope(_ id: String, in app: XCUIApplication) {
        let chip = app.buttons["codaSearch.scope.\(id)"].firstMatch
        let strip = element("codaSearch.providerChips", in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 5), app.debugDescription)
        for _ in 0..<5 where !chip.isHittable {
            if id == "all" || id == "netease" { strip.swipeRight() }
            else { strip.swipeLeft() }
        }
        XCTAssertTrue(chip.isHittable, "Provider chip not reachable: \(id); \(app.debugDescription)")
    }
}
