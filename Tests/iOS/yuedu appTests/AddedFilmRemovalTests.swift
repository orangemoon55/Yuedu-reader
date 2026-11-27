import Foundation
import Testing
@testable import yuedu_app

@Suite("Music survives removal of the added film feature")
@MainActor
struct AddedFilmRemovalTests {
    @Test func menuContainsMusicOnly() {
        #expect(MediaHubKind.allCases == [.music])
        #expect(MediaHubKind.discoveryMenuKinds == [.music])
        #expect(MediaHubKind.libraryMenuKinds == [.music])
    }

    @Test func legacyMixedArchiveKeepsMusicWithoutRewritingOriginal() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("library.json")
        var music = MediaHubLibraryItem(sourceID: "fixture", siteKey: "wy", videoID: "track-1",
            title: "Saved track", poster: "", kind: .music, siteName: "Music",
            musicURL: "https://example.invalid/track.mp3", musicHeaders: ["X-Fixture": "kept"])
        music.musicQuality = "320k"
        let object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(music)) as? [String: Any])
        let original = try JSONSerialization.data(withJSONObject: [
            ["kind": "video", "videoID": "old-unsupported"], object,
            ["kind": "drama", "videoID": "another-unsupported"]
        ])
        try original.write(to: file)
        let library = MediaHubLibrary(fileURL: file)
        #expect(library.loadFailure == nil)
        #expect(library.items == [music])
        #expect(try Data(contentsOf: file) == original)
        library.reload()
        #expect(library.items.first?.musicHeaders?["X-Fixture"] == "kept")
        #expect(library.items.first?.musicQuality == "320k")
        #expect(try Data(contentsOf: file) == original)
    }

    @Test func malformedMusicStillReportsAnErrorRatherThanSilentlyDeletingIt() throws {
        let data = Data(#"[{"kind":"music","title":"missing identity"}]"#.utf8)
        #expect(throws: (any Error).self) { try MediaHubLibrary.decodeMusicRecords(data) }
    }
}
