import CryptoKit
import Foundation
import Testing
@testable import yuedu_app

@Suite("Original IPA genre sources")
struct OriginalGenreSourcesTests {
    // SHA-256 of the unmodified files in 閱讀-3.0.2_1.ipa/Payload/YueduReader.app.
    private static let originals: [String: (version: String, sha256: String, entries: [String])] = [
        "trends": ("1.3", "866d75d3bbf151687ccac5abe334a5327a9209f5f3bb0e7c83ad973031980cee", [
            "fiction", "genre-romance", "genre-mystery", "genre-scifi", "genre-fantasy", "genre-wuxia",
            "genre-horror", "genre-history", "genre-youth",
        ]),
        "bangumi": ("1.1", "75bf957cba0296aa637c1295fb12a85e9e28e789fd0f225e74976064fc73819a", ["comics"]),
        "openlibrary": ("1.1", "324a518317377affa6a61135d53209540c9dd0e37db2d1740ee72c0f8592a333", [
            "kids", "nonfiction", "biography", "history", "business", "health", "religion", "politics",
            "education", "cooking", "sports", "computers", "arts", "science", "travel", "lifestyle",
            "parenting", "humor", "professional", "reference",
        ]),
    ]

    /// Source files, never Bundle.main or an optional test that silently passes without assets.
    /// Fixtures may be exact IPA copies at Tests/Fixtures/official-module-<id>.json.
    private static func originalData(_ id: String) throws -> Data {
        let name = "official-module-\(id).json"
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        var candidates: [URL] = []
        for _ in 0..<6 {
            candidates.append(directory.appendingPathComponent("Resources/Assets/\(name)"))
            candidates.append(directory.appendingPathComponent("Tests/Fixtures/\(name)"))
            directory.deleteLastPathComponent()
        }
        let file = try #require(candidates.first { FileManager.default.fileExists(atPath: $0.path) },
                                "Missing exact IPA source asset: \(name)")
        return try Data(contentsOf: file)
    }

    @Test("All three exact IPA files validate on 3.0.2 and round-trip", arguments: ["trends", "bangumi", "openlibrary"])
    func exactSources(_ id: String) throws {
        let data = try Self.originalData(id)
        let expected = try #require(Self.originals[id])
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        #expect(hash == expected.sha256, "Do not remove fields, rewrite JSON or substitute old modules")
        // Deliberately no try?, availability check, catch-and-skip, or capability fallback.
        let module = try RuleModuleValidator.validate(data, appVersion: "3.0.2")
        #expect(module.version == expected.version)
        #expect(module.requiredVersion == "3.0.2")
        #expect(module.modules.filter { !($0.store ?? []).isEmpty }.compactMap(\.id) == expected.entries)
        let encoded = try JSONEncoder().encode(module)
        #expect(try RuleModuleValidator.validate(encoded, appVersion: "3.0.2") == module)
        let entries = Dictionary(uniqueKeysWithValues: module.modules.compactMap { entry in entry.id.map { ($0, entry) } })
        for entry in module.modules {
            for section in entry.store ?? [] {
                for shelf in section.shelves ?? [] {
                    let target = try #require(entries[shelf.list ?? entry.id ?? ""])
                    for (name, value) in shelf.params ?? [:] {
                        let param = try #require(target.params.first { $0.name == name })
                        if param.kind == .enumeration { #expect(param.enumOptions?.contains { $0.value == value } == true) }
                    }
                    if let condition = shelf.belongTo {
                        let ownerParam = try #require(entry.params.first { $0.name == condition.paramName })
                        #expect(!condition.value.isEmpty)
                        if ownerParam.kind == .enumeration {
                            #expect(condition.value.allSatisfy { value in ownerParam.enumOptions?.contains { $0.value == value } == true })
                        }
                    }
                }
            }
        }
    }

    @Test("The original storefront order contains exactly nine plus one plus twenty categories")
    func allThirtyCategories() throws {
        #expect(OfficialRuleModules.storeOrder == ["trends", "bangumi", "openlibrary"])
        var counts: [Int] = []
        var keys: [String] = []
        for id in OfficialRuleModules.storeOrder {
            let module = try RuleModuleValidator.validate(Self.originalData(id), appVersion: "3.0.2")
            let entries = module.modules.filter { !($0.store ?? []).isEmpty }
            counts.append(entries.count)
            keys += entries.compactMap { entry in entry.id.map { "\(id)/\($0)" } }
        }
        #expect(counts == [9, 1, 20])
        #expect(keys.count == 30)
        #expect(Set(keys).count == 30)
        #expect(keys.first == "trends/fiction")
        #expect(keys[9] == "bangumi/comics")
        #expect(keys.last == "openlibrary/reference")
    }

    private static let fixture = #"""
    {
      "id":"store.test","title":"Store","version":"1.0","requiredVersion":"3.0.2","hosts":["example.com"],
      "modules":[
        {"id":"main","title":"Main","params":[
          {"name":"sort","type":"enumeration","value":"new","enumOptions":[{"title":"New","value":"new"}]},
          {"name":"size","type":"count","value":"10"},
          {"name":"region","type":"enumeration","value":"en","enumOptions":[{"title":"English","value":"en"}]}],
         "request":{"url":"https://example.com/books"},"list":{"items":"$.books[*]","title":"$.title"},
         "store":[{"layout":"heroCards","params":{"sort":"new"}},
           {"layout":"groupedShelves","shelves":[{"list":"other","params":{"topic":"mystery"},
             "belongTo":{"paramName":"region","value":["en"]}},{"params":{"sort":"new"}}]}]},
        {"id":"other","title":"Other","params":[
          {"name":"topic","type":"enumeration","value":"mystery","enumOptions":[{"title":"Mystery","value":"mystery"}]}],
         "request":{"url":"https://example.com/other"},"list":{"items":"$.books[*]","title":"$.title"}}
      ]
    }
    """#

    private static func changingStore(_ change: (inout [[String: Any]]) -> Void) throws -> Data {
        var object = try #require(JSONSerialization.jsonObject(with: Data(fixture.utf8)) as? [String: Any])
        var entries = try #require(object["modules"] as? [[String: Any]])
        var store = try #require(entries[0]["store"] as? [[String: Any]])
        change(&store)
        entries[0]["store"] = store
        object["modules"] = entries
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static func rejection(_ data: Data) -> RuleModuleRejection? {
        do { _ = try RuleModuleValidator.validate(data, appVersion: "3.0.2"); return nil }
        catch { return error }
    }

    @Test("Store layouts, sizes and every parameter value are checked")
    func storeValidation() throws {
        #expect(try RuleModuleValidator.validate(Data(Self.fixture.utf8), appVersion: "3.0.2").modules[0].store?.count == 2)
        #expect(try Self.rejection(Self.changingStore { $0[0]["layout"] = "futureLayout" }) ==
                .unknownValue(field: "modules[0].store[0].layout", value: "futureLayout"))
        #expect(try Self.rejection(Self.changingStore { $0[0]["params"] = ["sort": "missing"] }) ==
                .unknownValue(field: "modules[0].store[0].params.sort", value: "missing"))
        #expect(try Self.rejection(Self.changingStore { $0[0]["params"] = ["size": "not-a-number"] }) ==
                .unknownValue(field: "modules[0].store[0].params.size", value: "not-a-number"))
        #expect(try Self.rejection(Self.changingStore { $0[0]["params"] = ["undeclared": "new"] }) != nil)
        #expect(try Self.rejection(Self.changingStore { $0 = [] }) != nil)
        #expect(try Self.rejection(Self.changingStore { $0 = Array(repeating: $0[0], count: RuleModuleValidator.maxStoreSections + 1) }) != nil)
        #expect(try Self.rejection(Self.changingStore {
            $0[1]["shelves"] = Array(repeating: ["list": "other"], count: RuleModuleValidator.maxStoreShelves + 1)
        }) != nil)
    }

    @Test("Shelf references stay in their module and parameters stay on their referenced list")
    func shelfReferences() throws {
        #expect(try Self.rejection(Self.changingStore {
            $0[1]["shelves"] = [["list": "another-module/other"]]
        }) == .unknownValue(field: "modules[0].store[1].shelves[0].list", value: "another-module/other"))
        #expect(try Self.rejection(Self.changingStore {
            $0[1]["shelves"] = [["list": "other", "params": ["sort": "new"]]]
        }) == .unknownValue(field: "modules[0].store[1].shelves[0].params.sort", value: "new"))
        #expect(try Self.rejection(Self.changingStore {
            $0[1]["shelves"] = [["params": ["topic": "mystery"]]]
        }) == .unknownValue(field: "modules[0].store[1].shelves[0].params.topic", value: "mystery"))
        let conditions: [[String: Any]] = [
            ["paramName": "missing", "value": ["en"]],
            ["paramName": "region", "value": []],
            ["paramName": "region", "value": ["not-an-option"]],
            ["paramName": "topic", "value": ["mystery"]], // target parameter is not an owner parameter
        ]
        for condition in conditions {
            #expect(try Self.rejection(Self.changingStore {
                $0[1]["shelves"] = [["list": "other", "belongTo": condition]]
            }) != nil)
        }
    }

    @Test("Unknown store, shelf and condition fields remain strict errors")
    func strictSchema() throws {
        #expect(try Self.rejection(Self.changingStore { $0[0]["badstore"] = true }) ==
                .unsupportedField("modules[0].store[0].badstore"))
        #expect(try Self.rejection(Self.changingStore { $0[1]["shelves"] = [["badstore": true]] }) ==
                .unsupportedField("modules[0].store[1].shelves[0].badstore"))
        #expect(try Self.rejection(Self.changingStore {
            $0[1]["shelves"] = [["belongTo": ["paramName": "region", "value": ["en"], "badstore": true]]]
        }) == .unsupportedField("modules[0].store[1].shelves[0].belongTo.badstore"))
        #expect(try Self.rejection(Self.changingStore { $0[0]["params"] = ["sort": 42] }) ==
                .malformed(field: "modules[0].store[0].params.sort"))
    }

    @Test("Native Store support does not enable old 2.x manifests or unrelated capabilities")
    func runtimeBoundary() throws {
        var module = try JSONDecoder().decode(RuleModule.self, from: Data(Self.fixture.utf8))
        #expect(RuleModuleRuntimeCompatibility.version == "3.0.2")
        try RuleModuleRuntimeCompatibility.validateCapabilities(module)
        #expect(throws: RuleModuleRejection.requiresNewerApp(required: "3.0.2", running: "2.0.8")) {
            try RuleModuleValidator.validate(module, appVersion: "2.0.8")
        }
        module.requiredVersion = "2.0.8"
        #expect(throws: RuleModuleRejection.unsupportedCapability("modules[0].store")) {
            try RuleModuleValidator.validate(module, appVersion: "3.0.2")
        }
        module.modules[0].store = nil
        module.modules[0].list.volumes = "$.volumes[*]"
        #expect(throws: RuleModuleRejection.unsupportedCapability("modules[0].list.volumes")) {
            try RuleModuleValidator.validate(module, appVersion: "3.0.2")
        }
        module.requiredVersion = "3.0.2"
        module.modules[0].list.volumes = nil
        module.icon = "https://example.com/icon.png"
        #expect(throws: RuleModuleRejection.unsupportedCapability("icon")) {
            try RuleModuleValidator.validate(module, appVersion: "3.0.2")
        }
    }
}
