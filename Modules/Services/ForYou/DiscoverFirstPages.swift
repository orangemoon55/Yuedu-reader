import Foundation
import CryptoKit

/// The one place a book-source category's first page is fetched for a home (Discovery Phase
/// 7a-1): the home's category rows, its 分類卡片 and its 「最新」 rows all ask here.
///
/// - **One request at a time per source.** A source's rules share one JS runtime, and
///   `BookSourceSession` does not serialize discover fetches (`SectionLoadPolicy.serialPerSource`),
///   so two of a source's rows never fetch side by side.
/// - **One request per category in flight.** Two rows asking for the same category together
///   share the request.
/// - **Cookies primed once per source per sync**, before its first fetch, as the source's own
///   page primes once per load (`primeDiscoverCookiesIfNeeded` drops the site's token).
/// - **Every page is saved** to `ForYouCandidateStore`, which 作品詳情's versions read with no
///   request (7b-1).
/// - **One request per category in the home's life**, until its pull to refresh: a page saved
///   since then answers a later ask (Discovery Phase 7a-5). A page less than five minutes old answers after relaunch too; older pages
///   draw immediately while the request runs (`savedPage`). Pull-to-refresh bypasses freshness.
///
/// One per home: `SourceProviderRegistry.homeProviders` hands it to the providers it makes,
/// and calls `beginSync()` each time it makes them. The queue and the requests on their way
/// are the app's (`DiscoverRequestLanes.shared`), not the home's: 探索's home, a library's home
/// and a section form's preview can be open at once, and a source's JS runtime must still see
/// one discover fetch at a time.
@MainActor
final class DiscoverFirstPages {
    typealias PrimeCookies = @Sendable (BookSource) async -> Void

    private let pageLoader: SectionPageLoader
    private let primeCookies: PrimeCookies
    private let store: ForYouCandidateStore
    private let lanes: DiscoverRequestLanes
    private let now: @Sendable () -> Date
    private var primed: Set<String> = []
    /// Pages saved since then answer from the store: the home's making, or its last pull to refresh.
    private var answersSince: Date
    private var forcesNetwork = false
    nonisolated static let freshCacheSeconds: TimeInterval = 300

    init(
        pageLoader: SectionPageLoader = .live,
        primeCookies: @escaping PrimeCookies = { await BookSourceFetcher.shared.primeDiscoverCookies(in: $0) },
        store: ForYouCandidateStore = .shared,
        lanes: DiscoverRequestLanes? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.pageLoader = pageLoader
        self.primeCookies = primeCookies
        self.store = store
        self.lanes = lanes ?? .shared
        self.now = now
        answersSince = now()
    }

    /// Pull to refresh: every category is asked for again.
    func refresh() {
        answersSince = now()
        forcesNetwork = true
    }

    /// The providers were made again: each source primes its cookies again before its next fetch.
    func beginSync() {
        primed.removeAll()
    }

    /// The category's first page, without the books it repeats: the page saved since
    /// `answersSince`, else a request. Joins a request for the same category already on its
    /// way; otherwise queues behind the source's other fetches. Failures are logged by
    /// `SectionPageLoader` and thrown to every asker; a failure saves nothing, so the next ask
    /// fetches again.
    func firstPage(of category: ExploreCategoryReference, in source: BookSource,
                   filterValues: [String: String] = [:]) -> Task<[OnlineBook], Error> {
        let since = answersSince, forced = forcesNetwork, store = store, now = now
        return Task { @MainActor in
            let context = try await Self.cacheContext(for: source, filters: filterValues)
            let key = DiscoverRequestLanes.Key(sourceURL: source.bookSourceUrl, categoryURL: category.url, contextID: context)
            if let running = lanes.running(key) { return try await running.value }
            if let saved = await store.read(sourceURL: key.sourceURL, categoryURL: key.categoryURL,
                                             sourceID: source.id, contextID: context),
               saved.fetchedAt >= since || (!forced && now().timeIntervalSince(saved.fetchedAt) >= 0 &&
                                            now().timeIntervalSince(saved.fetchedAt) < Self.freshCacheSeconds) {
                return saved.books
            }
            return try await self.fetch(category, key, in: source).value
        }
    }

    /// Read-only disk/memory first paint. Never waits for a source's JS request lane.
    func savedPage(of category: ExploreCategoryReference, in source: BookSource,
                   filterValues: [String: String] = [:]) async -> [OnlineBook]? {
        do {
            let context = try await Self.cacheContext(for: source, filters: filterValues)
            return await store.read(sourceURL: source.bookSourceUrl, categoryURL: category.url,
                                    sourceID: source.id, contextID: context)?.books
        } catch {
            AppLogger.cache("home cache identity unavailable", error: error, context: ["source": source.bookSourceName])
            return nil
        }
    }

    /// A digest of request-affecting definition and per-section filters, prepared off main.
    /// Raw headers/scripts are never used as file names or printed in diagnostics.
    nonisolated static func cacheContext(for source: BookSource, filters: [String: String]) async throws -> String? {
        struct Input: Encodable {
            let revision: Int64
            let type: Int
            let explore: String
            let header: String
            let library: String
            let loginCheck: String
            let rule: ExploreRule
            let filters: [String: String]
        }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let rule = try encoder.encode(source.ruleExplore)
        let emptyRule = try encoder.encode(ExploreRule())
        // Shipped context-free caches remain usable for definition-free legacy consumers.
        if source.lastUpdateTime == 0, source.exploreUrl.isEmpty, source.header.isEmpty,
           source.jsLib.isEmpty, source.loginCheckJs.isEmpty, source.bookSourceType == 0,
           filters.isEmpty, rule == emptyRule { return nil }
        let input = Input(revision: source.lastUpdateTime, type: source.bookSourceType,
                          explore: source.exploreUrl, header: source.header, library: source.jsLib,
                          loginCheck: source.loginCheckJs, rule: source.ruleExplore, filters: filters)
        let start = SourcePerfTrace.now
        let data = try encoder.encode(input)
        let key = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        SourcePerfTrace.record("home.cache.identity", "bytes=\(data.count) main=\(Thread.isMainThread)", since: start)
        return key
    }

    private func fetch(_ category: ExploreCategoryReference, _ key: DiscoverRequestLanes.Key,
                       in source: BookSource) -> Task<[OnlineBook], Error> {
        // Another ask may have started it while this one read the store.
        if let running = lanes.running(key) { return running }
        let primes = primed.insert(key.sourceURL).inserted
        let pageLoader = pageLoader, primeCookies = primeCookies, store = store, now = now
        return lanes.enqueue(key) {
            if primes { await primeCookies(source) }
            guard let item = category.cardItem else { return [] }
            let section = DiscoverShowcaseSection(item: item, coverBaseURL: source.bookSourceUrl,
                                                  coverHeaders: await source.resolvedHeaders())
            let books = try await pageLoader.books(page: 1, of: section, in: source, after: []).map(\.book)
            await store.write(ForYouCandidates(sourceURL: key.sourceURL, categoryURL: key.categoryURL,
                                               fetchedAt: now(), books: books, contextID: key.contextID))
            return books
        }
    }
}

/// The app's discover requests by source: one at a time per source, and one per category on
/// its way, whichever home asked.
@MainActor
final class DiscoverRequestLanes {
    static let shared = DiscoverRequestLanes()

    struct Key: Hashable {
        let sourceURL: String
        let categoryURL: String
        var contextID: String? = nil
    }

    private var inFlight: [Key: (id: UUID, task: Task<[OnlineBook], Error>)] = [:]
    /// The last request queued for each source; the next one starts after it.
    private var tails: [String: Task<[OnlineBook], Error>] = [:]

    /// The request for `key` on its way, to join.
    func running(_ key: Key) -> Task<[OnlineBook], Error>? {
        inFlight[key]?.task
    }

    /// Runs `work` after the source's requests queued before it.
    func enqueue(_ key: Key, _ work: @escaping @MainActor () async throws -> [OnlineBook]) -> Task<[OnlineBook], Error> {
        let id = UUID()
        let previous = tails[key.sourceURL]
        // On the main actor, so the request is forgotten before anyone waiting on it resumes:
        // an ask after a failure fetches again.
        let task = Task<[OnlineBook], Error> { @MainActor in
            defer { if inFlight[key]?.id == id { inFlight[key] = nil } }
            _ = await previous?.result
            return try await work()
        }
        inFlight[key] = (id, task)
        tails[key.sourceURL] = task
        return task
    }
}
