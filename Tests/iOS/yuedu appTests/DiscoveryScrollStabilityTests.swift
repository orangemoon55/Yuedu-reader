import XCTest
@testable import yuedu_app

private actor DiscoveryPagingProbe {
    private(set) var requests: [Int] = []
    private var failingPages: Set<Int> = []
    private var heldPage: Int?
    private var held: CheckedContinuation<Void, Never>?
    private var entered: CheckedContinuation<Void, Never>?

    func fail(_ page: Int) { failingPages.insert(page) }
    func hold(_ page: Int) { heldPage = page }
    func waitUntilHeld() async {
        if held != nil { return }
        await withCheckedContinuation { entered = $0 }
    }
    func release() { held?.resume(); held = nil; heldPage = nil }

    func fetch(_ page: Int, source: BookSource) async throws -> [OnlineBook] {
        requests.append(page)
        if heldPage == page {
            await withCheckedContinuation { continuation in
                held = continuation
                entered?.resume(); entered = nil
            }
        }
        if failingPages.remove(page) != nil { throw URLError(.notConnectedToInternet) }
        return [OnlineBook(name: "page-\(page)", author: "author", intro: "", coverUrl: "",
                           bookUrl: "https://scroll.fixture/book/\(page)", tocUrl: "", wordCount: "",
                           lastChapter: "", kind: "", sourceId: source.id, sourceName: "fixture")]
    }
}

@MainActor
final class DiscoveryScrollStabilityTests: XCTestCase {
    private func choice(_ source: BookSource, filters: [String: String] = [:]) -> DiscoveryCategoryChoice {
        .init(reference: .init(sourceURL: source.bookSourceUrl, title: "Books", url: "/books"), filters: filters)
    }

    private func model(_ probe: DiscoveryPagingProbe) -> (DiscoveryBookListModel, URL) {
        let source = BookSource(bookSourceUrl: "https://scroll.fixture", bookSourceName: "fixture")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("discovery-scroll-\(UUID())")
        let loader = SectionPageLoader { _, page, source in try await probe.fetch(page, source: source) }
        let first = DiscoverFirstPages(pageLoader: loader, primeCookies: { _ in },
                                      store: ForYouCandidateStore(directory: directory), lanes: DiscoverRequestLanes())
        return (DiscoveryBookListModel(choice: choice(source), source: source, firstPages: first, pageLoader: loader), directory)
    }

    func testIdenticalReconciliationPreservesEverySameSourceListInstance() throws {
        let suite = "discovery-scroll-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let category = DiscoveryCategoryModel(defaults: defaults)
        var source = BookSource(bookSourceUrl: "https://scroll.fixture", bookSourceName: "fixture")
        let selected = choice(source)
        let second = DiscoveryCategoryChoice(reference: .init(sourceURL: source.bookSourceUrl, title: "Other", url: "/other"), filters: [:])
        category.choose(selected, at: 0)
        category.choose(second, at: 1)
        let firstList = category.list(for: selected, source: source)
        let secondList = category.list(for: second, source: source)
        let items = try [selected, second].map {
            try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: $0.reference.title, url: $0.reference.url)))
        }
        for _ in 0..<4 {
            category.reconcileSource(sourceURL: source.bookSourceUrl, values: [:], items: items, error: nil)
            XCTAssertTrue(firstList === category.list(for: selected, source: source), "Same choice must not reset to page 1")
            XCTAssertTrue(secondList === category.list(for: second, source: source))
        }
        source.lastUpdateTime += 1
        XCTAssertFalse(firstList === category.list(for: selected, source: source), "A changed source revision still invalidates")
    }

    func testFilterRoundTripReusesOriginalListWithoutMixingFeeds() throws {
        let suite = "discovery-filter-scroll-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let category = DiscoveryCategoryModel(defaults: defaults)
        let source = BookSource(bookSourceUrl: "https://scroll.fixture", bookSourceName: "fixture")
        let original = choice(source, filters: ["mode": "old"])
        category.choose(original, at: 0)
        let originalList = category.list(for: original, source: source)
        let item = try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "Books", url: "/books")))
        category.reconcileSource(sourceURL: source.bookSourceUrl, values: ["mode": "new"], items: [item], error: nil)
        let changed = try XCTUnwrap(category.slots.choices[0])
        XCTAssertNotEqual(changed.id, original.id)
        XCTAssertFalse(originalList === category.list(for: changed, source: source))
        category.reconcileSource(sourceURL: source.bookSourceUrl, values: original.filters, items: [item], error: nil)
        XCTAssertTrue(originalList === category.list(for: try XCTUnwrap(category.slots.choices[0]), source: source))
    }

    func testRepeatedTailAppearanceDoesNotRetryFailureButExplicitRetryWorks() async throws {
        let probe = DiscoveryPagingProbe()
        let (list, directory) = model(probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        await list.loadFirst()
        let tail = try XCTUnwrap(list.books.last?.id)
        await probe.fail(2)
        await list.loadMoreIfNeeded(after: tail)
        for _ in 0..<8 { await list.loadMoreIfNeeded(after: tail) }
        let failedRequests = await probe.requests
        XCTAssertEqual(failedRequests, [1, 2])
        XCTAssertNotNil(list.error)
        await list.retry()
        let retried = await probe.requests
        XCTAssertEqual(retried, [1, 2, 2])
        XCTAssertEqual(list.books.map(\.book.name), ["page-1", "page-2"])
        await list.loadMoreIfNeeded(after: tail)
        let staleTailRequests = await probe.requests
        XCTAssertEqual(staleTailRequests, retried, "A formerly last row is not a paging sentinel")
        await list.loadMoreIfNeeded(after: try XCTUnwrap(list.books.last?.id))
        let next = await probe.requests
        XCTAssertEqual(next, [1, 2, 2, 3])
    }

    func testRefreshSupersedesInFlightPageWithoutLateAppend() async throws {
        let probe = DiscoveryPagingProbe()
        let (list, directory) = model(probe)
        defer { try? FileManager.default.removeItem(at: directory) }
        await list.loadFirst()
        let tail = try XCTUnwrap(list.books.last?.id)
        await probe.hold(2)
        let paging = Task { await list.loadMoreIfNeeded(after: tail) }
        await probe.waitUntilHeld()
        await list.loadFirst(force: true)
        await probe.release()
        await paging.value
        XCTAssertEqual(list.books.map(\.book.name), ["page-1"])
        XCTAssertFalse(list.isLoading)
        await list.loadMoreIfNeeded(after: try XCTUnwrap(list.books.last?.id))
        let requests = await probe.requests
        XCTAssertEqual(requests, [1, 2, 1, 2])
        XCTAssertEqual(list.books.map(\.book.name), ["page-1", "page-2"])
    }
}
