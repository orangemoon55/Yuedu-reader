import Testing
@testable import yuedu_app

struct MediaTabMenuTests {
    @Test("discovery quick menu keeps video, music, drama order")
    func discoveryMenuOrder() {
        #expect(MediaHubKind.quickActionKinds(for: .explore) == [.video, .music, .drama])
    }

    @Test("bookshelf quick menu contains only video and music libraries")
    func bookshelfMenuOrder() {
        #expect(MediaHubKind.quickActionKinds(for: .bookshelf) == [.video, .music])
        #expect(!MediaHubKind.quickActionKinds(for: .bookshelf).contains(.drama))
    }

    @Test("other root tabs do not receive a media menu")
    func nonTargetTabsHaveNoMenu() {
        #expect(MediaHubKind.quickActionKinds(for: .settings).isEmpty)
        #expect(MediaHubKind.quickActionKinds(for: .search).isEmpty)
        #expect(MediaHubKind.quickActionKinds(for: .library).isEmpty)
        #expect(MediaHubKind.quickActionKinds(for: .rss).isEmpty)
    }

    @Test("home and library media routes keep separate stable identities")
    func mediaRouteIdentities() {
        for kind in MediaHubKind.allCases {
            let home = MediaHubRoute(kind: kind, isLibrary: false)
            let library = MediaHubRoute(kind: kind, isLibrary: true)
            #expect(home.id == "\(kind.rawValue).hub")
            #expect(library.id == "\(kind.rawValue).library")
            #expect(home != library)
            #expect(home.id != library.id)
        }
    }
}
