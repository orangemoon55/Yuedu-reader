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
            RootTabItem.library.hiddenMarker
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

        #expect(ids == [RootTabItem.bookshelf.rawValue, RootTabItem.settings.rawValue])
    }

    @Test("the tabs are 探索・書架・設定・搜尋; 資源庫 and RSS are no longer tabs")
    func tabOrder() {
        #expect(RootTabItem.tabs == [.explore, .bookshelf, .settings])
        #expect(!RootTabItem.tabs.contains(.search))
        #expect(RootTabItem.search.defaultSystemImage == "magnifyingglass")
        #expect(RootTabItem.addedLater.isEmpty)
        #expect(GlobalSettings.defaultRootTabVisibleIDs == RootTabItem.tabs.map(\.rawValue))
    }

    @Test("legacy search ids are removed from saved visible tabs")
    func oldSearchEntryIsFiltered() {
        let legacy = ["bookshelf", "explore", "library", "search", "settings"]
        let saved = GlobalSettings.sanitizedRootTabVisibleIDs(legacy)
        #expect(saved == ["explore", "bookshelf", "settings"])
        #expect(!GlobalSettings.visibleRootTabs(visibleIDs: legacy, orderIDs: legacy).contains(.search))
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
            #expect(migrated == ["explore", "bookshelf", "settings"])
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
        #expect(RootTabIconRenderer.sanitizedIconSize(10) == 22)
        #expect(RootTabIconRenderer.sanitizedIconSize(28) == 28)
        #expect(RootTabIconRenderer.sanitizedIconSize(80) == 36)
    }

    @Test("zero tab icon size keeps Apple's system default")
    func zeroTabIconSizeKeepsSystemDefault() {
        #expect(GlobalSettings.sanitizedRootTabIconSize(0) == 0)
        #expect(GlobalSettings.sanitizedRootTabIconSize(-8) == 0)
        #expect(GlobalSettings.sanitizedRootTabIconSize(10) == 22)
    }
}
