import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Media hub presentation and bookmark compatibility", .serialized)
struct MediaHubPresentationTests {
    @Test("video.sites are not advertised as music even when their name says music")
    func truthfulCapabilities() {
        let sites = [site("a", name: "音樂 QQ music"), site("b", name: "電影"), site("a", name: "duplicate")]
        #expect(MediaHubPresentation.compatibleSites(sites, kind: .video).map(\.key) == ["a", "b"])
        #expect(MediaHubPresentation.compatibleSites(sites, kind: .music).isEmpty)
        #expect(MediaHubPresentation.compatibleSites(sites, kind: .drama).isEmpty)
    }

    @Test("hero selection is bounded, deduplicated and backed by source posters")
    func heroCandidates() {
        let input = [video("empty", poster: ""), video("1"), video("1")]
            + (2...8).map { video(String($0)) }
        #expect(MediaHubPresentation.heroVideos(input).map(\.id) == ["1", "2", "3", "4", "5"])
        #expect(MediaHubPresentation.uniqueVideos([video(""), video("1"), video("1")]).map(\.id) == ["1"])
    }

    @Test("hero facts use only supplied metadata, without a fabricated rating")
    func sourceFacts() {
        let item = video("1", year: " 2026 ", area: "日本", remarks: "<b>更新至 3 集</b>")
        #expect(MediaHubPresentation.facts(for: item) == "2026 · 日本 · 更新至 3 集")
        #expect(MediaHubPresentation.facts(for: video("2")).isEmpty)
        #expect(MediaHubPresentation.plainText("<p>來源&nbsp;簡介</p>\n &amp; 其他") == "來源 簡介 & 其他")
    }

    @Test("category rails keep the site's exact ordering and names with bounded requests")
    func categoryCandidates() {
        let categories = [CatVodCategory(id: "movie", name: "電影"),
                          CatVodCategory(id: "movie", name: "duplicate"),
                          CatVodCategory(id: "series", name: "劇集"),
                          CatVodCategory(id: "animation", name: "動畫"),
                          CatVodCategory(id: "other", name: "其他")]
        #expect(MediaHubPresentation.categoryCandidates(categories).map(\.id) == ["movie", "series", "animation"])
    }

    @Test("music only shows real records explicitly marked music, with local-only search")
    func savedMediaIsolation() {
        let movie = bookmark("1", title: "Music documentary", kind: .video)
        let music = bookmark("2", title: "真實音樂收藏", kind: .music)
        let other = bookmark("3", source: "another", title: "另一首", kind: .music)
        let items = [movie, music, other]
        #expect(MediaHubPresentation.savedItems(items, kind: .music).map(\.videoID) == ["2", "3"])
        #expect(MediaHubPresentation.savedItems(items, kind: .music, query: "真實音樂").map(\.videoID) == ["2"])
        #expect(MediaHubPresentation.savedItems(items, kind: .music, query: "真實站點").map(\.videoID) == ["2", "3"])
        #expect(MediaHubPresentation.savedItems(items, kind: .music, sourceID: "another").map(\.videoID) == ["3"])
        #expect(MediaHubPresentation.savedItems(items, kind: .video).map(\.videoID) == ["1"])
    }

    @Test("unclassified saved items group by actual site instead of a guessed movie or series type")
    func bookmarkRails() {
        let unknown = bookmark("1", title: "未知分類")
        var categorized = bookmark("2", title: "來源電影")
        categorized.categoryName = "電影"
        let secondUnknown = bookmark("3", title: "另一收藏")
        let rails = MediaHubPresentation.savedRails([unknown, categorized, secondUnknown])
        #expect(rails.count == 2)
        #expect(rails[0].title == "真實站點")
        #expect(rails[0].items.map(\.videoID) == ["1", "3"])
        #expect(rails[1].title == "電影")
        #expect(rails[1].subtitle == "真實站點")
    }

    @Test("public saved artwork works without activating a source but never bypasses proxy safety")
    func publicArtworkFallback() {
        #expect(MediaHubPresentation.publicArtworkURL("https://example.invalid/art.jpg")?.host == "example.invalid")
        #expect(MediaHubPresentation.publicArtworkURL("/relative/art.jpg") == nil)
        #expect(MediaHubPresentation.publicArtworkURL("http://127.0.0.1:8123/art") == nil)
        #expect(MediaHubPresentation.publicArtworkURL("https://example.invalid/art?token=secret") == nil)
    }

    @Test("poster density respects preferences and gives accessibility sizes a single grid column")
    func posterDensity() {
        #expect(MediaHubPresentation.posterColumnCount(3, accessibility: false) == 3)
        #expect(MediaHubPresentation.posterColumnCount(0, accessibility: false) == 2)
        #expect(MediaHubPresentation.posterColumnCount(99, accessibility: false) == 5)
        #expect(MediaHubPresentation.posterColumnCount(5, accessibility: true) == 1)
    }

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
            videoID: item.videoID, title: "更新標題", poster: item.poster, kind: .video, siteName: item.siteName))
        let reopened = MediaHubLibrary(fileURL: file)
        let updated = try #require(reopened.items.first)
        #expect(reopened.items.count == 1)
        #expect(updated.id == identity)
        #expect(updated.title == "更新標題")
        #expect(updated.categoryName == "電影")
        #expect(MediaHubPresentation.facts(for: updated) == "2026 · 日本 · 來源備註")
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

    private func video(_ id: String, poster: String = "https://example.invalid/poster.jpg",
                       year: String = "", area: String = "", remarks: String = "") -> CatVodVideo {
        CatVodVideo(id: id, title: "來源影片 \(id)", poster: poster, remarks: remarks, summary: "",
            actor: "", director: "", year: year, area: area, routes: [])
    }

    private func site(_ key: String, name: String) -> CatVodSite {
        CatVodSite(key: key, name: name, api: "/source.js", type: 3,
            searchable: true, filterable: true, indexs: true)
    }

    private func bookmark(_ id: String, source: String = "source", title: String = "真實收藏",
                          kind: MediaHubKind = .video,
                          poster: String = "https://example.invalid/poster.jpg") -> MediaHubLibraryItem {
        MediaHubLibraryItem(sourceID: source, siteKey: "site", videoID: id, title: title,
            poster: poster, kind: kind, siteName: "真實站點")
    }

    private func legacyJSON(poster: String = "https://example.invalid/old.jpg") -> Data {
        Data("""
        [{"sourceID":"source","siteKey":"site","videoID":"old","title":"舊收藏","poster":"\(poster)","kind":"video","siteName":"舊站點"}]
        """.utf8)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
