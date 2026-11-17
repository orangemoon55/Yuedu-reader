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
    mutating func configureRotatingRank(_ choice: HomeContentChoice, source: BookSource) {
        guard case .sourceCategories(let refs) = choice.binding, let ref = refs.first,
              ref.sourceURL == source.bookSourceUrl else { return }
        binding = .sourceCategories([ref]); parameters = choice.parameters
        parameters[Self.rotatingRankKey] = "1"; parameters[Self.rotatingRankSourceKey] = source.bookSourceUrl
    }
}

struct HomeRankRotation: Equatable {
    static let interval: TimeInterval = 30
    var ids: [SourceItemKey] = []; var current: SourceItemKey?; var started = Date.distantPast
    mutating func set(_ values: [SourceItemKey], now: Date) { var seen = Set<SourceItemKey>()
        ids = values.filter { seen.insert($0).inserted }; current = current.flatMap { ids.contains($0) ? $0 : nil } ?? ids.first; if current == ids.first { started = now } }
    mutating func restart(at now: Date) { started = now }
    mutating func move(by offset: Int, at now: Date) {
        guard !ids.isEmpty else { return }
        let index = ids.firstIndex(of: current ?? ids[0]) ?? 0
        current = ids[(index + offset + ids.count) % ids.count]
        started = now
    }
    mutating func next(now: Date) -> Bool { guard ids.count > 1, now.timeIntervalSince(started) >= Self.interval else { return false }; let i = ids.firstIndex(of: current ?? ids[0]) ?? 0; current = ids[(i + 1) % ids.count]; started = now; return true }
}
