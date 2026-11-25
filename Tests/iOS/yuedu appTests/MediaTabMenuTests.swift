import Foundation
import Testing
@testable import yuedu_app

struct MediaTabMenuTests {
    @Test("home quick menu contains only video and music")
    func discoveryMenuOrder() {
        #expect(MediaHubKind.quickActionKinds(for: .explore) == [.video, .music])
        #expect(!MediaHubKind.quickActionKinds(for: .explore).contains(.drama))
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

    @Test("menu actions do not mutate route inline and only the latest selection executes")
    @MainActor func deferredMenuSelection() async {
        let gate = MenuDismissalGate()
        let coordinator = RootTabMediaActionCoordinator(waitForDismissal: { await gate.wait() })
        var selected: [String] = []
        coordinator.schedule { selected.append("video") }
        coordinator.schedule { selected.append("music") }
        #expect(selected.isEmpty)
        await gate.open()
        for _ in 0..<200 where selected.isEmpty { await Task.yield() }
        #expect(selected == ["music"])
    }

    @Test("a subsequent normal tab tap cancels pending menu navigation")
    @MainActor func cancelledMenuSelection() async {
        let gate = MenuDismissalGate()
        let coordinator = RootTabMediaActionCoordinator(waitForDismissal: { await gate.wait() })
        var changed = false
        coordinator.schedule { changed = true }
        coordinator.cancel()
        await gate.open()
        for _ in 0..<200 { await Task.yield() }
        #expect(!changed)
    }
}

private actor MenuDismissalGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() {
        isOpen = true
        let continuations = waiters
        waiters.removeAll()
        for continuation in continuations { continuation.resume() }
    }
}
