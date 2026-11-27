import Foundation
import Testing
@testable import CodaCore

@Suite struct LyricsSynchronizationTests {
    private func response(lrc: String?, yrc: String) throws -> LyricResponse {
        var object: [String: Any] = ["yrc": ["lyric": yrc]]
        if let lrc { object["lrc"] = ["lyric": lrc] }
        return try JSONDecoder().decode(LyricResponse.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func lyricClockProjectsSamplesAndFreezesOnPauseOrBuffering() {
        var clock = LyricPlaybackClock()
        let date = Date(timeIntervalSince1970: 1_000)
        clock.reanchor(to: 35.13, rate: 1, at: date)
        #expect(abs(clock.position(at: date.addingTimeInterval(0.75), duration: 273.2) - 35.88) < 0.000001)
        clock.reanchor(to: 42, rate: 0, at: date)
        #expect(clock.position(at: date.addingTimeInterval(30), duration: 273.2) == 42)
        clock.reanchor(to: 272, rate: 1, at: date)
        #expect(clock.position(at: date.addingTimeInterval(10), duration: 273.2) == 273.2)
        clock.reanchor(to: .nan, rate: .nan, at: date)
        #expect(clock.position(at: date.addingTimeInterval(10), duration: 273.2) == 0)
    }

    @Test func parsesTheReportedSongTimingWithoutInventingAnOffset() throws {
        let raw = try response(lrc: "[00:34.69]第一句\n[00:42.58]第二句",
            yrc: "[35130,4020](35130,310,0)第(35440,190,0)一(35630,3520,0)句\n[43070,4380](43070,340,0)第(43410,220,0)二(43630,3820,0)句")
        let karaoke = LyricsParser.parse(raw)
        #expect(karaoke.lines.map(\.time) == [35.13, 43.07])
        #expect(karaoke.lines[0].words?.map(\.start) == [35.13, 35.44, 35.63])
        #expect(karaoke.activeIndex(at: 35.12) == nil)
        #expect(karaoke.activeIndex(at: 35.13) == 0)
        #expect(karaoke.activeIndex(at: 42) == 0)
        #expect(karaoke.activeIndex(at: 43.07) == 1)
        // Both render modes use the same YRC source with their own lead time.
        let lineOnly = LyricsParser.parse(try response(lrc: "[00:34.69]第一句\n[00:42.58]第二句", yrc: ""))
        #expect(lineOnly.lines.map(\.time) == [34.69, 42.58])
        #expect(lineOnly.lines.allSatisfy { $0.words == nil })
    }

    @Test func dropsUpstreamCreditsKeepsSortingAndLiteralParentheses() throws {
        let raw = try response(lrc: nil,
            yrc: "{\"t\":-1000,\"c\":[{\"tx\":\"作词：作者\"}]}\n[20000,1000](20000,1000,0)再见\n[10000,2000](10000,1000,0)你好(hello)(11000,1000,0)世界")
        let parsed = LyricsParser.parse(raw)
        #expect(parsed.lines.map(\.time) == [10, 20])
        #expect(parsed.lines[0].text == "你好(hello)世界")
        #expect(parsed.lines[0].words?.map(\.start) == [10, 11])
    }

    @Test func dropsWholeNeteaseCreditBlocksWithUnknownRoles() throws {
        let lrc = """
        [00:00.00] 作词 : 梁博
        [00:01.00] 音乐总监 : 谭伊哲@TYZ
        [00:02.00] 爱尔兰风笛 : Eric Rigler
        [00:03.00] 鼓 : 祁大为
        [00:04.00] 和声 : 秋子／李郡洲
        [00:05.00] 乐器技师 : 于磊
        [00:06.00] 调音 : 杨光
        [00:33.02]我跟你 本应该
        [00:40.00]男：各自好 各自坏
        [00:45.46]Love : is all
        [03:57.14]谁也没有想过再想回来
        [04:00.00] 监棚 : Bruce
        [04:01.00] 母带 : 某人
        """
        let parsed = LyricsParser.parse(try response(lrc: lrc, yrc: ""))
        let texts = parsed.lines.map(\.text).joined(separator: "|")
        for name in ["梁博", "谭伊哲", "Eric", "祁大为", "秋子", "于磊", "杨光", "Bruce", "某人"] {
            #expect(!texts.contains(name), "\(name) should be removed: \(texts)")
        }
        #expect(texts.contains("我跟你 本应该"))
        #expect(texts.contains("各自好 各自坏"))
        #expect(texts.contains("is all"))
        #expect(texts.contains("谁也没有想过再想回来"))
    }

    @Test func dropsQQCreditBlockAndHeaderInWordTimedLyrics() throws {
        let track = try JSONDecoder().decode(Track.self, from: Data(#"{"id":1,"name":"出现又离开 (Live)","ar":[{"id":2,"name":"梁博"}],"al":{"id":3,"name":"我是唱作人 第2期"},"dt":404000}"#.utf8))
        let lrc = "[00:01.10]出现又离开 (Live) - 梁博\n[00:01.82]词：梁博\n[00:02.15]音乐总监：谭伊哲@TYZ\n[00:02.58]爱尔兰风笛：Eric Rigler\n[00:03.44]和声：秋子/李郡洲\n[00:03.68]乐器技师：于磊\n[00:33.14]我和你 本应该\n[00:37.31]女：各自好 各自坏"
        let yrc = "[0,2350](0,130,0)出现又离开(650,130,0) Live(1300,130,0) - (1560,130,0)梁博(2080,130,0) Bruce\n[2350,2360](2350,590,0)词：梁博\n[4710,2360](4710,236,0)音乐总监：谭伊哲@TYZ\n[7070,2360](7070,262,0)爱尔兰风笛：Eric Rigler\n[9430,2360](9430,262,0)和声：秋子/李郡洲\n[11790,2360](11790,337,0)乐器技师：于磊\n[33027,4081](33027,344,0)我跟(33627,1440,0)你\n[37108,4036](37108,320,0)各自好(37708,1529,0) 各自坏"
        let parsed = LyricsParser.parse(try response(lrc: lrc, yrc: yrc), track: track)
        let texts = parsed.lines.map(\.text).joined(separator: "|")
        for name in ["Bruce", "梁博", "谭伊哲", "Eric", "秋子", "于磊"] {
            #expect(!texts.contains(name), "\(name) should be removed: \(texts)")
        }
        #expect(parsed.lines.count == 2)
    }

    @Test func dropsQQBackingVocalCreditsButKeepsDuetLabels() throws {
        let lrc = "[00:02.25]词：周杰伦\n[00:09.00]制作人：周杰伦\n[00:11.25]合声：周杰伦\n[00:13.50]合声编写：周杰伦\n[00:15.75]吉他：蔡科俊Again\n[00:29.00]故事的小黄花\n[00:40.00]合：一起唱"
        let texts = LyricsParser.parse(try response(lrc: lrc, yrc: "")).lines.map(\.text)
        #expect(texts.first == "故事的小黄花")
        #expect(texts.contains { $0.contains("一起唱") })
    }

    @Test func dropsOpeningTitleArtistHeaderOnly() throws {
        let track = try JSONDecoder().decode(Track.self, from: Data(#"{"id":1,"name":"晴天","ar":[{"id":2,"name":"周杰伦"}],"al":{"id":3,"name":"叶惠美"},"dt":269000}"#.utf8))
        let lrc = "[00:00.00]晴天 - 周杰伦\n[00:01.00]词：方文山\n[00:29.00]故事的小黄花\n[01:00.00]晴天 - 周杰伦"
        let parsed = LyricsParser.parse(try response(lrc: lrc, yrc: ""), track: track)
        #expect(parsed.lines.map(\.text) == ["故事的小黄花", "晴天 - 周杰伦"])
        #expect(LyricsParser.parse(try response(lrc: lrc, yrc: "")).lines.first?.text == "晴天 - 周杰伦")
        #expect(LyricsParser.isTitleHeader("周杰伦 - 晴天", track: track))
        #expect(!LyricsParser.isTitleHeader("晴天 - 周杰伦 - 故事的小黄花从出生那年就飘着", track: track))
    }

    @Test func showsOnlyLyricBodyWithoutCreditsOrNotices() throws {
        let lrc = """
        [00:00.00] 作词 : 佚名
        [00:00.50] 作曲 : 佚名
        [00:01.00]编曲 Arranger：某人
        [00:01.50]Lyrics by Someone
        [00:02.00]Producer: Someone
        [00:03.00]男：你好
        [00:04.00]合：一起唱
        [00:05.00]Love: it is all
        [00:06.00]正文
        [03:00.00]录音工程&MIDI制作：某人
        [03:01.00]未经许可，不得翻唱或使用
        """
        let parsed = LyricsParser.parse(try response(lrc: lrc, yrc: ""))
        #expect(!parsed.lines.contains { $0.text.contains("佚名") || $0.text.contains("某人") || $0.text.contains("Someone") })
        #expect(!parsed.lines.contains { $0.text.contains("未经许可") })
        #expect(parsed.lines.contains { $0.text.contains("正文") })
        #expect(parsed.lines.contains { $0.text.contains("一起唱") })
        #expect(parsed.lines.contains { $0.text.contains("你好") })
        #expect(parsed.lines.contains { $0.text.contains("it is all") })
        #expect(LyricsParser.isCredit("OP：Sony Music"))
        #expect(!LyricsParser.isCredit("你说：我爱你"))
    }

    @Test func preciseOverlapsAndInstrumentalGapsFollowLyricFocusRules() {
        let lines = [TimedLyricLine(id: "a", time: 10, duration: 10, text: "长句"),
                     TimedLyricLine(id: "b", time: 12, duration: 2, text: "短句"),
                     TimedLyricLine(id: "c", time: 30, duration: 2, text: "后句")]
        let overlap = LyricPlaybackTimeline.position(at: 13, in: lines)
        #expect(overlap.activeLyricIDs == ["a", "b"])
        #expect(overlap.highlightedLyricID == "b")
        #expect(overlap.nextTransitionTime == 14)
        let afterShort = LyricPlaybackTimeline.position(at: 15, in: lines)
        #expect(afterShort.highlightedLyricID == "a")
        #expect(afterShort.activeLyricIDs == ["a"])
        let gap = LyricPlaybackTimeline.position(at: 25, in: lines)
        #expect(gap.highlightedLyricID == "b")
        #expect(gap.nextTransitionTime == 30)
    }

    @MainActor @Test func glyphProgressUsesLongToneCurveWithoutEarlyHighlight() {
        let syllables = [LyricSyllable(text: "字", startTime: 35, endTime: 36)]
        let timing = TimedLyricTextBuilder.attributes(from: syllables)[0]
        func progress(_ time: Double) -> Double {
            LyricHighlightRevealProgress.progress(playbackTime: time, timing: timing,
                detectionMode: .character, durationThreshold: 0.95)
        }
        #expect(progress(34.9) == 0)
        #expect(progress(35) == 0)
        #expect(abs(progress(35.5) - 0.86) < 0.000001)
        #expect(abs(progress(36) - 1) < 0.000001)
    }

    @MainActor @Test func scheduledTransitionAndPauseUseTheSameProjectedClock() async throws {
        let parsed = ParsedLyrics(lines: [LyricLine(id: 0, time: 0.03, text: "第一句"),
                                          LyricLine(id: 1, time: 0.3, text: "第二句")])
        let cursor = LyricsCursor()
        cursor.synchronize(lyrics: parsed, at: 0, playing: true)
        try await Task.sleep(for: .milliseconds(100))
        #expect(cursor.activeIndex == 0)
        cursor.synchronize(lyrics: parsed, at: 0.1, playing: false)
        try await Task.sleep(for: .milliseconds(250))
        #expect(cursor.activeIndex == 0)
        #expect(cursor.playbackTime == 0.1)
    }

    @MainActor @Test func karaokeSettingChangesLeadWithoutReplacingTheAuthoredTimeline() {
        let lyrics = ParsedLyrics(lines: [LyricLine(id: 0, time: 35.13, text: "第一句")])
        let cursor = LyricsCursor()
        cursor.synchronize(lyrics: lyrics, at: 35, playing: false, advanceTime: 0)
        #expect(cursor.activeIndex == nil)
        cursor.synchronize(lyrics: lyrics, at: 35, playing: false, advanceTime: 0.2)
        #expect(cursor.activeIndex == 0)
        #expect(cursor.playbackTime == 35)
        cursor.synchronize(lyrics: lyrics, at: 35, playing: false, advanceTime: 0)
        #expect(cursor.activeIndex == nil)
        #expect(cursor.playbackTime == 35)
    }

    @MainActor @Test func manualTimingMovesLineAndWordClockTogetherAndResets() {
        let lyrics = ParsedLyrics(lines: [LyricLine(id: 0, time: 10, text: "第一句")])
        let cursor = LyricsCursor()
        cursor.synchronize(lyrics: lyrics, at: 9.95, playing: false, timeOffset: 0.1)
        #expect(cursor.activeIndex == 0)
        #expect(abs(cursor.playbackTime - 10.05) < 0.000001)
        cursor.synchronize(lyrics: lyrics, at: 10.05, playing: false, timeOffset: -0.1)
        #expect(cursor.activeIndex == nil)
        #expect(abs(cursor.playbackTime - 9.95) < 0.000001)
        cursor.synchronize(lyrics: lyrics, at: 10.05, playing: false, timeOffset: 0)
        #expect(cursor.activeIndex == 0)
        #expect(cursor.playbackTime == 10.05)
        // Delaying lyrics at the beginning must not clamp away the adjustment.
        cursor.synchronize(lyrics: lyrics, at: 0, playing: false, timeOffset: -0.1)
        #expect(cursor.playbackTime == -0.1)
    }

    @MainActor @Test func seekAndReplacementCancelThePreviousSongTransition() async throws {
        let first = ParsedLyrics(lines: [LyricLine(id: 0, time: 0.05, text: "旧歌")])
        let replacement = ParsedLyrics(lines: [LyricLine(id: 0, time: 10, text: "新歌")])
        let cursor = LyricsCursor()
        cursor.synchronize(lyrics: first, at: 0, playing: true)
        cursor.synchronize(lyrics: replacement, at: 9, playing: false)
        cursor.seekRevision &+= 1
        try await Task.sleep(for: .milliseconds(100))
        #expect(cursor.activeIndex == nil)
        #expect(cursor.playbackTime == 9)
        cursor.synchronize(lyrics: replacement, at: 10, playing: false)
        #expect(cursor.activeIndex == 0)
        cursor.synchronize(lyrics: replacement, at: 0, playing: false)
        #expect(cursor.activeIndex == nil)
    }
}
