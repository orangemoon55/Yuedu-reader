import Testing
@testable import CodaCore

@Suite("Navigation destination tests")
struct NavigationDestinationTests {
    @Test func doesNotAppendTheCurrentDestination() {
        var destinations: [Destination] = [.artist(42)]

        destinations.appendIfNotCurrent(.artist(42))

        #expect(destinations == [.artist(42)])
    }

    @Test func appendsADifferentDestination() {
        var destinations: [Destination] = [.album(7)]

        destinations.appendIfNotCurrent(.artist(42))

        #expect(destinations == [.album(7), .artist(42)])
    }

    @Test func onlyExplicitSidebarRoutesReplaceTheRoot() {
        let items: [SidebarItem] = [.home, .account, .downloaded, .recents,
                                    .cloud, .collections, .daily, .playlist(42), .likedSongs]
        for item in items {
            #expect(Destination.sidebar(item).sidebarRoot == item)
        }
    }

    @Test func pageLinksKeepTheirBackHistory() {
        let destinations: [Destination] = [
            .downloaded, .recents, .cloud, .collections, .daily, .playlist(7),
            .album(7), .artist(7), .downloadTasks, .playRanking,
            .librarySection(.createdPlaylists), .librarySection(.albums)
        ]
        for destination in destinations {
            #expect(destination.sidebarRoot == nil)
        }
    }
}
