import Foundation
import Observation

/// UI-only state. A draw never mutates BookStore, group membership or saved ordering.
@MainActor @Observable
final class BookshelfRingDrawState {
    enum Phase: Equatable { case idle, spinning, revealed }

    struct Run {
        let id: UUID
        let winner: ReadingBook
        let slot: Int
        let previousSlot: Int
    }

    private(set) var phase: Phase = .idle
    private(set) var displayedBooks: [ReadingBook] = []
    private(set) var selectedID: UUID?
    private(set) var run: Run?
    private(set) var recommendation: String?
    private var previousID: UUID?
    private var category: String?

    var isDrawing: Bool { phase == .spinning }
    var selectedBook: ReadingBook? {
        displayedBooks.first { $0.id == selectedID } ?? displayedBooks.first
    }

    func synchronize(base: [ReadingBook], all: [ReadingBook]) {
        let pool = BookshelfDrawRecommendation.eligible(in: all)
        if isDrawing {
            if let run, !pool.contains(where: { $0.id == run.winner.id }) { cancel(base: base) }
            return
        }
        if phase == .revealed, let run {
            guard pool.contains(where: { $0.id == run.winner.id }) else {
                cancel(base: base)
                return
            }
            let byID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            displayedBooks = displayedBooks.compactMap { byID[$0.id] }
            return
        }
        displayedBooks = BookshelfDrawRecommendation.visibleBooks(from: base, including: selectedID)
        if !displayedBooks.contains(where: { $0.id == selectedID }) { selectedID = displayedBooks.first?.id }
    }

    func refreshInformation(from all: [ReadingBook]) {
        let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        displayedBooks = displayedBooks.map { byID[$0.id] ?? $0 }
    }

    @discardableResult
    func begin<R: RandomNumberGenerator>(base: [ReadingBook], all: [ReadingBook], using random: inout R) -> Run? {
        guard !isDrawing,
              let winner = BookshelfDrawRecommendation.choose(from: all, using: &random) else { return nil }
        let oldSelection = selectedID
        let shown = BookshelfDrawRecommendation.visibleBooks(from: base, preserving: oldSelection,
                                                             including: winner, from: all)
        guard let slot = shown.firstIndex(where: { $0.id == winner.id }) else { return nil }
        let previousSlot = shown.firstIndex { $0.id == oldSelection } ?? 0
        let next = Run(id: UUID(), winner: winner, slot: slot, previousSlot: previousSlot)
        displayedBooks = shown
        previousID = oldSelection
        // Keep the old header visible until the wheel has stopped.
        selectedID = shown.contains(where: { $0.id == oldSelection }) ? oldSelection : shown.first?.id
        run = next
        phase = .spinning
        recommendation = nil
        category = nil
        return next
    }

    @discardableResult
    func finish(runID: UUID, slot: Int) -> Bool {
        guard isDrawing, let run, run.id == runID, run.slot == slot,
              displayedBooks.indices.contains(slot), displayedBooks[slot].id == run.winner.id else { return false }
        phase = .revealed
        selectedID = run.winner.id
        recommendation = BookshelfDrawRecommendation.message(for: run.winner, category: category)
        return true
    }

    func setCategory(_ value: String?, runID: UUID) {
        guard let run, run.id == runID else { return }
        category = value
        if phase == .revealed {
            recommendation = BookshelfDrawRecommendation.message(for: run.winner, category: value)
        }
    }

    func select(slot: Int) {
        guard !isDrawing, displayedBooks.indices.contains(slot) else { return }
        let id = displayedBooks[slot].id
        if id != selectedID { recommendation = nil }
        selectedID = id
        if id != run?.winner.id { phase = .idle; run = nil; category = nil }
    }

    func cancel(base: [ReadingBook]) {
        run = nil
        phase = .idle
        recommendation = nil
        category = nil
        selectedID = previousID ?? selectedID
        displayedBooks = BookshelfDrawRecommendation.visibleBooks(from: base, including: selectedID)
        if !displayedBooks.contains(where: { $0.id == selectedID }) { selectedID = displayedBooks.first?.id }
    }
}
