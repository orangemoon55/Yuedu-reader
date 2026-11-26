import Foundation
import Testing
@testable import yuedu_app

struct MediaHubInteractionTests {
    @Test("configuration labels are native settings, not a film catalogue")
    func configurationSiteRole() {
        #expect(CatVodSiteRole.isConfiguration(name: "配置 | 中心", key: "spider-config"))
        #expect(CatVodSiteRole.isConfiguration(name: "配置中心", key: "custom"))
        #expect(CatVodSiteRole.isConfiguration(name: "設定中心", key: "settings"))
        #expect(!CatVodSiteRole.isConfiguration(name: "玩偶 | 4K", key: "wogg"))
        #expect(!CatVodSiteRole.isConfiguration(name: "配置電影", key: "movie"))
        #expect(!CatVodSiteRole.isConfiguration(name: "我的 | 网盘", key: "drive"))
    }

    @Test("long-press destinations stay transient and scoped to each root")
    func transientRootSelections() {
        var homeSelection: MediaHubKind? = nil
        var librarySelection: MediaHubKind? = nil
        #expect(MediaHubSelection.route(homeSelection, isLibrary: false) == nil)
        #expect(MediaHubSelection.route(librarySelection, isLibrary: true) == nil)

        homeSelection = .video
        librarySelection = .music
        #expect(MediaHubSelection.route(homeSelection, isLibrary: false)?.id == "video.hub")
        #expect(MediaHubSelection.route(librarySelection, isLibrary: true)?.id == "music.library")
        #expect(MediaHubSelection.route(.drama, isLibrary: true) == nil)

        // Closing returns to the normal root and drops the in-memory selection.
        homeSelection = nil
        librarySelection = nil
        #expect(MediaHubSelection.route(homeSelection, isLibrary: false) == nil)
        #expect(MediaHubSelection.route(librarySelection, isLibrary: true) == nil)
    }

    @Test("typed destinations keep stable route identities")
    func routeIdentities() {
        #expect(MediaHubSelection.route(.music, isLibrary: false)?.id == "music.hub")
        #expect(MediaHubSelection.route(.video, isLibrary: true)?.id == "video.library")
        #expect(MediaHubSelection.route(nil, isLibrary: false) == nil)
    }
}
