import Foundation
import Testing
@testable import yuedu_app

struct RemovedVideoUIBoundaryTests {
    @Test("music is the only standalone media destination; retired kinds cannot route")
    func onlyMusicRoutesRemain() {
        #expect(MediaHubKind.allCases == [.music])
        #expect(MediaHubKind(rawValue: "video") == nil)
        #expect(MediaHubKind(rawValue: "drama") == nil)
        #expect(MediaHubKind.discoveryMenuKinds == [.music])
        #expect(MediaHubKind.libraryMenuKinds == [.music])
        #expect(MediaHubKind.music.titleKey == "音乐")
        #expect(MediaHubKind.music.libraryTitleKey == "音乐库")
        #expect(MediaHubSelection.route(.music, isLibrary: false)?.id == "music.hub")
        #expect(MediaHubSelection.route(.music, isLibrary: true)?.id == "music.library")
    }

    @Test("retired film home bindings use lossless unknown JSON without resetting reading sections")
    func retiredHomeBindingIsPreservedButNotOffered() throws {
        let data = Data("""
        {"type":"catVod","catVodFeed":{"sourceID":"legacy","siteKey":"site","categoryID":"all"}}
        """.utf8)
        let old = try JSONDecoder().decode(HomeSectionBinding.self, from: data)
        #expect(!old.isKnown)
        let encoded = try JSONEncoder().encode(old)
        let roundTrip = try JSONDecoder().decode(HomeSectionBinding.self, from: encoded)
        #expect(roundTrip == old)
        #expect(HomeSectionBinding.bookshelf.isKnown)
        #expect(HomeSectionBinding.continueReading.isKnown)
        #expect(HomeSectionBinding.subscriptionArticles.isKnown)
    }
}
