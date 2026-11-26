import XCTest

/// Exercises both long-press roots through repeated video/music route replacement,
/// then relaunches to prove the menu choice was only transient state.
final class MediaMenuCrashUITests: XCTestCase {
    @MainActor
    func testRepeatedVideoMusicContextMenuSwitchKeepsProcessAliveAndDoesNotPersist() throws {
        continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        let baseArguments = ["-onboarding.completed", "YES", "-no-official-modules",
            "-yd_source_disclaimer_accepted", "YES", "-debug-force-pro",
            "-yd_root_tab_visible_ids", "(explore, bookshelf, settings, search)",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        // Simulate values left by the previous persistent implementation. They must be ignored.
        app.launchArguments = baseArguments + [
            "-readcc.mediaHub.homeContent.v1", "video",
            "-readcc.mediaHub.bookshelfContent.v1", "music"]
        app.launch()
        let home = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "rootTab.explore", "主页")).firstMatch
        let bookshelf = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "rootTab.bookshelf", "书架")).firstMatch
        guard home.waitForExistence(timeout: 30) else {
            XCTFail("Missing floating Home: \(app.debugDescription)"); return
        }
        XCTAssertFalse(visible("mediaHub.videoHome", app).waitForExistence(timeout: 3),
                       "A legacy saved Home destination must not be restored")
        XCTAssertFalse(visible("mediaHub.musicLibrary", app).exists,
                       "A legacy saved Library destination must not be restored")

        for cycle in 0..<5 {
            for kind in ["music", "video"] {
                XCTAssertTrue(home.isHittable, app.debugDescription)
                home.press(forDuration: 1.0)
                let item = app.buttons["rootTabMedia.explore.\(kind)"].firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
                item.tap()
                XCTAssertTrue(visible("mediaHub.\(kind)Home", app).waitForExistence(timeout: 20),
                              "Home cycle \(cycle), \(kind): \(app.debugDescription)")
                XCTAssertEqual(app.state, .runningForeground, "Home route switch terminated the process")
            }
        }

        XCTAssertTrue(bookshelf.waitForExistence(timeout: 10), app.debugDescription)
        bookshelf.tap()
        XCTAssertFalse(visible("mediaHub.musicLibrary", app).waitForExistence(timeout: 3),
                       "A legacy Library value must be ignored when that root becomes visible")
        for cycle in 0..<3 {
            for kind in (cycle == 2 ? ["video", "music"] : ["music", "video"]) {
                XCTAssertTrue(bookshelf.isHittable, app.debugDescription)
                bookshelf.press(forDuration: 1.0)
                let item = app.buttons["rootTabMedia.bookshelf.\(kind)"].firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
                item.tap()
                let page = kind == "music" ? "mediaHub.musicLibrary" : "mediaHub.videoLibrary"
                XCTAssertTrue(visible(page, app).waitForExistence(timeout: 20),
                              "Library cycle \(cycle), \(kind): \(app.debugDescription)")
                XCTAssertEqual(app.state, .runningForeground, "Library route switch terminated the process")
            }
        }
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "media-library-after-repeated-context-menu-switches"
        shot.lifetime = .keepAlways
        add(shot)

        app.terminate()
        app.launchArguments = baseArguments
        app.launch()
        XCTAssertTrue(home.waitForExistence(timeout: 30), app.debugDescription)
        XCTAssertFalse(visible("mediaHub.videoHome", app).waitForExistence(timeout: 3),
                       "Home menu choice survived relaunch")
        XCTAssertTrue(bookshelf.waitForExistence(timeout: 10), app.debugDescription)
        bookshelf.tap()
        XCTAssertFalse(visible("mediaHub.musicLibrary", app).waitForExistence(timeout: 3),
                       "Library menu choice survived relaunch")
        XCTAssertEqual(app.state, .runningForeground, "App failed to relaunch on the reading root")
        app.terminate()
    }

    @MainActor private func visible(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
