import XCTest
import CoreFoundation

final class CodaIOSUITests: XCTestCase {
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testLegacyIPadPlayerSpacingAndDragToDismiss() throws {
        try requireLegacyIPad()
        if #available(iOS 18.0, *) { throw XCTSkip("This regression targets iPadOS 16/17.") }
        let app = XCUIApplication()
        // Also keeps the automatic update sheet from covering the player.
        app.launchEnvironment["CODA_PLAYER_TRANSITION_DIAGNOSTICS"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let open = app.buttons["iPadOpenNowPlaying"]
        XCTAssertTrue(open.waitForExistence(timeout: 20))
        XCTAssertFalse(open.label.contains("未在播放"), "Keep the device's restored track for this regression.")
        let originalPlayer = open.frame
        let handle = app.descendants(matching: .any)["nowPlayingDismissIndicator"].firstMatch

        for cycle in 0..<2 {
            open.tap()
            XCTAssertTrue(handle.waitForExistence(timeout: 5))
            func frame(_ id: String) -> CGRect {
                let element = app.descendants(matching: .any)[id].firstMatch
                XCTAssertTrue(element.waitForExistence(timeout: 5), id)
                return element.frame
            }
            let artwork = frame("splitPlayerArtwork")
            let left = frame("splitPlayerLeftFooter")
            let right = frame("splitPlayerRightFooter")
            XCTAssertGreaterThanOrEqual(artwork.minY - handle.frame.minY, 16)
            XCTAssertEqual(left.midY, right.midY, accuracy: 1,
                           "Both bottom button rows must share a horizontal center line.")
            print("PLAYER_SPLIT_LAYOUT artwork=\(artwork) handle=\(handle.frame) left=\(left) right=\(right)")
            attachScreen("Legacy iPad player aligned cycle \(cycle)")
            if cycle == 0 {
                for _ in 0..<2 {
                    let start = handle.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.2))
                    start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 35)),
                                withVelocity: .slow, thenHoldForDuration: 0.3)
                    XCTAssertTrue(handle.exists, "A short drag must keep the player open.")
                    let add = app.buttons["iPadAddToPlaylistButton"]
                    XCTAssertTrue(add.waitForExistence(timeout: 5))
                    add.tap()
                    let panel = app.descendants(matching: .any)["nowPlayingAddToPlaylist"].firstMatch
                    XCTAssertTrue(panel.waitForExistence(timeout: 5),
                                  "Player controls must still respond after each cancelled drag.")
                    app.buttons["关闭添加歌单"].tap()
                    let closed = XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "exists == false"), object: panel)
                    XCTAssertEqual(XCTWaiter.wait(for: [closed], timeout: 5), .completed)
                }
                attachScreen("Legacy iPad player after cancelled drag")
            }
            handle.tap()
            XCTAssertTrue(open.waitForExistence(timeout: 5))
            let restoredPlayer = open.frame
            XCTAssertEqual(originalPlayer.minY, restoredPlayer.minY, accuracy: 2)
            attachScreen("Legacy iPad browsing restored cycle \(cycle)")
        }
        XCUIDevice.shared.orientation = .portrait
        open.tap()
        XCTAssertTrue(handle.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any)["portraitNowPlaying"].firstMatch.exists)
        handle.tap()
        XCTAssertTrue(open.waitForExistence(timeout: 5))
        app.terminate()
    }

    @MainActor
    func testLegacyIPadSearchKeyboardKeepsContentVisible() throws {
        try requireLegacyIPad()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        var problems: [String] = []

        func record(_ name: String, field: XCUIElement? = nil) {
            attachScreen(name)
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = name + " accessibility"
            tree.lifetime = .keepAlways
            add(tree)
            guard let snapshot = try? app.snapshot() else { return }
            let dock = elementFrame("iPadPlayerDock", in: snapshot) ?? .zero
            let settings = app.buttons["sidebarSettingsButton"].frame
            let keyboard = app.keyboards.firstMatch
            let fieldFrame = field?.frame ?? .zero
            print("KEYBOARD_LAYOUT \(name) window=\(app.windows.firstMatch.frame) keyboard=\(keyboard.exists ? keyboard.frame : .zero) settings=\(settings) dock=\(dock) field=\(fieldFrame)")
            let sidebarTop = settings.minY - 8
            let headerID = field == nil ? "homeFeatureCards"
                : (field?.identifier == "likedSongsSearch" ? "playlistSearchBar" : "iPadSearchBar")
            if let header = elementFrame(headerID, in: snapshot), abs(header.minY - sidebarTop) > 1 {
                problems.append(name + ": content top does not align with sidebar")
                print("HEADER_ALIGNMENT \(headerID) header=\(header) sidebarTop=\(sidebarTop)")
            }
            if let field {
                if !field.isHittable || fieldFrame.minY < 20 {
                    problems.append(name + ": focused search is clipped or offscreen")
                }
                if keyboard.exists && fieldFrame.maxY > keyboard.frame.minY {
                    problems.append(name + ": focused search is behind the keyboard")
                }
                if dock.minY < fieldFrame.maxY {
                    problems.append(name + ": player overlaps search")
                }
            }
            if settings.minY < 20 {
                problems.append(name + ": sidebar moved above the status bar")
            }
        }

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            app.terminate()
            XCUIDevice.shared.orientation = orientation
            app.launch()
            XCTAssertTrue(app.buttons["sidebarSettingsButton"].waitForExistence(timeout: 15))
            record("Initial \(orientation.rawValue)")
            app.buttons["搜索"].firstMatch.tap()
            let search = app.textFields["搜索歌曲、歌手、专辑、歌单"]
            XCTAssertTrue(search.waitForExistence(timeout: 10))
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
            // Observe the settled result, including UIKit focus scrolling.
            _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                search.isHittable && search.frame.minY >= 20
            }, object: nil)], timeout: 3)
            record("Search focused \(orientation.rawValue)", field: search)
            if search.isHittable {
                search.typeText("Coda")
                record("Search typing \(orientation.rawValue)", field: search)
                search.typeText("\n")
                XCTAssertFalse(app.keyboards.firstMatch.exists)
                search.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            }
            app.buttons["推荐"].firstMatch.tap()
            let searchDismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !app.keyboards.firstMatch.exists
            }, object: nil)
            XCTAssertEqual(XCTWaiter.wait(for: [searchDismissed], timeout: 5), .completed)

            let liked = app.buttons["我喜欢的音乐"].firstMatch
            if liked.exists && liked.isHittable {
                liked.tap()
                let playlistSearch = app.textFields["likedSongsSearch"]
                XCTAssertTrue(playlistSearch.waitForExistence(timeout: 15))
                record("Liked before focus \(orientation.rawValue)")
                if playlistSearch.isHittable {
                    playlistSearch.tap()
                    XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10))
                    _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                        playlistSearch.isHittable && playlistSearch.frame.minY >= 20
                    }, object: nil)], timeout: 3)
                    record("Liked focused \(orientation.rawValue)", field: playlistSearch)
                    if playlistSearch.isHittable {
                        playlistSearch.typeText("Coda")
                        record("Liked typing \(orientation.rawValue)", field: playlistSearch)
                        playlistSearch.typeText("\n")
                        XCTAssertFalse(app.keyboards.firstMatch.exists)
                        playlistSearch.tap()
                        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                    }
                } else {
                    problems.append("Liked search is not reachable before focus")
                }
            }
            app.buttons["推荐"].firstMatch.tap()
            let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                !app.keyboards.firstMatch.exists
            }, object: nil)
            if XCTWaiter.wait(for: [dismissed], timeout: 5) != .completed {
                problems.append("Keyboard remains after sidebar navigation")
            }
            record("Home restored \(orientation.rawValue)")
        }
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    @MainActor
    func testLegacyIPadOtherPagesKeepChromeAndNavigation() throws {
        try requireLegacyIPad()
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].waitForExistence(timeout: 15))
        var problems: [String] = []

        func inspect(_ name: String, pushed: Bool = false) throws {
            attachScreen("Page " + name)
            let snapshot = try app.snapshot()
            let settings = app.buttons["sidebarSettingsButton"].frame
            let sidebarTop = settings.minY - 8
            let dock = elementFrame("iPadPlayerDock", in: snapshot) ?? .zero
            let header = elementFrame("musicLibraryHeader", in: snapshot)
                ?? elementFrame("accountPageHeader", in: snapshot)
            let back = elementFrame("iPadDestinationBackRow", in: snapshot)
            print("PAGE_LAYOUT \(name) sidebarTop=\(sidebarTop) dock=\(dock) header=\(String(describing: header)) back=\(String(describing: back))")
            if dock.height < 60 || !app.buttons["sidebarSettingsButton"].isHittable {
                problems.append(name + ": persistent chrome is missing")
            }
            if pushed {
                if let back {
                    if abs(back.minY - sidebarTop) > 1 { problems.append(name + ": back row top shifted") }
                    if let header, header.minY < back.maxY - 1 { problems.append(name + ": header overlaps back row") }
                } else { problems.append(name + ": back row is missing") }
            } else if let first = header {
                if abs(first.minY - sidebarTop) > 1 { problems.append(name + ": header top does not align") }
            }
            let field = app.textFields["likedSongsSearch"]
            if field.exists && field.isHittable {
                field.tap()
                XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
                if !field.isHittable || field.frame.minY < sidebarTop - 1 {
                    problems.append(name + ": focused search moved above its page")
                }
                attachScreen("Page keyboard " + name)
                field.typeText("\n")
                let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    !app.keyboards.firstMatch.exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 5), .completed)
            }
        }

        for title in ["探索", "账户", "已下载", "最近播放", "我的收藏", "音乐云盘"] {
            let button = app.buttons[title].firstMatch
            guard button.exists && button.isHittable else {
                problems.append(title + ": sidebar entry is unreachable")
                continue
            }
            button.tap()
            _ = app.otherElements["musicLibraryHeader"].waitForExistence(timeout: 3)
            try inspect(title)
            if title == "我的收藏" {
                for (prefix, tab) in [("collectionAlbum-", "专辑"), ("collectionArtist-", "歌手")] {
                    let segment = app.segmentedControls.buttons[tab].firstMatch
                    if segment.exists { segment.tap() }
                    let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
                    if card.exists && card.isHittable {
                        card.tap()
                        XCTAssertTrue(app.buttons["iPad.destination.back"].waitForExistence(timeout: 10))
                        _ = app.otherElements["musicLibraryHeader"].waitForExistence(timeout: 3)
                        try inspect(prefix + "detail", pushed: true)
                        app.buttons["iPad.destination.back"].tap()
                    }
                }
            }
        }
        app.buttons["sidebarSettingsButton"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["settingsForm"].waitForExistence(timeout: 5))
        try inspect("设置")
        app.buttons["推荐"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["homeFeatureCards"].waitForExistence(timeout: 15))
        let daily = app.buttons["homeFeatureCard-daily"]
        if daily.exists && daily.isHittable {
            daily.tap()
            XCTAssertTrue(app.buttons["iPad.destination.back"].waitForExistence(timeout: 10))
            try inspect("每日推荐", pushed: true)
            app.buttons["iPad.destination.back"].tap()
        }
        app.buttons["推荐"].firstMatch.tap()
        XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
    }

    @MainActor
    private func requireLegacyIPad() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This regression covers the legacy iPad browsing canvas.")
        }
        if #available(iOS 26.0, *) { throw XCTSkip("Native iPad chrome uses system safe areas.") }
    }

    @MainActor
    func testLegacyIPadSkeletonsMatchLoadedHeaders() throws {
        try requireLegacyIPad()
        let app = XCUIApplication()
        app.launchEnvironment["CODA_UI_TEST_SKELETONS"] = "1"
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }

        func releaseLoading() {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                CFNotificationName(rawValue: "wow.caicai.coda.ui-tests.release-skeletons" as CFString),
                nil, nil, true)
        }

        func checkHeader(_ name: String, pushed: Bool) throws {
            let skeleton = app.descendants(matching: .any)["musicLibraryHeaderSkeleton"].firstMatch
            XCTAssertTrue(skeleton.waitForExistence(timeout: 10), name + " must expose its real loading state")
            let before = skeleton.frame
            let sidebarTop = app.buttons["sidebarSettingsButton"].frame.minY - 8
            let expectedTop = pushed ? try XCTUnwrap(elementFrame("iPadDestinationBackRow", in: app.snapshot())).maxY : sidebarTop
            XCTAssertEqual(before.minY, expectedTop, accuracy: 1, name + " skeleton top shifted")
            attachScreen("Skeleton " + name)
            releaseLoading()
            let loaded = app.descendants(matching: .any)["musicLibraryHeader"].firstMatch
            XCTAssertTrue(loaded.waitForExistence(timeout: 45))
            let after = loaded.frame
            print("SKELETON_LAYOUT \(name) before=\(before) after=\(after)")
            XCTAssertEqual(after.minY, before.minY, accuracy: 1, name + " jumped after loading")
            XCTAssertEqual(after.height, before.height, accuracy: 1, name + " header height changed")
            attachScreen("Loaded " + name)
        }

        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            app.terminate()
            XCUIDevice.shared.orientation = orientation
            app.launch()
            XCTAssertTrue(app.buttons["sidebarSettingsButton"].waitForExistence(timeout: 15))
            let skeleton = app.descendants(matching: .any)["homeFeatureSkeleton"].firstMatch
            XCTAssertTrue(skeleton.waitForExistence(timeout: 10))
            let before = skeleton.frame
            let sidebarTop = app.buttons["sidebarSettingsButton"].frame.minY - 8
            XCTAssertEqual(before.minY, sidebarTop, accuracy: 1)
            XCTAssertEqual(before.height, 336, accuracy: 1)
            attachScreen("Skeleton home \(orientation.rawValue)")
            releaseLoading()
            let loaded = app.descendants(matching: .any)["homeFeatureCards"].firstMatch
            XCTAssertTrue(loaded.waitForExistence(timeout: 45))
            let after = loaded.frame
            print("SKELETON_LAYOUT home \(orientation.rawValue) before=\(before) after=\(after)")
            XCTAssertEqual(after.minY, before.minY, accuracy: 1)
            XCTAssertEqual(after.height, before.height, accuracy: 1)
            let daily = app.buttons["homeFeatureCard-daily"]
            if daily.exists {
                XCTAssertEqual(daily.frame.minX, before.minX + 24, accuracy: 1)
                XCTAssertEqual(daily.frame.width, 178, accuracy: 1)
                XCTAssertEqual(daily.frame.height, 160, accuracy: 1)
            }
            attachScreen("Loaded home \(orientation.rawValue)")

            app.buttons["我的收藏"].firstMatch.tap()
            try checkHeader("collections \(orientation.rawValue)", pushed: false)
            for (prefix, tab) in [("collectionAlbum-", "专辑"), ("collectionArtist-", "歌手")] {
                let segment = app.segmentedControls.buttons[tab].firstMatch
                if segment.exists { segment.tap() }
                let card = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", prefix)).firstMatch
                XCTAssertTrue(card.waitForExistence(timeout: 10))
                XCTAssertTrue(card.isHittable)
                card.tap()
                XCTAssertTrue(app.buttons["iPad.destination.back"].waitForExistence(timeout: 10))
                try checkHeader(prefix + "detail \(orientation.rawValue)", pushed: true)
                app.buttons["iPad.destination.back"].tap()
            }
            app.buttons["推荐"].firstMatch.tap()
        }
    }

    @MainActor
    func testPortraitPanelsKeepOnlyBottomUtilityBar() throws {
        let app = XCUIApplication()
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let open = app.buttons["iPhoneOpenNowPlaying"]
        XCTAssertTrue(open.waitForExistence(timeout: 15))
        open.tap()
        for panel in ["待播清单", "歌曲评论", "添加到歌单"] {
            let button = app.buttons[panel].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            let hidden = NSPredicate { _, _ in
                !app.staticTexts["nowPlayingElapsedTime"].exists
            }
            expectation(for: hidden, evaluatedWith: app)
            waitForExpectations(timeout: 5)
            XCTAssertFalse(app.descendants(matching: .any)["音量"].firstMatch.exists)
            XCTAssertTrue(app.buttons["iPadAirPlayButton"].isHittable)
            let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
            let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
            start.press(forDuration: 0.05, thenDragTo: end)
            end.press(forDuration: 0.05, thenDragTo: start)
            XCTAssertFalse(app.staticTexts["nowPlayingElapsedTime"].exists)
            XCTAssertTrue(app.buttons["歌词"].isHittable)
            app.buttons["歌词"].tap()
            XCTAssertTrue(app.staticTexts["nowPlayingElapsedTime"].waitForExistence(timeout: 5))
            XCTAssertTrue(app.descendants(matching: .any)["音量"].firstMatch.waitForExistence(timeout: 5))
        }
    }

    @MainActor
    func testIPadDockLayoutAcrossLaunchAndRotation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        for initial in [UIDeviceOrientation.landscapeLeft, .portrait] {
            app.terminate()
            XCUIDevice.shared.orientation = initial
            app.launch()
            XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 15))
            for (index, orientation) in [initial, .portrait, .landscapeLeft, .portrait, .landscapeLeft].enumerated() {
                XCUIDevice.shared.orientation = orientation
                // Query a fresh tree: iPadOS 16 can cache element frames across rotation.
                let settled = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    guard let snapshot = try? app.snapshot(),
                          let dock = self.elementFrame("iPadPlayerDock", in: snapshot),
                          let open = self.playerFrame(in: snapshot) else { return false }
                    let window = app.windows.firstMatch.frame
                    let title = app.navigationBars["推荐"].frame
                    print("DOCK_LAYOUT orientation=\(orientation.rawValue) window=\(window) title=\(title) dock=\(dock) open=\(open)")
                    return abs(dock.maxX - (window.maxX - 24)) <= 1
                        && abs(dock.minX - (title.minX + 20)) <= 2
                        && (24...40).contains(window.maxY - dock.maxY)
                        && dock.width > 300 && abs(dock.height - 44) <= 1
                        && open.width > 40 && open.minX >= dock.minX
                        && open.maxX < dock.maxX
                }, object: nil)
                let result = XCTWaiter.wait(for: [settled], timeout: 8)
                attachScreen("Dock launch \(initial.rawValue) orientation \(orientation.rawValue)")
                XCTAssertEqual(result, .completed)
                let open = app.buttons["iPadOpenNowPlaying"]
                if initial == .landscapeLeft, index == 1, !open.label.contains("未在播放") {
                    // Use the native element tap, not a coordinate workaround:
                    // retaining the dock must also retain correct hit targets.
                    open.tap()
                    let dismiss = app.otherElements["nowPlayingDismissIndicator"]
                    XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
                    let start = dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                    start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
                    XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 5))
                }
            }
            XCUIDevice.shared.press(.home)
            XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
            app.activate()
            XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 10))
        }
    }

    private func elementFrame(_ identifier: String, in snapshot: XCUIElementSnapshot) -> CGRect? {
        if snapshot.identifier == identifier { return snapshot.frame }
        for child in snapshot.children {
            if let frame = elementFrame(identifier, in: child) { return frame }
        }
        return nil
    }

    @MainActor
    func testIPadKeepsCurrentPageAfterReturningToForeground() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].waitForExistence(timeout: 15))

        for title in ["探索", "已下载"] {
            app.buttons[title].firstMatch.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            for _ in 0..<2 {
                XCUIDevice.shared.press(.home)
                XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
                app.activate()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10),
                              "Returning to the app must keep the selected section.")
            }
        }

        app.buttons["sidebarSettingsButton"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        let storage = app.buttons["存储空间"].firstMatch
        for _ in 0..<5 {
            if storage.exists && storage.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(storage.isHittable)
        storage.tap()
        XCTAssertTrue(app.navigationBars["存储空间"].waitForExistence(timeout: 5))
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 5))
        app.activate()
        XCTAssertTrue(app.navigationBars["存储空间"].waitForExistence(timeout: 10),
                      "Returning to the app must also keep the pushed detail page.")
        app.navigationBars["存储空间"].buttons["设置"].tap()
        XCTAssertTrue(app.navigationBars["设置"].waitForExistence(timeout: 5))
        app.buttons["探索"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["探索"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testIPadCreatePlaylistActionRemainsVisibleWhenNameChanges() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 15))
        try tapPlayerCenter(in: app)
        let add = app.buttons["iPadAddToPlaylistButton"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        XCTAssertTrue(app.staticTexts["添加到歌单"].waitForExistence(timeout: 5))
        app.buttons["新建歌单并收藏"].tap()
        let name = app.textFields["newPlaylistName"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let confirm = app.buttons["创建并收藏"]
        XCTAssertTrue(confirm.exists)
        XCTAssertFalse(confirm.isEnabled)
        name.typeText("Coda regression")
        XCTAssertTrue(confirm.isEnabled)
        app.buttons["取消新建歌单"].tap()
        XCTAssertFalse(name.exists)
        XCTAssertTrue(app.staticTexts["添加到歌单"].waitForExistence(timeout: 5))
        app.buttons["关闭添加歌单"].tap()
        XCTAssertFalse(app.staticTexts["添加到歌单"].exists)
    }

    @MainActor
    func testIPadPlayerBackdropWhileScrollingAndRotating() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].waitForExistence(timeout: 15))
        let player = app.buttons["iPadOpenNowPlaying"]
        XCTAssertTrue(player.waitForExistence(timeout: 10))
        let initialPlayerFrame = player.frame
        for title in ["探索", "推荐"] {
            app.buttons[title].firstMatch.tap()
            XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            let window = app.windows.firstMatch.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let start = origin.withOffset(CGVector(dx: window.width * 0.78, dy: window.height * 0.78))
            let end = origin.withOffset(CGVector(dx: window.width * 0.78, dy: window.height * 0.25))
            var backdropSamples: [[UInt8]] = []
            for index in 0..<3 {
                if index > 0 {
                    start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
                }
                assertPersistentPlayer(player, initialFrame: initialPlayerFrame)
                print("PLAYERDOCK \(title) \(index): \(app.otherElements["iPadPlayerDock"].frame)")
                attachScreen("Player backdrop \(title) \(index)")
                if title == "探索" {
                    backdropSamples.append(try playerBackdropPixels(app: app, player: player))
                }
            }
            if let first = backdropSamples.first {
                var greatestChange = 0.0
                for sample in backdropSamples.dropFirst() {
                    XCTAssertEqual(sample.count, first.count)
                    var totalDifference = 0.0
                    for index in 0..<min(first.count, sample.count) {
                        totalDifference += abs(Double(first[index]) - Double(sample[index]))
                    }
                    greatestChange = max(greatestChange, totalDifference / Double(first.count))
                }
                XCTAssertGreaterThan(greatestChange, 1,
                                     "The translucent dock must change as different artwork scrolls behind it; a fixed blank backdrop is a regression.")
            }
        }
        for orientation in [UIDeviceOrientation.portrait, .landscapeLeft] {
            XCUIDevice.shared.orientation = orientation
            let interactive = XCTNSPredicateExpectation(predicate: NSPredicate(format: "isHittable == true"), object: player)
            XCTAssertEqual(XCTWaiter.wait(for: [interactive], timeout: 5), .completed)
            XCTAssertTrue(app.buttons["下一首"].firstMatch.isHittable)
            attachScreen("Player backdrop orientation \(orientation.rawValue)")
        }
    }

    @MainActor
    private func playerBackdropPixels(app: XCUIApplication, player: XCUIElement) throws -> [UInt8] {
        let window = app.windows.firstMatch.frame
        // Sample below the labels and controls, but above the home indicator.
        let band = CGRect(x: window.width * 0.50, y: player.frame.maxY + 4,
                          width: window.width * 0.18, height: 4).integral
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let screenshot = app.screenshot().image
        let image = UIGraphicsImageRenderer(size: band.size, format: format).image { _ in
            screenshot.draw(in: CGRect(x: -band.minX, y: -band.minY,
                                       width: window.width, height: window.height))
        }
        let cgImage = try XCTUnwrap(image.cgImage)
        let data = try XCTUnwrap(cgImage.dataProvider?.data)
        return Array(data as Data)
    }

    @MainActor
    func testIPadNavigationTitleBackgroundTransitions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].waitForExistence(timeout: 15))
        for title in ["推荐", "探索", "我的收藏"] {
            app.buttons[title].firstMatch.tap()
            let bar = app.navigationBars[title]
            XCTAssertTrue(bar.waitForExistence(timeout: 10))
            let frame = app.windows.firstMatch.frame
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let top = origin.withOffset(CGVector(dx: frame.width * 0.78, dy: frame.height * 0.25))
            let bottom = origin.withOffset(CGVector(dx: frame.width * 0.78, dy: frame.height * 0.78))
            for _ in 0..<4 {
                top.press(forDuration: 0.05, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 0.1)
            }
            attachScreen("\(title) title visible")
            let expandedHeight = bar.frame.height
            print("NAVBAR \(title) top: \(bar.frame)")
            for index in 1...3 {
                bottom.press(forDuration: 0.05, thenDragTo: top, withVelocity: .slow, thenHoldForDuration: 0.2)
                attachScreen("\(title) scrolled \(index)")
                print("NAVBAR \(title) scrolled \(index): \(bar.frame)")
                if title != "我的收藏" {
                    XCTAssertLessThan(bar.frame.height, expandedHeight - 20,
                                      "The main title must leave the viewport before checking its background.")
                }
            }
            for _ in 0..<4 {
                top.press(forDuration: 0.05, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 0.1)
            }
            attachScreen("\(title) title visible again")
            XCTAssertEqual(bar.frame.height, expandedHeight, accuracy: 2,
                           "Returning to the top must restore the main title.")
        }
        app.buttons["推荐"].firstMatch.tap()
    }

    @MainActor
    func testHomeToplistVerticalScrolling() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .portrait
        app.launch()
        let home = app.buttons["推荐"].firstMatch
        if home.waitForExistence(timeout: 10), home.isHittable { home.tap() }
        let ranking = app.buttons["排行榜"].firstMatch
        XCTAssertTrue(ranking.waitForExistence(timeout: 20))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let frame = app.windows.firstMatch.frame
        let x = frame.width * 0.72
        let bottom = origin.withOffset(CGVector(dx: x, dy: frame.height * 0.78))
        let top = origin.withOffset(CGVector(dx: x, dy: frame.height * 0.23))
        attachScreen("Home before crossing complete ranking shelf")
        let options = XCTMeasureOptions()
        options.iterationCount = 3
        measure(metrics: [XCTOSSignpostMetric.scrollingAndDecelerationMetric, XCTCPUMetric(application: app)], options: options) {
            // Three screen-spanning drags cross the whole 760pt chart shelf,
            // including its entry and exit from the vertical viewport.
            for _ in 0..<3 {
                bottom.press(forDuration: 0.05, thenDragTo: top, withVelocity: .fast, thenHoldForDuration: 0)
            }
            XCTAssertTrue(app.staticTexts["新碟上架"].firstMatch.isHittable)
            attachScreen("Below complete ranking shelf")
            for _ in 0..<3 {
                top.press(forDuration: 0.05, thenDragTo: bottom, withVelocity: .fast, thenHoldForDuration: 0)
            }
        }
        attachScreen("Home after repeated full ranking passes")
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
        XCTAssertTrue(true)
    }

    @MainActor
    func testLyricScrollFollowsPlaybackBarSeek() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()

        XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 15))
        try tapPlayerCenter(in: app)

        let scrubber = app.otherElements["nowPlayingProgress"]
        XCTAssertTrue(scrubber.waitForExistence(timeout: 5))
        let elapsed = app.staticTexts["nowPlayingElapsedTime"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        let oldElapsed = elapsed.label

        let lyricButtons = app.buttons.matching(
            NSPredicate(format: "identifier BEGINSWITH %@", "syncedLyricLine-")
        )
        let activeLine = lyricButtons.matching(NSPredicate(format: "isSelected == true")).firstMatch
        XCTAssertTrue(activeLine.waitForExistence(timeout: 5), "Expected the current timed lyric to be active.")
        let oldActiveIdentifier = activeLine.identifier

        // Drag the playback bar directly. Lyric rows can be visually clipped
        // during their scroll animation, which makes XCTest's auto-scroll
        // produce an off-screen tap instead of a useful synchronization check.
        let start = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.5))
        let end = scrubber.coordinate(withNormalizedOffset: CGVector(dx: 0.80, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)

        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        XCTAssertNotEqual(elapsed.label, oldElapsed, "Dragging the playback bar should change playback time.")
        let updatedActiveLine = lyricButtons.matching(NSPredicate(format: "isSelected == true")).firstMatch
        XCTAssertTrue(updatedActiveLine.waitForExistence(timeout: 5))
        XCTAssertNotEqual(updatedActiveLine.identifier, oldActiveIdentifier,
                          "The active lyric should follow the playback bar time.")
    }

    @MainActor
    func testIPadSidebarSettingsPressFeedback() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()

        let settings = app.buttons["sidebarSettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        XCTAssertTrue(settings.isHittable)
        XCTAssertGreaterThanOrEqual(settings.frame.width, 44)
        XCTAssertGreaterThanOrEqual(settings.frame.height, 44)
        attachScreen("Sidebar settings before press")

        // Hold long enough to inspect the pressed feedback on the real iPad.
        let center = settings.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.press(forDuration: 8)
        let settingsPage = app.navigationBars["设置"]
        XCTAssertTrue(settingsPage.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(settingsPage.frame.minX, settings.frame.maxX,
                                    "Settings should open in the detail column.")
        XCTAssertFalse(settingsPage.buttons["完成"].exists)
        app.buttons["推荐"].firstMatch.tap()
        XCTAssertTrue(settings.waitForExistence(timeout: 5))

        center.press(forDuration: 0.1,
                     thenDragTo: center.withOffset(CGVector(dx: -120, dy: 120)),
                     withVelocity: .slow, thenHoldForDuration: 0.3)
        XCTAssertFalse(settingsPage.exists,
                       "Dragging outside the button should cancel the press.")
        attachScreen("Sidebar settings after cancelled press")

        for _ in 0..<2 {
            settings.tap()
            XCTAssertTrue(settingsPage.waitForExistence(timeout: 5))
            XCTAssertTrue(settings.isHittable)
            attachScreen("Sidebar settings in detail column")
            app.buttons["推荐"].firstMatch.tap()
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            XCTAssertTrue(settings.isHittable)
        }
    }

    /// iPadOS 16 resolves a finger tap using its contact radius. Inside a
    /// short horizontal scroll view, or between closely packed buttons, the
    /// tap used to be dropped while an Apple Pencil tap still worked. XCTest's
    /// device taps carry a finger radius, so these exercise the same path.
    @MainActor
    func testIPadSearchKeywordChipsRespondToTouch() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This regression covers the iPad search page.")
        }
        for index in [0, 1] {
            let app = launchSearchPage()
            defer { app.terminate() }
            let field = app.textFields["搜索歌曲、歌手、专辑、歌单"]
            let chips = app.descendants(matching: .any)["searchKeywordChips"].buttons
            XCTAssertTrue(chips.firstMatch.waitForExistence(timeout: 15))
            // A chip between two neighbours is the harder case, when the service offers one.
            if index > 0 && chips.count <= index { continue }
            assertChipTap(index: index, in: app, field: field, name: "Hot search chip \(index)")
            assertChipTap(index: 0, in: app, field: field, name: "Suggestion chip after \(index)")
        }
    }

    @MainActor
    func testIPadSearchShelfRespondsToTouch() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This regression covers the iPad search page.")
        }
        for target in ["header", "cover", "title"] {
            let app = launchSearchPage()
            defer { app.terminate() }
            let field = app.textFields["搜索歌曲、歌手、专辑、歌单"]
            // The first loaded shelf and the header directly above it.
            let firstCard = app.buttons.matching(NSPredicate { object, _ in
                guard let item = object as? XCUIElementAttributes else { return false }
                return item.frame.width > 150 && item.frame.height > 150
            }).firstMatch
            XCTAssertTrue(firstCard.waitForExistence(timeout: 20))
            let buttons = app.buttons.allElementsBoundByIndex
            let cardFrame = firstCard.frame
            guard let card = buttons.first(where: { $0.frame == cardFrame }),
                  let header = buttons.filter({ abs($0.frame.minX - cardFrame.minX) < 4
                      && $0.frame.maxY <= cardFrame.minY && $0.frame.maxY > cardFrame.minY - 80 })
                      .max(by: { $0.frame.maxY < $1.frame.maxY }) else {
                XCTFail("No loaded shelf below a header")
                continue
            }
            print("SEARCH_SHELF \(target) card=\(card.frame) header=\(header.label) \(header.frame)")
            let element = target == "header" ? header : card
            // The title sits along the scroll view's bottom edge.
            let offset = target == "header" ? CGVector(dx: 0.5, dy: 0.5)
                : target == "cover" ? CGVector(dx: 0.5, dy: 0.4)
                : CGVector(dx: 0.5, dy: 1 - 10 / card.frame.height)
            element.coordinate(withNormalizedOffset: offset).tap()
            let pushed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: field)
            let result = XCTWaiter.wait(for: [pushed], timeout: 5)
            attachScreen("Shelf \(target)")
            XCTAssertEqual(result, .completed, "Shelf \(target) did not open its destination")
        }
    }

    /// Only opens the removal confirmation and dismisses it outside the popover.
    @MainActor
    func testIPadAccountRemoveButtonRespondsToTouch() throws {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("This regression covers the iPad settings page.")
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        defer { app.terminate() }
        let settings = app.buttons["sidebarSettingsButton"]
        XCTAssertTrue(settings.waitForExistence(timeout: 15))
        settings.tap()
        let remove = app.buttons.matching(NSPredicate(format: "label BEGINSWITH '移除'")).firstMatch
        guard remove.waitForExistence(timeout: 10) else { throw XCTSkip("No saved account to probe.") }
        let removeLabel = remove.label
        print("ACCOUNT_REMOVE frame=\(remove.frame)")
        remove.tap()
        let confirm = app.buttons["移除账号"].firstMatch
        let shown = confirm.waitForExistence(timeout: 4)
        attachScreen("Account removal confirmation")
        XCTAssertTrue(shown, "The remove button did not respond")
        if shown {
            // Outside the popover: dismiss without choosing an action.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.98)).tap()
            let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: confirm)
            XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 4), .completed)
        }
        XCTAssertTrue(app.buttons[removeLabel].exists, "The account must remain")
    }

    @MainActor
    private func launchSearchPage() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].waitForExistence(timeout: 15))
        app.buttons["探索"].firstMatch.tap()
        XCTAssertTrue(app.textFields["搜索歌曲、歌手、专辑、歌单"].waitForExistence(timeout: 10))
        return app
    }

    @MainActor
    private func assertChipTap(index: Int, in app: XCUIApplication, field: XCUIElement, name: String) {
        let chips = app.descendants(matching: .any)["searchKeywordChips"].buttons
        let chip = chips.element(boundBy: index)
        guard chip.waitForExistence(timeout: 15) else { return XCTFail("\(name): no chip") }
        let keyword = chip.label
        print("SEARCH_CHIP \(name) \(keyword) \(chip.frame)")
        chip.tap()
        let applied = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            (field.value as? String) == keyword
        }, object: nil)
        let result = XCTWaiter.wait(for: [applied], timeout: 5)
        attachScreen(name)
        XCTAssertEqual(result, .completed, "\(name): field is \(field.value ?? "nil"), expected \(keyword)")
    }

    @MainActor
    func testIPadMainContentRemainsInteractive() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.terminate()
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft

        for launch in 1...2 {
            app.launch()
            let settings = app.buttons["sidebarSettingsButton"]
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            for title in ["探索", "已下载", "推荐"] {
                app.buttons[title].firstMatch.tap()
                XCTAssertTrue(app.navigationBars[title].waitForExistence(timeout: 10))
            }
            settings.tap()
            let settingsPage = app.navigationBars["设置"]
            XCTAssertTrue(settingsPage.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(settingsPage.frame.minX, settings.frame.maxX)
            XCTAssertFalse(settingsPage.buttons["完成"].exists)
            let manage = app.buttons["storageManageDownloads"]
            for _ in 0..<5 {
                if manage.exists && manage.isHittable { break }
                app.swipeUp()
            }
            XCTAssertTrue(manage.isHittable)
            manage.tap()
            XCTAssertTrue(app.navigationBars["已下载"].waitForExistence(timeout: 10))
            app.buttons["推荐"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 5))
            let player = app.buttons["iPadOpenNowPlaying"]
            if player.exists && !player.label.contains("未在播放") {
                try tapPlayerCenter(in: app)
                let indicator = app.otherElements["nowPlayingDismissIndicator"]
                XCTAssertTrue(indicator.waitForExistence(timeout: 5))
                let start = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                start.press(forDuration: 0.1,
                            thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
                XCTAssertTrue(settings.isHittable)
            }
            attachScreen("Responsive main content after launch \(launch)")
            app.terminate()
        }
    }

    @MainActor
    func testIPadAirPlayPopoverKeepsPlayerStable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 15))
        try tapPlayerCenter(in: app)
        let route = app.buttons["iPadAirPlayButton"]
        XCTAssertTrue(route.waitForExistence(timeout: 5))
        let shuffle = app.buttons["随机播放"]
        let indicator = app.otherElements["nowPlayingDismissIndicator"]
        let originalRoute = route.frame
        let originalShuffle = shuffle.frame
        let originalIndicator = indicator.frame
        for cycle in 1...2 {
            route.tap()
            #if targetEnvironment(simulator)
            let notice = app.alerts["播放设备"]
            XCTAssertTrue(notice.waitForExistence(timeout: 5))
            attachScreen("Simulator output notice \(cycle)")
            notice.buttons["好"].tap()
            XCTAssertFalse(notice.exists)
            #else
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已展开"), object: route)], timeout: 5) == .completed)
            attachScreen("Anchored AirPlay popover \(cycle)")
            app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.15)).tap()
            XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", "已收起"), object: route)], timeout: 5) == .completed)
            #endif
            XCTAssertEqual(route.frame.minX, originalRoute.minX, accuracy: 1)
            XCTAssertEqual(route.frame.minY, originalRoute.minY, accuracy: 1)
            XCTAssertEqual(shuffle.frame.minY, originalShuffle.minY, accuracy: 1)
            XCTAssertEqual(indicator.frame.minY, originalIndicator.minY, accuracy: 1)
        }
        XCTAssertTrue(shuffle.isHittable)
        let start = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].isHittable)
    }

    @MainActor
    func testIPadPlayerBlankAreasDoNotTriggerControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let orientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = orientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 15))
        try tapPlayerCenter(in: app)
        let play = app.buttons["iPadPlayPauseButton"]
        XCTAssertTrue(play.waitForExistence(timeout: 10))
        let wasPlaying = play.label == "暂停"
        if wasPlaying { play.tap() }
        defer { if wasPlaying && play.exists && play.label == "播放" { play.tap() } }
        let elapsed = app.staticTexts["nowPlayingElapsedTime"]
        XCTAssertTrue(elapsed.waitForExistence(timeout: 5))
        // Session restoration can publish its saved position after the page
        // appears. Wait for that initial update before testing inert taps.
        _ = XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate:
            NSPredicate(format: "label != %@", "0:00"), object: elapsed)], timeout: 12)
        let originalElapsed = elapsed.label
        let shuffle = app.buttons["随机播放"]
        let originalShuffle = shuffle.value as? String
        let repeatMode = app.buttons["循环模式"]
        let originalRepeat = repeatMode.value as? String
        let indicator = app.otherElements["nowPlayingDismissIndicator"]
        let window = app.windows.firstMatch.frame
        let cover = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开专辑：")).firstMatch
        XCTAssertTrue(cover.exists)
        let originalAlbum = cover.label
        let metadata = app.descendants(matching: .any)["immersiveTrackMetadata"].firstMatch
        let originalMetadata = metadata.staticTexts.allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(originalMetadata.isEmpty)
        let route = app.buttons["iPadAirPlayButton"]
        let routeState = route.value as? String
        let frame = cover.frame
        let progress = app.descendants(matching: .any)["nowPlayingProgress"].firstMatch.frame
        let points = [
            CGPoint(x: progress.minX + 24, y: progress.maxY - 2),
            CGPoint(x: progress.maxX - 24, y: progress.maxY - 2),
            CGPoint(x: window.minX + 12, y: window.midY),
            CGPoint(x: window.minX + 12, y: window.maxY - 100),
            CGPoint(x: frame.midX, y: frame.minY - 24),
            CGPoint(x: frame.minX - 24, y: frame.midY),
            CGPoint(x: frame.maxX + 24, y: frame.midY),
            CGPoint(x: frame.maxX + 24, y: frame.maxY - 10),
            CGPoint(x: frame.midX, y: window.maxY - 34)
        ]
        let origin = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
        for point in points {
            origin.withOffset(CGVector(dx: point.x - window.minX, dy: point.y - window.minY)).tap()
            XCTAssertTrue(indicator.exists, "Blank tap must not dismiss/navigate away: \(point)")
            XCTAssertEqual(play.label, "播放", "Blank tap must not start playback: \(point)")
            XCTAssertEqual(elapsed.label, originalElapsed, "Blank tap must not seek: \(point)")
            XCTAssertEqual(shuffle.value as? String, originalShuffle)
            XCTAssertEqual(repeatMode.value as? String, originalRepeat)
            XCTAssertEqual(cover.label, originalAlbum, "Blank tap changed the album")
            XCTAssertEqual(metadata.staticTexts.allElementsBoundByIndex.map(\.label), originalMetadata,
                           "Blank tap changed the playing song")
            XCTAssertEqual(route.value as? String, routeState, "Blank tap opened the route picker")
            XCTAssertFalse(app.switches["总是最高"].exists, "Blank tap opened an invisible quality menu")
        }
        // The shield must not intercept genuine controls above it.
        play.tap()
        XCTAssertEqual(play.label, "暂停")
        play.tap()
        XCTAssertEqual(play.label, "播放")
        attachScreen("Player blank areas remain inert")
        if wasPlaying && play.exists && play.label == "播放" { play.tap() }
        let start = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
    }

    @MainActor
    func testIPadPagesKeepScrollViewportAboveDock() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let orientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = orientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        let dock = app.otherElements["iPadPlayerDock"]
        XCTAssertTrue(dock.waitForExistence(timeout: 15))
        var checkedPages = 0
        for name in ["推荐", "我喜欢的音乐", "已下载"] {
            let page = app.buttons[name].firstMatch
            guard page.exists && page.isHittable else { continue }
            page.tap()
            checkedPages += 1
            let frame = dock.frame
            let scrolls = app.scrollViews.allElementsBoundByIndex.filter {
                let rect = $0.frame
                // Exclude horizontal shelves and offscreen carousels inside
                // the vertical page; their content frames intentionally extend.
                return rect.width > frame.width * 0.8 && rect.height > 300
                    && rect.minY < 120 && rect.midX > frame.minX + 40
            }
            XCTAssertFalse(scrolls.isEmpty, "Expected scroll content on \(name)")
            for scroll in scrolls {
                XCTAssertLessThanOrEqual(scroll.frame.maxY, frame.minY + 1,
                                         "\(name) scroll viewport extends under the dock")
            }
            attachScreen("Dock clearance on \(name)")
        }
        XCTAssertGreaterThanOrEqual(checkedPages, 2)
    }

    @MainActor
    func testIPadPlaybackControlsKeepLayoutStable() throws {
        continueAfterFailure = true
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.terminate()
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 15))
        try tapPlayerCenter(in: app)
        let shuffle = app.buttons["随机播放"]
        XCTAssertTrue(shuffle.waitForExistence(timeout: 10))
        let artwork = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "打开专辑：")).firstMatch
        XCTAssertTrue(artwork.exists)
        let indicator = app.otherElements["nowPlayingDismissIndicator"]
        let originalArtwork = artwork.frame
        let originalShuffle = shuffle.frame
        let originalIndicator = indicator.frame
        let originalShuffleValue = shuffle.value as? String
        attachScreen("Playback controls before tap")
        defer {
            // Restore shuffle when an assertion aborts after the first toggle.
            if shuffle.exists && shuffle.value as? String != originalShuffleValue { shuffle.tap() }
        }
        for cycle in 1...2 {
            shuffle.tap()
            attachScreen("Playback controls after shuffle tap \(cycle)")
            XCTAssertEqual(shuffle.frame.minY, originalShuffle.minY, accuracy: 1)
            XCTAssertEqual(shuffle.frame.minX, originalShuffle.minX, accuracy: 1)
            XCTAssertEqual(artwork.frame.minY, originalArtwork.minY, accuracy: 1)
            XCTAssertEqual(artwork.frame.minX, originalArtwork.minX, accuracy: 1)
            XCTAssertEqual(indicator.frame.minY, originalIndicator.minY, accuracy: 1)
        }
        let repeatMode = app.buttons["循环模式"]
        for _ in 0..<3 {
            repeatMode.tap()
            XCTAssertEqual(shuffle.frame.minY, originalShuffle.minY, accuracy: 1)
            XCTAssertEqual(artwork.frame.minY, originalArtwork.minY, accuracy: 1)
        }
        func assertControlLayout(_ context: String) {
            XCTAssertEqual(shuffle.frame.minY, originalShuffle.minY, accuracy: 1, context)
            // Play/pause deliberately scales the cover around its center.
            XCTAssertEqual(artwork.frame.midY, originalArtwork.midY, accuracy: 1, context)
            XCTAssertEqual(artwork.frame.midX, originalArtwork.midX, accuracy: 1, context)
            XCTAssertEqual(indicator.frame.minY, originalIndicator.minY, accuracy: 1, context)
        }
        let playPause = app.buttons["iPadPlayPauseButton"]
        let originalPlayLabel = playPause.label
        defer {
            if playPause.exists && playPause.label != originalPlayLabel { playPause.tap() }
        }
        for _ in 0..<2 {
            playPause.tap()
            assertControlLayout("Play/pause must keep the column anchored")
        }
        let volume = app.descendants(matching: .any)["音量"].firstMatch
        let volumeText = try XCTUnwrap(volume.value as? String)
        let originalVolume = try XCTUnwrap(Double(volumeText.filter { $0.isNumber })) / 100
        defer { if volume.exists { volume.adjust(toNormalizedSliderPosition: originalVolume) } }
        volume.adjust(toNormalizedSliderPosition: originalVolume > 0.5 ? 0.4 : 0.6)
        assertControlLayout("Volume must keep the column anchored")
        volume.adjust(toNormalizedSliderPosition: originalVolume)

        func seconds(_ label: String) throws -> Double {
            let parts = label.split(separator: ":")
            let minutes = try XCTUnwrap(Double(parts[0].filter { $0.isNumber }))
            let seconds = try XCTUnwrap(Double(parts[1]))
            return minutes * 60 + seconds
        }
        let elapsed = try seconds(app.staticTexts["nowPlayingElapsedTime"].label)
        let remaining = try seconds(app.staticTexts["nowPlayingRemainingTime"].label)
        let fraction = elapsed / max(1, elapsed + remaining)
        let progress = app.descendants(matching: .any)["nowPlayingProgress"].firstMatch
        defer {
            if progress.exists {
                progress.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).tap()
            }
        }
        progress.coordinate(withNormalizedOffset: CGVector(dx: fraction > 0.5 ? 0.3 : 0.7, dy: 0.5)).tap()
        assertControlLayout("Seeking must keep the column anchored")
        progress.coordinate(withNormalizedOffset: CGVector(dx: fraction, dy: 0.5)).tap()
        attachScreen("Playback controls remain aligned after interactions")
        let dismissStart = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        dismissStart.press(forDuration: 0.1,
                           thenDragTo: dismissStart.withOffset(CGVector(dx: 0, dy: 300)))
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].isHittable)
    }

    @MainActor
    func testIPadLyricsScrollWithoutDismissingPlayer() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.terminate()
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(app.buttons["iPadOpenNowPlaying"].waitForExistence(timeout: 15))
        try tapPlayerCenter(in: app)
        let scroll = app.descendants(matching: .any)["syncedLyricsScroll"].firstMatch
        XCTAssertTrue(scroll.waitForExistence(timeout: 20), "Restore a song with lyrics for this regression.")
        let viewport = scroll.frame
        let indicator = app.otherElements["nowPlayingDismissIndicator"]
        let initialIndicatorY = indicator.frame.minY
        let rows = lyricFrames(in: try app.snapshot())
        let candidates = rows.filter {
            $0.value.midY > viewport.midY && $0.value.maxY < viewport.maxY - 30
        }
        let row = try XCTUnwrap(candidates.min(by: { $0.value.minY < $1.value.minY }))
        attachScreen("Lyrics before manual scroll")
        let start = app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: row.value.midX, dy: row.value.midY))
        start.press(forDuration: 0.05,
                    thenDragTo: start.withOffset(CGVector(dx: 0, dy: -180)),
                    withVelocity: .slow, thenHoldForDuration: 0.1)
        let moved = try XCTUnwrap(lyricFrames(in: try app.snapshot())[row.key])
        XCTAssertLessThan(moved.minY, row.value.minY - 50,
                          "Dragging a lyric line must scroll the lyrics list.")
        XCTAssertEqual(indicator.frame.minY, initialIndicatorY, accuracy: 1,
                       "Scrolling lyrics must not move the whole player.")
        attachScreen("Lyrics after manual scroll")
        let dismissStart = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        dismissStart.press(forDuration: 0.1,
                           thenDragTo: dismissStart.withOffset(CGVector(dx: 0, dy: 300)))
        XCTAssertTrue(app.buttons["sidebarSettingsButton"].isHittable)
    }

    private func lyricFrames(in snapshot: XCUIElementSnapshot) -> [String: CGRect] {
        var frames: [String: CGRect] = [:]
        if snapshot.identifier.hasPrefix("syncedLyricLine-") {
            frames[snapshot.identifier] = snapshot.frame
        }
        for child in snapshot.children {
            frames.merge(lyricFrames(in: child), uniquingKeysWith: { first, _ in first })
        }
        return frames
    }

    @MainActor
    func testIPadBrowsingPositionSurvivesPlayerPresentation() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        let openPlayer = app.buttons["iPadOpenNowPlaying"]
        guard openPlayer.waitForExistence(timeout: 15) else {
            throw XCTSkip("This regression test requires the iPad split-view layout.")
        }
        guard !openPlayer.label.contains("未在播放") else {
            throw XCTSkip("Restore a current track before running this device regression test.")
        }
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            try assertBrowsingPositionSurvivesPlayerPresentation(app: app)
        }
    }

    @MainActor
    func testIPadPlayerRemainsVisibleOnNavigationDestinations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        let originalOrientation = XCUIDevice.shared.orientation
        defer { XCUIDevice.shared.orientation = originalOrientation }
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            app.launch()
            XCUIDevice.shared.orientation = orientation
            let player = app.buttons["iPadOpenNowPlaying"]
            guard player.waitForExistence(timeout: 15) else {
                throw XCTSkip("This regression test requires the iPad player bar.")
            }
            let initialPlayerFrame = player.frame
            let toplists = app.buttons["排行榜"].firstMatch
            XCTAssertTrue(toplists.waitForExistence(timeout: 20))
            toplists.tap()
            XCTAssertTrue(app.navigationBars["排行榜"].waitForExistence(timeout: 10))
            assertPersistentPlayer(player, initialFrame: initialPlayerFrame)
            attachScreen("Player on secondary destination")

            if !player.label.contains("未在播放") {
                try tapPlayerCenter(in: app)
                let indicator = app.otherElements["nowPlayingDismissIndicator"]
                XCTAssertTrue(indicator.waitForExistence(timeout: 5))
                let start = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 300)))
                XCTAssertTrue(app.navigationBars["排行榜"].waitForExistence(timeout: 5))
                assertPersistentPlayer(player, initialFrame: initialPlayerFrame)
            }

            let chart = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "飙升榜")).firstMatch
            XCTAssertTrue(chart.waitForExistence(timeout: 20))
            chart.tap()
            let backToToplists = app.navigationBars.buttons["排行榜"].firstMatch
            XCTAssertTrue(backToToplists.waitForExistence(timeout: 10))
            assertPersistentPlayer(player, initialFrame: initialPlayerFrame)
            attachScreen("Player on tertiary destination")
            if orientation == .landscapeLeft {
                XCUIDevice.shared.orientation = .portrait
                XCTAssertTrue(player.isHittable)
                XCTAssertGreaterThanOrEqual(player.frame.minX, 0)
                XCTAssertLessThanOrEqual(player.frame.maxX, app.windows.firstMatch.frame.maxX)
                XCUIDevice.shared.orientation = orientation
                assertPersistentPlayer(player, initialFrame: initialPlayerFrame)
            }
            backToToplists.tap()
            XCTAssertTrue(app.navigationBars["排行榜"].waitForExistence(timeout: 5))
            assertPersistentPlayer(player, initialFrame: initialPlayerFrame)
            app.navigationBars.buttons["推荐"].firstMatch.tap()
            XCTAssertTrue(app.navigationBars["推荐"].waitForExistence(timeout: 5))
            assertPersistentPlayer(player, initialFrame: initialPlayerFrame)
        }
    }

    @MainActor
    private func assertPersistentPlayer(_ player: XCUIElement, initialFrame: CGRect) {
        XCTAssertTrue(player.exists, "The persistent player disappeared on a pushed page.")
        XCTAssertTrue(player.isHittable, "The persistent player is covered by the pushed page.")
        XCTAssertEqual(player.frame.minY, initialFrame.minY, accuracy: 1)
    }

    @MainActor
    private func assertBrowsingPositionSurvivesPlayerPresentation(app: XCUIApplication) throws {
        let settings = app.buttons["设置"].firstMatch
        let homeBar = app.navigationBars["推荐"]
        XCTAssertTrue(homeBar.waitForExistence(timeout: 10))
        // In portrait, the system may collapse the sidebar. Compare its
        // geometry only when it was visible before presenting the player.
        let initialSettingsFrame = settings.exists && settings.isHittable ? settings.frame : nil
        let initialHomeFrame = homeBar.frame
        attachScreen("Browsing before presentation")

        for cycle in 1...3 {
            try tapPlayerCenter(in: app)
            let indicator = app.otherElements["nowPlayingDismissIndicator"]
            XCTAssertTrue(indicator.waitForExistence(timeout: 5))
            attachScreen("Player presented \(cycle)")
            if cycle == 1 {
                let start = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
                start.press(forDuration: 0.1,
                            thenDragTo: start.withOffset(CGVector(dx: 0, dy: 45)),
                            withVelocity: .slow, thenHoldForDuration: 0.3)
                XCTAssertTrue(indicator.exists, "A short drag must leave the player presented.")
            }
            let start = indicator.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
            let end = start.withOffset(CGVector(dx: 0, dy: 300))
            start.press(forDuration: 0.1, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.1)
            XCTAssertTrue(homeBar.waitForExistence(timeout: 5))
            attachScreen("Browsing after dismissal \(cycle)")
            if let initialSettingsFrame {
                XCTAssertTrue(settings.exists)
                XCTAssertEqual(settings.frame.minY, initialSettingsFrame.minY, accuracy: 1,
                               "The sidebar shifted after dismissing the player.")
            }
            XCTAssertEqual(homeBar.frame.minY, initialHomeFrame.minY, accuracy: 1,
                           "The home navigation bar shifted after dismissing the player.")
        }
    }

    @MainActor
    private func tapPlayerCenter(in app: XCUIApplication) throws {
        // iPadOS 16 caches the individual element's frame across rotation.
        // Refresh the full tree to tap the control's current visible bounds.
        guard let frame = playerFrame(in: try app.snapshot()) else {
            XCTFail("The persistent player is missing from the current screen.")
            return
        }
        app.windows.firstMatch.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: frame.midX, dy: frame.midY))
            .tap()
    }

    private func playerFrame(in snapshot: XCUIElementSnapshot) -> CGRect? {
        if snapshot.identifier == "iPadOpenNowPlaying" { return snapshot.frame }
        for child in snapshot.children {
            if let frame = playerFrame(in: child) { return frame }
        }
        return nil
    }

    @MainActor
    private func attachScreen(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
