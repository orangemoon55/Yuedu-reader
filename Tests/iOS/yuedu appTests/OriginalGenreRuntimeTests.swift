import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Original IPA runtime", .serialized)
struct OriginalGenreRuntimeTests {
    private final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var value = Date(timeIntervalSince1970: 1_000)
        var date: Date {
            get { lock.withLock { value } }
            set { lock.withLock { value = newValue } }
        }
    }

    private func fixture() -> (RuleModuleClient, Clock, URL) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("OriginalRuntime-\(UUID())")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ModuleStub.self]
        let clock = Clock()
        return (RuleModuleClient(fetcher: WebFetcher(session: URLSession(configuration: config)),
                                 store: RuleModuleStore(directory: folder), now: { clock.date }), clock, folder)
    }

    private func module() -> RuleModule {
        RuleModule(id: "runtime.test", title: "Runtime", version: "1.0", requiredVersion: "3.0.2",
                   hosts: ["example.com"], modules: [])
    }

    private func item(intro: String = "", tags: [String]? = nil) -> RuleListItem {
        RuleListItem(name: "Book", author: "Author", bookUrl: "https://example.com/book", coverUrl: "",
                     intro: intro, wordCount: "", lastChapter: "", kind: "", tags: tags)
    }

    private func detail(_ ttl: Int? = 60) -> RuleModule.Detail {
        RuleModule.Detail(request: RuleModule.Request(url: "{{url}}"), intro: "$.intro", tags: "$.tags[*]", cacheDuration: ttl)
    }

    @Test("Detail patch hits, expires at TTL, rejects future timestamps and fills only gaps")
    func detailExpiryAndMerge() async throws {
        let (client, clock, folder) = fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        ModuleStub.install(["example.com/book": .json(#"{"intro":"Remote","tags":["Fantasy"]}"#)])
        let first = try await client.detailed(item(intro: "Existing A"), by: detail(), in: module())
        #expect(first.intro == "Existing A")
        let second = try await client.detailed(item(intro: "Existing B", tags: ["Own"]), by: detail(), in: module())
        #expect(second.intro == "Existing B" && second.tags == ["Own"])
        let blank = try await client.detailed(item(), by: detail(), in: module())
        #expect(blank.intro == "Remote" && blank.tags == ["Fantasy"])
        #expect(ModuleStub.urls.count == 1, "cached patch never contains A's existing intro")
        clock.date = Date(timeIntervalSince1970: 1_060)
        _ = try await client.detailed(item(), by: detail(), in: module())
        #expect(ModuleStub.urls.count == 2)
        clock.date = Date(timeIntervalSince1970: 1_059)
        _ = try await client.detailed(item(), by: detail(), in: module())
        #expect(ModuleStub.urls.count == 3, "negative age is not fresh")
    }

    @Test("Disabled TTLs always fetch", arguments: [nil, 0, -1] as [Int?])
    func disabledTTL(_ ttl: Int?) async throws {
        let (client, _, folder) = fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        ModuleStub.install(["example.com/book": .json(#"{"intro":"Remote"}"#)])
        _ = try await client.detailed(item(), by: detail(ttl), in: module())
        _ = try await client.detailed(item(), by: detail(ttl), in: module())
        #expect(ModuleStub.urls.count == 2)
        #expect((try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty != false)
    }

    @Test("Version, module, record, globals, request and parser rules separate detail caches")
    func cacheIdentity() async throws {
        let (client, _, folder) = fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        ModuleStub.install(["example.com/book": .json(#"{"intro":"One","other":"Two"}"#),
                            "example.com/other": .json(#"{"intro":"Other"}"#)])
        var m = module()
        _ = try await client.detailed(item(), by: detail(), in: m)
        m.version = "1.1"
        _ = try await client.detailed(item(), by: detail(), in: m)
        m.id = "runtime.other"
        _ = try await client.detailed(item(), by: detail(), in: m)
        m.globalParams = [RuleModule.Param(name: "region", type: "constant", value: "en")]
        _ = try await client.detailed(item(), by: detail(), in: m)
        m.globalParams?[0].value = "ja"
        _ = try await client.detailed(item(), by: detail(), in: m)
        var changed = detail()
        changed.intro = "$.other"
        #expect(try await client.detailed(item(), by: changed, in: m).intro == "Two")
        changed.request.headers = ["X-Variant": "two"]
        _ = try await client.detailed(item(), by: changed, in: m)
        var other = item()
        other.bookUrl = "https://example.com/other"
        _ = try await client.detailed(other, by: detail(), in: m)
        #expect(ModuleStub.urls.count == 8)
    }

    @Test("Unreadable cache falls back; failures and cancellation never seed detail cache")
    func fallbackFailureAndCancellation() async throws {
        let (client, _, folder) = fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        ModuleStub.install(["example.com/book": .status(503)])
        do {
            _ = try await client.detailed(item(), by: detail(), in: module())
            Issue.record("failed detail returned successfully")
        } catch { #expect(!(error is CancellationError)) }
        ModuleStub.install(["example.com/book": .hang])
        let task = Task { try await client.detailed(item(), by: detail(), in: module()) }
        for _ in 0..<100 {
            if !ModuleStub.urls.isEmpty { break }
            try await Task.sleep(for: .milliseconds(5))
        }
        task.cancel()
        do { _ = try await task.value; Issue.record("cancelled detail succeeded") }
        catch { #expect(error is CancellationError || (error as? URLError)?.code == .cancelled) }
        ModuleStub.install(["example.com/book": .json(#"{"intro":"Recovered"}"#)])
        #expect(try await client.detailed(item(), by: detail(), in: module()).intro == "Recovered")
        #expect(ModuleStub.urls.count == 1)
        let cache = RuleModuleStore(directory: folder).cacheDirectory(id: module().id)
        let files = try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
        let file = try #require(files.first { $0.lastPathComponent.hasPrefix("detail-") })
        try Data("broken cache".utf8).write(to: file)
        _ = try await client.detailed(item(), by: detail(), in: module())
        #expect(ModuleStub.urls.count == 2)
    }

    @Test("Volumes are selected records, retain order and routes, never recurse or become JSON titles")
    func nestedVolumes() throws {
        let list = RuleModule.ListRules(items: "$.items[*]", title: "$.title", author: "$.author",
                                       cover: "$.cover", url: "$.url", volumes: "$.volumes[*]")
        let entry = RuleModule.Entry(id: "series", title: "Series", request: RuleModule.Request(url: "https://example.com/list"), list: list)
        let json = #"{"items":[{"title":"Series","volumes":[{"title":"First","url":"https://example.com/first","cover":"https://evil.example/cover","volumes":[{"title":"Never"}]},{"title":"Second","cover":"https://example.com/cover"}]},{"title":"Single","url":"https://example.com/single"}]}"#
        let m = module()
        let items = RuleListMapping.items(engine: m.ruleEngine(), content: json, baseURL: "https://example.com/list",
                                          listRule: list.items, fields: list.fields)
        #expect(items.count == 2)
        #expect(items[0].volumes?.map(\.name) == ["First", "Second"])
        #expect(items[0].volumes?.first?.volumes == nil)
        #expect(try JSONDecoder().decode([RuleListItem].self, from: JSONEncoder().encode(items)) == items)
        guard case .item(_, let summary, let opening)? = ModuleProvider.entry(
            items[0], of: entry, instance: ModuleProvider.instanceKey(moduleID: m.id), hasURLRule: true,
            hosts: RuleModuleHosts(m.hosts)) else { Issue.record("series missing"); return }
        #expect(opening == .bibliographic)
        let volumes = try #require(summary.volumes)
        #expect(volumes.map(\.title) == ["First", "Second"])
        #expect(volumes[0].cover == nil)
        #expect(volumes[0].work?.record.key.instance == ModuleProvider.instanceKey(moduleID: m.id))
        #expect(volumes[0].work?.summary.volumes == nil)
        #expect(volumes[0].id != volumes[1].id)
        #expect(volumes[1].work == nil, "a named-only volume never inherits the list URL")
        #expect(volumes[1].cover == .remote(URL(string: "https://example.com/cover")!, headers: [:]))
    }

    @Test("Legacy manifests still reject volumes and entry detail TTL")
    func legacyBoundary() throws {
        var m = module()
        m.requiredVersion = "2.0"
        var entry = RuleModule.Entry(id: "main", title: "Main", request: RuleModule.Request(url: "https://example.com/list"),
                                     list: RuleModule.ListRules(items: "$.items[*]", title: "$.title", volumes: "$.volumes[*]"))
        m.modules = [entry]
        #expect(throws: RuleModuleRejection.unsupportedCapability("modules[0].list.volumes")) {
            try RuleModuleRuntimeCompatibility.validateCapabilities(m)
        }
        entry.list.volumes = nil
        entry.detail = detail()
        m.modules = [entry]
        #expect(throws: RuleModuleRejection.unsupportedCapability("modules[0].detail.cacheDuration")) {
            try RuleModuleRuntimeCompatibility.validateCapabilities(m)
        }
        m.requiredVersion = "3.0.2"
        try RuleModuleRuntimeCompatibility.validateCapabilities(m)
    }

    @Test("Exact IPA modules validate without field removal or module ID exceptions", arguments: ["trends", "bangumi", "openlibrary"])
    func originalManifests(_ id: String) throws {
        var root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        for _ in 0..<3 { root.deleteLastPathComponent() }
        let data = try Data(contentsOf: root.appendingPathComponent("Resources/Assets/official-module-\(id).json"))
        let original = try JSONDecoder().decode(RuleModule.self, from: data)
        let validated = try RuleModuleValidator.validate(data, appVersion: "3.0.2")
        #expect(validated == original)
        var renamed = original
        renamed.id = "runtime.renamed.\(id)"
        try RuleModuleRuntimeCompatibility.validateCapabilities(renamed)
    }
}
