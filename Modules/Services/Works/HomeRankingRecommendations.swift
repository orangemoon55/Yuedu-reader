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
    typealias AuthorSearch = @MainActor (String, BookSource) async throws -> [OnlineBook]
    typealias GenreLoad = @MainActor (OnlineBook, BookSource) async throws -> [OnlineBook]
    nonisolated static let limit = 8

    private let searchAuthor: AuthorSearch
    private let loadGenre: GenreLoad

    init(searchAuthor: AuthorSearch? = nil, loadGenre: GenreLoad? = nil) {
        self.searchAuthor = searchAuthor ?? { query, source in
            guard !source.searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
            return try await BookSourceFetcher.shared.search(query: query, in: source, page: 1,
                                                             failureMode: .propagateTransportError)
        }
        self.loadGenre = loadGenre ?? { book, source in
            try await Self.sourceGenreBooks(for: book, source: source)
        }
    }

    nonisolated static func genreTags(_ raw: String) -> [String] {
        let ignored: Set<String> = ["", "连载", "連載", "连载中", "連載中", "完结", "完結", "小说", "小說", "漫画", "漫畫", "text", "manga", "comic", "audio"]
        var seen = Set<String>()
        return raw.components(separatedBy: CharacterSet(charactersIn: ",，、|/;；"))
            .map { normalized($0) }
            .filter { !ignored.contains($0) && seen.insert($0).inserted }
    }

    func recommendations(for current: OnlineBook, source: BookSource,
                         pool: [OnlineBook]) async throws -> HomeRankingRecommendationResult {
        try Task.checkCancellation()
        let authorPool = Self.filter(pool, current: current, source: source, author: true)
        if !authorPool.isEmpty { return .init(kind: .author, books: authorPool) }

        if let query = Self.authorQuery(current.author) {
            do {
                let searched = try await searchAuthor(query, source)
                try Task.checkCancellation()
                let exact = Self.filter(searched, current: current, source: source, author: true)
                if !exact.isEmpty { return .init(kind: .author, books: exact) }
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                AppLogger.network("home ranking author fallback failed", error: SourceFailure.loggable(error),
                                  context: ["source": source.bookSourceName])
            }
        }

        let genrePool = Self.filter(pool, current: current, source: source, author: false)
        if !genrePool.isEmpty { return .init(kind: .genre, books: genrePool) }

        let fetched = try await loadGenre(current, source)
        try Task.checkCancellation()
        let accepted = Self.filterCategory(fetched, current: current, source: source)
        return .init(kind: accepted.isEmpty ? .none : .genre, books: accepted)
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
            do {
                let books = try await BookSourceFetcher.shared.discoverBooks(from: item.raw, page: 1, in: source)
                try Task.checkCancellation()
                let filtered = Self.filterCategory(books, current: current, source: source)
                if !filtered.isEmpty { return filtered }
            } catch {
                if Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw CancellationError()
                }
                AppLogger.network("home ranking genre category unavailable", error: SourceFailure.loggable(error),
                                  context: ["source": source.bookSourceName, "category": item.title])
            }
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
        let unknown: Set<String> = ["", "作者", "未知", "未知作者", "佚名", "匿名", "无名氏", "無名氏", "不详", "不詳", "unknown", "unknownauthor", "anonymous", "n/a", "null", "-"]
        return unknown.contains(key) ? nil : value
    }

    nonisolated private static func tags(_ raw: String) -> Set<String> {
        Set(genreTags(raw))
    }

    nonisolated private static func medium(of book: OnlineBook, source: BookSource) -> OnlineBookContentKind {
        OnlineBookContentInference.explicitKind(runtimeVariables: book.runtimeVariables,
                                               urls: [book.bookUrl, book.tocUrl], metadataText: [book.kind])
            ?? OnlineBookContentInference.infer(sourceType: source.bookSourceType)
    }

    nonisolated private static func filterCategory(_ candidates: [OnlineBook], current: OnlineBook,
                                                   source: BookSource) -> [OnlineBook] {
        var seen = Set<String>()
        return candidates.filter { book in
            book.sourceId == source.id && !book.name.isEmpty && !book.bookUrl.isEmpty &&
            normalized(book.name) != normalized(current.name) && book.bookUrl != current.bookUrl &&
            medium(of: book, source: source) == medium(of: current, source: source)
        }
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
        return candidates.compactMap { book -> OnlineBook? in
            guard book.sourceId == source.id else { return nil }
            let title = normalized(book.name)
            let url = book.bookUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !url.isEmpty, title != currentTitle, url != currentURL,
                  medium(of: book, source: source) == medium(of: current, source: source) else { return nil }
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
