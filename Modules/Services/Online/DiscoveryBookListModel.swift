import Combine
import Foundation

/// Each real category/filter identity owns its own list. Switching categories never lets an
/// older response replace the visible one and returning reuses already-loaded pages.
@MainActor
final class DiscoveryBookListModel: ObservableObject {
    let choice: DiscoveryCategoryChoice
    let source: BookSource
    @Published private(set) var books: [DiscoverBookDisplay] = []
    @Published private(set) var headers: [String: String] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var hasMore = true
    @Published private(set) var loaded = false

    private let firstPages: DiscoverFirstPages
    private let pageLoader: SectionPageLoader
    private var nextPage = 2
    private var generation = 0
    /// Appearance is not a user request: lazy rows may appear repeatedly during layout.
    /// Try automatic paging once per tail; errors require the existing explicit retry.
    private var automaticallyRequestedTail: UUID?

    init(choice: DiscoveryCategoryChoice, source: BookSource,
         firstPages: DiscoverFirstPages? = nil, pageLoader: SectionPageLoader = .live) {
        self.choice = choice
        self.source = source
        self.pageLoader = pageLoader
        self.firstPages = firstPages ?? DiscoverFirstPages(pageLoader: pageLoader)
    }

    var section: DiscoverShowcaseSection? {
        choice.reference.cardItem.map {
            DiscoverShowcaseSection(item: $0, coverBaseURL: source.bookSourceUrl, coverHeaders: headers)
        }
    }

    func loadFirst(force: Bool = false) async {
        guard force || (!loaded && !isLoading) else { return }
        generation += 1
        let request = generation
        isLoading = true
        error = nil
        defer { if generation == request { isLoading = false } }
        if force { firstPages.refresh() }
        if books.isEmpty, let cached = await firstPages.savedPage(of: choice.reference, in: source,
                                                                 filterValues: choice.filters) {
            let displays = await DiscoverViewModel.makeDisplays(cached, source: source)
            guard !Task.isCancelled, request == generation else { return }
            books = displays
        }
        do {
            let fetched = try await firstPages.firstPage(of: choice.reference, in: source, filterValues: choice.filters).value
            let displays = await DiscoverViewModel.makeDisplays(fetched, source: source)
            let requestHeaders = await source.resolvedHeaders()
            try Task.checkCancellation()
            guard request == generation else { return }
            books = displays
            headers = requestHeaders
            nextPage = 2
            automaticallyRequestedTail = nil
            hasMore = !displays.isEmpty
            loaded = true
        } catch {
            guard !Task.isCancelled, request == generation else { return }
            self.error = SourceFailure.loggable(error).localizedDescription
            // Keep cached books on network failure. Retrying must still request page 1.
        }
    }

    /// Only the actual last row may prefetch. A recycled appearance (or a failure)
    /// cannot start the same automatic request again; the button/retry still can.
    func loadMoreIfNeeded(after bookID: UUID) async {
        guard loaded, hasMore, !isLoading, error == nil,
              books.last?.id == bookID, automaticallyRequestedTail != bookID else { return }
        automaticallyRequestedTail = bookID
        defer {
            // Leaving the screen cancels a row task, not the reader's right to retry
            // when they reach the same tail again.
            if Task.isCancelled, automaticallyRequestedTail == bookID {
                automaticallyRequestedTail = nil
            }
        }
        await loadMore()
    }

    func loadMore() async {
        guard loaded, hasMore, !isLoading, let section else { return }
        let request = generation
        let page = nextPage
        isLoading = true
        error = nil
        defer { if request == generation { isLoading = false } }
        do {
            let more = try await pageLoader.books(page: page, of: section, in: source, after: books.map(\.book))
            try Task.checkCancellation()
            guard request == generation else { return }
            books.append(contentsOf: more)
            hasMore = !more.isEmpty
            nextPage = page + 1
        } catch {
            guard !Task.isCancelled, request == generation else { return }
            self.error = SourceFailure.loggable(error).localizedDescription
        }
    }

    func retry() async {
        if loaded { await loadMore() } else { await loadFirst(force: true) }
    }
}
