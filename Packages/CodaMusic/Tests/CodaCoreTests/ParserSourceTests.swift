import Foundation
import Testing
@testable import CodaCore

@Suite("Parser source tests")
struct ParserSourceTests {
    private let query = UnblockQuery(origin: .netease, title: "晴天", artists: ["周杰伦"],
                                     album: "叶惠美", durationMS: 269_000, neteaseID: 186016)

    private func answer(_ json: String) -> ParserUnblockSource.Answer? {
        ParserUnblockSource.Answer(Data(json.utf8))
    }

    @Test func isAMirrorTriedBeforeThePlatforms() {
        #expect(AudioSourceID.parser.isMirror)
        #expect(AudioSourceID.mirror.isMirror)
        #expect(!AudioSourceID.qq.isMirror)
        #expect(AudioSourceID.parser.displayName == "备用音源")
        #expect(AudioSourceID(rawValue: "parser") == .parser)
    }

    @Test func qishuiRefusalsFallBackToOtherSources() {
        #expect(QishuiError.previewOnly.invitesUnblock)
        #expect(QishuiError.unavailable.invitesUnblock)
        #expect(!QishuiError.expiredLogin.invitesUnblock)
        #expect(!QishuiError.signerFailed.invitesUnblock)
        #expect(!QishuiError.encryptedAudio.invitesUnblock)
    }

    @Test func neverAsksForTheHiResPreview() {
        #expect(ParserUnblockSource.level(for: .standard) == "standard")
        #expect(ParserUnblockSource.level(for: .higher) == "exhigh")
        #expect(ParserUnblockSource.level(for: .exhigh) == "exhigh")
        #expect(ParserUnblockSource.level(for: .lossless) == "lossless")
        #expect(ParserUnblockSource.level(for: .hires) == "lossless")
        #expect(ParserUnblockSource.level(for: .jymaster) == "lossless")
    }

    @Test func parsesDurationAndSize() {
        #expect(ParserUnblockSource.Answer.durationMS("4分29秒") == 269_000)
        #expect(ParserUnblockSource.Answer.durationMS("1时2分3秒") == 3_723_000)
        #expect(ParserUnblockSource.Answer.durationMS("") == nil)
        #expect(ParserUnblockSource.Answer.byteCount("52.83 MB") == 52.83 * 1024 * 1024)
        #expect(ParserUnblockSource.Answer.byteCount("512 KB") == 524_288.0)
        #expect(ParserUnblockSource.Answer.byteCount("0B") == nil)
    }

    @Test func acceptsTheSameRecordingFromAnotherPlatform() throws {
        let parsed = try #require(answer("""
        {"code":200,"msg":"换源成功，换源度100%","data":{"rid":"186016","name":"晴天","artist":"周杰伦",
        "album":"叶惠美","quality":"无损音质 FLAC","duration":"4分29秒","size":"52.83 MB",
        "url":"https://car-er.kuwo.cn/x/F000000bYDlc2XxKLs.flac"}}
        """))
        let candidate = try #require(parsed.candidate(for: query))
        #expect(candidate.url.hasSuffix(".flac"))
        #expect(candidate.durationMS == 269_000)
    }

    @Test func rejectsMissesAndOtherRecordings() throws {
        #expect(answer(#"{"code":404,"msg":"歌曲不存在","data":null}"#)?.candidate(for: query) == nil)
        let live = try #require(answer("""
        {"code":200,"data":{"name":"晴天 (Live)","artist":"周杰伦","duration":"4分29秒","url":"https://a/b.mp3"}}
        """))
        #expect(live.candidate(for: query) == nil)
        let otherArtist = try #require(answer("""
        {"code":200,"data":{"name":"晴天","artist":"某翻唱","duration":"4分29秒","url":"https://a/b.mp3"}}
        """))
        #expect(otherArtist.candidate(for: query) == nil)
        let noURL = try #require(answer(#"{"code":200,"data":{"name":"晴天","artist":"周杰伦","duration":"4分29秒","url":""}}"#))
        #expect(noURL.candidate(for: query) == nil)
        #expect(answer("<html>404</html>") == nil)
    }

    @Test func kugouAnswersWithoutDurationFallBackToTheQuery() throws {
        let parsed = try #require(answer("""
        {"code":200,"data":{"hash":"B3A5","name":"晴天","artist":"周杰伦","size":"10.29 MB","url":"https://a/b.mp3"}}
        """))
        #expect(parsed.candidate(for: query)?.durationMS == 269_000)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_UNBLOCK_LIVE"] == "1"))
    func liveResolvesAGrayNeteaseTrack() async throws {
        let source = ParserUnblockSource()
        let stream = try #require(try await source.resolve(query, quality: .lossless))
        print("live parser host=\(stream.url.host ?? "") quality=\(stream.quality?.rawValue ?? "nil") title=\(stream.title ?? "")")
        #expect(stream.quality == .lossless || stream.quality == .hires)
        let tiers = try await source.qualityOptions(query)
        print("live parser tiers=\(tiers.map(\.title))")
        #expect(tiers.count > 1)
    }
}
