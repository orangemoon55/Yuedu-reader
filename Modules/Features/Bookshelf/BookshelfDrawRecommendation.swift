import Foundation

/// A draw is local only. It neither changes shelf order nor fetches book metadata.
enum BookshelfDrawRecommendation {
    static func eligible(in books: [ReadingBook]) -> [ReadingBook] {
        var seen = Set<UUID>()
        return books.filter { $0.isInBookshelf && seen.insert($0.id).inserted }
    }

    static func choose<R: RandomNumberGenerator>(from books: [ReadingBook], using random: inout R) -> ReadingBook? {
        eligible(in: books).randomElement(using: &random)
    }

    /// A result outside the first nine temporarily takes the last visible slot.
    /// The caller's shelf array and its saved ordering remain untouched.
    static func visibleBooks(from books: [ReadingBook], including id: UUID?) -> [ReadingBook] {
        let shelf = eligible(in: books)
        var visible = Array(shelf.prefix(BookshelfRingGeometry.maximumCount))
        if let id, !visible.contains(where: { $0.id == id }), let winner = shelf.first(where: { $0.id == id }) {
            if visible.count == BookshelfRingGeometry.maximumCount { visible.removeLast() }
            visible.append(winner)
        }
        return visible
    }

    static func visibleBooks(from books: [ReadingBook], preserving selectedID: UUID?, including winnerID: UUID) -> [ReadingBook] {
        var visible = Array(eligible(in: books).prefix(BookshelfRingGeometry.maximumCount))
        let protected = Set([selectedID, Optional(winnerID)].compactMap { $0 })
        guard let winner = books.first(where: { $0.id == winnerID && $0.isInBookshelf }),
              !visible.contains(where: { $0.id == winnerID }) else { return visible }
        if visible.count == BookshelfRingGeometry.maximumCount,
           let replace = visible.indices.reversed().first(where: { !protected.contains(visible[$0].id) }) {
            visible.remove(at: replace)
        }
        if visible.count < BookshelfRingGeometry.maximumCount { visible.append(winner) }
        return visible
    }

    static func visibleBooks(from base: [ReadingBook], preserving selectedID: UUID?, including winner: ReadingBook,
                             from all: [ReadingBook]) -> [ReadingBook] {
        var shown = visibleBooks(from: base, including: selectedID)
        guard winner.isInBookshelf, all.contains(where: { $0.id == winner.id && $0.isInBookshelf }),
              !shown.contains(where: { $0.id == winner.id }) else { return shown }
        if shown.count >= BookshelfRingGeometry.maximumCount {
            let replacement = shown.indices.reversed().first { shown[$0].id != selectedID } ?? shown.count - 1
            shown.remove(at: replacement)
        }
        shown.append(winner)
        return shown
    }

    static func safeVisibleBooks(from books: [ReadingBook], including id: UUID?) -> [ReadingBook] {
        let shelf = eligible(in: books)
        var visible = Array(shelf.prefix(BookshelfRingGeometry.maximumCount))
        guard let id, !visible.contains(where: { $0.id == id }), let winner = shelf.first(where: { $0.id == id }) else {
            return visible
        }
        if visible.count == BookshelfRingGeometry.maximumCount { visible.removeLast() }
        visible.append(winner)
        return visible
    }

    static func slot(for id: UUID?, in books: [ReadingBook], fallback: Int) -> Int {
        guard let id, let index = books.firstIndex(where: { $0.id == id }) else { return fallback }
        return index
    }

    static func message(for book: ReadingBook, category: String?) -> String {
        let kind = category?.lowercased() ?? ""
        let title = String(book.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        let name = title.isEmpty ? "这本书" : "《\(title)》"
        let invitation: String
        if contains(kind, ["悬疑", "懸疑", "推理", "侦探", "偵探", "mystery", "detective", "惊悚", "驚悚"]) {
            invitation = "沿着线索往下读，让谜底慢慢现身。"
        } else if contains(kind, ["科幻", "science fiction", "sci-fi", "星际", "星際"]) {
            invitation = "把想象交给远方，去看看世界之外。"
        } else if contains(kind, ["仙侠", "仙俠", "修仙", "玄幻", "奇幻", "fantasy", "武侠", "武俠"]) {
            invitation = "暂别尘嚣，随这一页赴一场山海奇遇。"
        } else if contains(kind, ["历史", "歷史", "架空", "history", "historical"]) {
            invitation = "翻开旧时光，在人物的抉择里走一程。"
        } else if contains(kind, ["言情", "爱情", "愛情", "romance", "婚恋", "婚戀"]) {
            invitation = "慢一点，听故事里那些尚未说出口的心意。"
        } else if contains(kind, ["都市", "现实", "現實", "职场", "職場", "生活", "urban"]) {
            invitation = "在日常的另一面，遇见一个不一样的人生。"
        } else if contains(kind, ["游戏", "遊戲", "电竞", "電競", "game", "esports"]) {
            invitation = "进入故事的下一关，和主角一起探索新的冒险。"
        } else if contains(kind, ["体育", "體育", "竞技", "競技", "sports", "sport"]) {
            invitation = "让热血再亮一回，跟随主角迎接下一场挑战。"
        } else {
            invitation = "就从这一页出发，让故事给今天一点惊喜。"
        }
        return "\(name) · \(invitation)"
    }

    private static func contains(_ value: String, _ words: [String]) -> Bool {
        words.contains { value.contains($0) }
    }

    /// Synchronous disk-cache read only, accepting stale metadata. The caller
    /// chooses the execution context; ReadingBook never crosses a task boundary here.
    static func cachedCategory(for book: ReadingBook) -> String? {
        cachedCategory(for: book) { url, sourceID in
            // Cache keys depend on the UUID, so a removed source can still have
            // useful saved metadata without loading or changing the source store.
            var source = BookSource()
            source.id = sourceID
            return BookSourceFetcher.shared.loadBookInfoPackageSync(
                url: url, source: source, maximumAge: nil
            )?.kind
        }
    }

    /// The local-kind reader is injectable so policy tests need no disk or network.
    static func cachedCategory(
        for book: ReadingBook,
        cacheKind: (_ url: String, _ sourceID: UUID) -> String?
    ) -> String? {
        guard let id = book.bookSourceId,
              let url = book.bookInfoURL?.trimmingCharacters(in: .whitespacesAndNewlines),
              !url.isEmpty else { return nil }
        if let kind = nonempty(cacheKind(url, id)) { return kind }
        for key in ["kind", "category", "genre"] {
            if let kind = nonempty(book.runtimeVariables?[key]) { return kind }
        }
        return nil
    }

    private static func nonempty(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return nil }
        return value
    }
}

/// Closed-form, monotonic roulette travel with a finite ending. The physical
/// result is selected uniformly before the animation starts, never by frame rate.
enum BookshelfDrawMotion {
    static func target(slot: Int, count: Int, from start: CGFloat, turns: Int = 4) -> CGFloat {
        guard count > 0, start.isFinite else { return 0 }
        let base = BookshelfRingGeometry.target(slot: slot, near: start, count: count)
        let minTurns = max(3, turns)
        // The rotor's pointer is at -90°, matching the shelf's sector-zero anchor.
        // Rotate forward (clockwise in the drawn coordinate system) into the slot.
        var travel = (base - start).truncatingRemainder(dividingBy: 360)
        if travel < 0 { travel += 360 }
        return start + CGFloat(minTurns) * 360 + travel
    }

    static func angle(from start: CGFloat, to target: CGFloat, progress: Double) -> CGFloat {
        guard start.isFinite, target.isFinite else { return start.isFinite ? start : 0 }
        let t = min(max(progress.isFinite ? progress : 0, 0), 1)
        let eased = 1 - pow(1 - t, 4)
        return start + (target - start) * CGFloat(eased)
    }

    static func angle(start: CGFloat, to target: CGFloat, progress: Double) -> CGFloat {
        angle(from: start, to: target, progress: progress)
    }
}
