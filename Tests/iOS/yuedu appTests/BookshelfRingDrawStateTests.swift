import CoreGraphics
import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Shelf draw integration and fixed stage")
struct BookshelfRingDrawStateTests {
    @Test("Changing shelf order never changes the winning sector after reveal")
    func stableWinningSnapshot() throws {
        let all = shelf(14)
        let base = Array(all.reversed())
        let state = BookshelfRingDrawState()
        state.synchronize(base: base, all: all)
        let prior = state.selectedID
        var random = HighRandom()
        let run = try #require(state.begin(base: base, all: all, using: &random))
        let snapshot = state.displayedBooks.map(\.id)
        #expect(state.selectedID == prior)
        #expect(state.isDrawing && state.recommendation == nil)
        #expect(!state.finish(runID: UUID(), slot: run.slot))
        #expect(state.finish(runID: run.id, slot: run.slot))
        #expect(state.displayedBooks.map(\.id) == snapshot)
        #expect(state.displayedBooks[run.slot].id == run.winner.id)
        #expect(state.selectedID == run.winner.id)
        state.synchronize(base: all, all: all)
        #expect(state.displayedBooks.map(\.id) == snapshot)
        #expect(base.map(\.id) == all.reversed().map(\.id))
    }

    @Test("Late genre data updates the current result and old draws cannot overwrite it")
    func lateCategoryAndManualSelection() throws {
        let all = shelf(12)
        let state = BookshelfRingDrawState()
        state.synchronize(base: all, all: all)
        var random = HighRandom()
        let run = try #require(state.begin(base: all, all: all, using: &random))
        #expect(!all.prefix(9).contains(where: { $0.id == run.winner.id }))
        #expect(state.finish(runID: run.id, slot: run.slot))
        state.setCategory("悬疑推理", runID: run.id)
        #expect(state.recommendation?.contains("谜底") == true)
        state.select(slot: 0)
        #expect(state.selectedID == state.displayedBooks[0].id)
        #expect(state.recommendation == nil)
        state.setCategory("言情", runID: run.id)
        #expect(state.recommendation == nil)
    }

    @Test("Removed books and explicit cancellation restore the previous shelf selection")
    func cancellationAndRemovedWinner() throws {
        let all = shelf(12)
        let state = BookshelfRingDrawState()
        state.synchronize(base: all, all: all)
        let previous = state.selectedID
        var random = HighRandom()
        let first = try #require(state.begin(base: all, all: all, using: &random))
        #expect(state.begin(base: all, all: all, using: &random) == nil)
        state.cancel(base: all)
        #expect(state.phase == .idle && state.run == nil)
        #expect(state.selectedID == previous)
        #expect(!state.finish(runID: first.id, slot: first.slot))
        let second = try #require(state.begin(base: all, all: all, using: &random))
        let remaining = all.filter { $0.id != second.winner.id }
        state.synchronize(base: remaining, all: remaining)
        #expect(!state.isDrawing && state.run == nil)
        #expect(!state.displayedBooks.contains(where: { $0.id == second.winner.id }))
    }

    @Test("Motion completes the chosen slot exactly once without a display server")
    func deterministicMotion() {
        for count in 1...9 {
            let motion = BookshelfRingMotion(usesDisplayLink: false, clock: { 100 })
            motion.isActive = true
            motion.configure(count: count, slot: 0)
            var results: [Int] = []
            let slot = count - 1
            #expect(motion.draw(slot: slot, reduceMotion: false) { results.append($0) })
            #expect(motion.isDrawing && !motion.canOpenSector)
            motion.select(0, reduceMotion: true)
            motion.advance(to: 100.5)
            #expect(motion.rotation > 0 && results.isEmpty)
            motion.advance(to: 103)
            motion.advance(to: 105)
            #expect(results == [slot])
            #expect(!motion.isDrawing && !motion.isSpinning)
            #expect(motion.selectedSlot == slot)
            #expect(BookshelfRingGeometry.nearestSlot(to: motion.rotation, count: count) == slot)
        }
    }

    @Test("Backgrounding cancels a draw and stale display-link ticks cannot reveal it")
    func motionCancellation() {
        let motion = BookshelfRingMotion(usesDisplayLink: false, clock: { 100 })
        motion.configure(count: 9, slot: 2)
        motion.isActive = true
        var completions = 0, cancellations = 0
        #expect(motion.draw(slot: 8, reduceMotion: false, onCancel: { cancellations += 1 }) { _ in completions += 1 })
        motion.advance(to: 100.3)
        motion.isActive = false
        motion.advance(to: 104)
        #expect(cancellations == 1 && completions == 0)
        #expect(!motion.isDrawing && !motion.isSpinning)
        motion.isActive = true
        #expect(motion.draw(slot: 4, reduceMotion: true) { _ in completions += 1 })
        #expect(completions == 1 && motion.selectedSlot == 4)
        #expect(!motion.isDrawing && !motion.isSpinning)
    }

    @Test("Square stage and more control remain on screen and outside the gear")
    func fixedStageGeometry() {
        for size in [CGSize(width: 320, height: 540), CGSize(width: 393, height: 650),
                     CGSize(width: 430, height: 740), CGSize(width: 920, height: 800)] {
            let layout = BookshelfRingStageLayout(size: size, headerHeight: 242)
            let side = layout.diameter
            #expect(side > 0 && side <= 440 && side + 24 <= size.width)
            #expect(side + 242 + 28 <= size.height)
            let rightCorner = CGRect(x: side - layout.moreSize.width + 12, y: -12,
                                     width: layout.moreSize.width, height: layout.moreSize.height)
            let center = CGPoint(x: side / 2, y: side / 2)
            let x = max(rightCorner.minX, min(center.x, rightCorner.maxX))
            let y = max(rightCorner.minY, min(center.y, rightCorner.maxY))
            #expect(hypot(x - center.x, y - center.y) > side * CyberGearShape.tipRadius)
        }
    }

    private func shelf(_ count: Int) -> [ReadingBook] {
        (0..<count).map { index in
            var book = ReadingBook(title: "书\(index)", contentFilename: "\(index).txt")
            book.group = index.isMultiple(of: 2) ? "分组" : ""
            return book
        }
    }
    private struct HighRandom: RandomNumberGenerator {
        mutating func next() -> UInt64 { .max }
    }
}
