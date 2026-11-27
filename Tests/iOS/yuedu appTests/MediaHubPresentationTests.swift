import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Music library persistence and bookmark compatibility", .serialized)
struct MediaHubPresentationTests {
    @Test("pre-metadata bookmarks decode without a migration reset or invented playback state")
    func legacySchemaDecoding() throws {
        let data = legacyJSON()
        let decoded = try JSONDecoder().decode([MediaHubLibraryItem].self, from: data)
        let item = try #require(decoded.first)
        #expect(item.sourceID == "source")
        #expect(item.title == "舊收藏")
        #expect(item.categoryName == nil)
        #expect(item.year == nil)
        #expect(item.area == nil)
        #expect(item.remarks == nil)
        let encoded = String(decoding: try JSONEncoder().encode(item), as: UTF8.self)
        #expect(!encoded.contains("lastPlayed"))
        #expect(!encoded.contains("resume"))
        #expect(!encoded.contains("stream"))
    }

    @Test("existing library files reopen, save optional source facts and survive another reopen")
    func legacyFileRoundTripAndMetadataMerge() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        try legacyJSON().write(to: file)
        let store = MediaHubLibrary(fileURL: file)
        #expect(store.items.count == 1)
        #expect(store.loadFailure == nil)
        var item = try #require(store.items.first)
        let identity = item.id
        item.categoryName = "電影"
        item.year = "2026"
        item.area = "日本"
        item.remarks = "來源備註"
        try store.save(item)
        // A detail page using the original initializer must not erase known source facts.
        try store.save(MediaHubLibraryItem(sourceID: item.sourceID, siteKey: item.siteKey,
            videoID: item.videoID, title: "更新標題", poster: item.poster, kind: .music, siteName: item.siteName))
        let reopened = MediaHubLibrary(fileURL: file)
        let updated = try #require(reopened.items.first)
        #expect(reopened.items.count == 1)
        #expect(updated.id == identity)
        #expect(updated.title == "更新標題")
        #expect(updated.categoryName == "電影")
        #expect(updated.year == "2026" && updated.area == "日本" && updated.remarks == "來源備註")
        try reopened.remove(updated)
        #expect(MediaHubLibrary(fileURL: file).items.isEmpty)
    }

    @Test("persistent artwork never stores loopback proxies or credential-bearing URLs")
    func safeArtworkReferences() {
        let unsafe = ["http://127.0.0.1:8787/poster?token=private", "http://localhost:80/image",
                      "http://[::1]:8000/art", "https://user:password@example.invalid/art",
                      "https://example.invalid/art?access_token=private", "/proxy?token=private",
                      "file:///private/image.png", "data:image/png;base64,AA", "//127.0.0.1:8000/image"]
        for input in unsafe { #expect(MediaHubLibraryItem.persistablePoster(input).isEmpty) }
        #expect(MediaHubLibraryItem.persistablePoster("/covers/image.jpg") == "/covers/image.jpg")
        #expect(MediaHubLibraryItem.persistablePoster("https://example.invalid/image.jpg?w=300") == "https://example.invalid/image.jpg?w=300")
        let item = bookmark("safe", poster: unsafe[0])
        #expect(item.poster.isEmpty)
    }

    @Test("unsafe legacy artwork is removed in memory without destroying the original file on reload")
    func legacyUnsafeArtwork() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("library.json")
        let data = legacyJSON(poster: "http://127.0.0.1:8123/proxy?token=private")
        try data.write(to: file)
        let store = MediaHubLibrary(fileURL: file)
        #expect(store.items.first?.poster == "")
        #expect(try Data(contentsOf: file) == data)
        let item = try #require(store.items.first)
        try store.save(item)
        let saved = String(decoding: try Data(contentsOf: file), as: UTF8.self)
        #expect(!saved.contains("127.0.0.1"))
        #expect(!saved.contains("private"))
        #expect(!saved.contains("headers"))
    }

    @Test("failed writes and malformed reloads expose errors without claiming a saved bookmark")
    func persistenceFailure() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let parentFile = dir.appendingPathComponent("not-a-directory")
        try Data("original".utf8).write(to: parentFile)
        let store = MediaHubLibrary(fileURL: parentFile.appendingPathComponent("library.json"))
        do { try store.save(bookmark("1")); Issue.record("write should fail") }
        catch { #expect(error is MediaHubLibraryError) }
        #expect(store.items.isEmpty)
        #expect(try String(contentsOf: parentFile, encoding: .utf8) == "original")
        let corrupt = MediaHubLibrary(fileURL: parentFile)
        #expect(corrupt.items.isEmpty)
        #expect(corrupt.loadFailure != nil)
    }

    @Test("invalid identifiers are rejected while source identity remains distinct")
    func bookmarkValidationAndIdentity() throws {
        let dir = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = MediaHubLibrary(fileURL: dir.appendingPathComponent("library.json"))
        do { try store.save(bookmark(" ")); Issue.record("blank identifier accepted") }
        catch { #expect(error is MediaHubLibraryError) }
        let first = bookmark("1")
        let second = bookmark("1", source: "another")
        #expect(first.id != second.id)
        try store.save(first)
        try store.save(first)
        try store.save(second)
        #expect(store.items.map(\.sourceID) == ["another", "source"])
    }

    private func bookmark(_ id: String, source: String = "source", title: String = "真實收藏",
                          kind: MediaHubKind = .music,
                          poster: String = "https://example.invalid/poster.jpg") -> MediaHubLibraryItem {
        MediaHubLibraryItem(sourceID: source, siteKey: "site", videoID: id, title: title,
            poster: poster, kind: kind, siteName: "真實站點")
    }

    private func legacyJSON(poster: String = "https://example.invalid/old.jpg") -> Data {
        Data("""
        [{"sourceID":"source","siteKey":"site","videoID":"old","title":"舊收藏","poster":"\(poster)","kind":"music","siteName":"舊站點"}]
        """.utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
