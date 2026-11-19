import Foundation

/// One nested module record, in source order. The optional route uses the same module
/// identity and normal URL/cover/readability gates as a standalone entry.
/// Based on the MPL-2.0 upstream WorkVolume at d6cfdb980346c3b82b8e56cb343d00b4fefb5de1.
struct WorkVolume: Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let cover: CoverReference?
    let work: WorkDetailRoute?
}
