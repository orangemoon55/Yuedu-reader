import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Ranked home loading", .serialized)
struct HomeRankLoadingTests {
    @Test("ranking provider policy never selects a different enabled source")
    func exactProvider() {
        var a = BookSource(bookSourceUrl: "https://rank-a.test", bookSourceName: "A")
        var b = BookSource(bookSourceUrl: "https://rank-b.test", bookSourceName: "B")
        a.exploreUrl = "/explore"; b.exploreUrl = "/explore"
        let ref = ExploreCategoryReference(sourceURL: b.bookSourceUrl, title: "月票榜", url: "/rank")
        var section = HomeSection(layout: .coverIntroCard, binding: .sourceCategories([ref]))
        section.configureRotatingRank(HomeContentChoice(binding: section.binding), source: b)
        #expect(BookSourceProvider(source: a, firstPages: DiscoverFirstPages()).loadPolicy(for: section) == nil)
        #expect(BookSourceProvider(source: b, firstPages: DiscoverFirstPages()).loadPolicy(for: section) == .serialPerSource)
    }

    @Test("a one-source preview bypasses whole-library provider construction")
    func oneSourcePreview() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = directory.appendingPathComponent("book_sources.json")
        try Data("[]".utf8).write(to: file)
        let sources = BookSourceStore(directory: directory)
        await sources.waitUntilLoaded()
        defer { try? FileManager.default.removeItem(at: directory) }
        let library = (0..<1000).map { index -> BookSource in
            var source = BookSource(bookSourceUrl: "https://rank-\(index).test", bookSourceName: "Source \(index)")
            source.exploreUrl = "/explore"
            return source
        }
        sources.replaceSources(library)
        var fullProviderCalls = 0
        let model = HomeModel(providers: { fullProviderCalls += 1; return [] }, waitForSources: {})
        let selected = library[900]
        let ref = ExploreCategoryReference(sourceURL: selected.bookSourceUrl, title: "月票榜", url: "/rank")
        var section = HomeSection(layout: .coverIntroCard, binding: .sourceCategories([ref]))
        section.configureRotatingRank(HomeContentChoice(binding: section.binding), source: selected)
        await model.syncPreview(with: HomePage(sections: [section]), sources: sources)
        #expect(model.isReady)
        #expect(model.rows.count == 1)
        #expect(model.rows.first?.source.id == selected.bookSourceUrl)
        #expect(fullProviderCalls == 0)
        section.title = "改标题"
        await model.syncPreview(with: HomePage(sections: [section]), sources: sources)
        #expect(fullProviderCalls == 0)
        #expect(model.rows.count == 1)
    }

    @Test("an old author's completion cannot overwrite the new visible book, which is cached")
    func staleRecommendationAndCache() async throws {
        let source = BookSource(bookSourceUrl: "https://rank.test", bookSourceName: "Source")
        func book(_ title: String, _ author: String) -> OnlineBook {
            OnlineBook(name: title, author: author, intro: "Intro", coverUrl: "", bookUrl: "https://rank.test/\(title)",
                       tocUrl: "", wordCount: "", lastChapter: "", kind: "玄幻", sourceId: source.id, sourceName: "Source")
        }
        func card(_ book: OnlineBook) throws -> HomeCardContent {
            try #require(HomeCardContent(.onlineBook(book, source: source), status: { _ in nil }, shelfBooks: [:]))
        }
        let alice = try card(book("AliceBook", "Alice"))
        let bob = try card(book("BobBook", "Bob"))
        var continuation: CheckedContinuation<[OnlineBook], Never>?
        var bobRequests = 0
        let service = HomeRankingRecommendationService(searchAuthor: { author, _ in
            if author == "Alice" {
                return await withCheckedContinuation { continuation = $0 }
            }
            bobRequests += 1
            return [book("BobOther", "Bob")]
        }, loadGenre: { _, _ in [] })
        let model = HomeRankRelatedModel(service: service, sourceLookup: { _ in source })
        let old = Task { await model.load(for: alice, pool: [alice, bob]) }
        for _ in 0..<100 where continuation == nil { await Task.yield() }
        let pending = try #require(continuation)
        await model.load(for: bob, pool: [alice, bob])
        #expect(model.bookID == bob.id)
        #expect(model.cards.map(\.title) == ["BobOther"])
        pending.resume(returning: [book("AliceOther", "Alice")])
        await old.value
        #expect(model.bookID == bob.id)
        #expect(model.cards.map(\.title) == ["BobOther"])
        await model.load(for: bob, pool: [alice, bob])
        #expect(bobRequests == 1)
        #expect(!model.loading)
    }
}
