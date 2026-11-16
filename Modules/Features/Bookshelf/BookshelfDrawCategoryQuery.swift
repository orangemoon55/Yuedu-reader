import Foundation

/// Only scalar, Sendable metadata crosses to the utility task; not a SwiftUI view or ReadingBook.
struct BookshelfDrawCategoryQuery: Sendable {
    let sourceID: UUID?
    let infoURL: String?
    let explicitCategories: [String]

    init(book: ReadingBook) {
        sourceID = book.bookSourceId
        infoURL = book.bookInfoURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        explicitCategories = ["kind", "category", "genre"].compactMap { book.runtimeVariables?[$0] }
    }

    nonisolated func load() -> String? {
        if let sourceID, let infoURL, !infoURL.isEmpty {
            var source = BookSource()
            source.id = sourceID
            if let value = BookSourceFetcher.shared.loadBookInfoPackageSync(
                url: infoURL, source: source, maximumAge: nil
            )?.kind.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return explicitCategories.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }
}
