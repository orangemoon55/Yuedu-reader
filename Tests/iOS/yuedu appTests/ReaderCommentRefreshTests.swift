import Combine
import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Reader module comments refresh", .serialized)
struct ReaderCommentRefreshTests {
    @MainActor private final class Gate {
        var continuation: CheckedContinuation<ReaderChapterCommentDecorator.ChapterData?, Never>?
        var started: (() -> Void)?
        func value() async -> ReaderChapterCommentDecorator.ChapterData? {
            await withCheckedContinuation { continuation in
                self.continuation = continuation
                started?()
            }
        }
        func finish(_ data: ReaderChapterCommentDecorator.ChapterData?) {
            let held = continuation
            continuation = nil
            held?.resume(returning: data)
        }
    }

    private func data(_ count: Int) throws -> ReaderChapterCommentDecorator.ChapterData {
        let input = Data(#"{"id":"local.hanyujian.comments","title":"Test","version":"1.0.0","requiredVersion":"3.0.2","hosts":["example.com"],"modules":[],"comments":{"chapters":{"request":{"url":"https://example.com/b/{{id}}/chapters"},"list":{"items":"$.items[*]","id":"$.id","title":"$.title"}},"chapter":{"request":{"url":"https://example.com/c/{{chapterId}}"},"list":{"items":"$.items[*]","text":"$.text"}},"paragraph":{"request":{"url":"https://example.com/c/{{chapterId}}/p/{{paragraphId}}"},"list":{"items":"$.items[*]","text":"$.text"}}}}"#.utf8)
        let module = try JSONDecoder().decode(RuleModule.self, from: input)
        let record = RuleListItem(name: "Book", author: "Author", bookUrl: "https://example.com/b/7",
                                  coverUrl: "", intro: "", wordCount: "", lastChapter: "", kind: "", id: "7")
        let thread = ChapterCommentThread(module: module, record: record, chapter: .init(id: "c1", title: "第一章"))
        var notes = RuleModuleChapterNotes(fetchedAt: Date(timeIntervalSince1970: 0))
        notes.counts = [.init(paragraph: .init(quote: ChapterParagraphMatch.fold("风起了"), index: nil, id: "p1"), count: count)]
        return .init(thread: thread, notes: notes)
    }

    private func reset(_ decorator: ReaderChapterCommentDecorator, name: String = "Book") {
        decorator.reset(work: WorkReviewQuery(title: name, authors: ["Author"], contentKind: .text), chapterTitles: { ["第一章"] })
    }
    private func placements(_ decorator: ReaderChapterCommentDecorator) -> ReaderCommentPlacements? {
        decorator.placements(forSpine: 0, title: "第一章", paragraphs: ["第一章", "风起了"])
    }

    @Test("a failed first request can retry after ten seconds rather than poison the session")
    func failedRequestRetries() async throws {
        var instant = Date(timeIntervalSince1970: 100)
        var attempts = 0
        var completed: (() -> Void)?
        let answer = try data(42)
        let decorator = ReaderChapterCommentDecorator(load: { _ in
            attempts += 1
            defer { completed?() }
            return attempts == 1 ? nil : answer
        }, now: { instant })
        reset(decorator)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            completed = { done.resume() }; _ = placements(decorator)
        }
        #expect(placements(decorator) == nil && attempts == 1)
        instant = instant.addingTimeInterval(11)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            completed = { done.resume() }; decorator.retryMissingIfNeeded(spine: 0, title: "第一章")
        }
        #expect(placements(decorator)?.bubbles[1]?.count == 42)
        #expect(attempts == 2)
        #expect(placements(decorator)?.limitsHotCardsPerPage == true)
    }

    @Test("counts are visible while the rest of the streamed request is still pending")
    func partialNotesShowBeforeFinal() async throws {
        let gate = Gate()
        let partial = try data(12)
        let final = try data(27)
        var published: (() -> Void)?
        let decorator = ReaderChapterCommentDecorator(streamingLoad: { _, progress in
            progress(partial)
            return await gate.value()
        })
        reset(decorator)
        let sink = decorator.updates.sink { _ in published?() }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            gate.started = { done.resume() }; _ = placements(decorator)
        }
        #expect(placements(decorator)?.bubbles[1]?.count == 12)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            published = { done.resume() }; gate.finish(final)
        }
        #expect(placements(decorator)?.bubbles[1]?.count == 27)
        sink.cancel()
    }

    @Test("a cancelled old book request cannot overwrite a new book at the same spine")
    func resetRejectsStaleReply() async throws {
        let old = Gate(), new = Gate()
        let oldAnswer = try data(99), newAnswer = try data(7)
        var oldReturned: (() -> Void)?
        let decorator = ReaderChapterCommentDecorator(load: { query in
            if query.work.title == "Old" {
                let value = await old.value(); oldReturned?(); return value
            }
            return await new.value()
        })
        reset(decorator, name: "Old")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            old.started = { done.resume() }; _ = placements(decorator)
        }
        reset(decorator, name: "New")
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            new.started = { done.resume() }; _ = placements(decorator)
        }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            oldReturned = { done.resume() }; old.finish(oldAnswer)
        }
        #expect(placements(decorator) == nil, "old 99-count answer must not enter the new book")
        var finished: (() -> Void)?
        let sink = decorator.updates.sink { _ in finished?() }
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            finished = { done.resume() }; new.finish(newAnswer)
        }
        #expect(placements(decorator)?.bubbles[1]?.count == 7)
        sink.cancel()
    }
}
