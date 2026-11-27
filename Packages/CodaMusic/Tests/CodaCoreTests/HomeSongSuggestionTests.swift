import Foundation
import Testing
@testable import CodaCore

@Suite("Home song recommendation selection")
struct HomeSongSuggestionTests {
    @Test func rotatesSeedsBeforeReusingPreviousBatch() {
        #expect(HomeSongSuggestionSelection.seeds(from: [1, 2, 3, 4, 5, 6], avoiding: [1, 2, 3]) == [4, 5, 6])
        #expect(HomeSongSuggestionSelection.seeds(from: [1, 2, 3, 4], avoiding: [1, 2, 3]) == [4, 1, 2])
    }

    @Test func seedSelectionHandlesSmallEmptyAndDuplicateLibraries() {
        #expect(HomeSongSuggestionSelection.seeds(from: [], avoiding: []).isEmpty)
        #expect(HomeSongSuggestionSelection.seeds(from: [1, 1, 2], avoiding: [1, 2]) == [1, 2])
        #expect(HomeSongSuggestionSelection.seeds(from: [1], avoiding: [], limit: 0).isEmpty)
    }

    @Test func retainsRecommendationsBeyondTheFirstVisibleColumn() throws {
        let source = try tracks(Array(1...12))
        let result = HomeSongSuggestionSelection.select([source], excluding: [])
        #expect(result.map(\.id) == Array(1...12))
    }

    private func tracks(_ ids: [Int]) throws -> [Track] {
        try ids.map { id in
            try JSONDecoder().decode(Track.self, from: Data("{\"id\":\(id),\"name\":\"Track \(id)\"}".utf8))
        }
    }

    @Test func balancesSeedsExcludesLikedSongsAndDeduplicates() throws {
        let groups = try [tracks([1, 2, 3]), tracks([2, 4, 5]), tracks([6, 7])]
        let result = HomeSongSuggestionSelection.select(groups, excluding: [1, 7], limit: 5)
        #expect(result.map(\.id) == [2, 6, 4, 3, 5])
    }

    @Test func neverInventsFallbackTracksWhenSourcesAreEmptyOrExcluded() throws {
        #expect(HomeSongSuggestionSelection.select([], excluding: []).isEmpty)
        let group = try tracks([1, 1, 2])
        #expect(HomeSongSuggestionSelection.select([group], excluding: [1, 2]).isEmpty)
        #expect(HomeSongSuggestionSelection.select([group], excluding: [], limit: 0).isEmpty)
        #expect(HomeSongSuggestionSelection.select([group], excluding: [], limit: 1).map(\.id) == [1])
    }
}
