import XCTest

/// Reproduces the uploaded recording: long-press Home while video is visible,
/// choose Music, then alternate without killing the menu's presentation host.
final class MediaMenuCrashUITests: XCTestCase {
    @MainActor
    func testRepeatedVideoMusicContextMenuSwitchKeepsProcessAlive() throws {
        continueAfterFailure = false
        _ = try StoreKitTestSessions.fresh(StoreKitTestSessions.yueduPro())
        let app = XCUIApplication()
        app.launchArguments = ["-onboarding.completed", "YES", "-no-official-modules",
            "-yd_source_disclaimer_accepted", "YES", "-debug-force-pro",
            "-yd_root_tab_visible_ids", "(explore, bookshelf, settings, search)",
            "-readcc.mediaHub.homeContent.v1", "video",
            "-readcc.mediaHub.bookshelfContent.v1", "",
            "-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let home = app.buttons.matching(NSPredicate(
            format: "identifier == %@ OR label == %@", "rootTab.explore", "主页")).firstMatch
        guard home.waitForExistence(timeout: 30) else {
            XCTFail("Missing floating Home: \(app.debugDescription)"); return
        }
        XCTAssertTrue(visible("mediaHub.videoHome", app).waitForExistence(timeout: 20))
        for cycle in 0..<5 {
            for kind in ["music", "video"] {
                XCTAssertTrue(home.isHittable, app.debugDescription)
                home.press(forDuration: 1.0)
                let item = app.buttons["rootTabMedia.explore.\(kind)"].firstMatch
                XCTAssertTrue(item.waitForExistence(timeout: 5), app.debugDescription)
                item.tap()
                XCTAssertTrue(visible("mediaHub.\(kind)Home", app).waitForExistence(timeout: 20),
                              "Cycle \(cycle), \(kind): \(app.debugDescription)")
                XCTAssertEqual(app.state, .runningForeground, "Menu route switch terminated the process")
            }
        }
        home.press(forDuration: 1.0)
        app.buttons["rootTabMedia.explore.music"].firstMatch.tap()
        XCTAssertTrue(visible("mediaHub.musicHome", app).waitForExistence(timeout: 20))
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = "music-home-after-repeated-context-menu-switch"
        shot.lifetime = .keepAlways
        add(shot)
        app.terminate()
    }

    @MainActor private func visible(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }
}
