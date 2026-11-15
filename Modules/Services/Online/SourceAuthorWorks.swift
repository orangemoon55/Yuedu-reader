import Combine
import Foundation

/// 作者其他作品 at an online source detail, fetched only through that page's source.
@MainActor
final class SourceAuthorWorks: ObservableObject {
    enum State {
        case hidden
        case loading
        case loaded([DiscoverBookDisplay])
        case failed(String)
    }

    @Published private(set) var state: State = .hidden
    private var loadedKey: String?

    static let limit = 12

    func load(
        key: String?,
        source: BookSource?,
        author: String,
        currentBook: OnlineBook,
        fetcher: any BookSourceFetching
    ) async {
        guard let key else {
            state = .hidden
            loadedKey = nil
            return
        }
        guard key != loadedKey else { return }
        guard let source, !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            state = .hidden
            loadedKey = key
            return
        }

        state = .loading
        do {
            let targetAuthor = Self.normalized(author)
            let books = try await fetcher.search(query: author, in: source, earlyFilter: { _, candidate in
                let name = Self.normalized(candidate)
                return !name.isEmpty && (name == targetAuthor || name.contains(targetAuthor) || targetAuthor.contains(name))
            })
            guard !Task.isCancelled else { return }
            let currentURL = currentBook.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            let currentTitle = SourceGenreMatching.normalized(currentBook.name)
            var seen = Set<String>()
            let others = books.filter { book in
                let url = book.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
                let title = SourceGenreMatching.normalized(book.name)
                guard !book.author.isEmpty, Self.normalized(book.author).contains(targetAuthor) else { return false }
                guard title != currentTitle, currentURL.isEmpty || url != currentURL else { return false }
                let key = url.isEmpty ? title : url
                return !key.isEmpty && seen.insert(key).inserted
            }.prefix(Self.limit)
            let displays = await DiscoverViewModel.makeDisplays(Array(others), source: source)
            guard !Task.isCancelled else { return }
            state = displays.isEmpty ? .hidden : .loaded(displays)
            loadedKey = key
        } catch {
            guard !Task.isCancelled else { return }
            AppLogger.network("⟐ source author works failed", error: SourceFailure.loggable(error),
                              context: ["source": source.bookSourceName, "author": author])
            state = .failed(error.localizedDescription)
            loadedKey = key
        }
    }

    func retry(key: String?, source: BookSource?, author: String, currentBook: OnlineBook,
               fetcher: any BookSourceFetching) async {
        loadedKey = nil
        await load(key: key, source: source, author: author, currentBook: currentBook, fetcher: fetcher)
    }

    private nonisolated static func normalized(_ value: String) -> String {
        SourceGenreMatching.normalized(value
            .replacingOccurrences(of: "作者：", with: "")
            .replacingOccurrences(of: "作者:", with: "")
            .replacingOccurrences(of: " 著", with: ""))
    }
}
