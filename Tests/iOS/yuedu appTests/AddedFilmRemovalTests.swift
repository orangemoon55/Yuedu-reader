import Foundation
import Testing
@testable import yuedu_app

@Suite("Music survives removal of the added film feature")
@MainActor
struct AddedFilmRemovalTests {
    @Test func menuContainsMusicOnly() {
        #expect(MediaHubKind.allCases == [.music])
        #expect(MediaHubKind.discoveryMenuKinds == [.music])
        #expect(MediaHubKind.libraryMenuKinds == [.music])
    }

    @Test func retiredKindsCannotDecodeBackIntoTheMenu() {
        for value in ["video", "drama"] {
            #expect(MediaHubKind(rawValue: value) == nil)
        }
    }

    @Test func codaRoutesRemainSeparateForHomeAndLibrary() {
        let home = MediaHubSelection.route(.music, isLibrary: false)
        let library = MediaHubSelection.route(.music, isLibrary: true)
        #expect(home?.id != library?.id)
        #expect(MediaHubSelection.route(nil, isLibrary: false) == nil)
        #expect(MediaHubSelection.route(nil, isLibrary: true) == nil)
    }
}
