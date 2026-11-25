import XCTest
@testable import yuedu_app

final class MusicImportServiceTests: XCTestCase {
    func testRemoteTrackPersistsPlayableURLAndHeaders() throws {
        let item = try MusicImportService.remote(
            title: "Fixture", urlString: "https://media.example.test/fixture.mp3",
            artist: "Test Artist", headers: ["Referer": "https://media.example.test/"])
        XCTAssertEqual(item.kind, .music)
        XCTAssertEqual(item.musicURL, "https://media.example.test/fixture.mp3")
        XCTAssertEqual(item.musicHeaders?["Referer"], "https://media.example.test/")
        XCTAssertNotNil(MusicTrackDescriptor.from(item)?.resolvedURL())
    }

    func testPlaylistParsesMetadataAndRequestHeadersWithoutNetwork() async throws {
        let text = """
        #EXTM3U
        #EXTVLCOPT:http-referrer=https://media.example.test/
        #EXTVLCOPT:http-user-agent=ReadccFixture/1.0
        #EXTINF:-1,Artist - Track One
        https://media.example.test/track-one.mp3
        """
        let items = try await MusicImportService.importPlaylist(text: text)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Track One")
        XCTAssertEqual(items[0].remarks, "Artist")
        XCTAssertEqual(items[0].musicHeaders?["Referer"], "https://media.example.test/")
        XCTAssertEqual(items[0].musicHeaders?["User-Agent"], "ReadccFixture/1.0")
    }

    func testOldLibraryJSONStillDecodes() throws {
        let old = """
        [{"sourceID":"s","siteKey":"site","videoID":"v","title":"Old","poster":"","kind":"video","siteName":"Site"}]
        """.data(using: .utf8)!
        let items = try JSONDecoder().decode([MediaHubLibraryItem].self, from: old)
        XCTAssertEqual(items.first?.title, "Old")
        XCTAssertNil(items.first?.musicURL)
    }

    func testRejectsNonHTTPRemoteURL() {
        XCTAssertThrowsError(try MusicImportService.remote(title: "bad", urlString: "javascript:alert(1)"))
    }
}
