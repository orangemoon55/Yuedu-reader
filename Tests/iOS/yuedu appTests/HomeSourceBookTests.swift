import Foundation
import Testing
@testable import yuedu_app

@Suite("Homepage exact book template")
@MainActor
struct HomeSourceBookTests {
    private func fixture() -> (BookSource, OnlineBook) {
        var source = BookSource()
        source.bookSourceUrl = "https://fixture.invalid"
        source.bookSourceName = "指定來源"
        let book = OnlineBook(name: "同名作品", author: "甲作者", intro: "這是選中的版本。",
                              coverUrl: "/cover.jpg", bookUrl: "/book/42", tocUrl: "/toc/42",
                              wordCount: "10萬", lastChapter: "第二章", kind: "奇幻",
                              sourceId: source.id, sourceName: source.bookSourceName,
                              runtimeVariables: ["book.id": "42"])
        return (source, book)
    }

    @Test("Exact source, URL, metadata and variables survive homepage configuration export")
    func roundTrip() throws {
        let (source, book) = fixture()
        let selected = HomeSourceBook(book: book, source: source)
        let section = HomeSection(layout: .coverIntroCard, binding: .sourceBook(selected))
        let restored = try JSONDecoder().decode(HomeSection.self, from: JSONEncoder().encode(section))
        #expect(restored == section)
        #expect(restored.layout.isKnown)
        #expect(restored.layout.style == .coverIntroCard)
        #expect(restored.binding.contentOwner == .bookSource(url: source.bookSourceUrl))
        let exact = try #require(selected.onlineBook(in: source))
        #expect(exact.bookUrl == book.bookUrl)
        #expect(exact.intro == book.intro)
        #expect(exact.runtimeVariables == book.runtimeVariables)
        var other = source
        other.bookSourceUrl = "https://other.invalid"
        #expect(selected.onlineBook(in: other) == nil)
    }

    @Test("Reinstalled source keeps its exact edition while using the installed identity")
    func reinstalledSource() throws {
        let (source, book) = fixture()
        let selected = HomeSourceBook(book: book, source: source)
        var reinstalled = source
        reinstalled.id = UUID()
        let restored = try #require(selected.onlineBook(in: reinstalled))
        #expect(restored.sourceId == reinstalled.id)
        #expect(restored.bookUrl == "/book/42")
        #expect(restored.author == "甲作者")
    }

    @Test("Exact book card loads its snapshot without searching or requiring discover support")
    func localProvider() async throws {
        let (source, book) = fixture()
        let provider = BookSourceProvider(source: source, firstPages: DiscoverFirstPages())
        let section = HomeSection(layout: .coverIntroCard, binding: .sourceBook(HomeSourceBook(book: book, source: source)))
        #expect(provider.loadPolicy(for: section) == .local)
        let entries = try await provider.load(section)
        #expect(entries.count == 1)
        let first = try #require(entries.first)
        guard case .item(_, let summary, .onlineBook(let frozen)) = first else {
            Issue.record("Expected selected book item")
            return
        }
        #expect(summary.title == book.name)
        #expect(summary.blurb == book.intro)
        #expect(frozen.book.bookUrl == book.bookUrl)
        #expect(!HomeReadFilter(hides: true, isRead: { _ in true }).hides(in: section.binding))
    }

    @Test("Template appears in gallery with cover and real introduction sample")
    func template() {
        #expect(HomeLayoutStyle.allCases.contains(.coverIntroCard))
        #expect(HomeSectionLayout(style: .coverIntroCard) == .coverIntroCard)
        let cards = HomeLayoutSample.standard.cards(for: .coverIntroCard)
        #expect(cards.count == 1)
        #expect(cards.first?.blurb?.isEmpty == false)
    }
}
