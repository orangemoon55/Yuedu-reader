import Foundation
import Testing
@testable import CodaCore

@Suite("Search refresh safety")
@MainActor
struct SearchRefreshTests {
    private func result(id: Int) throws -> NeteaseAPI.SearchResult {
        try JSONDecoder().decode(NeteaseAPI.SearchResult.self,
            from: Data("{\"songs\":[{\"id\":\(id),\"name\":\"song\"}]}".utf8))
    }

    @Test func olderQueryCannotOverwriteNewerResults() async throws {
        var pending: CheckedContinuation<NeteaseAPI.SearchResult, Error>?
        let fresh = try result(id: 2)
        let model = SearchViewModel(query: "old") { query, _, _, _ in
            if query == "old" { return try await withCheckedThrowingContinuation { pending = $0 } }
            return fresh
        }
        let old = Task { await model.load(tab: .songs) }
        while pending == nil { await Task.yield() }
        model.setQuery("new")
        await model.load(tab: .songs)
        pending?.resume(returning: try result(id: 1))
        await old.value
        #expect(model.songs.map(\.id) == [2])
    }

    @Test func failedTabCanRetry() async throws {
        var attempts = 0
        let fresh = try result(id: 2)
        let model = SearchViewModel(query: "song") { _, _, _, _ in
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return fresh
        }
        await model.load(tab: .songs)
        #expect(!model.loadedTabs.contains(.songs))
        #expect(model.errorMessage != nil)
        await model.load(tab: .songs)
        #expect(attempts == 2)
        #expect(model.loadedTabs.contains(.songs))
        #expect(model.errorMessage == nil)
    }

    @Test func switchingThroughAllRestoresFullSongTab() async throws {
        let full = try result(id: 100)
        let preview = try result(id: 12)
        let model = SearchViewModel(query: "song") { _, _, limit, _ in limit == 100 ? full : preview }
        await model.load(tab: .songs)
        #expect(model.songs.first?.id == 100)
        await model.load(tab: .all)
        #expect(model.songs.first?.id == 12)
        await model.load(tab: .songs)
        #expect(model.songs.first?.id == 100)
    }

    private func page(_ ids: [Int], total: Int? = nil) throws -> NeteaseAPI.SearchResult {
        var json: [String: Any] = ["songs": ids.map { ["id": $0, "name": "song"] }]
        if let total { json["songCount"] = total }
        return try JSONDecoder().decode(NeteaseAPI.SearchResult.self,
            from: JSONSerialization.data(withJSONObject: json))
    }

    @Test func paginationAppendsUniqueSongsAndStopsAtEnd() async throws {
        var offsets: [Int] = []
        let first = try page(Array(1...100), total: 102)
        let last = try page([100, 101, 102], total: 102)
        let model = SearchViewModel(query: "song") { _, _, _, offset in
            offsets.append(offset)
            return offset == 0 ? first : last
        }
        model.tab = .songs
        await model.load(tab: .songs)
        #expect(model.hasMoreSongs)
        await model.loadMoreSongs()
        #expect(offsets == [0, 100])
        #expect(model.songs.map(\.id) == Array(1...102))
        #expect(!model.hasMoreSongs)
        await model.loadMoreSongs()
        #expect(offsets == [0, 100])
        await model.load(tab: .all)
        await model.load(tab: .songs)
        #expect(model.songs.count == 102)
        #expect(!model.hasMoreSongs)
    }

    @Test func oldPageCannotAppendAfterQueryChanges() async throws {
        var pending: CheckedContinuation<NeteaseAPI.SearchResult, Error>?
        let first = try page(Array(1...100))
        let fresh = try page([999])
        let model = SearchViewModel(query: "old") { query, _, _, offset in
            if query == "new" { return fresh }
            if offset == 0 { return first }
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        model.tab = .songs
        await model.load(tab: .songs)
        let next = Task { await model.loadMoreSongs() }
        while pending == nil { await Task.yield() }
        #expect(model.isLoadingMoreSongs)
        model.setQuery("new")
        await model.load(tab: .songs)
        pending?.resume(returning: try page([101]))
        await next.value
        #expect(model.songs.map(\.id) == [999])
        #expect(!model.isLoadingMoreSongs)
    }

    @Test func failedPagePreservesSongsAndRetriesSameOffset() async throws {
        let first = try page(Array(1...100))
        let last = try page([101])
        var pageAttempts = 0
        let model = SearchViewModel(query: "song") { _, _, _, offset in
            if offset == 0 { return first }
            #expect(offset == 100)
            pageAttempts += 1
            if pageAttempts == 1 { throw URLError(.notConnectedToInternet) }
            return last
        }
        model.tab = .songs
        await model.load(tab: .songs)
        await model.loadMoreSongs()
        #expect(model.songs.count == 100)
        #expect(model.songPageError != nil)
        #expect(!model.isLoadingMoreSongs)
        await model.loadMoreSongs()
        #expect(model.songs.count == 101)
        #expect(model.songPageError == nil)
    }

    private func cardPage(_ ids: [Int], total: Int) throws -> NeteaseAPI.SearchResult {
        let entries = ids.map { ["id": $0, "name": "card"] as [String: Any] }
        return try JSONDecoder().decode(NeteaseAPI.SearchResult.self,
            from: JSONSerialization.data(withJSONObject: [
                "artists": entries, "albums": entries, "playlists": entries,
                "artistCount": total, "albumCount": total, "playlistCount": total
            ]))
    }

    @Test func allSearchCardShelvesContinueAndCacheTheirPages() async throws {
        let first = try cardPage(Array(1...10), total: 12)
        let last = try cardPage([10, 11, 12], total: 12)
        var nextOffsets: [Int] = []
        let model = SearchViewModel(query: "cards") { _, _, _, offset in
            if offset > 0 { nextOffsets.append(offset) }
            return offset == 0 ? first : last
        }
        await model.load(tab: .all)
        for kind in [SearchViewModel.Tab.artists, .albums, .playlists] {
            #expect(model.horizontalLoading(for: kind).hasMore)
            await model.loadMoreCards(kind)
            #expect(!model.horizontalLoading(for: kind).hasMore)
        }
        #expect(nextOffsets == [10, 10, 10])
        #expect(model.artists.map(\.id) == Array(1...12))
        #expect(model.albums.map(\.id) == Array(1...12))
        #expect(model.playlists.map(\.id) == Array(1...12))
        await model.load(tab: .artists)
        await model.load(tab: .all)
        #expect(model.albums.count == 12)
        #expect(!model.horizontalLoading(for: .albums).hasMore)
    }

    @Test func oldCardPageCannotAppendAfterQueryChanges() async throws {
        let first = try cardPage(Array(1...10), total: 20)
        let fresh = try cardPage([999], total: 1)
        var pending: CheckedContinuation<NeteaseAPI.SearchResult, Error>?
        let model = SearchViewModel(query: "old") { query, _, _, offset in
            if query == "new" { return fresh }
            if offset == 0 { return first }
            return try await withCheckedThrowingContinuation { pending = $0 }
        }
        await model.load(tab: .all)
        let request = Task { await model.loadMoreCards(.albums) }
        while pending == nil { await Task.yield() }
        #expect(model.horizontalLoading(for: .albums).isLoading)
        model.setQuery("new")
        await model.load(tab: .all)
        pending?.resume(returning: try cardPage([11], total: 20))
        await request.value
        #expect(model.albums.map(\.id) == [999])
        #expect(!model.horizontalLoading(for: .albums).isLoading)
    }

}
