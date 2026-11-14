import Foundation

/// A thread-safe projection for discovery-source pickers; never crosses actors with BookSource.
struct DiscoverableBookSource: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let url: String
    let displayName: String

    nonisolated init(id: UUID, name: String, url: String) {
        self.id = id
        self.name = name
        self.url = url
        self.displayName = BookSourceDisplayName.title(name)
    }
}
