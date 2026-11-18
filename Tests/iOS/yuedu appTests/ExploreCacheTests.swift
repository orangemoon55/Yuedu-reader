import Foundation
import Testing
@testable import yuedu_app

private actor CacheRequestProbe {
    private(set) var requests = 0
    func next() -> Int { requests += 1; return requests }
}

@MainActor
@Suite("Explore configured source cache", .serialized)
struct ExploreCacheTests {
    private func source() -> BookSource {
        var source = BookSource(bookSourceUrl: "https://cache.test", bookSourceName: "Cache source")
        source.exploreUrl = "/explore"
        return source
    }
    private func book(_ name: String, source: BookSource) -> OnlineBook {
        OnlineBook(name: name, author: "Author", intro: "Intro", coverUrl: "", bookUrl: "https://cache.test/\(name)",
                   tocUrl: "", wordCount: "", lastChapter: "", kind: "都市", sourceId: source.id, sourceName: "Cache source")
    }

    @Test("new homepage reuses a fresh page without waiting for network, refresh forces one")
    func freshAcrossHomes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ForYouCandidateStore(directory: directory)
        let source = source()
        let ref = ExploreCategoryReference(sourceURL: source.bookSourceUrl, title: "排行榜", url: "/rank")
        let now = Date(timeIntervalSince1970: 20000)
        let context = try await DiscoverFirstPages.cacheContext(for: source, filters: [:])
        await store.write(ForYouCandidates(sourceURL: source.bookSourceUrl, categoryURL: ref.url, fetchedAt: now.addingTimeInterval(-60),
                                          books: [book("Cached", source: source)], contextID: context))
        let requests = CacheRequestProbe()
        let pages = DiscoverFirstPages(pageLoader: SectionPageLoader { _, _, _ in
            _ = await requests.next()
            return [self.book("Updated", source: source)]
        }, primeCookies: { _ in }, store: store, lanes: DiscoverRequestLanes(), now: { now })
        let first = try await pages.firstPage(of: ref, in: source).value
        #expect(first.map(\.name) == ["Cached"])
        #expect(await requests.requests == 0)
        pages.refresh()
        #expect(try await pages.firstPage(of: ref, in: source).value.map(\.name) == ["Updated"])
        #expect(await requests.requests == 1)
    }

    @Test("stale page can be painted offline and cache does not cross source filters or source rule edits")
    func staleAndFilterIsolation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ForYouCandidateStore(directory: directory)
        let source = source()
        let ref = ExploreCategoryReference(sourceURL: source.bookSourceUrl, title: "排行榜", url: "/rank")
        let context = try await DiscoverFirstPages.cacheContext(for: source, filters: ["channel": "male"])
        await store.write(.init(sourceURL: source.bookSourceUrl, categoryURL: ref.url, fetchedAt: .distantPast,
                               books: [book("Cached", source: source)], contextID: context))
        let pages = DiscoverFirstPages(primeCookies: { _ in }, store: store, lanes: DiscoverRequestLanes())
        #expect(await pages.savedPage(of: ref, in: source, filterValues: ["channel": "male"])?.map(\.name) == ["Cached"])
        #expect(await pages.savedPage(of: ref, in: source, filterValues: ["channel": "female"]) == nil)
        var changed = source; changed.ruleExplore.name = "$.newTitle"
        #expect(await pages.savedPage(of: ref, in: changed, filterValues: ["channel": "male"]) == nil)
        var other = source; other.bookSourceUrl = "https://other.test"
        let otherRef = ExploreCategoryReference(sourceURL: other.bookSourceUrl, title: "排行榜", url: ref.url)
        #expect(await pages.savedPage(of: otherRef, in: other, filterValues: ["channel": "male"]) == nil)
    }

    @Test("unchanged books do not rewrite cache files and keep stable book ids")
    func unchangedDoesNotWrite() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ForYouCandidateStore(directory: directory)
        let source = source()
        let original = book("Cached", source: source)
        let time = Date(timeIntervalSince1970: 10000)
        await store.write(.init(sourceURL: source.bookSourceUrl, categoryURL: "/rank", fetchedAt: time, books: [original]))
        let file = store.fileURL(sourceURL: source.bookSourceUrl, categoryURL: "/rank")
        let before = try Data(contentsOf: file)
        await store.write(.init(sourceURL: source.bookSourceUrl, categoryURL: "/rank", fetchedAt: time.addingTimeInterval(30),
                               books: [book("Cached", source: source)]))
        #expect(try Data(contentsOf: file) == before)
        let cached = try #require(await store.read(sourceURL: source.bookSourceUrl, categoryURL: "/rank", sourceID: source.id))
        #expect(cached.books.first?.id == original.id)
        #expect(cached.fetchedAt == time.addingTimeInterval(30))
        let remade = ForYouCandidateStore(directory: directory)
        #expect(await remade.read(sourceURL: source.bookSourceUrl, categoryURL: "/rank", sourceID: source.id)?.books.first?.id == original.id)
    }
}
