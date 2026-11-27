import Foundation
import Testing
@testable import yuedu_app

struct MediaHubInteractionTests {
    @Test("long-press destinations stay transient and scoped to each root")
    func transientRootSelections() {
        var homeSelection: MediaHubKind? = nil
        var librarySelection: MediaHubKind? = nil
        #expect(MediaHubSelection.route(homeSelection, isLibrary: false) == nil)
        #expect(MediaHubSelection.route(librarySelection, isLibrary: true) == nil)

        homeSelection = .music
        librarySelection = .music
        #expect(MediaHubSelection.route(homeSelection, isLibrary: false)?.id == "music.hub")
        #expect(MediaHubSelection.route(librarySelection, isLibrary: true)?.id == "music.library")

        // Closing returns to the normal root and drops the in-memory selection.
        homeSelection = nil
        librarySelection = nil
        #expect(MediaHubSelection.route(homeSelection, isLibrary: false) == nil)
        #expect(MediaHubSelection.route(librarySelection, isLibrary: true) == nil)
    }

    @Test("typed destinations keep stable route identities")
    func routeIdentities() {
        #expect(MediaHubSelection.route(.music, isLibrary: false)?.id == "music.hub")
        #expect(MediaHubSelection.route(.music, isLibrary: true)?.id == "music.library")
        #expect(MediaHubSelection.route(nil, isLibrary: false) == nil)
    }
}
