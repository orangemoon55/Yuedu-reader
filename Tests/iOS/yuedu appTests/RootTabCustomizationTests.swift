import Testing
import Foundation
@testable import yuedu_app

@Suite("Root tab customization")
struct RootTabCustomizationTests {
    @Test("settings tab is always restored")
    func settingsTabIsAlwaysRestored() {
        let ids = GlobalSettings.sanitizedRootTabVisibleIDs([
            RootTabItem.bookshelf.rawValue
        ])

        #expect(ids.contains(RootTabItem.bookshelf.rawValue))
        #expect(ids.contains(RootTabItem.settings.rawValue))
    }

    @Test("at least one content tab remains visible")
    func atLeastOneContentTabRemainsVisible() {
        // A removed 資源庫 marker does not count as a visible content tab.
        let ids = GlobalSettings.sanitizedRootTabVisibleIDs([
            RootTabItem.settings.rawValue,
            RootTabItem.library.hiddenMarker,
            RootTabItem.search.hiddenMarker
        ])

        #expect(ids.contains(RootTabItem.bookshelf.rawValue))
        #expect(ids.contains(RootTabItem.settings.rawValue))
    }

    @Test("unknown tab ids are dropped and order is stable")
    func unknownTabIDsAreDroppedAndOrderIsStable() {
        let ids = GlobalSettings.sanitizedRootTabVisibleIDs([
            "unknown",
            RootTabItem.search.rawValue,
            RootTabItem.library.rawValue,
            RootTabItem.bookshelf.rawValue,
            RootTabItem.settings.rawValue
        ])

        #expect(ids == [RootTabItem.bookshelf.rawValue, RootTabItem.settings.rawValue, RootTabItem.search.rawValue])
    }

    @Test("the tabs are 探索・書架・設定・搜尋; 資源庫 and RSS are no longer tabs")
    func tabOrder() {
        #expect(RootTabItem.tabs == [.explore, .bookshelf, .settings, .search])
        #expect(RootTabItem.explore.titleKey == "主页")
        #expect(RootTabItem.search.defaultSystemImage == "magnifyingglass")
        #expect(RootTabItem.addedLater == [.search])
        #expect(GlobalSettings.defaultRootTabVisibleIDs == RootTabItem.tabs.map(\.rawValue))
    }

    @Test("legacy search ids remain visible while removed library ids are dropped")
    func oldSearchEntryIsPreserved() {
        let legacy = ["bookshelf", "explore", "library", "search", "settings"]
        let saved = GlobalSettings.sanitizedRootTabVisibleIDs(legacy)
        #expect(saved == ["explore", "bookshelf", "settings", "search"])
        #expect(GlobalSettings.visibleRootTabs(visibleIDs: legacy, orderIDs: legacy).contains(.search))
    }

    @Test("build18 three-tab preferences restore search without changing the main tabs")
    func threeTabPreferencesRestoreSearch() {
        let legacy = ["explore", "bookshelf", "settings"]
        let migrated = GlobalSettings.sanitizedRootTabVisibleIDs(legacy)
        #expect(migrated == ["explore", "bookshelf", "settings", "search"])
        #expect(GlobalSettings.sanitizedRootTabVisibleIDs(migrated) == migrated)
        #expect(GlobalSettings.visibleRootTabs(visibleIDs: legacy, orderIDs: legacy)
            == [.explore, .bookshelf, .settings, .search])
    }

    @Test("explicitly hiding search survives sanitization and can be reversed")
    func searchHiddenMarkerRoundTrips() {
        let hidden = GlobalSettings.updatedRootTabVisibleIDs(
            GlobalSettings.defaultRootTabVisibleIDs, setting: .search, visible: false)
        #expect(hidden == ["explore", "bookshelf", "settings", "-search"])
        #expect(GlobalSettings.sanitizedRootTabVisibleIDs(hidden) == hidden)
        #expect(GlobalSettings.visibleRootTabs(visibleIDs: hidden, orderIDs: ["search"])
            == [.explore, .bookshelf, .settings])
        let shown = GlobalSettings.updatedRootTabVisibleIDs(hidden, setting: .search, visible: true)
        #expect(shown == GlobalSettings.defaultRootTabVisibleIDs)
        #expect(GlobalSettings.sanitizedRootTabVisibleIDs(hidden + ["search"]) == shown)
    }

    @Test("restored search retains its custom icon asset identity")
    func searchIconAssetStillDecodes() throws {
        let asset = RootTabIconAsset(tabID: "search", slotRawValue: "dark", fileName: "search-dark.png",
                                     originalFileName: "custom-search.png", addedAt: Date(timeIntervalSince1970: 0))
        let restored = try JSONDecoder().decode(RootTabIconAsset.self, from: JSONEncoder().encode(asset))
        #expect(restored == asset)
        #expect(restored.tab == .search)
        #expect(restored.slot == .dark)
        #expect(RootTabItem.tabs.contains(.search))
    }

    @Test("legacy visible lists never restore 資源庫, whether shown, hidden or absent")
    func libraryDoesNotRejoinOldLists() {
        let lists = [
            ["bookshelf", "explore", "rss", "settings", "search"],
            ["bookshelf", "explore", "library", "search", "settings"],
            ["bookshelf", "explore", "-library", "search", "settings"],
            ["bookshelf", "explore", "library", "-library", "-rss", "search", "settings"]
        ]
        for list in lists {
            let migrated = GlobalSettings.sanitizedRootTabVisibleIDs(list)
            #expect(migrated == ["explore", "bookshelf", "settings", "search"])
            #expect(GlobalSettings.sanitizedRootTabVisibleIDs(migrated) == migrated)
        }
    }

    @Test("a removed 資源庫 tab cannot be restored by changing its visibility")
    @MainActor
    func removedLibraryCannotBeShown() {
        let ids = GlobalSettings.sanitizedRootTabVisibleIDs(
            GlobalSettings.updatedRootTabVisibleIDs(["bookshelf", "explore", "library", "search", "settings"],
                                             setting: .library, visible: false))
        #expect(!ids.contains("library"))
        #expect(GlobalSettings.sanitizedRootTabVisibleIDs(ids) == ids, "stable once removed")
        let shown = GlobalSettings.sanitizedRootTabVisibleIDs(
            GlobalSettings.updatedRootTabVisibleIDs(ids, setting: .library, visible: true))
        #expect(shown == ids)
    }

    @Test("custom icons for removed tabs still decode", arguments: [RootTabItem.rss, .library])
    func removedTabIconAssetsKept(tab: RootTabItem) {
        let fileName = "\(tab.rawValue).png"
        let asset = RootTabIconAsset(tabID: tab.rawValue, slotRawValue: "light", fileName: fileName,
                                     originalFileName: fileName, addedAt: Date())
        #expect(asset.tab == tab)
        #expect(!RootTabItem.tabs.contains(tab))
    }

    @Test("tab icon size is clamped")
    func tabIconSizeIsClamped() {
        #expect(FloatingRootTabBarLayout.defaultIconSize == 20)
        #expect(RootTabIconRenderer.sanitizedIconSize(10) == 20)
        #expect(RootTabIconRenderer.sanitizedIconSize(20) == 20)
        #expect(RootTabIconRenderer.sanitizedIconSize(28) == 28)
        #expect(RootTabIconRenderer.sanitizedIconSize(80) == 36)
    }

    @Test("zero tab icon size keeps Apple's system default")
    func zeroTabIconSizeKeepsSystemDefault() {
        #expect(GlobalSettings.sanitizedRootTabIconSize(0) == 0)
        #expect(GlobalSettings.sanitizedRootTabIconSize(-8) == 0)
        #expect(GlobalSettings.sanitizedRootTabIconSize(10) == 20)
    }
}
