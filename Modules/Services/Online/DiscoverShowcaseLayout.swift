import Foundation

/// One rendered block per lazy-stack entry: the charts together, or one cover shelf.
struct DiscoverShowcaseGroup: Identifiable {
    let id: UUID
    let charts: [DiscoverShowcaseSection]
    let shelf: DiscoverShowcaseSection?
}

enum DiscoverShowcaseLayout {
    /// Partition once with one settings snapshot, instead of reading UserDefaults and
    /// rescanning all sections inside every lazy-stack row.
    nonisolated static func groups(
        sections: [DiscoverShowcaseSection], rankedKeywords: [String], rankedFirst: Bool
    ) -> [DiscoverShowcaseGroup] {
        var charts: [DiscoverShowcaseSection] = []
        var chartIDs: Set<UUID> = []
        for section in sections {
            if DiscoverViewModel.sectionStyle(for: section.title, rankedKeywords: rankedKeywords) == .ranked {
                charts.append(section)
                chartIDs.insert(section.id)
            }
        }
        var result: [DiscoverShowcaseGroup] = []
        if rankedFirst, let first = charts.first {
            result.append(DiscoverShowcaseGroup(id: first.id, charts: charts, shelf: nil))
        }
        var chartsPlaced = rankedFirst
        for section in sections {
            if chartIDs.contains(section.id) {
                if !chartsPlaced {
                    result.append(DiscoverShowcaseGroup(id: section.id, charts: charts, shelf: nil))
                    chartsPlaced = true
                }
            } else {
                result.append(DiscoverShowcaseGroup(id: section.id, charts: [], shelf: section))
            }
        }
        return result
    }
}
