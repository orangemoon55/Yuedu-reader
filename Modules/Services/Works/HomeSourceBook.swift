import Combine
import Foundation

/// A manually selected book, bound to its exact installed source and detail URL.
/// The homepage reads this snapshot without repeating a search or selecting a different edition.
struct HomeSourceBook: Codable, Hashable, Sendable {
    let sourceURL: String
    let bookURL: String
    let title: String
    let author: String
    let intro: String
    let coverURL: String
    let tocURL: String
    let kind: String
    let wordCount: String
    let lastChapter: String
    let runtimeVariables: [String: String]?

    init(book: OnlineBook, source: BookSource) {
        sourceURL = source.bookSourceUrl
        bookURL = book.bookUrl
        title = String(book.name.prefix(300))
        author = String(book.author.prefix(300))
        intro = String(book.intro.prefix(12_000))
        coverURL = book.coverUrl
        tocURL = book.tocUrl
        kind = String(book.kind.prefix(500))
        wordCount = book.wordCount
        lastChapter = String(book.lastChapter.prefix(500))
        runtimeVariables = book.runtimeVariables
    }

    func onlineBook(in source: BookSource) -> OnlineBook? {
        guard source.bookSourceUrl == sourceURL, !bookURL.isEmpty else { return nil }
        return OnlineBook(name: title, author: author, intro: intro, coverUrl: coverURL,
                          bookUrl: bookURL, tocUrl: tocURL, wordCount: wordCount,
                          lastChapter: lastChapter, kind: kind, sourceId: source.id,
                          sourceName: source.bookSourceName, runtimeVariables: runtimeVariables)
    }
}

/// Search and detail enrichment for the explicit choice; the view only presents its state.
@MainActor
final class HomeSourceBookPickerModel: ObservableObject {
    @Published private(set) var books: [OnlineBook] = []
    @Published private(set) var isLoading = false
    @Published private(set) var selectingID: UUID?
    @Published private(set) var error: String?
    @Published private(set) var hasMore = false
    private var page = 0
    private var query = ""
    private var generation = UUID()

    func search(_ text: String, in source: BookSource, more: Bool = false) async {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !more || (!isLoading && text == query) else { return }
        let request = UUID()
        generation = request
        if !more { query = text; page = 0; books = []; hasMore = false }
        let next = more ? page + 1 : 1
        isLoading = true
        error = nil
        defer { if generation == request { isLoading = false } }
        do {
            let results = try await BookSourceFetcher.shared.search(query: text, in: source, page: next,
                                                                    failureMode: .propagateTransportError)
            guard !Task.isCancelled, generation == request else { return }
            var existing = Set(books.map(\.bookUrl))
            let additions = results.filter { !$0.bookUrl.isEmpty && existing.insert($0.bookUrl).inserted }
            books += additions
            page = next
            hasMore = !additions.isEmpty
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            self.error = error.localizedDescription
        }
    }

    func select(_ book: OnlineBook, in source: BookSource) async -> HomeSourceBook? {
        guard selectingID == nil else { return nil }
        selectingID = book.id
        defer { selectingID = nil }
        // Search results already identify the exact edition. A failed detail enrichment keeps
        // that explicit choice, never substitutes a similarly titled book from another source.
        let enriched = try? await BookSourceFetcher.shared.fetchBookInfo(
            url: book.bookUrl, source: source, runtimeVariables: book.runtimeVariables, knownBook: book)
        guard !Task.isCancelled else { return nil }
        var chosen = enriched ?? book
        chosen.bookUrl = book.bookUrl
        return HomeSourceBook(book: chosen, source: source)
    }
}
