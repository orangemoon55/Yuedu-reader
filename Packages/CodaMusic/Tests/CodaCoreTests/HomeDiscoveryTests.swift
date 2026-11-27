import Foundation
import Testing
@testable import CodaCore

@Suite("Homepage discovery shelves")
@MainActor
struct HomeDiscoveryTests {
    private func track(_ id: Int) throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data("{\"id\":\(id),\"name\":\"Song \(id)\"}".utf8))
    }

    @Test func extractsTypedModulesAndIgnoresUnplayableResources() throws {
        let fixture = Data("""
        {"code":200,"data":{"blocks":[
          {"blockCode":"HOMEPAGE_BLOCK_PLAYLIST_RCMD","creatives":[{"resources":[
            {"resourceType":"list","resourceId":"42","uiElement":{"mainTitle":{"title":"Playlist"},"image":{"imageUrl":"https://example.com/cover.jpg"}}},
            {"resourceType":"playlist","resourceId":42,"uiElement":{"mainTitle":{"title":"Duplicate"}}},
            {"resourceType":"list","resourceId":43,"valid":false}
          ]}]},
          {"uiElement":{"subTitle":{"title":"近期云村热播"}},"creatives":[{"resources":[
            {"resourceType":"song","resourceExtInfo":{"songData":{"id":7,"name":"Song","dt":123000,"al":{"id":8,"name":"Album"}}}},
            {"resourceType":"song","resourceExtInfo":{"song":{"id":7,"name":"Duplicate"}}},
            {"resourceType":"video","resourceId":9},
            {"resourceType":"song","resourceId":10}
          ]}]},
          {"uiElement":{"mainTitle":{"title":"欧美最近的热门歌曲"}},"creatives":[{"resources":[
            {"resourceType":"playlist","resourceId":99,"uiElement":{"mainTitle":{"title":"Regional playlist"}}}
          ]}]},
          {"blockCode":"UNRELATED","creatives":[]}
        ]}}
        """.utf8)
        let result = try NeteaseAPI.decodeHomeDiscovery(fixture)
        guard case .playlists(let playlists) = result[.playlists],
              case .songs(let songs) = result[.trending],
              case .playlists(let regional) = result[.regional] else {
            Issue.record("Source resource types must be preserved")
            return
        }
        #expect(playlists.map(\.id) == [42])
        #expect(playlists.first?.coverURL == "https://example.com/cover.jpg")
        #expect(songs.map(\.id) == [7])
        #expect(songs.first?.durationMS == 123000)
        #expect(regional.map(\.id) == [99])
    }

    @Test func aggregatesMultipleRegionalModules() throws {
        let fixture = Data("""
        {"code":200,"data":{"blocks":[
          {"uiElement":{"subTitle":{"title":"华语最近的热门歌曲"}},"creatives":[{"resources":[
            {"resourceType":"song","resourceExtInfo":{"songData":{"id":1,"name":"Chinese"}}}
          ]}]},
          {"uiElement":{"subTitle":{"title":"欧美最近的热门歌曲"}},"creatives":[{"resources":[
            {"resourceType":"song","resourceExtInfo":{"songData":{"id":2,"name":"Western"}}},
            {"resourceType":"song","resourceExtInfo":{"songData":{"id":1,"name":"Duplicate"}}}
          ]}]}
        ]}}
        """.utf8)
        let result = try NeteaseAPI.decodeHomeDiscovery(fixture)
        if case .songs(let songs) = result[.regional] { #expect(songs.map(\.id) == [1, 2]) }
        else { Issue.record("Expected aggregated regional modules") }
    }

    @Test func regionalAggregationInterleavesAndDeduplicates() throws {
        let groups = try [[1, 2], [3, 1], [4, 5], [6, 7]].map { try $0.map(track) }
        #expect(HomeDiscoveryModel.mergeSongs(groups, limit: 7).map(\.id) == [1, 3, 4, 6, 2, 5, 7])
    }

    @Test func missingModulesFallbackIndependentlyAndFailuresPreserveSnapshot() async throws {
        var fail = false
        var calls: [Int] = []
        let song = try track(8)
        let model = HomeDiscoveryModel(fetchHome: { _ in [.playlists: .playlists([])] },
                                       fetchPlaylists: { _ in Issue.record("Server module should win"); return [] },
                                       fetchSongs: { area in
            calls.append(area)
            if fail { throw URLError(.notConnectedToInternet) }
            return [song]
        })
        let now = Date()
        await model.load(loggedIn: false, now: now)
        #expect(Set(calls) == Set([0, 7, 96, 8, 16]))
        #expect(model.failedSlots.isEmpty)
        let count = calls.count
        await model.load(loggedIn: false, now: now.addingTimeInterval(30))
        #expect(calls.count == count)
        fail = true
        await model.load(loggedIn: false, force: true)
        #expect(model.failedSlots == Set([.trending, .regional]))
        if case .songs(let tracks) = model.contents[.regional] { #expect(tracks.map(\.id) == [8]) }
        else { Issue.record("Refresh failure erased previous songs") }
        fail = false
        await model.load(loggedIn: false)
        #expect(model.failedSlots.isEmpty)
    }

    @Test func serverShelvesAppearBeforeSlowFallbackFinishes() async throws {
        var pending: CheckedContinuation<[PlaylistSummary], Error>?
        let song = try track(12)
        let model = HomeDiscoveryModel(
            fetchHome: { _ in [.trending: .songs([song])] },
            fetchPlaylists: { _ in try await withCheckedThrowingContinuation { pending = $0 } },
            fetchSongs: { _ in [song] })
        let loading = Task { await model.load(loggedIn: false) }
        while pending == nil { await Task.yield() }
        if case .songs(let tracks) = model.contents[.trending] {
            #expect(tracks.map(\.id) == [12])
        } else { Issue.record("A slow fallback hid a completed server shelf") }
        #expect(model.isLoading)
        #expect(!model.loadingSlots.contains(.trending))
        #expect(model.loadingSlots.contains(.playlists))
        pending?.resume(returning: [])
        await loading.value
        #expect(!model.isLoading)
    }

    @Test func regionalModuleWaitsForEveryRegion() async throws {
        var pending: CheckedContinuation<[Track], Error>?
        var completed = Set<Int>()
        let song = try track(21)
        let model = HomeDiscoveryModel(
            fetchHome: { _ in [.playlists: .playlists([]), .trending: .songs([song])] },
            fetchPlaylists: { _ in [] },
            fetchSongs: { area in
                if area == 16 {
                    return try await withCheckedThrowingContinuation { pending = $0 }
                }
                completed.insert(area)
                return [song]
            }, availableSlots: { MusicProvider.netease.homeDiscoverySlots })
        let loading = Task { await model.load(loggedIn: false) }
        while pending == nil || completed.count < 3 { await Task.yield() }
        #expect(model.loadingSlots == [.regional])
        #expect(model.contents[.regional] == nil)
        #expect(model.contents[.trending] != nil)
        pending?.resume(returning: [song])
        await loading.value
        #expect(model.loadingSlots.isEmpty)
        if case .songs(let tracks) = model.contents[.regional] {
            #expect(tracks.map(\.id) == [21])
        } else { Issue.record("Expected a complete regional module") }
    }

    @Test func forcedRefreshRejectsLateEarlierResponse() async throws {
        var first: CheckedContinuation<[HomeDiscoverySlot: HomeDiscoveryContent], Error>?
        var count = 0
        let olderSong = try track(1)
        let newerSong = try track(2)
        let model = HomeDiscoveryModel(fetchHome: { _ in
            count += 1
            if count == 1 { return try await withCheckedThrowingContinuation { first = $0 } }
            return Dictionary(uniqueKeysWithValues: HomeDiscoverySlot.allCases.map { ($0, .songs([newerSong])) })
        }, fetchPlaylists: { _ in [] }, fetchSongs: { _ in [] })
        let older = Task { await model.load(loggedIn: false) }
        while first == nil { await Task.yield() }
        await model.load(loggedIn: false, force: true)
        first?.resume(returning: [.trending: .songs([olderSong])])
        await older.value
        if case .songs(let songs) = model.contents[.trending] { #expect(songs.map(\.id) == [2]) }
        else { Issue.record("Expected newest response") }
        #expect(!model.isLoading)
    }
}
