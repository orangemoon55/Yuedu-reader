import Foundation
import Testing
@testable import yuedu_app

struct MediaTabMenuTests {
    @Test("home quick menu contains only music")
    func discoveryMenuOrder() {
        #expect(MediaHubKind.quickActionKinds(for: .explore) == [.music])
    }

    @Test("bookshelf quick menu contains only music library")
    func bookshelfMenuOrder() {
        #expect(MediaHubKind.quickActionKinds(for: .bookshelf) == [.music])
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

    @Test("route updates execute immediately without a guessed dismissal delay")
    @MainActor func immediateMenuSelection() {
        let coordinator = RootTabMediaActionCoordinator()
        var selected: [String] = []
        coordinator.perform { selected.append("music") }
        #expect(selected == ["music"])
        coordinator.perform { selected.append("reading") }
        #expect(selected == ["music", "reading"])
    }
}
