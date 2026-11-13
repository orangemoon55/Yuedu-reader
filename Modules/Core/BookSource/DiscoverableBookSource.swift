import Foundation

/// A thread-safe projection for discovery-source pickers; never crosses actors with BookSource.
struct DiscoverableBookSource: Identifiable, Sendable {
    let id: UUID
    let name: String
    let url: String
}
