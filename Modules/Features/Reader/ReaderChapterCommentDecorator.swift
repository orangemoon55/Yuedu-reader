import Combine
import SwiftUI

/// A module's comments in the text of the book being read (maintainer, 2026-11-15: 段評、熱評、
/// 本章說、作者說都在閱讀介面): a count bubble at the end of a paragraph, a 熱評 card under one,
/// 作者說 and 本章說 cards after the chapter, each drawn as a 來源配置's own is and opening the
/// comments it stands for.
///
/// A chapter is asked about once, when it is first built; its answer is kept for the reading
/// session and said on `updates`, on which the reader builds the chapter again. Nothing is
/// asked for a chapter whose source drew comments of its own, with the switch off, or with no
/// module that has comments.
@MainActor
final class ReaderChapterCommentDecorator: ReaderChapterDecorationSource {
    /// What a module's site holds about one chapter.
    struct ChapterData: Equatable {
        var thread: ChapterCommentThread
        var notes: RuleModuleChapterNotes
        /// The chapter's first comments, for its 本章說 card.
        var top: [WorkReview] = []
        var total: Int?

        var isEmpty: Bool {
            notes.counts.isEmpty && notes.hot.isEmpty && notes.authorSay == nil && top.isEmpty && (total ?? 0) == 0
        }
    }

    private enum State {
        case loading(ChapterData?)
        /// Empty answers are short-lived: a failed request must not poison the session.
        case ready(ChapterData?, retryAt: Date?)
    }

    /// 設定 → 模組's 「在正文顯示模組的評論」; on unless the reader turned it off.
    nonisolated static let enabledKey = "yd_module_chapter_comments"
    static var isEnabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
    /// Comments drawn on a 本章說 card.
    nonisolated static let cardComments = 3

    /// A chapter's answer is in: the spine to build again.
    let updates = PassthroughSubject<Int, Never>()
    /// The book, as a module is asked about it; nil until a book is being read.
    var work: WorkReviewQuery?
    /// Every chapter's title, in order, read when a chapter is asked about.
    var chapterTitles: () -> [String] = { [] }

    typealias Progress = @MainActor @Sendable (ChapterData) -> Void
    typealias StreamingLoad = @MainActor (ChapterCommentQuery, @escaping Progress) async -> ChapterData?

    private var states: [Int: State] = [:]
    private var tasks: [Int: Task<Void, Never>] = [:]
    private var generation = UUID()
    private let load: StreamingLoad
    private let now: () -> Date

    /// Existing injected loaders still announce only their final answer.
    init(load: @escaping (ChapterCommentQuery) async -> ChapterData?, now: @escaping () -> Date = { .now }) {
        self.load = { query, _ in await load(query) }
        self.now = now
    }

    init(streamingLoad: @escaping StreamingLoad = ReaderChapterCommentDecorator.loadStreaming,
         now: @escaping () -> Date = { .now }) {
        self.load = streamingLoad
        self.now = now
    }

    /// Another book: nothing of the last one's is kept.
    func reset(work: WorkReviewQuery?, chapterTitles: @escaping () -> [String]) {
        tasks.values.forEach { $0.cancel() }
        generation = UUID()
        tasks = [:]
        states = [:]
        self.work = work
        self.chapterTitles = chapterTitles
    }

    // MARK: - Asking

    /// The chapter's thread, its notes and its first comments. A part that fails is logged where
    /// it is read and left out.
    static func load(_ query: ChapterCommentQuery) async -> ChapterData? {
        guard let thread = await ChapterComments.thread(for: query) else { return nil }
        var data = ChapterData(thread: thread, notes: await ChapterComments.notes(in: thread))
        do {
            let page = try await ChapterComments.comments(in: thread, sort: nil, page: 1)
            data.top = Array(page.comments.prefix(cardComments))
            data.total = page.total
        } catch is CancellationError {
            return nil
        } catch {
            AppLogger.network("⟐ chapter comments: the chapter's own comments failed", error: SourceFailure.loggable(error),
                              context: ["module": thread.module.id])
        }
        return data
    }

    @MainActor private final class Accumulator {
        var data: ChapterData
        init(_ data: ChapterData) { self.data = data }
    }

    /// Counts and hot cards publish independently; a slow author note or chapter list
    /// no longer holds every paragraph bubble behind all of the other requests.
    static func loadStreaming(_ query: ChapterCommentQuery, progress: @escaping Progress) async -> ChapterData? {
        guard let thread = await ChapterComments.thread(for: query), !Task.isCancelled else { return nil }
        let state = Accumulator(ChapterData(thread: thread, notes: RuleModuleChapterNotes(fetchedAt: .now)))
        guard let block = thread.module.comments else { return state.data }
        state.data.notes = await RuleModuleClient().chapterNotes(chapterID: thread.chapter.id, of: thread.record,
                                                                 by: block, in: thread.module) { notes in
            state.data.notes = notes
            progress(state.data)
        }
        guard !Task.isCancelled else { return nil }
        do {
            let page = try await ChapterComments.comments(in: thread, sort: nil, page: 1)
            state.data.top = Array(page.comments.prefix(cardComments))
            state.data.total = page.total
        } catch is CancellationError { return nil }
        catch {
            AppLogger.network("⟐ chapter comments: the chapter's own comments failed", error: SourceFailure.loggable(error),
                              context: ["module": thread.module.id])
        }
        return state.data
    }

    /// Reaching another page is an explicit retry opportunity, not an unbounded timer.
    func retryMissingIfNeeded(spine: Int, title: String) {
        guard case .ready(let data, let deadline?) = states[spine], now() >= deadline else { return }
        ask(spine: spine, title: title, previous: data)
    }

    private func data(forSpine spine: Int, title: String) -> ChapterData? {
        switch states[spine] {
        case .ready(let data, let retryAt):
            if let retryAt, now() >= retryAt {
                ask(spine: spine, title: title, previous: data)
                return data
            }
            return data
        case .loading(let data): return data
        case nil:
            ask(spine: spine, title: title)
            return nil
        }
    }

    private func ask(spine: Int, title: String, previous: ChapterData? = nil) {
        guard Self.isEnabled, let work, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            states[spine] = .ready(nil, retryAt: now().addingTimeInterval(10))
            return
        }
        let requestGeneration = generation
        states[spine] = .loading(previous)
        let query = ChapterCommentQuery(work: work, chapterTitle: title, chapterTitles: chapterTitles())
        tasks[spine] = Task { [weak self, load] in
            let found = await load(query) { [weak self] partial in
                guard let self, self.generation == requestGeneration, !Task.isCancelled else { return }
                let visible = partial.isEmpty ? previous : partial
                self.states[spine] = .loading(visible)
                if visible != nil { self.updates.send(spine) }
            }
            guard let self, self.generation == requestGeneration, !Task.isCancelled else { return }
            let fresh = found.flatMap { $0.isEmpty ? nil : $0 }
            let data = fresh ?? previous
            let retryDelay = fresh == nil ? 10.0 : 300.0
            self.states[spine] = .ready(data, retryAt: self.now().addingTimeInterval(retryDelay))
            self.tasks[spine] = nil
            if data != nil { self.updates.send(spine) }
        }
    }

    // MARK: - ReaderChapterDecorationSource

    func placements(forSpine spineIndex: Int, title: String, paragraphs: [String]) -> ReaderCommentPlacements? {
        guard let data = data(forSpine: spineIndex, title: title) else { return nil }
        let body = ChapterParagraphMatch.body(of: paragraphs, title: title)
        let keys = body.map(\.key)
        let chapterToken = ModuleCommentTargets.token(for: ModuleCommentTarget(thread: data.thread, paragraphID: nil, heading: title))
        let hasParagraphComments = data.thread.module.comments?.paragraph != nil
        var placements = ReaderCommentPlacements()
        placements.limitsHotCardsPerPage = data.thread.module.id == "local.hanyujian.comments"

        /// The paragraph a site's item is about, and the comments tapping it opens: that
        /// paragraph's when the module reads them, else the chapter's.
        func place(_ reference: ModuleParagraphReference) -> (position: Int, token: String)? {
            guard let index = ChapterParagraphMatch.index(of: reference, in: keys, remoteCount: data.notes.paragraphCount) else { return nil }
            let position = body[index].position
            guard hasParagraphComments, !reference.id.isEmpty else { return (position, chapterToken) }
            let heading = String(paragraphs[position].trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
            return (position, ModuleCommentTargets.token(for: ModuleCommentTarget(thread: data.thread, paragraphID: reference.id,
                                                                                  heading: heading)))
        }

        for count in data.notes.counts {
            guard let place = place(count.paragraph), placements.bubbles[place.position] == nil,
                  let href = ReaderHTMLUtilities.moduleReviewHref(count: String(count.count), title: localized("段評"), token: place.token)
            else { continue }
            placements.bubbles[place.position] = .init(count: count.count, href: href, title: localized("段評"))
        }
        let hotTitle = ReaderCommentCardKind.hotComment.localizedTitle
        for hot in data.notes.hot {
            // One card under a paragraph: the site's first for it.
            guard let place = place(hot.paragraph), placements.cards[place.position] == nil,
                  let href = ReaderHTMLUtilities.moduleReviewHref(count: "", title: hotTitle, token: place.token) else { continue }
            placements.cards[place.position] = [.init(content: ReviewCardContent(
                kind: .hotComment, title: hotTitle, count: "", number: "",
                comments: [.init(user: hot.comment.author ?? "", likes: hot.comment.likes.map(String.init) ?? "", content: hot.comment.text)]),
                href: href)]
        }
        let sayTitle = ReaderCommentCardKind.authorSay.localizedTitle
        if let say = data.notes.authorSay,
           let href = ReaderHTMLUtilities.moduleReviewHref(count: "", title: sayTitle, token: chapterToken) {
            placements.chapterEnd.append(.init(content: ReviewCardContent(
                kind: .authorSay, title: sayTitle, count: "", number: "",
                comments: [.init(user: say.author ?? "", likes: "", content: say.text)]), href: href))
        }
        let chapterTitle = ReaderCommentCardKind.chapterSay.localizedTitle
        if !data.top.isEmpty || (data.total ?? 0) > 0,
           let href = ReaderHTMLUtilities.moduleReviewHref(count: String(data.total ?? data.top.count), title: chapterTitle,
                                                           token: chapterToken) {
            placements.chapterEnd.append(.init(content: ReviewCardContent(
                kind: .chapterSay, title: chapterTitle,
                count: data.total.map { String(format: localized("%d 條評論"), $0) } ?? "", number: data.total.map(String.init) ?? "",
                comments: data.top.map { .init(user: $0.author ?? "", likes: $0.likes.map(String.init) ?? "", content: $0.text) }),
                href: href))
        }
        return placements.isEmpty ? nil : placements
    }
}

/// What a tapped bubble or card opens: a module's comments in the app's own list, a source's
/// in its own page.
struct ReaderReviewSheetContent: View {
    let target: ReaderHTMLUtilities.ReviewTarget
    let onDismiss: (_ body: String?) -> Void

    var body: some View {
        if let comments = ModuleCommentTargets.target(target.moduleToken) {
            ChapterCommentsSheet(target: comments)
        } else {
            LegadoReviewBrowserView(target: target, onDismiss: onDismiss)
        }
    }
}
