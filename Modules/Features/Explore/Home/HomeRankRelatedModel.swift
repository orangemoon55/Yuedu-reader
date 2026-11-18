import Combine
import Foundation

@MainActor
final class HomeRankRelatedModel: ObservableObject {
    typealias SourceLookup = @MainActor (HomeCardContent) async -> BookSource?
    @Published private(set) var bookID: SourceItemKey?
    @Published private(set) var cards: [HomeCardContent] = []
    @Published private(set) var kind: HomeRankingRecommendationResult.Kind = .none
    @Published private(set) var loading = false
    @Published private(set) var error: String?
    private var generation = UUID()
    private var poolIDs: [SourceItemKey] = []
    private var cache: [SourceItemKey: (HomeRankingRecommendationResult.Kind, [HomeCardContent])] = [:]
    private let service: HomeRankingRecommendationService
    private let sourceLookup: SourceLookup

    init(service: HomeRankingRecommendationService = HomeRankingRecommendationService(),
         sourceLookup: @escaping SourceLookup = { card in
             guard case .onlineBook(let frozen) = card.opening else { return nil }
             return await HomeRankSourceLookup.source(url: card.id.instance.id, id: frozen.book.sourceId)
         }) {
        self.service = service
        self.sourceLookup = sourceLookup
    }

    func load(for card: HomeCardContent, pool: [HomeCardContent], force: Bool = false) async {
        let token = UUID()
        generation = token
        let ids = pool.map(\.id)
        if ids != poolIDs { cache.removeAll(keepingCapacity: true); poolIDs = ids }
        bookID = card.id
        cards = []
        kind = .none
        error = nil
        if !force, let saved = cache[card.id] {
            kind = saved.0; cards = saved.1; loading = false
            return
        }
        loading = true
        defer { if generation == token { loading = false } }
        guard case .onlineBook(let frozen) = card.opening,
              let source = await sourceLookup(card), source.enabled,
              !Task.isCancelled, generation == token else { return }
        let books = pool.compactMap { value -> OnlineBook? in
            guard case .onlineBook(let book) = value.opening else { return nil }
            return book.book
        }
        do {
            let result = try await service.recommendations(for: frozen.book, source: source, pool: books)
            let entries = try await CollectionEntry.preparedRankBooks(result.books, source: source)
            try Task.checkCancellation()
            guard generation == token else { return }
            cards = entries.compactMap { HomeCardContent($0, status: { _ in nil }, shelfBooks: [:]) }
            kind = cards.isEmpty ? .none : result.kind
            // Cache is bounded to this visible section, not another persisted data store.
            if cache.count >= HomeRow.limit { cache.removeAll(keepingCapacity: true) }
            cache[card.id] = (kind, cards)
        } catch {
            guard !Task.isCancelled, generation == token, !(error is CancellationError) else { return }
            self.error = error.localizedDescription
            AppLogger.network("home ranking related cards failed", error: SourceFailure.loggable(error),
                              context: ["source": source.bookSourceName])
        }
    }
}
