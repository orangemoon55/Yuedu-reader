import SwiftUI

extension HomeSection {
    static let rotatingRankKey = "home.rotatingRank.v1"
    static let rotatingRankSourceKey = "home.rotatingRankSource.v1"
    var rotatingRank: ExploreCategoryReference? {
        guard layout.style == .coverIntroCard, parameters[Self.rotatingRankKey] == "1",
              case .sourceCategories(let refs) = binding, refs.count == 1 else { return nil }
        return refs.first
    }
    var rotatingRankSourceURL: String? { parameters[Self.rotatingRankSourceKey] }

    /// A purely local selection. Neither selecting a rank nor enabling Save waits for a book request.
    mutating func configureRotatingRank(_ choice: HomeContentChoice, source: BookSource) {
        guard case .sourceCategories(let refs) = choice.binding, refs.count == 1,
              let ref = refs.first, ref.sourceURL == source.bookSourceUrl, ref.cardItem != nil else { return }
        binding = .sourceCategories([ref])
        parameters = choice.parameters
        parameters[Self.rotatingRankKey] = "1"
        parameters[Self.rotatingRankSourceKey] = source.bookSourceUrl
    }
}

struct HomeRankRotation: Equatable {
    static let interval: TimeInterval = 30
    private(set) var ids: [SourceItemKey] = []
    private(set) var current: SourceItemKey?
    private(set) var started = Date.distantPast

    mutating func set(_ values: [SourceItemKey], now: Date) {
        var seen = Set<SourceItemKey>()
        ids = values.filter { seen.insert($0).inserted }
        let previous = current
        if let current, ids.contains(current) {
            // Metadata refreshes must not restart a book that is already on screen.
        } else {
            current = ids.first
        }
        if previous != current { started = now }
    }

    mutating func restart(at now: Date) { started = now }

    mutating func move(by offset: Int, at now: Date) {
        guard !ids.isEmpty else { return }
        let index = current.flatMap { ids.firstIndex(of: $0) } ?? 0
        let target = ((index + offset) % ids.count + ids.count) % ids.count
        current = ids[target]
        started = now
    }

    @discardableResult
    mutating func next(now: Date) -> Bool {
        guard ids.count > 1, now.timeIntervalSince(started) >= Self.interval else { return false }
        move(by: 1, at: now)
        return true
    }
}
