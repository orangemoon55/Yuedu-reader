import Foundation

struct HomeRankingRecommendationResult: Sendable {
    enum Kind: Equatable, Sendable { case author, genre, none }
    let kind: Kind
    let books: [OnlineBook]
}

/// Recommendation policy for a single ranking snapshot. It never invents a genre:
/// it uses the source's own `kind` labels and same-source ranking/search results.
@MainActor
struct HomeRankingRecommendationService {
    static let limit = 8

    func recommendations(for current: OnlineBook, source: BookSource,
                         pool: [OnlineBook]) async throws -> HomeRankingRecommendationResult {
        try Task.checkCancellation()
        let authorPool = Self.filter(pool, current: current, source: source, author: true)
        if !authorPool.isEmpty { return .init(kind: .author, books: authorPool) }

        if let query = Self.authorQuery(current.author) {
            do {
                let searched = try await BookSourceFetcher.shared.search(
                    query: query, in: source, page: 1, failureMode: .emptyResult)
                try Task.checkCancellation()
                let exact = Self.filter(searched, current: current, source: source, author: true)
                if !exact.isEmpty { return .init(kind: .author, books: exact) }
            } catch is CancellationError { throw CancellationError() }
            catch { AppLogger.network("home ranking author fallback failed", error: SourceFailure.loggable(error), context: ["source": source.bookSourceName]) }
        }

        let genrePool = Self.filter(pool, current: current, source: source, author: false)
        if !genrePool.isEmpty { return .init(kind: .genre, books: genrePool) }

        let fetched = try await Self.sourceGenreBooks(for: current, source: source)
        return .init(kind: fetched.isEmpty ? .none : .genre, books: fetched)
    }

    private nonisolated static func sourceGenreBooks(for current: OnlineBook,
                                                     source: BookSource) async throws -> [OnlineBook] {
        let tags = Self.genreTags(current.kind)
        guard !tags.isEmpty else { return [] }
        await BookSourceFetcher.shared.primeDiscoverCookies(in: source)
        let items = try await BookSourceFetcher.shared.discoverItems(page: 1, in: source)
            .compactMap(DiscoverViewModel.mapItem)
            .filter(\.isFetchable)
        let matches = SourceGenreMatching.matchedCategories(for: tags, among: items)
        for item in matches.prefix(3) {
            try Task.checkCancellation()
            let books = try await BookSourceFetcher.shared.discoverBooks(from: item.raw, page: 1, in: source)
            let filtered = Self.filterCategory(books, current: current, source: source)
            if !filtered.isEmpty { return filtered }
        }
        return []
    }

    nonisolated static func normalized(_ raw: String) -> String {
        raw.folding(options: [.caseInsensitive, .widthInsensitive], locale: nil)
            .components(separatedBy: .whitespacesAndNewlines).joined()
            .lowercased()
    }

    nonisolated static func authorQuery(_ raw: String) -> String? {
        let value = raw.replacingOccurrences(of: "^作者\\s*[:：]\\s*", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s+著$", with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let key = normalized(value)
        let unknown: Set<String> = ["", "作者", "未知", "未知作者", "佚名", "匿名", "unknown", "anonymous", "n/a", "null", "-"]
        return unknown.contains(key) ? nil : value
    }

    nonisolated static func tags(_ raw: String) -> Set<String> {
        let ignored: Set<String> = ["", "连载", "連載", "连载中", "連載中", "完结", "完結", "小说", "小說", "漫画", "漫畫", "text", "manga", "comic", "audio"]
        return Set(raw.components(separatedBy: CharacterSet(charactersIn: ",，、|/;；"))
            .map { normalized($0) }.filter { !ignored.contains($0) })
    }

    nonisolated private static func filterCategory(_ candidates: [OnlineBook], current: OnlineBook,
                                                   source: BookSource) -> [OnlineBook] {
        var seen = Set<String>()
        return candidates.filter { $0.sourceId == source.id && normalized($0.name) != normalized(current.name) }
            .filter { seen.insert(normalized($0.name)).inserted }
            .prefix(limit).map { $0 }
    }

    nonisolated private static func filter(_ candidates: [OnlineBook], current: OnlineBook,
                                           source: BookSource, author: Bool) -> [OnlineBook] {
        let currentTitle = normalized(current.name)
        let currentURL = current.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let authorKey = authorQuery(current.author).map(normalized)
        let currentTags = tags(current.kind)
        var titles = Set<String>()
        var urls = Set<String>()
        return candidates.compactMap { book in
            guard book.sourceId == source.id else { return nil }
            let title = normalized(book.name)
            let url = book.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, title != currentTitle, url != currentURL else { return nil }
            if author {
                guard let authorKey, authorQuery(book.author).map(normalized) == authorKey else { return nil }
            } else {
                guard !currentTags.isEmpty, !currentTags.isDisjoint(with: tags(book.kind)) else { return nil }
            }
            guard titles.insert(title).inserted, urls.insert(url).inserted else { return nil }
            return book
        }.prefix(limit).map { $0 }
    }
}
