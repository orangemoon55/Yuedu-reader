import Foundation
import Testing
@testable import CodaCore

/// Titles, artists and instrumental flags as the catalogs actually return them.
@Suite struct LyricsIdentityTests {
    private func track(_ name: String, artist: String, artistID: Int = 0, album: String = "",
                       seconds: Double, alias: [String] = []) throws -> Track {
        let object: [String: Any] = ["id": 1, "name": name, "ar": [["id": artistID, "name": artist]],
                                     "al": ["id": 3, "name": album], "dt": Int(seconds * 1000), "alia": alias]
        return try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: object))
    }

    private func lyrics(_ lrc: String = "[00:10.00]第一句\n[00:20.00]第二句") throws -> LyricResponse {
        try AlternativeLyricsAPI.response(lrc: lrc)
    }

    @Test func annotationsDoNotChangeIdentityButVersionTagsDo() throws {
        let river = try track("River Flows in You", artist: "Yiruma", seconds: 214.7)
        #expect(LyricsMatching.titleMatch("River Flows in You (你的心河)", track: river) != nil)
        let summer = try track("Summer", artist: "久石譲", seconds: 384)
        #expect(LyricsMatching.titleMatch("Summer (映画「菊次郎の夏」より)", track: summer) != nil)
        #expect(LyricsMatching.titleMatch("Summer　（「菊次郎の夏」より）", track: summer) != nil)
        #expect(LyricsMatching.titleMatch("Summer（Cover 久石让）", track: summer) == nil)

        let sunny = try track("晴天", artist: "周杰伦", seconds: 269)
        #expect(LyricsMatching.titleMatch("晴天 - 电影《不能说的秘密》插曲", track: sunny) != nil)
        #expect(LyricsMatching.titleMatch("晴天 (feat. 某人)", track: sunny) != nil)
        for version in ["晴天 (Live)", "晴天 (伴奏)", "晴天 (Remix)", "晴天 - DJ版", "晴天 (粤语版)",
                        "晴天 (钢琴版)", "晴天 (女声版)", "晴天 (0.8x)", "晴天 (Inst.)"] {
            #expect(LyricsMatching.titleMatch(version, track: sunny) == nil, "\(version)")
        }
        #expect(LyricsMatching.titleMatch("晴天 (2019 Remaster)", track: sunny) != nil)

        let live = try track("出现又离开 (Live)", artist: "梁博", seconds: 404)
        #expect(LyricsMatching.titleMatch("出现又离开(live)", track: live) != nil)
        #expect(LyricsMatching.titleMatch("出现又离开 - Live", track: live) != nil)
        #expect(LyricsMatching.titleMatch("出现又离开 (2019我是唱作人第2期现场)", track: live) != nil)
        // Lyric catalogs drop "(Live)"; only a near-identical length proves it.
        func untagged(_ seconds: Double) -> Double? {
            LyricsMatching.metadataScore(title: "出现又离开", artists: ["梁博"], album: nil, duration: seconds, track: live)
        }
        #expect(untagged(404.2) != nil)
        #expect(untagged(410) == nil)
        #expect(untagged(0) == nil, "no duration, no proof")
        let tagged = try #require(LyricsMatching.metadataScore(title: "出现又离开 (Live)", artists: ["梁博"],
                                                              album: nil, duration: 404.2, track: live))
        #expect(tagged > (untagged(404.2) ?? .infinity))
        // A Live title never names a studio track, and 伴奏 is never implied.
        #expect(LyricsMatching.metadataScore(title: "晴天 (Live)", artists: ["周杰伦"], album: nil,
                                             duration: 269, track: sunny) == nil)
        let accompaniment = try track("晴天 (伴奏)", artist: "周杰伦", seconds: 269)
        #expect(LyricsMatching.titleMatch("晴天", track: accompaniment) == nil)
    }

    @Test func searchKeywordDropsBracketsAndUsesChineseScript() throws {
        #expect(LyricsTitle.searchKeyword(for: try track("Summer", artist: "久石譲", seconds: 384)) == "Summer 久石让")
        #expect(LyricsTitle.searchKeyword(for: try track("出现又离开 (Live)", artist: "梁博", seconds: 404)) == "出现又离开 梁博")
        #expect(LyricsTitle.searchKeyword(for: try track("晴天 - 电影版", artist: "周杰伦", seconds: 269)) == "晴天 周杰伦")
    }

    @Test func translatedTitleAndCatalogAliasNameTheSameSong() throws {
        let translated = try track("你的心河", artist: "Yiruma", seconds: 214.7)
        #expect(LyricsMatching.titleMatch("River Flows in You (你的心河)", track: translated) != nil)
        let aliased = try track("River Flows in You", artist: "Yiruma", seconds: 214.7, alias: ["你的心河"])
        #expect(LyricsMatching.titleMatch("你的心河", track: aliased) != nil)
        // An annotation alone never outranks an exact title.
        let exact = try #require(LyricsMatching.metadataScore(title: "你的心河", artists: ["Yiruma"], album: nil,
                                                             duration: 214.7, track: translated))
        let viaAnnotation = try #require(LyricsMatching.metadataScore(title: "River Flows in You (你的心河)",
                                                                     artists: ["Yiruma"], album: nil, duration: 214.7, track: translated))
        #expect(exact > viaAnnotation)
    }

    @Test func artistsMatchAcrossScriptsAndCatalogAliases() throws {
        let summer = try track("Summer", artist: "久石譲", seconds: 386)
        #expect(LyricsMatching.metadataScore(title: "Summer (映画「菊次郎の夏」より)", artists: ["久石让"],
                                             album: nil, duration: 386, track: summer) != nil)

        let river = try track("River Flows in You", artist: "Yiruma", artistID: 990_001, seconds: 218)
        #expect(!LyricsMatching.artistMatches(["李闰珉"], track: river))
        LyricsArtistAliases.shared.store(["이루마", "李闰珉"], for: 990_001)
        #expect(LyricsMatching.artistMatches(["李闰珉"], track: river))
        #expect(LyricsMatching.metadataScore(title: "River Flows in You (你的心河)", artists: ["李闰珉"],
                                             album: nil, duration: 218, track: river) != nil)
    }

    @Test func aliasesLoadOnlyForNeteaseCatalogTracksAndOnce() async throws {
        let river = try track("River Flows in You", artist: "Yiruma", artistID: 990_002, seconds: 218)
        let calls = Counter()
        let loader: @Sendable (Int) async throws -> [String] = { _ in await calls.increment(); return ["李闰珉"] }
        await LyricsArtistAliases.shared.load(for: river, loader: loader)
        await LyricsArtistAliases.shared.load(for: river, loader: loader)
        #expect(await calls.value == 1)
        #expect(LyricsMatching.artistMatches(["李闰珉"], track: river))
    }

    @Test func differentArtistIsAcceptedOnlyForNearIdenticalInstrumentals() throws {
        let river = try track("River Flows in You", artist: "Yiruma", album: "The Best", seconds: 214.7)
        func score(_ instrumental: Bool?, album: String? = nil, duration: Double = 215.5) -> Double? {
            LyricsMatching.metadataScore(title: "River Flows in You", artists: ["某个别名"], album: album,
                                         duration: duration, track: river, instrumental: instrumental)
        }
        #expect(score(true) != nil)
        #expect(score(nil) != nil, "pre-filter keeps it until lyrics are known")
        #expect(score(false) == nil, "sung lyrics by another artist is a cover")
        #expect(score(false, album: "The Best") == nil, "covers reuse album names too")
        #expect(score(true, duration: 218) == nil, "more than two seconds apart")
        let named = try #require(LyricsMatching.metadataScore(title: "River Flows in You", artists: ["Yiruma"],
                                                             album: nil, duration: 215.5, track: river))
        #expect(named > (score(true) ?? .infinity))
    }

    @Test func eachPlatformInstrumentalSignalBecomesPureMusic() throws {
        let qq = try AlternativeLyricsAPI.qqLyricsResponse(
            ["lyric": "[00:00:00]此歌曲为没有填词的纯音乐，请您欣赏", "trans": ""], base64Encoded: false)
        #expect(qq.pureMusic == true)
        #expect(LyricsParser.parse(qq).isInstrumental)
        #expect(LyricsParser.parse(qq).lines.isEmpty)
        #expect(AlternativeLyricsAPI.isQQInstrumental("[00:00.00]纯音乐，请欣赏"))
        #expect(!AlternativeLyricsAPI.isQQInstrumental("[00:10.00]第一句\n[00:20.00]第二句"))
        #expect(LyricsParser.parse(AlternativeLyricsAPI.instrumentalResponse()).isInstrumental)
    }

    @Test func instrumentalVoteFollowsTheCatalogThenRealLyrics() throws {
        let river = try track("River Flows in You", artist: "Yiruma", seconds: 214.7)
        let pure = AlternativeLyricsAPI.instrumentalResponse()
        func candidate(_ source: LyricsSource, _ response: LyricResponse, byID: Bool = false) -> LyricsCandidate {
            LyricsCandidate(source: source, id: source.rawValue, title: "River Flows in You", artists: ["Yiruma"],
                            album: nil, duration: 214.7, response: response, matchedByID: byID)
        }
        // Any platform's flag counts: QQ alone settles it.
        #expect(LyricsMatching.best([candidate(.qqMusic, pure)], for: river)?.source == .qqMusic)
        // Without the catalog's own word, real lyrics outvote a flag.
        let mixed = LyricsMatching.best([candidate(.qqMusic, pure), candidate(.lrclib, try lyrics())], for: river)
        #expect(mixed?.source == .lrclib)
        // The track's own catalog decides, whichever platform that is.
        let native = LyricsMatching.best([candidate(.kugou, pure, byID: true), candidate(.lrclib, try lyrics())], for: river)
        #expect(native?.source == .kugou)
        #expect(native.map { LyricsParser.parse($0.response).isInstrumental } == true)
    }

    @Test func idMatchedCandidatesNeedNoTitleMatch() throws {
        let live = try track("出现又离开 (Live)", artist: "梁博", seconds: 404)
        let byID = LyricsCandidate(source: .kugou, id: "1", title: "别的歌", artists: ["梁博"], album: nil,
                                   duration: 404, response: try lyrics(), matchedByID: true)
        let bySearch = LyricsCandidate(source: .kugou, id: "2", title: "别的歌", artists: ["梁博"], album: nil,
                                       duration: 404, response: try lyrics())
        #expect(LyricsMatching.score(byID, for: live) != nil)
        #expect(LyricsMatching.score(bySearch, for: live) == nil)
    }
}

private actor Counter {
    private(set) var value = 0
    func increment() { value += 1 }
}
