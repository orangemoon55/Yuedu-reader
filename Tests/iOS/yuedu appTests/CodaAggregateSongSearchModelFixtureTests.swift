import Foundation
import Testing
@testable import CodaCore

// Offline fixtures only. No provider activation, login, live HTTP or playback.
@MainActor
@Suite("Coda explicit-provider aggregate SONG search")
struct CodaAggregateSongSearchModelFixtureTests {
    @Test func fourSourcesRunConcurrentlyAndKeepCollidingNumericIDsSeparate() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 2)
        let load = Task { await model.load(query: "  shared title  ", scope: .all) }
        try await fixture.waitForRequests(4)
        #expect(model.isLoading)
        #expect(Set(fixture.requests.map(\.provider)) == Set(MusicProvider.allCases))
        #expect(fixture.requests.allSatisfy { $0.query == "shared title" && $0.offset == 0 })
        // Complete in reverse order: publication order must not depend on latency.
        for request in fixture.requests.reversed() {
            let track = try CodaAggregateSongFixture.track(request.provider, id: 77123)
            fixture.succeed(request, tracks: [track, track], next: 2, more: false)
        }
        await load.value
        #expect(model.tracks.count == 4)
        #expect(Set(model.tracks.map(\.id)).count == 4)
        #expect(model.tracks.map { $0.platformSong?.source.rawValue ?? "netease" } == MusicProvider.allCases.map(\.rawValue))
        #expect(model.tracks[0].id == 77123)
        #expect(model.tracks.dropFirst().allSatisfy { $0.id < 0 })
        #expect(!model.isLoading && !model.hasMore && model.failureMessage == nil)
    }

    @Test func partialFailureRetriesOnlyFailedSourceAtItsUnchangedOffset() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 1)
        let load = Task { await model.load(query: "fixture", scope: .all) }
        try await fixture.waitForRequests(4)
        for request in fixture.requests {
            if request.provider == .qq { fixture.fail(request) }
            else { fixture.succeed(request, tracks: [try CodaAggregateSongFixture.track(request.provider, id: 401)], next: 1, more: false) }
        }
        await load.value
        #expect(model.tracks.count == 3 && model.failedProviders == [.qq])
        #expect(model.failureMessage?.contains("QQ") == true && !model.hasMore)
        let retry = Task { await model.retryFailures() }
        try await fixture.waitForRequests(5)
        let request = try #require(fixture.requests.last)
        #expect(request.provider == .qq && request.offset == 0)
        fixture.succeed(request, tracks: [try CodaAggregateSongFixture.track(.qq, id: 401)], next: 1, more: false)
        await retry.value
        #expect(model.tracks.count == 4 && model.failedProviders.isEmpty && model.failureMessage == nil)
        #expect(fixture.requests.count == 5)
    }

    @Test func perSourcePagingDeduplicatesAndSerializesLoadMore() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 2)
        let load = Task { await model.load(query: "fixture", scope: .all) }
        try await fixture.waitForRequests(4)
        for request in fixture.requests {
            let first = try CodaAggregateSongFixture.track(request.provider, id: 801)
            fixture.succeed(request, tracks: request.provider == .qq ? [first] : [first, first],
                            next: request.provider == .qq ? 1 : 2,
                            more: request.provider == .netease || request.provider == .qq)
        }
        await load.value
        #expect(model.tracks.count == 4 && model.hasMore)
        let more = Task { await model.loadMore() }
        try await fixture.waitForRequests(6)
        #expect(model.isLoadingMore && !model.isLoading)
        await model.loadMore() // No overlapping pagination request is allowed.
        #expect(fixture.requests.count == 6)
        for request in fixture.requests.suffix(2) {
            #expect(request.offset == (request.provider == .qq ? 1 : 2))
            if request.provider == .qq { fixture.fail(request) }
            else { fixture.succeed(request, tracks: [try CodaAggregateSongFixture.track(.netease, id: 801), try CodaAggregateSongFixture.track(.netease, id: 802)], next: 4, more: false) }
        }
        await more.value
        #expect(model.tracks.count == 5 && model.failedProviders == [.qq] && !model.hasMore)
        let retry = Task { await model.retryFailures() }
        try await fixture.waitForRequests(7)
        let retryRequest = try #require(fixture.requests.last)
        #expect(retryRequest.provider == .qq && retryRequest.offset == 1)
        fixture.succeed(retryRequest, tracks: [try CodaAggregateSongFixture.track(.qq, id: 801), try CodaAggregateSongFixture.track(.qq, id: 802)], next: 3, more: false)
        await retry.value
        #expect(model.tracks.count == 6 && !model.hasMore && !model.isLoadingMore)
    }

    @Test func supersededSearchAndPaginationCannotOverwriteNewScope() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 1)
        let first = Task { await model.load(query: "old", scope: .qq) }
        try await fixture.waitForRequests(1)
        fixture.succeed(fixture.requests[0], tracks: [try CodaAggregateSongFixture.track(.qq, id: 901)], next: 1, more: true)
        await first.value
        let paging = Task { await model.loadMore() }
        try await fixture.waitForRequests(2)
        let new = Task { await model.load(query: "new", scope: .qishui) }
        try await fixture.waitForRequests(3)
        // An uncooperative old transport returns despite cancellation.
        fixture.succeed(fixture.requests[1], tracks: [try CodaAggregateSongFixture.track(.qq, id: 902)], next: 2, more: false)
        await paging.value
        #expect(model.isLoading && model.tracks.isEmpty)
        fixture.succeed(fixture.requests[2], tracks: [try CodaAggregateSongFixture.track(.qishui, id: 903)], next: 1, more: false)
        await new.value
        #expect(model.tracks.count == 1 && model.tracks.first?.platformSong?.source == .qishui)
    }

    @Test func staleInitialSearchAndCallerCancellationDoNotPublishOrInventFailures() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 1)
        let old = Task { await model.load(query: "old", scope: .netease) }
        try await fixture.waitForRequests(1)
        let fresh = Task { await model.load(query: "fresh", scope: .netease) }
        try await fixture.waitForRequests(2)
        fixture.succeed(fixture.requests[1], tracks: [try CodaAggregateSongFixture.track(.netease, id: 921)], next: 1, more: false)
        await fresh.value
        fixture.succeed(fixture.requests[0], tracks: [try CodaAggregateSongFixture.track(.netease, id: 920)], next: 1, more: false)
        await old.value
        #expect(model.tracks.map(\.id) == [921] && !model.isLoading)
        let cancelled = Task { await model.load(query: "cancelled", scope: .netease) }
        try await fixture.waitForRequests(3)
        cancelled.cancel()
        fixture.succeed(fixture.requests[2], tracks: [try CodaAggregateSongFixture.track(.netease, id: 922)], next: 1, more: false)
        await cancelled.value
        #expect(model.tracks.isEmpty && model.failedProviders.isEmpty && model.failureMessage == nil)
        #expect(!model.isLoading && !model.isLoadingMore)
    }

    @Test func accountTicketChangeDiscardsResultsAndRequiresFreshSearch() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 1)
        let load = Task { await model.load(query: "fixture", scope: .qq) }
        try await fixture.waitForRequests(1)
        fixture.session = "new-account-ticket"
        fixture.succeed(fixture.requests[0], tracks: [try CodaAggregateSongFixture.track(.qq, id: 930)], next: 1, more: true)
        await load.value
        #expect(model.tracks.isEmpty && !model.hasMore && !model.isLoading)
        #expect(model.failureMessage?.contains("重新搜索") == true)
        await model.loadMore()
        #expect(fixture.requests.count == 1)
        let retry = Task { await model.retryFailures() }
        try await fixture.waitForRequests(2)
        #expect(fixture.requests[1].offset == 0)
        fixture.succeed(fixture.requests[1], tracks: [try CodaAggregateSongFixture.track(.qq, id: 931)], next: 1, more: false)
        await retry.value
        #expect(model.tracks.first?.platformSong?.id == 931 && model.failureMessage == nil)
    }

    @Test func wrongSourcePageCannotBePublishedOrAdvanceOffset() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 1)
        let load = Task { await model.load(query: "fixture", scope: .qq) }
        try await fixture.waitForRequests(1)
        fixture.succeed(fixture.requests[0], tracks: [try CodaAggregateSongFixture.track(.kugou, id: 935)], next: 1, more: false)
        await load.value
        #expect(model.tracks.isEmpty && model.failedProviders == [.qq])
        let retry = Task { await model.retryFailures() }
        try await fixture.waitForRequests(2)
        #expect(fixture.requests[1].offset == 0)
        fixture.succeed(fixture.requests[1], tracks: [], next: 0, more: false)
        await retry.value
        #expect(model.failureMessage == nil && !model.hasMore)
    }

    @Test func repeatedPageAndEmptyQueryCannotLoopForever() async throws {
        let fixture = CodaAggregateSongFixture()
        let model = fixture.model(pageSize: 1)
        await model.load(query: " \n ", scope: .all)
        #expect(fixture.requests.isEmpty && !model.hasMore)
        let first = Task { await model.load(query: "fixture", scope: .kugou) }
        try await fixture.waitForRequests(1)
        let track = try CodaAggregateSongFixture.track(.kugou, id: 940)
        fixture.succeed(fixture.requests[0], tracks: [track], next: 1, more: true)
        await first.value
        let more = Task { await model.loadMore() }
        try await fixture.waitForRequests(2)
        fixture.succeed(fixture.requests[1], tracks: [track], next: 2, more: true)
        await more.value
        #expect(model.tracks.count == 1 && !model.hasMore)
        await model.loadMore()
        #expect(fixture.requests.count == 2)
    }

    @Test func nativeNetEaseMetadataAndRegisteredProvenanceRemainCompatible() throws {
        let native = try CodaAggregateSongFixture.track(.netease, id: 951)
        let result = try PlatformMusicAPI.shared.registerSearchTracks([native], provider: .netease)
        #expect(result == [native] && result[0].platformSong == nil && result[0].id == 951)
        #expect(result[0].embeddedPrivilege?.fee == 1 && result[0].alias == ["alias"])
        #expect(result[0].musicShareURL?.absoluteString.contains("id=951") == true)
        #expect(try PlatformMusicAPI.shared.song(951, provider: .netease).source == .netease)
        #expect(throws: MusicProviderError.self) { try PlatformMusicAPI.shared.song(951, provider: .qq) }
        let qq = try CodaAggregateSongFixture.track(.qq, id: 951)
        #expect(try PlatformMusicAPI.shared.song(qq.id, provider: .qq).qqMid == "fixture-mid-951")
        #expect(throws: MusicProviderError.self) { try PlatformMusicAPI.shared.registerSearchTracks([qq], provider: .kugou) }
    }
}

@MainActor
private final class CodaAggregateSongFixture {
    struct Request {
        let id: Int
        let provider: MusicProvider
        let query: String
        let offset: Int
    }
    enum Failure: Error { case offline, timedOut }
    var session = "fixture-account-ticket"
    private(set) var requests: [Request] = []
    private var pending: [Int: CheckedContinuation<CodaProviderSongSearch.Page, Error>] = [:]

    func model(pageSize: Int) -> CodaProviderSongSearchModel {
        CodaProviderSongSearchModel(pageSize: pageSize, loader: { [self] provider, query, _, offset in
            let request = Request(id: requests.count, provider: provider, query: query, offset: offset)
            requests.append(request)
            // Intentionally ignores cancellation: the model must fence late replies.
            return try await withCheckedThrowingContinuation { pending[request.id] = $0 }
        }, sessionIdentity: { [self] in session })
    }
    func waitForRequests(_ count: Int) async throws {
        for _ in 0..<10_000 {
            if requests.count >= count { return }
            await Task.yield()
        }
        Issue.record("Expected \(count) fixture requests, got \(requests.count)")
        throw Failure.timedOut
    }
    func succeed(_ request: Request, tracks: [Track], next: Int, more: Bool) {
        pending.removeValue(forKey: request.id)?.resume(returning: .init(tracks: tracks, nextOffset: next, hasMore: more))
    }
    func fail(_ request: Request) {
        pending.removeValue(forKey: request.id)?.resume(throwing: Failure.offline)
    }
    static func track(_ provider: MusicProvider, id: Int) throws -> Track {
        if provider == .netease {
            return try PlatformMusicAPI.decode(Track.self, ["id": id, "name": "shared title", "dt": 180_000,
                "alia": ["alias"], "fee": 1, "privilege": ["id": id, "fee": 1, "pl": 320_000]])
        }
        let song = ProviderSong(id: id, name: "shared title", artists: "artist", album: "album",
            coverURL: nil, duration: 180, source: ProviderSongSource(rawValue: provider.rawValue)!,
            qqMid: provider == .qq ? "fixture-mid-\(id)" : nil,
            qqMediaMid: provider == .qq ? "fixture-media-\(id)" : nil,
            kugouHash: provider == .kugou ? "fixture-hash-\(id)" : nil,
            kugouAlbumAudioId: provider == .kugou ? "\(id)" : nil,
            qishui: provider == .qishui ? QishuiTrackReference(trackID: "\(id)") : nil)
        return try PlatformMusicAPI.shared.register(song)
    }
}
