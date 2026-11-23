import Foundation
import Testing
@testable import yuedu_app

/// The uploaded module, unchanged: all HTTP requests are intercepted by the private protocol.
/// Keep this separate from the synthetic format tests so import defaults and real JSON paths
/// cannot silently regress together. No public service, app preferences or shared store is used.
@MainActor
@Suite("Qingyun real comments module compatibility", .serialized)
struct QingyunModuleCompatibilityTests {
    private static let moduleID = "local.hanyujian.comments"
    private static let token = "offline-reader-token+/= literal"
    private static let fixtureURL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Fixtures/RuleModules/hanyujian-comments.module.json")

    @MainActor
    private struct Storage {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QingyunModuleCompatibility-\(UUID().uuidString)", isDirectory: true)
        let suiteName = "QingyunModuleCompatibility-\(UUID().uuidString)"
        var store: RuleModuleStore { RuleModuleStore(directory: directory) }
        var preferences: UserDefaults { UserDefaults(suiteName: suiteName)! }
        func library() -> RuleModuleLibrary {
            RuleModuleLibrary(store: store, officialFiles: { [] }, availability: nil,
                              language: "zh-Hans", preferences: preferences)
        }
        func cleanUp() {
            preferences.removePersistentDomain(forName: suiteName)
            try? FileManager.default.removeItem(at: directory)
        }
    }

    private func fixture() throws -> Data { try Data(contentsOf: Self.fixtureURL) }

    private func fixture(replacing path: [String], with value: Any?) throws -> Data {
        let source = try JSONSerialization.jsonObject(with: fixture())
        var object = try #require(source as? [String: Any])
        func replace(_ keys: ArraySlice<String>, in object: inout [String: Any]) throws {
            let key = try #require(keys.first)
            if keys.count == 1 {
                object[key] = value
            } else {
                var child = try #require(object[key] as? [String: Any])
                try replace(keys.dropFirst(), in: &child)
                object[key] = child
            }
        }
        try replace(path[...], in: &object)
        return try JSONSerialization.data(withJSONObject: object)
    }

    private func rejection(_ data: Data) -> RuleModuleRejection? {
        do { _ = try RuleModuleValidator.validate(data); return nil }
        catch { return error }
    }

    private func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [QingyunModuleHTTPStub.self]
        configuration.urlCache = nil
        return URLSession(configuration: configuration)
    }

    @Test("real fixture validates, installs, lists and round-trips with default engine compatibility")
    func defaultInstallAndRoundTrip() async throws {
        let data = try fixture()
        // Deliberately do not pass appVersion: the marketing version is not the module engine.
        let validated = try RuleModuleValidator.validate(data)
        #expect(validated.id == Self.moduleID)
        #expect(validated.requiredVersion == "3.0.2")
        #expect(validated.modules.isEmpty && validated.search != nil && validated.comments != nil)
        #expect(validated.search?.list.id == "$.book_id")
        #expect(validated.globalParams?.map(\.name) == ["readerToken"])
        #expect(validated.globalParams?.first?.value == "")
        #expect(validated.comments?.counts != nil && validated.comments?.paragraph != nil)
        #expect(validated.comments?.hot != nil && validated.comments?.authorSay != nil)

        let storage = Storage()
        defer { storage.cleanUp() }
        let library = storage.library()
        let installed = try await library.install(data, from: nil)
        #expect(installed.module == validated)
        #expect(library.isLoaded && library.failures.isEmpty)
        #expect(library.modules.map(\.module.id) == [Self.moduleID])
        let listing = storage.store.list()
        #expect(listing.failures.isEmpty && listing.modules.count == 1)
        let listed = try #require(listing.modules.first).module
        #expect(listed == validated)
        #expect(try storage.store.data(id: Self.moduleID) == data, "the uploaded bytes are kept intact")

        let encoded = try JSONEncoder().encode(listed)
        let decoded = try JSONDecoder().decode(RuleModule.self, from: encoded)
        #expect(decoded == validated)
        #expect(decoded.comments == validated.comments)
        #expect(decoded.globalParams == validated.globalParams)
        #expect(decoded.search?.list.id == validated.search?.list.id)
        #expect(try RuleModuleValidator.validate(encoded) == validated)
    }

    @Test("global Reader Token survives a new library and UserDefaults instance and reaches search")
    func tokenSurvivesLibraryReinitialization() async throws {
        let storage = Storage()
        defer { storage.cleanUp() }
        let library = storage.library()
        try await library.install(fixture(), from: nil)
        library.setGlobalValue(Self.token, name: "readerToken", id: Self.moduleID)
        #expect(library.module(id: Self.moduleID)?.module.globalParams?.first?.value == Self.token)

        // A second store, preferences instance and library must read the persisted override.
        let restored = storage.library()
        await restored.load()
        #expect(restored.failures.isEmpty)
        #expect(restored.globalValues[Self.moduleID]?["readerToken"] == Self.token)
        let module = try #require(restored.module(id: Self.moduleID)).module
        #expect(module.globalParams?.first?.value == Self.token)
        let raw = try RuleModuleValidator.validate(storage.store.data(id: Self.moduleID))
        #expect(raw.globalParams?.first?.value == "", "settings must not rewrite the imported default")

        QingyunModuleHTTPStub.install(["/search": Self.searchResponse])
        let session = session()
        defer { session.invalidateAndCancel() }
        let client = RuleModuleClient(fetcher: WebFetcher(session: session), store: storage.store)
        let keyword = "长夜 \"offline\""
        let items = try #require(try await ModuleProvider(module: module, client: client).searchItems(keyword))
        #expect(items.first?.id == "4242")
        let requests = QingyunModuleHTTPStub.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.value(forHTTPHeaderField: "X-Reader-Token") == Self.token)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        let body = try #require(request.httpBody)
        let decodedBody = try JSONSerialization.jsonObject(with: body)
        let object = try #require(decodedBody as? [String: Any])
        #expect(object["keyword"] as? String == keyword, "JSON body templates escape embedded quotes")
        #expect(object["page"] as? Int == 1 && object["page_size"] as? Int == 20)
    }

    @Test("real search, chapter and paragraph rules carry IDs and headers through the whole request chain")
    func searchChaptersAndParagraphRequestChain() async throws {
        let storage = Storage()
        defer { storage.cleanUp() }
        let library = storage.library()
        try await library.install(fixture(), from: nil)
        library.setGlobalValue(Self.token, name: "readerToken", id: Self.moduleID)
        let restored = storage.library()
        await restored.load()
        let module = try #require(restored.module(id: Self.moduleID)).module
        let comments = try #require(module.comments)
        let paragraphQuery = "bookId=4242&chapterId=9001&paragraphId=7&page=2&size=20&type=all&sort=hot"
        QingyunModuleHTTPStub.install([
            "/search": Self.searchResponse,
            "/books/4242/chapters": #"{"Data":{"Chapters":[{"C":9001,"N":"第1章 起风"}]}}"#,
            "/reviews/list": Self.reviewsResponse,
            "/reviews/list?\(paragraphQuery)": Self.paragraphResponse,
        ])
        let session = session()
        defer { session.invalidateAndCancel() }
        let client = RuleModuleClient(fetcher: WebFetcher(session: session), store: storage.store)
        let items = try #require(try await ModuleProvider(module: module, client: client).searchItems("长夜"))
        let record = try #require(items.first)
        #expect(items.count == 1 && record.id == "4242" && record.name == "长夜")
        #expect(record.author == "离线作者")
        #expect(record.bookUrl == "http://210.16.175.40:11451/books/4242")
        #expect(record.coverUrl == "https://qidian.qpic.cn/qdbimg/349573/4242/600")
        #expect(RuleModuleClient.canAskComments(of: record, by: comments))
        let chapters = try await client.commentChapters(of: record, by: comments, in: module)
        #expect(chapters == [ModuleCommentChapter(id: "9001", title: "第1章 起风")])
        let chapter = try #require(chapters.first)
        let notes = await client.chapterNotes(chapterID: chapter.id, of: record, by: comments, in: module)
        #expect(notes.counts == [ModuleParagraphCount(
            paragraph: .init(quote: "风起了他推开门", index: nil, id: "7"), count: 3)],
            "paragraphId > 0 filters chapter/author entries; zero reviewCount has no bubble")
        #expect(notes.hot.count == 1 && notes.hot.first?.paragraph.id == "7")
        #expect(notes.hot.first?.comment.text == "热评示例" && notes.hot.first?.comment.author == "甲")
        #expect(notes.authorSay == ModuleAuthorSay(text: "今天两更。", author: "离线作者"))
        let page = try await client.chapterComments(chapterID: chapter.id, of: record, sort: "new", page: 2,
                                                    by: comments, in: module)
        #expect(page.total == 23 && page.comments.map(\.text) == ["本章评论"])
        let paragraphID = try #require(notes.counts.first).paragraph.id
        let paragraph = try await client.chapterComments(chapterID: chapter.id, paragraphID: paragraphID,
                                                         of: record, sort: "hot", page: 2, by: comments, in: module)
        #expect(paragraph.total == 3 && paragraph.comments.map(\.text) == ["段落评论"])
        #expect(paragraph.comments.first?.author == "乙")

        let requests = QingyunModuleHTTPStub.requests
        #expect(requests.count == 7, "search, chapters, counts, hot, authorSay, chapter and paragraph")
        #expect(requests.map { $0.url?.path } == ["/search", "/books/4242/chapters"] + Array(repeating: "/reviews/list", count: 5))
        for request in requests {
            #expect(request.url?.host == "210.16.175.40" && request.url?.port == 11451)
            #expect(request.value(forHTTPHeaderField: "X-Reader-Token") == Self.token)
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            #expect(!(request.url?.absoluteString.contains("{{") ?? true))
        }
        let queries = requests.dropFirst(2).map { $0.url?.query ?? "" }
        #expect(queries == [
            "bookId=4242&chapterId=9001&page=1&size=20&type=all&sort=default",
            "bookId=4242&chapterId=9001&page=1&size=20&type=all&sort=default",
            "bookId=4242&chapterId=9001&paragraphId=-10&page=1&size=20&type=all&sort=default",
            "bookId=4242&chapterId=9001&page=2&size=20&type=all&sort=new",
            paragraphQuery,
        ])
        #expect(requests.dropFirst().allSatisfy { $0.httpMethod == "GET" })
    }

    @Test("unknown fields at module and nested request/list boundaries are rejected before installation")
    func rejectsUnknownFields() throws {
        let storage = Storage()
        defer { storage.cleanUp() }
        let paths = [
            ["futureCapability"],
            ["comments", "futurePage"],
            ["comments", "counts", "list", "futureRule"],
            ["search", "request", "futureTransport"],
        ]
        for path in paths {
            let data = try fixture(replacing: path, with: true)
            let expected = RuleModuleRejection.unsupportedField(path.joined(separator: "."))
            #expect(rejection(data) == expected)
            do {
                try storage.store.install(data, from: nil)
                Issue.record("unknown field was installed: \(path.joined(separator: "."))")
            } catch {
                #expect(error as? RuleModuleStoreError == .rejected(expected))
            }
        }
        #expect(storage.store.list().modules.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: storage.store.moduleFile(id: Self.moduleID).path))
    }

    @Test("comments require their version and fields; future requirements use the engine, not marketing version")
    func rejectsMissingAndFutureRequirements() throws {
        #expect(rejection(try fixture(replacing: ["requiredVersion"], with: nil))
                == .needsRequiredVersion(field: "globalParams", minimum: "3.0.2"))
        #expect(rejection(try fixture(replacing: ["comments", "chapters", "list", "id"], with: nil))
                == .missingField("comments.chapters.list.id"))
        // Derive a genuinely future major; never pretend 3.0.3 is a supported runtime.
        let major = try #require(RuleModuleRuntimeCompatibility.version.split(separator: ".").first.flatMap { Int($0) })
        let future = "\(major + 1).0.0"
        let data = try fixture(replacing: ["requiredVersion"], with: future)
        let expected = RuleModuleRejection.requiresNewerApp(required: future, running: RuleModuleRuntimeCompatibility.version)
        #expect(rejection(data) == expected)
        let storage = Storage()
        defer { storage.cleanUp() }
        do {
            try storage.store.install(data, from: nil)
            Issue.record("a future engine requirement was installed")
        } catch {
            #expect(error as? RuleModuleStoreError == .rejected(expected))
        }
        #expect(storage.store.list().modules.isEmpty)
    }

    @Test("an incompatible module's explanation names the module engine")
    func versionMessageNamesEngine() {
        let message = RuleModuleRejection.requiresNewerApp(
            required: "999.0.0", running: RuleModuleRuntimeCompatibility.version).message
        #expect(message.contains(RuleModuleRuntimeCompatibility.version))
        #expect(message.contains("999.0.0"))
        #expect(["引擎", "engine", "エンジン", "엔진"].contains { message.lowercased().contains($0) },
                "requiredVersion describes the module engine; the 1.0.1 marketing version must not be requested")
    }

    // Small synthetic responses for the real rules. Numeric IDs exercise list.id coercion.
    private static let searchResponse = #"{"books":[{"book_id":4242,"name":"长夜","author":"离线作者","intro":"离线简介","category":"小说"}]}"#
    private static let reviewsResponse = #"""
    {"data":{"total":23,"comments":[{"content":"本章评论","nickname":"甲","createTime":"2026-01-02 12:00:00","likeCount":4}],
      "segments":[
        {"paragraphId":-10,"reviewCount":99,"quote":"作者说不是段落","comments":[{"content":"排除作者条目","nickname":"甲","likeCount":1}]},
        {"paragraphId":0,"reviewCount":98,"quote":"本章说不是段落","comments":[{"content":"排除章节条目","nickname":"甲","likeCount":1}]},
        {"paragraphId":7,"reviewCount":3,"quote":"风起了，他推开门。","comments":[{"content":"热评示例","nickname":"甲","likeCount":9}]},
        {"paragraphId":8,"reviewCount":0,"quote":"这一段还没有评论。","comments":[]}],
      "authorActivity":{"content":"今天两更。","authorName":"离线作者"}}}
    """#
    private static let paragraphResponse = #"{"data":{"total":3,"comments":[{"content":"段落评论","nickname":"乙","createTime":"2026-01-03 12:00:00","likeCount":2}]}}"#
}

/// ModuleStub only captures User-Agent. This narrowly scoped JSON protocol also captures the
/// uploaded fixture's X-Reader-Token. It is private, has no forwarding session, and rejects
/// unregistered paths; unrelated suites using ModuleStub cannot replace its replies.
private final class QingyunModuleHTTPStub: URLProtocol {
    nonisolated(unsafe) private static var replies: [String: String] = [:]
    nonisolated(unsafe) private static var captured: [URLRequest] = []
    private static let lock = NSLock()

    static var requests: [URLRequest] { lock.withLock { captured } }
    static func install(_ table: [String: String]) {
        lock.withLock { replies = table; captured = [] }
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            capturedRequest.httpBody = body
        }
        let text: String? = Self.lock.withLock {
            Self.captured.append(capturedRequest)
            return url.query.flatMap { Self.replies["\(url.path)?\($0)"] } ?? Self.replies[url.path]
        }
        guard let text else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(text.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
