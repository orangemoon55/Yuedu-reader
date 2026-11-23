import Foundation

/// A catalogue choice names a real section from an installed source, including the source filters that
/// were active when the section was chosen. Its ID is not the transient ID of a displayed book.
struct DiscoveryCategoryChoice: Codable, Hashable, Identifiable, Sendable {
    let reference: ExploreCategoryReference
    let filters: [String: String]
    var label: String? = nil

    struct ID: Hashable, Sendable {
        let reference: ExploreCategoryReference
        let filters: [String: String]
    }

    var title: String { label ?? reference.title }
    var id: ID { ID(reference: reference, filters: filters) }
}
