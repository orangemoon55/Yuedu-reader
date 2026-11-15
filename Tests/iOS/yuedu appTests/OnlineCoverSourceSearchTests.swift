import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Online cover source search")
struct OnlineCoverSourceSearchTests {
    @Test("all enabled search sources participate, including script sources with no cover rule")
    func includesEveryEnabledSearchSource() {
        var scripted = source("scripted")
        scripted.searchUrl = "@js:search(key)"
        var disabled = source("disabled")
        disabled.enabled = false
        var noSearch = source("no-search")
        noSearch.searchUrl = " \n "
        let ordinary = source("ordinary")

        let queried = OnlineCoverSearchViewModel.searchableSources(
            in: [scripted, disabled, noSearch, ordinary]
        )

        #expect(queried.map(\.id) == [scripted.id, ordinary.id])
        #expect(queried.allSatisfy { $0.ruleSearch.coverUrl.isEmpty })
    }

    @Test("normalized URLs merge across sources and keep the first source's download identity")
    func normalizesAndKeepsSourceIdentity() {
        let first = source("first")
        let second = source("second")
        var accumulator = OnlineCoverCandidateAccumulator()
        accumulator.append([
            origin("  https://IMG.example.test:443/cover.jpg#preview  ", in: first),
            origin("https://img.example.test/cover.jpg#other", in: second),
        ])

        #expect(accumulator.candidates.count == 1)
        #expect(accumulator.candidates.first?.coverUrl == "https://IMG.example.test:443/cover.jpg#preview")
        #expect(accumulator.candidates.first?.sourceId == first.id)
        #expect(accumulator.candidates.first?.providerName == first.bookSourceName)
        #expect(OnlineCoverCandidateAccumulator.normalizedURLKey("HTTP://IMG.example.test:80")
            == OnlineCoverCandidateAccumulator.normalizedURLKey("http://img.example.test/"))
    }

    @Test("incremental batches preserve completion order and have no two-result limit")
    func incrementalOrderAndNoResultCap() {
        let first = source("first")
        let second = source("second")
        var accumulator = OnlineCoverCandidateAccumulator()
        accumulator.append([
            origin("https://img.example.test/a.jpg", in: first),
            origin("https://img.example.test/b.jpg", in: first),
        ])
        accumulator.append([
            origin("https://img.example.test/b.jpg", in: second),
            origin("https://img.example.test/c.jpg", in: second),
            origin("https://img.example.test/d.jpg", in: second),
        ])
        accumulator.append([origin("https://img.example.test/a.jpg", in: first)])

        #expect(accumulator.candidates.map(\.coverUrl) == [
            "https://img.example.test/a.jpg", "https://img.example.test/b.jpg",
            "https://img.example.test/c.jpg", "https://img.example.test/d.jpg",
        ])
        #expect(accumulator.candidates.map(\.sourceId) == [first.id, first.id, second.id, second.id])
    }

    @Test("empty and unsupported covers are discarded without altering the remaining order")
    func skipsMissingCovers() {
        let provider = source("provider")
        var accumulator = OnlineCoverCandidateAccumulator()
        accumulator.append([
            origin(" \n ", in: provider),
            origin("javascript:alert(1)", in: provider),
            origin("https://img.example.test/valid.jpg", in: provider),
        ])

        #expect(accumulator.candidates.map(\.coverUrl) == ["https://img.example.test/valid.jpg"])
    }

    @Test("signed queries and case-sensitive image paths are not collapsed")
    func preservesDistinctRequests() {
        let provider = source("provider")
        var accumulator = OnlineCoverCandidateAccumulator()
        let urls = [
            "https://img.example.test/Cover.jpg?token=one",
            "https://img.example.test/Cover.jpg?token=two",
            "https://img.example.test/cover.jpg?token=two",
        ]
        accumulator.append(urls.map { origin($0, in: provider) })

        #expect(accumulator.candidates.map(\.coverUrl) == urls)
    }

    @Test("same-book filtering folds script differences and rejects sequels or other authors")
    func sameBookMatching() {
        let target = SearchWorkKeys(name: "三體", author: "劉慈欣")
        #expect(BookOriginSearchService.isSameBook(
            target, SearchWorkKeys(name: "三体", author: "刘慈欣"), matchesAuthor: true
        ))
        #expect(!BookOriginSearchService.isSameBook(
            target, SearchWorkKeys(name: "三体II", author: "刘慈欣"), matchesAuthor: true
        ))
        #expect(!BookOriginSearchService.isSameBook(
            target, SearchWorkKeys(name: "三体", author: "王晋康"), matchesAuthor: true
        ))
    }

    private func source(_ name: String) -> BookSource {
        var source = BookSource(bookSourceUrl: "https://\(name).example.test", bookSourceName: name)
        source.searchUrl = "/search?key={{key}}"
        return source
    }

    private func origin(_ cover: String, in source: BookSource) -> BookOrigin {
        BookOrigin(
            sourceId: source.id, sourceName: source.bookSourceName,
            bookUrl: source.bookSourceUrl + "/book", tocUrl: "", coverUrl: cover,
            intro: "", lastChapter: "", wordCount: "", kind: "", runtimeVariables: nil
        )
    }
}
