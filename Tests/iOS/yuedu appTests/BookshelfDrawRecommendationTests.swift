import CoreGraphics
import Foundation
import Testing
@testable import yuedu_app

@Suite("Local full-shelf draw policy")
struct BookshelfDrawRecommendationTests {
    @Test("Every group is eligible, with first shelved UUID winning")
    func eligibilityAcrossGroups() {
        let books = shelf(count: 6)
        var hidden = books[0]
        hidden.isInBookshelf = false
        var duplicate = books[1]
        duplicate.title = "重复副本"
        duplicate.group = "另一分组"
        let input = [hidden] + books + [duplicate, hidden]
        let before = input
        #expect(BookshelfDrawRecommendation.eligible(in: input) == books)
        #expect(input == before)
        #expect(BookshelfDrawRecommendation.eligible(in: [hidden]).isEmpty)
        #expect(BookshelfDrawRecommendation.eligible(in: []).isEmpty)
    }

    @Test("Controlled equal random intervals select every eligible UUID equally")
    func uniformChoice() {
        let books = shelf(count: 4)
        var hidden = ReadingBook(title: "不在书架", contentFilename: "")
        hidden.isInBookshelf = false
        let input = [hidden] + books + [books[0], books[0]]
        var random = ControlledRandom(words: [0, 0x5555_5555_5555_5555,
                                               0xAAAA_AAAA_AAAA_AAAA, .max])
        let ids = (0..<8).compactMap { _ in
            BookshelfDrawRecommendation.choose(from: input, using: &random)?.id
        }
        #expect(ids == (books + books).map(\.id))
        for book in books {
            #expect(ids.filter { $0 == book.id }.count == 2)
        }
    }

    @Test("Empty and singleton draws are safe")
    func choiceBoundaries() {
        var random = ControlledRandom(words: [0])
        #expect(BookshelfDrawRecommendation.choose(from: [], using: &random) == nil)
        #expect(random.calls == 0)
        let book = shelf(count: 1)[0]
        #expect(BookshelfDrawRecommendation.choose(from: [book, book], using: &random) == book)
        var hidden = book
        hidden.isInBookshelf = false
        #expect(BookshelfDrawRecommendation.choose(from: [hidden], using: &random) == nil)
    }

    @Test("An outer-shelf winner replaces only the ninth displayed book")
    func outerWinnerBecomesVisible() {
        let books = shelf(count: 14)
        let input = books + [books[12], books[0]]
        let before = input
        let visible = BookshelfDrawRecommendation.visibleBooks(from: input, including: books[12].id)
        #expect(visible == Array(books.prefix(8)) + [books[12]])
        #expect(visible.count == 9)
        #expect(Set(visible.map(\.id)).count == 9)
        #expect(input == before)
        #expect(BookshelfDrawRecommendation.visibleBooks(from: input, including: nil)
                == Array(books.prefix(9)))
        var random = ControlledRandom(words: [.max])
        #expect(BookshelfDrawRecommendation.choose(from: input, using: &random)?.id == books[13].id)
    }

    @Test("Visible boundaries reject missing and unshelved winners without mutation")
    func visibleBoundaries() {
        #expect(BookshelfDrawRecommendation.visibleBooks(from: [], including: UUID()).isEmpty)
        for count in 1...9 {
            let books = shelf(count: count)
            #expect(BookshelfDrawRecommendation.visibleBooks(from: books + books, including: books.last?.id) == books)
        }
        let books = shelf(count: 11)
        var hidden = ReadingBook(title: "未入架", contentFilename: "")
        hidden.isInBookshelf = false
        for id: UUID? in [nil, UUID(), hidden.id, books[2].id] {
            #expect(BookshelfDrawRecommendation.visibleBooks(from: books + [hidden], including: id)
                    == Array(books.prefix(9)))
        }
    }

    @Test("Local cached kind wins; blank or missing kind uses explicit runtime keys in order")
    func cachedKindPrecedence() {
        var book = boundBook()
        book.runtimeVariables = ["kind": "言情", "category": "科幻", "genre": "历史"]
        let cached = BookshelfDrawRecommendation.cachedCategory(for: book) { url, sourceID in
            #expect(url == book.bookInfoURL)
            #expect(sourceID == book.bookSourceId)
            return "  悬疑推理\n"
        }
        #expect(cached == "悬疑推理")
        #expect(BookshelfDrawRecommendation.message(for: book, category: cached)
                == "《题材以缓存为准》 · 沿着线索往下读，让谜底慢慢现身。")
        #expect(BookshelfDrawRecommendation.cachedCategory(for: book, cacheKind: { _, _ in nil }) == "言情")
        book.runtimeVariables?["kind"] = " \n"
        #expect(BookshelfDrawRecommendation.cachedCategory(for: book, cacheKind: { _, _ in " " }) == "科幻")
        book.runtimeVariables?["category"] = ""
        #expect(BookshelfDrawRecommendation.cachedCategory(for: book, cacheKind: { _, _ in nil }) == "历史")
        book.runtimeVariables = ["book.kind": "玄幻", "book.category": "悬疑"]
        #expect(BookshelfDrawRecommendation.cachedCategory(for: book, cacheKind: { _, _ in nil }) == nil)
        #expect(BookshelfDrawRecommendation.cachedCategory(for: book, cacheKind: { _, _ in "未知分类" }) == "未知分类")
    }

    @Test("Incomplete source bindings return nil before looking up cache or runtime values")
    func incompleteCacheBinding() {
        let book = boundBook()
        var missingID = book
        missingID.bookSourceId = nil
        var missingURL = book
        missingURL.bookInfoURL = nil
        var blankURL = book
        blankURL.bookInfoURL = " \n "
        var calls = 0
        for var candidate in [missingID, missingURL, blankURL] {
            candidate.runtimeVariables = ["kind": "科幻"]
            #expect(BookshelfDrawRecommendation.cachedCategory(for: candidate) { _, _ in
                calls += 1
                return "玄幻"
            } == nil)
        }
        #expect(calls == 0)
        #expect(BookshelfDrawRecommendation.cachedCategory(for: ReadingBook(title: "本地", contentFilename: "local.txt")) == nil)
    }

    @Test("Explicit Chinese and translated genres produce the corresponding invitation")
    func genreMessages() {
        let book = ReadingBook(title: "测试书", contentFilename: "")
        let cases: [([String], String)] = [
            (["仙侠", "玄幻", "仙俠", "fantasy"], "暂别尘嚣，随这一页赴一场山海奇遇。"),
            (["悬疑", "推理", "偵探", "mystery"], "沿着线索往下读，让谜底慢慢现身。"),
            (["科幻", "science fiction", "SCI-FI"], "把想象交给远方，去看看世界之外。"),
            (["言情", "愛情", "romance"], "慢一点，听故事里那些尚未说出口的心意。"),
            (["历史", "歷史", "historical"], "翻开旧时光，在人物的抉择里走一程。"),
            (["都市", "職場", "urban"], "在日常的另一面，遇见一个不一样的人生。"),
            (["游戏", "電競", "game"], "进入故事的下一关，和主角一起探索新的冒险。"),
            (["体育", "體育", "sports"], "让热血再亮一回，跟随主角迎接下一场挑战。"),
            (["其他", "文学", "未分类"], "就从这一页出发，让故事给今天一点惊喜。")
        ]
        for (categories, invitation) in cases {
            for category in categories {
                #expect(BookshelfDrawRecommendation.message(for: book, category: category)
                        == "《测试书》 · \(invitation)")
            }
        }
    }

    @Test("Cache misses and genre-looking titles retain a neutral, error-free message")
    func neutralWithoutTitleGuessing() {
        let neutral = "就从这一页出发，让故事给今天一点惊喜。"
        for title in ["仙侠玄幻修仙", "悬疑推理侦探", "星际科幻", "都市言情", "历史游戏体育", "三体", " "] {
            var book = boundBook()
            book.title = title
            let category = BookshelfDrawRecommendation.cachedCategory(for: book, cacheKind: { _, _ in nil })
            #expect(category == nil)
            let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = displayTitle.isEmpty ? "这本书" : "《\(displayTitle)》"
            for kind: String? in [category, "", " \n ", "未识别题材"] {
                #expect(BookshelfDrawRecommendation.message(for: book, category: kind) == "\(name) · \(neutral)")
            }
        }
        let longTitle = ReadingBook(title: String(repeating: "书", count: 100), contentFilename: "")
        #expect(BookshelfDrawRecommendation.message(for: longTitle, category: nil)
                == "《\(String(repeating: "书", count: 80))》 · \(neutral)")
    }

    @Test("Every target maps the front pointer to its intended slot after at least three turns")
    func targetPointMapping() {
        let center = CGPoint(x: 200, y: 200)
        let pointer = CGPoint(x: 200, y: 80)
        for count in Array(1...9) + [10, 25] {
            for slot in 0..<min(count, 9) {
                for start: CGFloat in [-1485, -765, -15, 0, 67, 405, 1080] {
                    for turns in [-3, 0, 1, 3, 4] {
                        let target = BookshelfDrawMotion.target(slot: slot, count: count, from: start, turns: turns)
                        #expect(target - start >= CGFloat(max(3, turns)) * 360 - 0.0001)
                        #expect(target - start < CGFloat(max(3, turns) + 1) * 360 + 0.0001)
                        #expect(abs(BookshelfRingGeometry.target(slot: slot, near: target, count: count) - target) < 0.0001)
                        #expect(BookshelfRingGeometry.slot(at: pointer, center: center, diameter: 400,
                                                          rotation: target, count: count) == slot)
                    }
                }
            }
        }
    }

    @Test("Target boundaries clamp slots and reject invalid counts or starts")
    func targetBoundaries() {
        let center = CGPoint(x: 200, y: 200)
        let pointer = CGPoint(x: 200, y: 80)
        for (slot, expected) in [(-20, 0), (20, 8)] {
            let target = BookshelfDrawMotion.target(slot: slot, count: 20, from: -100)
            #expect(BookshelfRingGeometry.slot(at: pointer, center: center, diameter: 400,
                                              rotation: target, count: 20) == expected)
        }
        for count in [0, -1] {
            #expect(BookshelfDrawMotion.target(slot: 0, count: count, from: 10) == 0)
        }
        for start: CGFloat in [.nan, .infinity, -.infinity] {
            #expect(BookshelfDrawMotion.target(slot: 0, count: 9, from: start) == 0)
        }
    }

    @Test("Fourth-power easing is monotonic, bounded, and exact at its endpoints")
    func easing() {
        let start: CGFloat = -20
        let target: CGFloat = 1420
        var previous = start
        for index in 0...100 {
            let progress = Double(index) / 100
            let angle = BookshelfDrawMotion.angle(start: start, to: target, progress: progress)
            let expected = start + (target - start) * CGFloat(1 - pow(1 - progress, 4))
            #expect(abs(angle - expected) < 0.0001)
            #expect(angle >= previous && angle <= target)
            previous = angle
        }
        #expect(BookshelfDrawMotion.angle(from: start, to: target, progress: 0.5) == 1330)
        #expect(BookshelfDrawMotion.angle(start: start, to: target, progress: -1) == start)
        #expect(BookshelfDrawMotion.angle(start: start, to: target, progress: 2) == target)
        #expect(BookshelfDrawMotion.angle(start: start, to: target, progress: .nan) == start)
        #expect(BookshelfDrawMotion.angle(start: start, to: target, progress: .infinity) == start)
        #expect(BookshelfDrawMotion.angle(start: start, to: .nan, progress: 0.5) == start)
        #expect(BookshelfDrawMotion.angle(start: .nan, to: target, progress: 0.5) == 0)
    }

    private func shelf(count: Int) -> [ReadingBook] {
        (0..<count).map { index in
            var book = ReadingBook(title: "书\(index)", contentFilename: "\(index).txt")
            book.group = ["", "科幻组", "其他组"][index % 3]
            return book
        }
    }

    private func boundBook() -> ReadingBook {
        var book = ReadingBook(title: "题材以缓存为准", contentFilename: "")
        book.bookSourceId = UUID()
        book.bookInfoURL = "https://cache.invalid/book"
        return book
    }

    private struct ControlledRandom: RandomNumberGenerator {
        let words: [UInt64]
        private(set) var calls = 0

        mutating func next() -> UInt64 {
            defer { calls += 1 }
            return words[calls % words.count]
        }
    }
}
