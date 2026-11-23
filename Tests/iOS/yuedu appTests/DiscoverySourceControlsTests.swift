import XCTest
@testable import yuedu_app

@MainActor
final class DiscoverySourceControlsTests: XCTestCase {
    func testFilterReloadPreservesOnlyReferencesStillInTheLiveCatalogue() throws {
        let name = "source-controls-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DiscoveryCategoryModel(defaults: defaults)
        let source = BookSource(bookSourceUrl: "https://a.test", bookSourceName: "A")
        model.prepare(configuration: "test", page: nil, sources: [source])
        let activation = try XCTUnwrap(model.activeSource)
        let first = try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "First", url: "/first")))
        let second = try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "Second", url: "/second")))
        let third = try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "Third", url: "/third")))
        model.reconcileSource(values: ["mode": "old"], items: [first, second], error: nil, activation: activation)
        model.select(model.catalog[1].reference, activation: activation)
        let selected = try XCTUnwrap(model.current)
        let old = model.list(for: selected, source: source)
        model.reconcileSource(values: ["mode": "new"], items: [second, third], error: nil, activation: activation)
        let updated = try XCTUnwrap(model.current)
        XCTAssertEqual(updated.reference, selected.reference)
        XCTAssertEqual(updated.filters, ["mode": "new"])
        XCTAssertFalse(old === model.list(for: updated, source: source))

        model.reconcileSource(values: [:], items: [third, first], error: nil, activation: activation)
        XCTAssertEqual(model.catalog.map(\.title), ["Third", "First"])
        XCTAssertEqual(model.current?.title, "Third")
        model.reconcileSource(values: [:], items: [], error: nil, activation: activation)
        XCTAssertNil(model.current)
        XCTAssertTrue(model.catalog.isEmpty)
    }
}
