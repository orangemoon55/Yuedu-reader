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
        await model.prepare(configuration: "A", page: nil, sources: [])
        model.choose(choice(1), at: 3)
        await model.prepare(configuration: "B", page: nil, sources: [])
        XCTAssertTrue(model.slots.choices.allSatisfy { $0 == nil })
        model.choose(choice(2), at: 0)
        let reopened = DiscoveryCategoryModel(defaults: defaults)
        await reopened.prepare(configuration: "A", page: nil, sources: [])
        XCTAssertEqual(reopened.slots.choices[3], choice(1))
        XCTAssertEqual(reopened.selection, 3)
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
