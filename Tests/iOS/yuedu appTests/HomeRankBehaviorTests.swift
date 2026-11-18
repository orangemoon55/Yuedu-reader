import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Ranked home behavior", .serialized)
struct HomeRankBehaviorTests {
    private func key(_ id: String) -> SourceItemKey {
        SourceItemKey(instance: SourceInstanceKey(type: .bookSource, id: "https://rank.test"), item: id)
    }

    @Test("a book stays five seconds and duplicates do not create extra stops")
    func fiveSecondsAndWrap() {
        let start = Date(timeIntervalSince1970: 1000)
        var rotation = HomeRankRotation()
        rotation.set([key("a"), key("a"), key("b")], now: start)
        #expect(rotation.ids == [key("a"), key("b")])
        #expect(rotation.current == key("a"))
        let advanced1 = rotation.next(now: start.addingTimeInterval(4.99))
        #expect(!advanced1)
        let advanced2 = rotation.next(now: start.addingTimeInterval(5))
        #expect(advanced2)
        #expect(rotation.current == key("b"))
        let advanced3 = rotation.next(now: start.addingTimeInterval(9.99))
        #expect(!advanced3)
        let advanced4 = rotation.next(now: start.addingTimeInterval(10))
        #expect(advanced4)
        #expect(rotation.current == key("a"))
    }

    @Test("refresh retains current identity and a resumed view starts a full interval")
    func refreshResumeAndSingleItem() {
        let start = Date(timeIntervalSince1970: 1000)
        var rotation = HomeRankRotation()
        rotation.set([key("a"), key("b")], now: start)
        rotation.move(by: 1, at: start.addingTimeInterval(10))
        rotation.set([key("c"), key("b"), key("a")], now: start.addingTimeInterval(20))
        #expect(rotation.current == key("b"))
        #expect(rotation.started == start.addingTimeInterval(10))
        rotation.restart(at: start.addingTimeInterval(100))
        let advanced5 = rotation.next(now: start.addingTimeInterval(104.9))
        #expect(!advanced5)
        let advanced6 = rotation.next(now: start.addingTimeInterval(105))
        #expect(advanced6)
        #expect(rotation.current == key("a"))
        rotation.move(by: -10, at: start)
        #expect(rotation.current == key("b"))
        rotation.set([key("c")], now: start)
        let advanced7 = rotation.next(now: start.addingTimeInterval(1000))
        #expect(!advanced7)
        rotation.set([], now: start)
        #expect(rotation.current == nil)
    }

    @Test("rank binding survives save without waiting for any preview or book detail")
    func localSaveRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RankSave.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = HomePageStore(fileURL: directory.appendingPathComponent("home.json"), defaults: defaults)
        store.save(HomePage(sections: []))
        defer {
            store.waitForPendingWritesForTesting()
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let preview = HomeModel(providers: { [] }, waitForSources: {})
        let source = BookSource(bookSourceUrl: "https://rank.test", bookSourceName: "測試源")
        let rank = ExploreCategoryReference(sourceURL: source.bookSourceUrl, title: "月票榜", url: "/month")
        let choice = HomeContentChoice(binding: .sourceCategories([rank]), parameters: ["filter": "kept"])
        var section = HomeSection(layout: .coverIntroCard, binding: choice.binding)
        section.configureRotatingRank(choice, source: source)
        let editor = HomeSectionEditor(newSectionIn: store, layout: .coverIntroCard, preview: preview)
        let start = ContinuousClock.now
        editor.choose(section.binding, parameters: section.parameters, itemTitle: "月票榜")
        #expect(editor.add())
        #expect(ContinuousClock.now - start < .seconds(1))
        #expect(!preview.isReady)
        let saved = try #require(store.page?.sections.last)
        #expect(saved.rotatingRank == rank)
        #expect(saved.parameters["filter"] == "kept")
        #expect(try JSONDecoder().decode(HomeSection.self, from: JSONEncoder().encode(saved)) == saved)
    }

    @Test("a category's group title can establish ranking membership")
    func actualRankCategories() throws {
        let item = try #require(DiscoverViewModel.mapItem(.init(title: "本周", url: "/week")))
        let genre = try #require(DiscoverViewModel.mapItem(.init(title: "玄幻", url: "/fantasy")))
        #expect(HomeRankCategoryPolicy.rankedItems(.init(id: "r", title: "排行榜", items: [item])).count == 1)
        #expect(HomeRankCategoryPolicy.rankedItems(.init(id: "g", title: "分類", items: [genre])).isEmpty)
    }
}

private func rankTestBook(_ title: String, author: String = "Alice", kind: String = "玄幻", source: BookSource) -> OnlineBook {
    OnlineBook(name: title, author: author, intro: "簡介", coverUrl: "", bookUrl: "https://rank.test/\(title)",
               tocUrl: "", wordCount: "", lastChapter: "", kind: kind, sourceId: source.id, sourceName: source.bookSourceName)
}

@MainActor
@Suite("Ranking related-work priority", .serialized)
struct HomeRankRecommendationTests {
    @Test("exact same-author candidates win; contains matches, editions and foreign sources do not")
    func strictAuthor() async throws {
        let source = BookSource(bookSourceUrl: "https://rank.test", bookSourceName: "測試源")
        let current = rankTestBook("Current", source: source)
        let sibling = rankTestBook("Sibling", author: "作者：Ａlice 著", source: source)
        let partial = rankTestBook("Other", author: "Alice Smith", source: source)
        var edition = rankTestBook("Current", source: source); edition.bookUrl = "https://mirror.test/current"
        var foreign = rankTestBook("Foreign", source: source); foreign.sourceId = UUID()
        let manga = rankTestBook("Manga", kind: "漫画", source: source)
        var searchCount = 0
        let service = HomeRankingRecommendationService(searchAuthor: { _, _ in searchCount += 1; return [] }, loadGenre: { _, _ in [] })
        let result = try await service.recommendations(for: current, source: source, pool: [partial, edition, foreign, manga, sibling, sibling])
        #expect(result.kind == .author)
        #expect(result.books.map(\.name) == ["Sibling"])
        #expect(searchCount == 0)
    }

    @Test("empty author results fall back to matching genres, never title substrings")
    func genreFallback() async throws {
        let source = BookSource(bookSourceUrl: "https://rank.test", bookSourceName: "測試源")
        let current = rankTestBook("Current", kind: "玄幻,都市", source: source)
        let exact = rankTestBook("SameGenre", author: "Bob", kind: "都市|系统", source: source)
        let partial = rankTestBook("WrongGenre", author: "Bob", kind: "都市生活", source: source)
        var genreLoads = 0
        let service = HomeRankingRecommendationService(searchAuthor: { _, _ in [] }, loadGenre: { _, _ in genreLoads += 1; return [] })
        let result = try await service.recommendations(for: current, source: source, pool: [partial, exact])
        #expect(result.kind == .genre)
        #expect(result.books.map(\.name) == ["SameGenre"])
        #expect(genreLoads == 0)
        #expect(HomeRankingRecommendationService.authorQuery("Unknown Author") == nil)
    }

    @Test("source genre categories may supply books whose list omits genre tags")
    func sourceCategoryFallback() async throws {
        let source = BookSource(bookSourceUrl: "https://rank.test", bookSourceName: "測試源")
        let current = rankTestBook("Current", source: source)
        let related = rankTestBook("Other", author: "Bob", kind: "", source: source)
        let service = HomeRankingRecommendationService(searchAuthor: { _, _ in [] }, loadGenre: { _, _ in [current, related, related] })
        let result = try await service.recommendations(for: current, source: source, pool: [])
        #expect(result.kind == .genre)
        #expect(result.books.map(\.name) == ["Other"])
    }

    @Test("upstream cancellation does not turn into genre recommendations")
    func cancellation() async {
        let source = BookSource(bookSourceUrl: "https://rank.test", bookSourceName: "測試源")
        let current = rankTestBook("Current", source: source)
        var genreLoads = 0
        let service = HomeRankingRecommendationService(searchAuthor: { _, _ in throw CancellationError() }, loadGenre: { _, _ in genreLoads += 1; return [] })
        do {
            _ = try await service.recommendations(for: current, source: source, pool: [])
            Issue.record("Expected cancellation")
        } catch is CancellationError { #expect(genreLoads == 0) }
        catch { Issue.record("Wrong error: \(error)") }
    }
}
