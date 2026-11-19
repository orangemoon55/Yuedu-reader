import XCTest
@testable import yuedu_app

@MainActor
final class DiscoveryCategoryTests: XCTestCase {
    private func choice(_ index: Int, filters: [String: String] = [:]) -> DiscoveryCategoryChoice {
        .init(reference: .init(sourceURL: "https://discovery.test", title: "分類\(index)", url: "/list/\(index)"), filters: filters)
    }

    func testSlotsAreAlwaysExactlyFiveAndSwapRatherThanDuplicate() throws {
        var slots = DiscoveryCategorySlots([choice(1), choice(2), nil])
        XCTAssertEqual(slots.choices.count, 5)
        slots.set(choice(2), at: 0)
        XCTAssertEqual(slots.choices[0], choice(2))
        XCTAssertEqual(slots.choices[1], choice(1))
        slots.set(choice(1), at: -1)
        XCTAssertEqual(slots.choices[1], choice(1))
        let encoded = try JSONEncoder().encode(slots)
        XCTAssertEqual(try JSONDecoder().decode(DiscoveryCategorySlots.self, from: encoded), slots)
        XCTAssertEqual(DiscoveryCategorySlots((0..<10).map { choice($0) }).choices.count, 5)
    }

    func testSameURLDifferentFiltersKeepsIndependentIdentity() {
        let first = choice(1, filters: ["频道": "男频"])
        let second = choice(1, filters: ["频道": "女频"])
        XCTAssertNotEqual(first.id, second.id)
        let slots = DiscoveryCategorySlots.filling(from: [first, second], catalog: [first, choice(3)])
        XCTAssertEqual(slots.choices.compactMap { $0 }.count, 3)
    }

    func testChoicesPersistAndAreIsolatedPerHomeConfiguration() async throws {
        let name = "discovery-test-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DiscoveryCategoryModel(defaults: defaults)
        model.prepare(configuration: "A", page: nil, sources: [])
        model.choose(choice(1), at: 3)
        model.prepare(configuration: "B", page: nil, sources: [])
        XCTAssertTrue(model.slots.choices.allSatisfy { $0 == nil })
        model.choose(choice(2), at: 0)
        let reopened = DiscoveryCategoryModel(defaults: defaults)
        reopened.prepare(configuration: "A", page: nil, sources: [])
        XCTAssertEqual(reopened.slots.choices[3], choice(1))
        XCTAssertEqual(reopened.selection, 3)
    }

    func testSourceSessionsRestoreTheirRealSlotsAndRejectStaleReloads() throws {
        let name = "discovery-sources-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DiscoveryCategoryModel(defaults: defaults)
        var a = BookSource(bookSourceUrl: "https://a.fixture", bookSourceName: "A")
        var b = BookSource(bookSourceUrl: "https://b.fixture", bookSourceName: "B")
        a.enabled = true; a.enabledExplore = true; a.exploreUrl = "/explore"
        b.enabled = true; b.enabledExplore = true; b.exploreUrl = "/explore"
        func entries(_ prefix: String, _ count: Int) throws -> [DiscoverCardItem] {
            try (0..<count).map { i in
                try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "\(prefix)\(i)", url: "/category\(i)")))
            }
        }
        model.prepare(configuration: "test", page: nil, sources: [a, b])
        let initialA = try XCTUnwrap(model.activeSource)
        let aItems = try entries("A", 6)
        let bItems = try entries("B", 2)
        model.reconcileSource(sourceURL: a.bookSourceUrl, values: [:], items: aItems, error: nil, activation: initialA)
        XCTAssertEqual(model.slots.choices.compactMap { $0?.title }, ["A0", "A1", "A2", "A3", "A4"])
        model.select(2)
        let aChoice = try XCTUnwrap(model.current)
        let firstList = model.list(for: aChoice, source: a)

        model.switchSource(to: b, page: nil)
        XCTAssertNil(model.current, "Do not keep old shortcuts while the new source loads")
        let currentB = try XCTUnwrap(model.activeSource)
        model.reconcileSource(sourceURL: a.bookSourceUrl, values: [:], items: aItems, error: nil, activation: initialA)
        XCTAssertNil(model.current)
        model.reconcileSource(sourceURL: b.bookSourceUrl, values: [:], items: bItems, error: nil, activation: currentB)
        XCTAssertEqual(model.slots.choices.compactMap { $0?.title }, ["B0", "B1"])
        XCTAssertEqual(model.activeSource?.sourceURL, b.bookSourceUrl)

        model.switchSource(to: a, page: nil)
        XCTAssertEqual(model.current, aChoice)
        XCTAssertTrue(model.list(for: aChoice, source: a) === firstList)
        model.reconcileSource(sourceURL: a.bookSourceUrl, values: [:], items: [], error: nil, activation: initialA)
        XCTAssertEqual(model.current, aChoice, "A pre-switch result for A must not affect the second activation")
        let reopened = DiscoveryCategoryModel(defaults: defaults)
        reopened.prepare(configuration: "test", page: nil, sources: [b, a])
        XCTAssertEqual(reopened.activeSource?.sourceURL, a.bookSourceUrl)
        XCTAssertEqual(reopened.current, aChoice)
    }

    func testTypesComeFromModuleStoresWithoutImportedBookSources() throws {
        func module(_ id: String, _ entry: String) throws -> RuleModule {
            let object: [String: Any] = ["id": id, "title": id, "version": "1.0", "requiredVersion": "3.0.2",
                "hosts": ["example.com"], "modules": [["id": entry, "title": entry,
                "request": ["url": "https://example.com/books"], "list": ["items": "$.books[*]", "title": "$.title"],
                "store": [["layout": "row"]]]]]
            return try JSONDecoder().decode(RuleModule.self, from: JSONSerialization.data(withJSONObject: object))
        }
        let originals = try [module("openlibrary", "kids"), module("trends", "fiction"), module("bangumi", "comics")]
        let listings = ModuleStores.listings(in: originals)
        XCTAssertEqual(listings.map(\.id), ["trends/fiction", "bangumi/comics", "openlibrary/kids"])
        XCTAssertEqual(listings[0].route.moduleID, "trends")
        XCTAssertEqual(listings[2].route.entryID, "kids")
    }
}
