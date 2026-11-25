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

    @Test("home content survives reopening defaults until explicitly replaced")
    func persistedHomeContent() throws {
        let suite = "readcc.media-selection.test." + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(MediaHubSelection.route(defaults.string(forKey: MediaHubSelection.homeKey) ?? "", isLibrary: false) == nil)
        defaults.set(MediaHubKind.video.rawValue, forKey: MediaHubSelection.homeKey)
        defaults.synchronize()
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(MediaHubSelection.route(reopened.string(forKey: MediaHubSelection.homeKey) ?? "", isLibrary: false)?.kind == .video)
        // Selecting a library does not clear the separately saved home selection.
        reopened.set(MediaHubKind.music.rawValue, forKey: MediaHubSelection.libraryKey)
        #expect(MediaHubSelection.route(reopened.string(forKey: MediaHubSelection.homeKey) ?? "", isLibrary: false)?.kind == .video)
        #expect(MediaHubSelection.route(reopened.string(forKey: MediaHubSelection.libraryKey) ?? "", isLibrary: true)?.kind == .music)
        reopened.set(MediaHubKind.drama.rawValue, forKey: MediaHubSelection.homeKey)
        #expect(MediaHubSelection.route(reopened.string(forKey: MediaHubSelection.homeKey) ?? "", isLibrary: false)?.kind == .drama)
        reopened.set("", forKey: MediaHubSelection.homeKey)
        #expect(MediaHubSelection.route(reopened.string(forKey: MediaHubSelection.homeKey) ?? "", isLibrary: false) == nil)
    }

    @Test("unknown persisted values and unsupported library kinds fall back to reading")
    func invalidStoredSelection() {
        #expect(MediaHubSelection.route("unknown", isLibrary: false) == nil)
        #expect(MediaHubSelection.route("drama", isLibrary: true) == nil)
        #expect(MediaHubSelection.route("music", isLibrary: false)?.id == "music.hub")
        #expect(MediaHubSelection.route("video", isLibrary: true)?.id == "video.library")
        #expect(MediaHubSelection.homeKey != MediaHubSelection.libraryKey)
    }
}
