import XCTest
@testable import yuedu_app

@MainActor
final class DiscoverySourceControlsTests: XCTestCase {
    private func choice(_ title: String, source: String = "https://a.test", url: String = "/old") -> DiscoveryCategoryChoice {
        .init(reference: .init(sourceURL: source, title: title, url: url), filters: ["mode": "old"])
    }

    func testFilterChangesRekeyEverySameSourceSlotAndKeepOtherSourceCache() throws {
        let name = "source-controls-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DiscoveryCategoryModel(defaults: defaults)
        let first = choice("First")
        let second = choice("Second", url: "/second")
        let other = choice("Other", source: "https://b.test")
        model.choose(first, at: 0)
        model.choose(second, at: 1)
        model.choose(other, at: 2)
        var sourceA = BookSource(); sourceA.bookSourceUrl = "https://a.test"
        var sourceB = BookSource(); sourceB.bookSourceUrl = "https://b.test"
        let oldA = model.list(for: first, source: sourceA)
        let oldB = model.list(for: other, source: sourceB)
        model.applyFilters(values: ["mode": "new"], sourceURL: sourceA.bookSourceUrl)
        let updated = try XCTUnwrap(model.slots.choices[0])
        XCTAssertNotEqual(updated.id, first.id)
        XCTAssertEqual(updated.reference, first.reference)
        XCTAssertEqual(model.slots.choices[1]?.filters, ["mode": "new"])
        XCTAssertEqual(model.slots.choices[2], other)
        XCTAssertFalse(oldA === model.list(for: updated, source: sourceA))
        XCTAssertTrue(oldB === model.list(for: other, source: sourceB))
    }

    func testReloadResolvesOnlyRealSameTitleOrMarksOriginalInvalid() throws {
        let name = "source-reconcile-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DiscoveryCategoryModel(defaults: defaults)
        let first = choice("First")
        let missing = choice("Missing", url: "/missing")
        model.choose(first, at: 0)
        model.choose(missing, at: 1)
        let item = try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "First", url: "/real-new")))
        model.reconcileSource(sourceURL: "https://a.test", values: ["mode": "new"], items: [item], error: nil)
        XCTAssertEqual(model.slots.choices[0]?.reference.url, "/real-new")
        XCTAssertEqual(model.slots.choices[0]?.reference.title, "First")
        XCTAssertEqual(model.slots.choices[1]?.reference, missing.reference)
        XCTAssertTrue(model.invalidReferences.contains(missing.reference))
        XCTAssertFalse(model.invalidReferences.contains(try XCTUnwrap(model.slots.choices[0]).reference))
    }
}
