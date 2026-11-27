import Foundation
import Testing
@testable import CodaCore

private final class RadarModuleProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var module = Data()
    private static var detail = Data()
    private static var songDetail = Data()
    private static var paths: [String] = []

    static func prepare(module: [String: Any], detail: [String: Any] = ["code": 500],
                        songDetail: [String: Any] = ["code": 500]) throws {
        let moduleData = try JSONSerialization.data(withJSONObject: module)
        let detailData = try JSONSerialization.data(withJSONObject: detail)
        let songData = try JSONSerialization.data(withJSONObject: songDetail)
        lock.withLock { self.module = moduleData; self.detail = detailData; self.songDetail = songData; paths = [] }
    }
    static var requests: [String] { lock.withLock { paths } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let data = Self.lock.withLock { () -> Data in
            let path = request.url!.path
            Self.paths.append(path)
            switch path {
            case "/eapi/pc/customize/block/page": return Self.module
            case "/eapi/v3/song/detail": return Self.songDetail
            default: return Self.detail
            }
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Radar playlist source updates", .serialized)
@MainActor
struct RadarPlaylistTests {
    @Test func chartPreviewExpiryPreservesStaleDataAndRetriesFailures() async {
        var calls = 0
        var fails = false
        let model = HomeViewModel(fetchToplistPreview: { _ in
            calls += 1
            if fails { throw URLError(.notConnectedToInternet) }
            return ([], [42: calls], [42: Double(calls)])
        })
        let now = Date()
        await model.loadToplistTracks(id: 42, now: now)
        await model.loadToplistTracks(id: 42, now: now.addingTimeInterval(1799))
        #expect(calls == 1)
        fails = true
        await model.loadToplistTracks(id: 42, now: now.addingTimeInterval(1801))
        #expect(calls == 2)
        #expect(model.toplistPreviousRanks[42] == [42: 1])
        #expect(model.failedToplistIDs.contains(42))
        fails = false
        await model.loadToplistTracks(id: 42, now: now.addingTimeInterval(1802))
        #expect(calls == 3)
        #expect(model.toplistPreviousRanks[42] == [42: 3])
        #expect(!model.failedToplistIDs.contains(42))
        await model.loadToplistTracks(id: 42, force: true, now: now.addingTimeInterval(1803))
        #expect(calls == 4)
    }

    @Test func newerForcedChartRefreshRejectsEarlierResponse() async {
        var first: CheckedContinuation<HomeViewModel.ToplistPreview, Error>?
        var calls = 0
        let model = HomeViewModel(fetchToplistPreview: { _ in
            calls += 1
            if calls == 1 { return try await withCheckedThrowingContinuation { first = $0 } }
            return ([], [42: 2], [:])
        })
        let older = Task { await model.loadToplistTracks(id: 42) }
        while first == nil { await Task.yield() }
        await model.loadToplistTracks(id: 42, force: true)
        first?.resume(returning: ([], [42: 1], [:]))
        await older.value
        #expect(model.toplistPreviousRanks[42] == [42: 2])
    }

    private func batch(_ revision: String) -> [NeteaseAPI.RadarPlaylist] {
        [91, 82, 73, 64, 55, 46].map { id in
            .init(brief: .init(id: id, name: "今天从《\(revision)》听起 | 私人雷达",
                              coverImgUrl: "https://example.com/\(id)/\(revision).jpg"))
        }
    }

    @Test func preservesSourceIntroAndCoverIncludingWatermarks() {
        let cover = "https://p1.music.126.net/cover.jpg?imageView=1&watermark&type=1&image=source"
        let playlist = NeteaseAPI.RadarPlaylist(brief: .init(
            id: 10_106_461_201, name: " 从《A | B》开始重温经典 | 怀旧雷达 ", coverImgUrl: cover))
        #expect(playlist.title == "怀旧雷达")
        #expect(playlist.subtitle == "从《A | B》开始重温经典")
        #expect(playlist.coverURL == cover)
        #expect(playlist.coverURL?.resizedImageURL(384)?.absoluteString.contains("watermark") == true)
    }

    @Test func unnamedIntroDoesNotReplaceSourceName() {
        let playlist = NeteaseAPI.RadarPlaylist(brief: .init(id: 8_402_996_200, name: "会员雷达", coverImgUrl: nil))
        #expect(playlist.title == "会员雷达")
        #expect(playlist.subtitle == nil)
    }

    @Test func cachedHomeStillUpdatesAfterExpiryAndManualRefresh() async {
        var calls = 0
        let model = HomeViewModel(fetchRadarPlaylists: { calls += 1; return batch("\(calls)") })
        let now = Date()
        await model.refreshRadarPlaylists(loggedIn: true, now: now)
        await model.refreshRadarPlaylists(loggedIn: true, now: now.addingTimeInterval(30))
        #expect(calls == 1)
        await model.refreshRadarPlaylists(loggedIn: true, now: now.addingTimeInterval(301))
        #expect(calls == 2)
        #expect(model.radarPlaylists.first?.subtitle == "今天从《2》听起")
        await model.refreshRadarPlaylists(loggedIn: true, force: true, now: now.addingTimeInterval(302))
        #expect(calls == 3)
        #expect(model.radarPlaylists.first?.coverURL?.hasSuffix("/3.jpg") == true)
        // Returning to an already loaded homepage still checks source freshness.
        model.state = .loaded
        await model.load(loggedIn: false)
        #expect(model.radarPlaylists.isEmpty)
        await model.load(loggedIn: true)
        #expect(calls == 4)
    }

    @Test func crossingMidnightInvalidatesEvenFreshCards() async {
        var calls = 0
        let model = HomeViewModel(fetchRadarPlaylists: { calls += 1; return batch("\(calls)") })
        let midnight = Calendar.current.startOfDay(for: Date()).addingTimeInterval(86_400)
        await model.refreshRadarPlaylists(loggedIn: true, now: midnight.addingTimeInterval(-30))
        await model.refreshRadarPlaylists(loggedIn: true, now: midnight.addingTimeInterval(30))
        #expect(calls == 2)
    }

    @Test func failedModuleRefreshKeepsSnapshotAndRetries() async {
        var calls = 0
        let model = HomeViewModel(fetchRadarPlaylists: {
            calls += 1
            if calls == 2 { throw NeteaseAPIError.http(503) }
            return batch("\(calls)")
        })
        let now = Date()
        await model.refreshRadarPlaylists(loggedIn: true, now: now)
        await model.refreshRadarPlaylists(loggedIn: true, force: true, now: now.addingTimeInterval(301))
        #expect(model.radarPlaylists == batch("1"))
        await model.refreshRadarPlaylists(loggedIn: true, now: now.addingTimeInterval(302))
        #expect(calls == 3)
        #expect(model.radarPlaylists == batch("3"))
    }

    @Test func membershipRemovalsAdditionsAndOrderFollowWholeSnapshot() async {
        var calls = 0
        let next = [batch("2")[4], NeteaseAPI.RadarPlaylist(
            id: 10001, title: "来源新增歌单", subtitle: "新文案", coverURL: nil), batch("2")[0]]
        let model = HomeViewModel(fetchRadarPlaylists: {
            calls += 1
            return calls == 1 ? batch("1") : next
        })
        await model.refreshRadarPlaylists(loggedIn: true)
        await model.refreshRadarPlaylists(loggedIn: true, force: true)
        #expect(model.radarPlaylists == next)
    }

    @Test func successfulEmptyModuleClearsPreviousCards() async {
        var calls = 0
        let model = HomeViewModel(fetchRadarPlaylists: {
            calls += 1
            return calls == 1 ? batch("1") : []
        })
        await model.refreshRadarPlaylists(loggedIn: true)
        await model.refreshRadarPlaylists(loggedIn: true, force: true)
        #expect(model.radarPlaylists.isEmpty)
    }

    @Test func logoutDiscardsInFlightResponse() async {
        var pending: CheckedContinuation<[NeteaseAPI.RadarPlaylist], Never>?
        let model = HomeViewModel(fetchRadarPlaylists: {
            await withCheckedContinuation { pending = $0 }
        })
        let request = Task { await model.refreshRadarPlaylists(loggedIn: true) }
        while pending == nil { await Task.yield() }
        await model.refreshRadarPlaylists(loggedIn: false)
        pending?.resume(returning: batch("stale"))
        await request.value
        #expect(model.radarPlaylists.isEmpty)
    }
    private func creative(_ id: Any, name: String = "来源文案", valid: Bool = true,
                          type: String = "playlist", hasCover: Bool = true) -> [String: Any] {
        ["creativeId": "not-a-playlist-id", "uiElement": ["mainTitle": ["title": name],
            "images": hasCover ? [["imageUrl": "https://example.com/source.jpg?watermark&image=source"]] : []],
         "resources": [["resourceId": id, "resourceType": type, "valid": valid]]]
    }

    private func module(_ creatives: [[String: Any]]) -> [String: Any] {
        ["code": 200, "data": ["blocks": [
            ["code": "CUSTOMIZE_PLAYLIST_OFFICIAL", "creatives": [creative("999")]],
            ["code": "CUSTOMIZE_PLAYLIST_MGC", "creatives": creatives]
        ]]]
    }

    private func client() -> NeteaseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [RadarModuleProtocol.self]
        return NeteaseClient(configuration: config, persistsCookies: false)
    }

    @Test func desktopModuleSelectsAllEntriesAndKeepsOrderWhenDetailFails() async throws {
        let ids = [91, 82, 73, 64, 55, 46, 37, 28, 19]
        let entries = ids.enumerated().map { creative($0.offset.isMultiple(of: 2) ? String($0.element) as Any : $0.element as Any) }
        try RadarModuleProtocol.prepare(module: module(entries + [creative("91"), creative("0"),
            creative("888", valid: false), creative("777", type: "song")]))
        let result = try await NeteaseAPI.radarPlaylists(using: client())
        #expect(result.map(\.id) == ids)
        #expect(result.allSatisfy { $0.title == "来源文案" && $0.coverURL?.contains("watermark") == true })
        #expect(RadarModuleProtocol.requests.filter { $0 == "/eapi/pc/customize/block/page" }.count == 1)
        #expect(RadarModuleProtocol.requests.filter { $0 == "/eapi/v6/playlist/detail" }.count == ids.count)
    }

    @Test func playlistArtworkWinsOverSongWhileKeepingSourceText() async throws {
        try RadarModuleProtocol.prepare(module: module([creative("91")]), detail: [
            "code": 200, "playlist": ["id": 91, "name": "详情页的另一句文案|会员雷达",
                "coverImgUrl": "https://example.com/different.jpg", "trackIds": [["id": 7]],
                "tracks": [song(7, cover: "https://example.com/first-song.jpg")]]])
        let playlist = try #require(try await NeteaseAPI.radarPlaylists(using: client()).first)
        #expect(playlist.title == "会员雷达")
        #expect(playlist.subtitle == "来源文案")
        #expect(playlist.coverURL == "https://example.com/different.jpg")
    }

    @Test func artworkLookupKeepsOwnCoverWithoutSongRequest() async throws {
        try RadarModuleProtocol.prepare(module: module([]), detail: [
            "code": 200, "playlist": ["id": 91, "coverImgUrl": "https://example.com/own.jpg",
                "trackIds": [["id": 7]]]])
        let cover = try await NeteaseAPI.playlistCover(id: 91, using: client())
        #expect(cover == "https://example.com/own.jpg")
        #expect(!RadarModuleProtocol.requests.contains("/eapi/v3/song/detail"))
    }

    @Test func artworkLookupResolvesOnlyTheFirstSong() async throws {
        try RadarModuleProtocol.prepare(module: module([]), detail: [
            "code": 200, "playlist": ["id": 91, "coverImgUrl": " ", "trackIds": [["id": 7], ["id": 8]],
                "tracks": [song(8, cover: "https://example.com/second.jpg")]]],
            songDetail: ["code": 200, "songs": [song(7, cover: "https://example.com/first.jpg")]])
        let cover = try await NeteaseAPI.playlistCover(id: 91, using: client())
        #expect(cover == "https://example.com/first.jpg")
        #expect(RadarModuleProtocol.requests.filter { $0 == "/eapi/v3/song/detail" }.count == 1)
    }

    @Test func artworkLookupLeavesEmptyPlaylistWithoutCover() async throws {
        try RadarModuleProtocol.prepare(module: module([]), detail: ["code": 200, "playlist": ["id": 91]])
        let cover = try await NeteaseAPI.playlistCover(id: 91, using: client())
        #expect(cover == nil)
        #expect(!RadarModuleProtocol.requests.contains("/eapi/v3/song/detail"))
    }

    private func song(_ id: Int, cover: String) -> [String: Any] {
        ["id": id, "name": "歌曲", "ar": [], "al": ["id": id, "name": "专辑", "picUrl": cover], "dt": 1000]
    }

    @Test func firstSongCoverFollowsPlaylistMembershipRatherThanReturnedTrackOrder() async throws {
        try RadarModuleProtocol.prepare(module: module([creative("91", hasCover: false)]), detail: [
            "code": 200, "playlist": ["id": 91, "name": "私人雷达", "trackIds": [["id": 7], ["id": 8]],
                "tracks": [song(8, cover: "https://example.com/second.jpg"),
                           song(7, cover: "https://example.com/first.jpg")]]])
        let playlist = try #require(try await NeteaseAPI.radarPlaylists(using: client()).first)
        #expect(playlist.coverURL == "https://example.com/first.jpg")
        #expect(!RadarModuleProtocol.requests.contains("/eapi/v3/song/detail"))
    }

    @Test func missingFirstTrackIsResolvedWithoutUsingTheSecondSongsArtwork() async throws {
        try RadarModuleProtocol.prepare(module: module([creative("91", hasCover: false)]), detail: [
            "code": 200, "playlist": ["id": 91, "trackIds": [["id": 7], ["id": 8]],
                "tracks": [song(8, cover: "https://example.com/second.jpg")]]],
            songDetail: ["code": 200, "songs": [song(7, cover: "https://example.com/first.jpg")]])
        let playlist = try #require(try await NeteaseAPI.radarPlaylists(using: client()).first)
        #expect(playlist.coverURL == "https://example.com/first.jpg")
        #expect(RadarModuleProtocol.requests.filter { $0 == "/eapi/v3/song/detail" }.count == 1)
    }

    @Test func coverChangesWithTheFirstSongOnNextRefresh() async throws {
        var covers: [String?] = []
        let apiClient = client()
        for id in [7, 9] {
            try RadarModuleProtocol.prepare(module: module([creative("91", hasCover: false)]), detail: [
                "code": 200, "playlist": ["id": 91, "name": "私人雷达", "trackIds": [["id": id]],
                    "tracks": [song(id, cover: "https://example.com/\(id).jpg")]]])
            covers.append(try await NeteaseAPI.radarPlaylists(using: apiClient).first?.coverURL)
        }
        #expect(covers == ["https://example.com/7.jpg", "https://example.com/9.jpg"])
    }

    @Test func pipesInsideSourceSongNamesRemainInFull() async throws {
        let text = "从《A | B》开始听"
        try RadarModuleProtocol.prepare(module: module([creative("91", name: text)]))
        let playlist = try #require(try await NeteaseAPI.radarPlaylists(using: client()).first)
        #expect(playlist.title == text)
    }

    @Test func unrelatedOrMalformedModulesAreFailuresRatherThanEmptySnapshots() async throws {
        for body: [String: Any] in [
            ["code": 200, "data": ["blocks": [["code": "CUSTOMIZE_PLAYLIST_OFFICIAL", "creatives": []]]]],
            ["code": 200, "data": ["blocks": [["code": "CUSTOMIZE_PLAYLIST_MGC"]]]]
        ] {
            try RadarModuleProtocol.prepare(module: body)
            await #expect(throws: NeteaseAPIError.self) {
                try await NeteaseAPI.radarPlaylists(using: client())
            }
        }
        try RadarModuleProtocol.prepare(module: module([]))
        #expect(try await NeteaseAPI.radarPlaylists(using: client()).isEmpty)
    }

    @Test func languageRadarNameKeepsSourceLabelBeforeDescription() {
        let playlist = NeteaseAPI.RadarPlaylist(brief: .init(id: 2829883282,
            name: "华语私人雷达 | 最懂你的华语推荐 每日更新35首", coverImgUrl: nil))
        #expect(playlist.title == "华语私人雷达")
        #expect(playlist.subtitle == "最懂你的华语推荐 每日更新35首")
    }

}
