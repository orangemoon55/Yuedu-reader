import XCTest
@testable import yuedu_app

@MainActor
final class DiscoveryCategoryTests: XCTestCase {
    func testSevenRealCategoriesRestoreByReferenceAndRejectStaleReloads() throws {
        let name = "discovery-sources-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let model = DiscoveryCategoryModel(defaults: defaults)
        var a = BookSource(bookSourceUrl: "https://a.fixture", bookSourceName: "A")
        var b = BookSource(bookSourceUrl: "https://b.fixture", bookSourceName: "B")
        a.enabled = true; a.enabledExplore = true; a.exploreUrl = "/explore"
        b.enabled = true; b.enabledExplore = true; b.exploreUrl = "/explore"
        func entries(_ prefix: String, _ count: Int) throws -> [DiscoverCardItem] {
            try (1...count).map { i in
                try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "\(prefix)\(i)", url: "/category\(i)")))
            }
        }
        let aItems = try entries("A", 7)
        let bItems = try entries("B", 2)
        let action = try XCTUnwrap(DiscoverViewModel.mapItem(.init(title: "Website", url: "@js:java.startBrowser('https://a.fixture')")))
        model.prepare(configuration: "test", page: nil, sources: [a, b])
        let initialA = try XCTUnwrap(model.activeSource)
        model.reconcileSource(values: [:], items: aItems + [aItems[0], action], error: nil, activation: initialA)
        XCTAssertEqual(model.catalog.map(\.title), (1...7).map { "A\($0)" })
        model.select(model.catalog[5].reference, activation: initialA)
        let aChoice = try XCTUnwrap(model.current)
        XCTAssertEqual(aChoice.title, "A6")
        let aList = model.list(for: aChoice, source: a)

        model.switchSource(to: b)
        let currentB = try XCTUnwrap(model.activeSource)
        model.reconcileSource(values: [:], items: aItems, error: nil, activation: initialA)
        XCTAssertNil(model.current)
        XCTAssertTrue(model.catalog.isEmpty)
        model.reconcileSource(values: [:], items: bItems, error: nil, activation: currentB)
        XCTAssertEqual(model.catalog.map(\.title), ["B1", "B2"])
        model.select(model.catalog[1].reference, activation: currentB)

        model.switchSource(to: a)
        let currentA = try XCTUnwrap(model.activeSource)
        model.reconcileSource(values: [:], items: [], error: "late", activation: initialA)
        XCTAssertTrue(model.isLoadingCatalog)
        XCTAssertNil(model.catalogError)
        model.reconcileSource(values: [:], items: Array(aItems.reversed()), error: nil, activation: currentA)
        XCTAssertEqual(model.catalog.map(\.title), (1...7).reversed().map { "A\($0)" })
        XCTAssertEqual(model.current, aChoice)
        XCTAssertTrue(aList === model.list(for: aChoice, source: a))

        let reopened = DiscoveryCategoryModel(defaults: defaults)
        reopened.prepare(configuration: "test", page: nil, sources: [b, a])
        let reopenedA = try XCTUnwrap(reopened.activeSource)
        XCTAssertEqual(reopenedA.sourceURL, a.bookSourceUrl)
        reopened.reconcileSource(values: [:], items: aItems, error: nil, activation: reopenedA)
        XCTAssertEqual(reopened.current, aChoice)
        reopened.switchSource(to: b)
        reopened.reconcileSource(values: [:], items: bItems, error: nil, activation: try XCTUnwrap(reopened.activeSource))
        XCTAssertEqual(reopened.current?.title, "B2")
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
