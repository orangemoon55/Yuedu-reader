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
        [00:00.10]Title: Fixture - Artist
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

    @Test func leadingBOMDoesNotHideFirstTimestampOrMetadata() throws {
        let timed = try #require(YingxiaMusicLyrics.parse("\u{FEFF}[00:01.00]首行\r\n[00:02.00]第二行"))
        #expect(timed.synced)
        #expect(timed.lines.map(\.text) == ["首行", "第二行"])
        #expect(timed.lines.map(\.time) == [1, 2])

        let offset = try #require(YingxiaMusicLyrics.parse("\u{FEFF}[offset:500]\n[00:01.00]首行"))
        #expect(offset.lines.first?.time == 0.5)
        #expect(YingxiaMusicLyrics.parse("\u{FEFF}[ar:Artist]\n[offset:120]") == nil)
        let plain = try #require(YingxiaMusicLyrics.parse("\u{FEFF}简体與繁體\n字中\u{FEFF}保留"))
        #expect(!plain.synced)
        #expect(plain.lines.map(\.text) == ["简体與繁體", "字中\u{FEFF}保留"])
    }

    @Test func indexRejectsNonFiniteTimesAndKeepsFiniteBoundaries() throws {
        let lyrics = try #require(YingxiaMusicLyrics.parse("[00:01.00]First\n[00:02.00]Second"))
        for time in [Double.nan, Double.infinity, -Double.infinity] {
            #expect(lyrics.index(at: time) == nil)
        }
        #expect(lyrics.index(at: -1) == nil)
        #expect(lyrics.index(at: 0.999) == nil)
        #expect(lyrics.index(at: 1) == 0)
        #expect(lyrics.index(at: 2) == 1)
        #expect(lyrics.index(at: Double.greatestFiniteMagnitude) == 1)
    }

    @Test func preservesOpeningLyricsWithColonOrSpacedHyphen() throws {
        let openingLines = [
            "I said: stay", "你说：别走", "说:别走", "Answer: not yet",
            "Hello - goodbye", "Fixture - Artist", "My title: a lyric"
        ]
        for opening in openingLines {
            let lyrics = try #require(YingxiaMusicLyrics.parse("[00:01.00]\(opening)\n[00:02.00]Next"))
            #expect(lyrics.lines.map(\.text) == [opening, "Next"])
            #expect(lyrics.lines.map(\.time) == [1, 2])
        }
    }

    @Test func removesOnlyExplicitOpeningCreditsAndKeepsBodyUnchanged() throws {
        let original = """
        [00:00.10] TITLE : Fixture - Artist
        [00:00.20]作词：Writer
        [00:00.30]作曲: Composer
        [00:00.40]編曲：Arranger
        [00:00.50]製作人：Producer
        [00:00.60]Produced By : Producer
        [00:00.70]混音：Mixer
        [00:01.00]你说：別走 - 别走
        [00:02.00]作詞：This is part of the body
        [00:03.00]End
        """
        let lyrics = try #require(YingxiaMusicLyrics.parse(original))
        #expect(lyrics.lines.map(\.text) == ["你说：別走 - 别走", "作詞：This is part of the body", "End"])
        #expect(lyrics.lines.map(\.time) == [1, 2, 3])
    }

    @Test func duplicateTimestampsStaySeparateWhenPairingTranslations() throws {
        let original = """
        [00:01.00]Same
        [00:01.00]Same
        [00:01.00]Other
        [00:02.00]End
        """
        let translation = "\u{FEFF}[00:01.00]譯文\n[00:02.00]End"
        let lyrics = try #require(YingxiaMusicLyrics.parse(original, translation: translation))
        #expect(lyrics.lines.map(\.text) == ["Same", "Same", "Other", "End"])
        #expect(lyrics.lines.map(\.time) == [1, 1, 1, 2])
        #expect(lyrics.lines.map(\.translation) == ["譯文", "譯文", "譯文", nil])
        #expect(lyrics.index(at: 1) == 2)
        #expect(lyrics.index(at: 2) == 3)
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

    @Test func translationToleranceAndSentinelsRemainUnchanged() throws {
        let original = "[00:00.00]Original"
        let inside = try #require(YingxiaMusicLyrics.parse(original, translation: "[00:00.349]譯文"))
        #expect(inside.lines.first?.translation == "譯文")
        for translation in ["[00:00.350]譯文", "[00:00.000]Original", "[00:00.000]//"] {
            let lyrics = try #require(YingxiaMusicLyrics.parse(original, translation: translation))
            #expect(lyrics.lines.first?.translation == nil)
        }
    }

    @Test func boundsLinesTimestampsAndTextBeforeTranslationMatching() {
        let tooMany = Array(repeating: "[00:01.00]Line", count: YingxiaMusicLyrics.maximumLines + 1).joined(separator: "\n")
        #expect(YingxiaMusicLyrics.parse(tooMany) == nil)
        #expect(YingxiaMusicLyrics.parse("[00:01.00]Line", translation: tooMany) == nil)
        let repeated = String(repeating: String(repeating: "[00:01.00]", count: 1_501) + "Line\n", count: 4)
        #expect(YingxiaMusicLyrics.parse(repeated) == nil)
        #expect(YingxiaMusicLyrics.parse("[00:01.00]Line", translation: repeated) == nil)
        let tooManyBytes = String(repeating: "x", count: YingxiaMusicLyrics.maximumTextBytes + 1)
        #expect(YingxiaMusicLyrics.parse(tooManyBytes) == nil)
        #expect(YingxiaMusicLyrics.parse("[00:01.00]Line", translation: tooManyBytes) == nil)
        let oversizedLine = String(repeating: "x", count: 16_385)
        #expect(YingxiaMusicLyrics.parse(oversizedLine) == nil)
        #expect(YingxiaMusicLyrics.parse("[00:01.00]Line", translation: oversizedLine) == nil)
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

        let bomLRC = directory.appendingPathComponent("utf8-bom.lrc")
        var bomData = Data([0xEF, 0xBB, 0xBF])
        bomData.append(contentsOf: "[00:01.00]简体與繁體\n[00:02.00]Second".utf8)
        try bomData.write(to: bomLRC)
        let bomLoaded = try YingxiaMusicLyrics.load(from: bomLRC)
        #expect(bomLoaded.synced)
        #expect(bomLoaded.lines.map(\.text) == ["简体與繁體", "Second"])
        #expect(bomLoaded.lines.map(\.time) == [1, 2])

        let other = directory.appendingPathComponent("fixture.txt")
        try Data("[00:01.00]Not accepted by the LRC importer".utf8).write(to: other)
        #expect(throws: MusicLyricsImportError.self) { try YingxiaMusicLyrics.load(from: other) }
    }
}
