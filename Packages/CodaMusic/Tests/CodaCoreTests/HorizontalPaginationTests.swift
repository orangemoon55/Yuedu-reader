import Foundation
import Testing
@testable import CodaCore

@Suite("Shared horizontal pagination")
@MainActor
struct HorizontalPaginationTests {
    private struct Item: Identifiable { let id: Int }
    private func items(_ ids: [Int]) -> [Item] { ids.map { Item(id: $0) } }

    @Test func finiteWindowRevealsEveryItemAndStops() {
        var window = HorizontalPageWindow(pageSize: 12)
        #expect(window.visibleCount(total: 31) == 12)
        window.advance(total: 31)
        #expect(window.visibleCount(total: 31) == 24)
        window.advance(total: 31)
        #expect(window.visibleCount(total: 31) == 31)
        window.advance(total: 31)
        #expect(window.visibleCount(total: 31) == 31)
        #expect(window.visibleCount(total: 0) == 0)
    }

    @Test func remotePagesDeduplicateAndUseRawOffsets() async {
        let source = HorizontalPageSource<Item>(pageSize: 3)
        source.replace(items([1, 2, 3]), hasMore: true)
        await source.loadMore { limit, offset in
            #expect(limit == 3)
            #expect(offset == 3)
            return .init(items: items([3, 4, 5]), hasMore: true)
        }
        #expect(source.items.map(\.id) == [1, 2, 3, 4, 5])
        #expect(source.offset == 6)
        await source.loadMore { _, offset in
            #expect(offset == 6)
            return .init(items: items([4, 5]), hasMore: true)
        }
        #expect(!source.hasMore)
        #expect(source.items.count == 5)
    }

    @Test func repeatedBoundaryCannotStartConcurrentRequests() async {
        let source = HorizontalPageSource<Item>(pageSize: 2)
        source.replace(items([1, 2]), hasMore: true)
        var pending: CheckedContinuation<HorizontalRemotePage<Item>, Error>?
        let request = Task {
            await source.loadMore { _, _ in
                try await withCheckedThrowingContinuation { pending = $0 }
            }
        }
        while pending == nil { await Task.yield() }
        #expect(source.isLoading)
        await source.loadMore { _, _ in
            Issue.record("A second page request started while the first was pending")
            return .init(items: [], hasMore: false)
        }
        pending?.resume(returning: .init(items: items([3]), hasMore: false))
        await request.value
        #expect(source.items.map(\.id) == [1, 2, 3])
        #expect(!source.isLoading)
    }

    @Test func refreshInvalidatesOldPage() async {
        let source = HorizontalPageSource<Item>(pageSize: 2)
        source.replace(items([1, 2]), hasMore: true)
        var pending: CheckedContinuation<HorizontalRemotePage<Item>, Error>?
        let request = Task {
            await source.loadMore { _, _ in
                try await withCheckedThrowingContinuation { pending = $0 }
            }
        }
        while pending == nil { await Task.yield() }
        source.replace(items([10, 11]), hasMore: true)
        pending?.resume(returning: .init(items: items([3]), hasMore: false))
        await request.value
        #expect(source.items.map(\.id) == [10, 11])
        #expect(source.offset == 2)
        #expect(source.hasMore)
        #expect(!source.isLoading)
    }

    @Test func failedPageCanRetryWithoutDiscardingExistingItems() async {
        let source = HorizontalPageSource<Item>(pageSize: 2)
        source.replace(items([1, 2]), hasMore: true)
        await source.loadMore { _, _ in throw URLError(.notConnectedToInternet) }
        #expect(source.error != nil)
        #expect(source.items.map(\.id) == [1, 2])
        #expect(source.offset == 2)
        await source.loadMore { _, offset in
            #expect(offset == 2)
            return .init(items: items([3]), hasMore: false)
        }
        #expect(source.error == nil)
        #expect(!source.isLoading)
        #expect(!source.hasMore)
        #expect(source.items.map(\.id) == [1, 2, 3])
    }
}
