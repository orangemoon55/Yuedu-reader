import Foundation
import Testing
@testable import yuedu_app

struct YingxiaMusicLyricsTests {
    @Test func parsesMultipleStampsAndAppliesMillisecondsOffset() throws {
        let lrc = """
        [ar:Fixture Artist]
        [offset:500]
        [00:04.00]Third
        [00:01.00][00:02.00]First
        [00:02.75]Second
        """
        let lyrics = try #require(YingxiaMusicLyrics.parse(lrc))
        #expect(lyrics.synced)
        #expect(lyrics.lines.map(\.text) == ["First", "First", "Second", "Third"])
        #expect(lyrics.lines.map(\.time) == [0.5, 1.5, 2.25, 3.5])
        #expect(lyrics.index(at: 0.49) == nil)
        #expect(lyrics.index(at: 1.49) == 0)
        #expect(lyrics.index(at: 1.5) == 1)
        #expect(lyrics.index(at: 2.3) == 2)
    }

    @Test func pairsCloseTranslationsAndDropsOpeningCredits() throws {
        let original = """
        [00:00.10]Fixture - Artist
        [00:00.50]詞：Writer
        [00:01.00]Hello
        [00:02.00]World
        """
        let translation = """
        [00:01.10]你好
        [00:02.20]世界
        """
        let lyrics = try #require(YingxiaMusicLyrics.parse(original, translation: translation))
        #expect(lyrics.lines.map(\.text) == ["Hello", "World"])
        #expect(lyrics.lines[0].translation == "你好")
        #expect(lyrics.lines[1].translation == "世界")
    }

    @Test func plainTextIsUnsyncedAndMetadataOnlyInputHasNoLyrics() throws {
        let plain = try #require(YingxiaMusicLyrics.parse("[ti:Fixture]\n\nFirst line\r\nSecond line\r"))
        #expect(!plain.synced)
        #expect(plain.lines.map(\.text) == ["First line", "Second line"])
        #expect(plain.index(at: 30) == nil)
        #expect(YingxiaMusicLyrics.parse("[ar:Artist]\n[offset:120]") == nil)
        #expect(YingxiaMusicLyrics.parse("[00:01.00]\n[00:02.00]") == nil)
    }

    @Test func stalePickerResultCannotAttachLyricsToDifferentOrReselectedTrack() {
        let initialGeneration = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        #expect(MusicLyricsImportOwnership.accepts(
            targetTrackID: "track-a", targetGeneration: initialGeneration,
            currentTrackID: "track-a", currentGeneration: initialGeneration))
        #expect(!MusicLyricsImportOwnership.accepts(
            targetTrackID: "track-a", targetGeneration: initialGeneration,
            currentTrackID: "track-b", currentGeneration: UUID(uuidString: "00000000-0000-0000-0000-000000000002")!))
        // Switching away and back to the same identity still invalidates the old picker.
        #expect(!MusicLyricsImportOwnership.accepts(
            targetTrackID: "track-a", targetGeneration: initialGeneration,
            currentTrackID: "track-a", currentGeneration: UUID(uuidString: "00000000-0000-0000-0000-000000000003")!))
        #expect(!MusicLyricsImportOwnership.accepts(
            targetTrackID: nil, targetGeneration: initialGeneration,
            currentTrackID: "track-a", currentGeneration: initialGeneration))
    }

    @Test func translationUsesTheSameOffsetCorrectedClock() throws {
        let pairs = [
            ("[offset:1000]\n[00:03.00]Original", "[offset:1000]\n[00:03.00]譯文"),
            ("[offset:1000]\n[00:03.00]Original", "[00:02.00]譯文"),
            ("[00:02.00]Original", "[offset:1000]\n[00:03.00]譯文"),
            ("[offset:-1000]\n[00:01.00]Original", "[00:02.00]譯文"),
            ("[00:02.00]Original", "[offset:-1000]\n[00:01.00]譯文")
        ]
        for (original, translated) in pairs {
            let value = try #require(YingxiaMusicLyrics.parse(original, translation: translated))
            #expect(value.lines.first?.time == 2)
            #expect(value.lines.first?.translation == "譯文")
        }
    }

    @Test func boundsLinesTimestampsAndTextBeforeTranslationMatching() {
        let tooMany = Array(repeating: "[00:01.00]Line", count: YingxiaMusicLyrics.maximumLines + 1).joined(separator: "\n")
        #expect(YingxiaMusicLyrics.parse(tooMany) == nil)
        #expect(YingxiaMusicLyrics.parse("[00:01.00]Line", translation: tooMany) == nil)
        let repeated = String(repeating: String(repeating: "[00:01.00]", count: 1_501) + "Line\n", count: 4)
        #expect(YingxiaMusicLyrics.parse(repeated) == nil)
        #expect(YingxiaMusicLyrics.parse(String(repeating: "x", count: YingxiaMusicLyrics.maximumTextBytes + 1)) == nil)
        #expect(YingxiaMusicLyrics.parse(String(repeating: "x", count: 16_385)) == nil)
    }

    @Test func loadsOnlyExplicitLocalLRCFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let lrc = directory.appendingPathComponent("fixture.lrc")
        try Data("[00:01.00]Local lyric".utf8).write(to: lrc)
        let loaded = try YingxiaMusicLyrics.load(from: lrc)
        #expect(loaded.synced)
        #expect(loaded.lines.first?.text == "Local lyric")

        let other = directory.appendingPathComponent("fixture.txt")
        try Data("[00:01.00]Not accepted by the LRC importer".utf8).write(to: other)
        #expect(throws: MusicLyricsImportError.self) { try YingxiaMusicLyrics.load(from: other) }
    }
}
