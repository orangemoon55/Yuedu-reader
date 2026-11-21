import Foundation
import Testing
import UIKit
@testable import yuedu_app

@MainActor
@Suite("Source picker management", .serialized)
struct SourcePickerManagementTests {
    private func source(_ index: Int) -> BookSource {
        BookSource(bookSourceUrl: "https://source-\(index).fixture.invalid",
                   bookSourceName: "来源 \(index)")
    }

    @Test("Edge jump targets follow visible result order without mutating source order")
    func edgeTargets() {
        let a = source(1), b = source(2), c = source(3)
        let rows = [b, a, c]
        #expect(SourcePickerActions.edgeID(in: rows, toTop: true) == b.id)
        #expect(SourcePickerActions.edgeID(in: rows, toTop: false) == c.id)
        #expect(SourcePickerActions.edgeID(in: [a], toTop: true) == a.id)
        #expect(SourcePickerActions.edgeID(in: [a], toTop: false) == a.id)
        #expect(SourcePickerActions.edgeID(in: [], toTop: false) == nil)
        #expect(rows.map(\.id) == [b.id, a.id, c.id])
    }

    @Test("Swipe deletion calls real source storage, persists and removes its pin")
    func persistedDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Readcc33-Delete-\(UUID())")
        let suite = "Readcc33-Delete-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = BookSourceStore(directory: directory)
        defer {
            store.waitForQueuedWrites()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let a = source(1), b = source(2), c = source(3)
        store.replaceSourcesFromSync([a, b, c])
        let pins = DiscoverySourcePins(defaults: defaults)
        pins.togglePin(b.id, availableIDs: [a.id, b.id, c.id])
        pins.togglePin(c.id, availableIDs: [a.id, b.id, c.id])
        defaults.set(b.bookSourceUrl, forKey: SourceDiscoverySelection.preferenceKey)
        defaults.set(b.bookSourceUrl, forKey: "yd_discovery_five_categories.v1.source.search")
        defaults.set(a.bookSourceUrl, forKey: "unrelated.preference")
        let revision = store.mutationRevision
        #expect(SourcePickerActions.delete(sourceID: b.id, store: store, pins: pins, defaults: defaults))
        #expect(store.source(id: b.id) == nil)
        #expect(store.sources.map(\.id) == [a.id, c.id])
        #expect(store.sources.map(\.lastUpdateTime) == [a.lastUpdateTime, c.lastUpdateTime])
        #expect(pins.pinnedIDs == [c.id])
        #expect(defaults.string(forKey: SourceDiscoverySelection.preferenceKey) == nil)
        #expect(defaults.string(forKey: "yd_discovery_five_categories.v1.source.search") == nil)
        #expect(defaults.string(forKey: "unrelated.preference") == a.bookSourceUrl)
        #expect(!store.replaceSourcesFromSync([a, b, c], expectedMutationRevision: revision))
        store.waitForQueuedWrites()
        let reopened = BookSourceStore(directory: directory)
        #expect(reopened.sources.map(\.id) == [a.id, c.id])
        #expect(DiscoverySourcePins(defaults: defaults).pinnedIDs == [c.id])
    }

    @Test("Deleting the active and final source safely falls back without admitting old callbacks")
    func activeAndFinalDeletion() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Readcc33-Active-\(UUID())")
        let suite = "Readcc33-Active-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        let store = BookSourceStore(directory: directory)
        defer {
            store.waitForQueuedWrites()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        let a = source(1), b = source(2)
        store.replaceSourcesFromSync([a, b])
        let pins = DiscoverySourcePins(defaults: defaults)
        let model = DiscoveryCategoryModel(defaults: defaults)
        model.prepare(configuration: "search", page: nil, sources: store.sources)
        let old = try #require(model.activeSource)
        #expect(old.sourceID == a.id)
        #expect(SourcePickerActions.delete(sourceID: a.id, store: store, pins: pins, defaults: defaults))
        model.prepare(configuration: "search", page: nil, sources: store.sources)
        #expect(model.activeSource?.sourceID == b.id)
        model.reconcileSource(values: [:], items: [], error: "stale", activation: old)
        #expect(model.catalogError == nil)
        #expect(SourcePickerActions.delete(sourceID: b.id, store: store, pins: pins, defaults: defaults))
        model.prepare(configuration: "search", page: nil, sources: store.sources)
        #expect(model.activeSource == nil && model.catalog.isEmpty && model.current == nil)
        #expect(!SourcePickerActions.delete(sourceID: b.id, store: store, pins: pins, defaults: defaults))
        #expect(store.sources.isEmpty)
    }

    @Test("Bottom state uses the actual visible row edge, not List prefetch")
    func bottomVisibility() {
        let viewport = CGRect(x: 0, y: 100, width: 390, height: 640)
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: nil, viewport: viewport, verticalColumns: false))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: 0, y: 800, width: 390, height: 44),
                                                   viewport: viewport, verticalColumns: false))
        #expect(ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: 0, y: 690, width: 390, height: 44),
                                                  viewport: viewport, verticalColumns: false))
        #expect(!ReaderTOCEdgeVisibility.isAtLatest(row: CGRect(x: 0, y: 710, width: 390, height: 44),
                                                   viewport: viewport, verticalColumns: false))
    }
}
