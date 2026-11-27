import Foundation
import Testing
@testable import CodaCore

@Suite struct AlternativeLyricsTests {
    private func track() throws -> Track {
        try JSONDecoder().decode(Track.self, from: Data(#"{"id":1,"name":"晴天","ar":[{"id":2,"name":"周杰伦"}],"al":{"id":3,"name":"叶惠美"},"dt":269000}"#.utf8))
    }

    @Test func rejectsCoversAndDifferentRecordings() throws {
        let track = try track()
        #expect(AlternativeLyricsAPI.matchScore(title: "晴天", artist: "周杰伦", duration: 268, track: track) == 1)
        #expect(AlternativeLyricsAPI.matchScore(title: "晴天", artist: "其他歌手", duration: 269, track: track) == nil)
        #expect(AlternativeLyricsAPI.matchScore(title: "晴天 (Live)", artist: "周杰伦", duration: 269, track: track) == nil)
        #expect(AlternativeLyricsAPI.matchScore(title: "晴天", artist: "周杰伦", duration: 116, track: track) == nil)
    }

    @Test func convertsRelativeKugouWordTimesToAbsoluteTimes() throws {
        let response = try AlternativeLyricsAPI.parseKRC("[10000,2000]<0,500,0>你好<500,1500,0>世界\n[12000,1000]<0,1000,0>再见")
        let lyrics = LyricsParser.parse(response)
        #expect(lyrics.lines.map(\.text) == ["你好世界", "再见"])
        #expect(lyrics.lines[0].words?.map(\.start) == [10, 10.5])
        #expect(lyrics.lines[0].words?.map(\.duration) == [0.5, 1.5])
        #expect(lyrics.lines[1].time == 12)
    }

    @Test func decodesQQPlayLyricInfoTranslationAndSkipsPlaceholders() throws {
        let original = "[00:00.00]Title\n[00:01.54]夢ならば\n[00:02.88]どれほどよかったでしょう"
        let translated = "[00:00.00]//\n[00:01.54]如果只是一场梦\n[00:02.88]那该有多好"
        let response = try AlternativeLyricsAPI.qqLyricsResponse([
            "crypt": 0, "lyric": Data(original.utf8).base64EncodedString(),
            "trans": Data(translated.utf8).base64EncodedString()
        ], base64Encoded: true)
        let lyrics = LyricsParser.parse(response)
        #expect(lyrics.lines.map(\.translation) == [nil, "如果只是一场梦", "那该有多好"])
    }

    @Test func decodesEncryptedQQWordTimingEvenWhenCryptFlagIsZero() throws {
        // Synthetic QRC XML encrypted with QQ's modified DES; no song data.
        let encrypted = "0C8D67DD3E549974B64ED2680459F13881AA15D10DB4CC8324B86311D0D741BD6AF5D8724F2B7571B2B2BF976BE395E454A23CCB367E464B21D3E3D96109C4A83E6466F98A1F73E1B6B981815534BDDC730599B49A3FACF542101A9E03D39F52BC5BC91DE2D9553D76B29D2964581A063A6C4249DCE21EBC0C13186BFEF3E82B5B64C3F85E586BD054CD1A15F71393630958584CB8CA0617A11B8B6B99215619"
        let response = try AlternativeLyricsAPI.qqLyricsResponse([
            "crypt": 0, "qrc": 1, "lyric": encrypted,
            "trans": Data("[00:11.20]你好世界\n[00:13.20]再次见面".utf8).base64EncodedString()
        ], base64Encoded: true, fallbackLRC: "[00:11.20]Hello world\n[00:13.20]Again")
        let lyrics = LyricsParser.parse(response)
        #expect(response.yrc != nil)
        #expect(lyrics.lines.map(\.text) == ["Hello world", "Again"])
        #expect(lyrics.lines[0].words?.map(\.start) == [10, 10.5])
        #expect(lyrics.lines[0].words?.map(\.duration) == [0.5, 1.5])
        #expect(lyrics.lines.map(\.translation) == ["你好世界", "再次见面"])
    }

    @Test func convertsQQWordTimingWithoutSeparateLineLyrics() throws {
        let qrc = "[10000,2000]Hello (10000,500)world(10500,1500)"
        let response = try AlternativeLyricsAPI.qqLyricsResponse([
            "lyric": Data(qrc.utf8).base64EncodedString(),
            "trans": Data("[00:10.00]你好世界".utf8).base64EncodedString()
        ], base64Encoded: true)
        let lyrics = LyricsParser.parse(response)
        #expect(response.lrc?.lyric == "[00:10.000]Hello world")
        #expect(lyrics.lines.first?.words?.count == 2)
        #expect(lyrics.lines.first?.translation == "你好世界")
    }

    @Test func qqLegacyAndMissingTranslationKeepOriginal() throws {
        let response = try AlternativeLyricsAPI.qqLyricsResponse([
            "lyric": "[00:01.00]You &amp; I", "trans": "[00:01.00]你和我"
        ], base64Encoded: false)
        #expect(LyricsParser.parse(response).lines.first?.translation == "你和我")
        #expect(LyricsParser.parse(response).lines.first?.text == "You & I")
        for translation in ["", "not base64"] {
            let response = try AlternativeLyricsAPI.qqLyricsResponse([
                "lyric": Data("[00:01.00]Original".utf8).base64EncodedString(), "trans": translation
            ], base64Encoded: true)
            #expect(LyricsParser.parse(response).lines.first?.text == "Original")
            #expect(LyricsParser.parse(response).lines.first?.translation == nil)
        }
        #expect(throws: (any Error).self) {
            try AlternativeLyricsAPI.qqLyricsResponse(["crypt": 1, "lyric": "encrypted"], base64Encoded: true)
        }
    }

    private func languageTag(_ rows: [Any]) throws -> String {
        let content: [[String: Any]] = [
            ["type": 0, "lyricContent": [["pronunciation"]]],
            ["type": 1, "lyricContent": rows]
        ]
        let data = try JSONSerialization.data(withJSONObject: ["content": content])
        return "[language:\(data.base64EncodedString())]"
    }

    @Test func attachesKugouTranslationsToWordTimedLyrics() throws {
        let tag = try languageTag([["你好世界"], ["再次见面"]])
        let response = try AlternativeLyricsAPI.parseKRC(tag + "\n[10000,2000]<0,500,0>Hello <500,1500,0>world\n[12000,1000]<0,1000,0>See you")
        let lyrics = LyricsParser.parse(response)
        #expect(lyrics.lines.map(\.translation) == ["你好世界", "再次见面"])
        #expect(lyrics.lines[0].words?.map(\.start) == [10, 10.5])
    }

    @Test func preservesKugouTranslationSlotsAndIgnoresExtraRows() throws {
        let tag = try languageTag([["//"], [], [" "], NSNull(), ["第五行"], ["多余翻译"]])
        let body = (0..<5).map { "[\(10000 + $0 * 1000),1000]<0,1000,0>Line \($0)" }.joined(separator: "\n")
        let lyrics = LyricsParser.parse(try AlternativeLyricsAPI.parseKRC(tag + "\n" + body))
        #expect(lyrics.lines.map(\.translation) == [nil, nil, nil, nil, "第五行"])
    }

    @Test func missingOrBrokenKugouTranslationKeepsOriginalLyrics() throws {
        let shortTag = try languageTag([["第一行"]])
        let body = "[10000,1000]<0,1000,0>First\n[11000,1000]<0,1000,0>Second"
        for tag in ["", "[language:not-base64]", "[language:e30=]", "[language:W10=]", shortTag] {
            let lyrics = LyricsParser.parse(try AlternativeLyricsAPI.parseKRC(tag + "\n" + body))
            #expect(lyrics.lines.map(\.text) == ["First", "Second"])
            #expect(lyrics.lines[1].translation == nil)
        }
    }

    @Test func rejectsInvalidAndUntimedPayloads() {
        #expect(throws: (any Error).self) { try AlternativeLyricsAPI.decodeKRC("bm90LWtyYw==") }
        #expect(throws: (any Error).self) { try AlternativeLyricsAPI.response(lrc: "没有时间戳") }
    }
}

@Suite struct AutomaticLyricsTests {
    private func track(album: String = "叶惠美", duration: Int = 269000) throws -> Track {
        let body: [String: Any] = ["id": 1, "name": "晴天", "ar": [["id": 2, "name": "周杰伦"]],
                                  "al": ["id": 3, "name": album], "dt": duration]
        return try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: body))
    }

    private func candidate(_ source: LyricsSource, album: String? = "叶惠美", duration: Double = 269,
                           title: String = "晴天", artist: String = "周杰伦", wordTimed: Bool = false) throws -> LyricsCandidate {
        let response = try AlternativeLyricsAPI.response(lrc: "[00:10.00]你好世界\n[00:12.00]再次见面",
            yrc: wordTimed ? "[10000,2000](10000,1000,0)你好(11000,1000,0)世界\n[12000,2000](12000,1000,0)再次(13000,1000,0)见面" : nil)
        return LyricsCandidate(source: source, id: source.rawValue, title: title, artists: [artist],
                               album: album, duration: duration, response: response)
    }

    @Test func prefersWordTimingWhenRecordingMatches() throws {
        let selection = LyricsMatching.best([try candidate(.netease), try candidate(.kugou, album: nil, wordTimed: true)], for: try track())
        #expect(selection?.source == .kugou)
    }

    @Test func albumAndDurationAffectRanking() throws {
        let albumWinner = LyricsMatching.best([try candidate(.qqMusic, album: "其他专辑"), try candidate(.lrclib)], for: try track())
        #expect(albumWinner?.source == .lrclib)
        let durationWinner = LyricsMatching.best([try candidate(.qqMusic, duration: 277), try candidate(.lrclib)], for: try track())
        #expect(durationWinner?.source == .lrclib)
        let wordMismatch = LyricsMatching.best([try candidate(.netease), try candidate(.kugou, album: nil, duration: 278, wordTimed: true)], for: try track())
        #expect(wordMismatch?.source == .netease)
    }

    @Test func wordTimingCannotRescueWrongRecording() throws {
        let rejected = [try candidate(.kugou, title: "晴天 (Live)", wordTimed: true),
                        try candidate(.qqMusic, artist: "周杰伦翻唱团", wordTimed: true),
                        try candidate(.lrclib, duration: 116, wordTimed: true)]
        #expect(LyricsMatching.best(rejected, for: try track()) == nil)
    }

    @Test func missingAlbumDoesNotReceiveExactAlbumBonus() throws {
        let track = try track()
        let missing = try #require(LyricsMatching.score(try candidate(.qqMusic, album: nil), for: track))
        let exact = try #require(LyricsMatching.score(try candidate(.qqMusic), for: track))
        #expect(exact > missing)
    }

    @Test func malformedWordTimesDoNotEarnWordBonus() throws {
        let plain = try AlternativeLyricsAPI.response(lrc: "[00:10.00]你好世界")
        let malformed = try AlternativeLyricsAPI.response(lrc: "[00:10.00]你好世界",
            yrc: "[10000,2000](11000,1000,0)你好(10000,1000,0)世界")
        #expect(LyricsMatching.qualityScore(malformed, duration: 269) == LyricsMatching.qualityScore(plain, duration: 269))
    }

    @Test func supportsTraditionalChineseWithoutRemovingVersionNames() throws {
        #expect(LyricsMatching.normalized("晴天（現場版）") == LyricsMatching.normalized("晴天 (现场版)"))
        #expect(LyricsMatching.normalized("晴天（現場版）") != LyricsMatching.normalized("晴天"))
    }

    @Test func artistSeparatorsDoNotBreakBandNames() throws {
        let data = Data(#"{"id":2,"name":"The Sound of Silence","ar":[{"name":"Simon & Garfunkel"}],"al":{"name":"Sounds of Silence"},"dt":185000}"#.utf8)
        let band = try JSONDecoder().decode(Track.self, from: data)
        #expect(LyricsMatching.metadataScore(title: band.name, artists: ["Simon & Garfunkel"],
            album: band.album.name, duration: 185, track: band) != nil)
        #expect(LyricsMatching.metadataScore(title: "晴天", artists: ["周杰伦 / 其他歌手"],
            album: "叶惠美", duration: 269, track: try track()) != nil)
    }

    @Test func tieBreakDoesNotDependOnArrivalOrder() throws {
        let a = try candidate(.qqMusic), b = try candidate(.lrclib), track = try track()
        #expect(LyricsMatching.best([a, b], for: track)?.source == .qqMusic)
        #expect(LyricsMatching.best([b, a], for: track)?.source == .qqMusic)
    }

    @Test func retainsOriginalInstrumentalDesignation() throws {
        let response = try AlternativeLyricsAPI.response(lrc: "[00:00.00]纯音乐，请欣赏")
        // The Netease route requests the track's own id, so it is matched by id.
        let original = LyricsCandidate(source: .netease, id: "1", title: "晴天", artists: ["周杰伦"],
            album: "叶惠美", duration: 269, response: response, matchedByID: true)
        #expect(LyricsMatching.best([try candidate(.kugou, wordTimed: true), original], for: try track())?.source == .netease)
    }

    @Test func failedAndSlowProvidersDoNotBlockSuccessfulMatch() async throws {
        let good = try candidate(.qishui)
        let result = try await AlternativeLyricsAPI.automatic(track: try track(), timeout: 0.04) { source in
            if source == .qishui { return [good] }
            if source == .lrclib {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return []
            }
            throw AlternativeLyricsAPI.Failure.invalidResponse
        }
        #expect(result.source == .qishui)
    }

    @Test func noMatchAndCancellationArePropagated() async throws {
        do {
            _ = try await AlternativeLyricsAPI.automatic(track: try track()) { _ in [] }
            Issue.record("An empty search must not create a selection")
        } catch AlternativeLyricsAPI.Failure.noMatch { }
        let track = try track()
        let task = Task {
            try await AlternativeLyricsAPI.automatic(track: track) { _ in
                try await Task.sleep(nanoseconds: 5_000_000_000)
                return []
            }
        }
        task.cancel()
        do {
            _ = try await task.value
            Issue.record("A cancelled search must not publish a selection")
        } catch is CancellationError { }
    }

    @Test func autoIsDefaultAndManualSelectionsAreRememberedPerTrack() throws {
        let name = "coda-lyrics-test-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        #expect(LyricsSource.saved(for: 1, defaults: defaults) == .automatic)
        LyricsSource.netease.save(for: 1, defaults: defaults)
        LyricsSource.kugou.save(for: 2, defaults: defaults)
        #expect(LyricsSource.saved(for: 1, defaults: defaults) == .netease)
        #expect(LyricsSource.saved(for: 2, defaults: defaults) == .kugou)
        LyricsSource.automatic.save(for: 1, defaults: defaults)
        #expect(LyricsSource.saved(for: 1, defaults: defaults) == .automatic)
        #expect(LyricsSource.saved(for: 2, defaults: defaults) == .kugou)
    }

    @Test func cacheUsesFullTrackMetadata() async throws {
        let cache = LyricsSelectionCache(), first = try track()
        let selection = LyricsSelection(source: .kugou, response: try candidate(.kugou, wordTimed: true).response)
        await cache.store(selection, for: first)
        #expect(await cache.value(for: first)?.source == .kugou)
        #expect(await cache.value(for: try track(album: "其他专辑")) == nil)
        #expect(await cache.value(for: try track(duration: 280000)) == nil)
    }
}
