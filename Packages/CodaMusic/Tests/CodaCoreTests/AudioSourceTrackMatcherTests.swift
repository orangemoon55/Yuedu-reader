import Foundation
import Testing
@testable import CodaCore

@Suite("Audio source track matcher tests")
struct AudioSourceTrackMatcherTests {
    private let query = UnblockQuery(origin: .qq, title: "Blue Moon (Live)", artists: ["Example Artist"],
                                     album: "Album", durationMS: 180_000)

    @Test func acceptsMatchingTitleArtistAndDuration() {
        #expect(score(title: "Blue Moon - Live", artist: "Example Artist / Guest", durationMS: 183_000) != nil)
    }

    @Test func rejectsWrongArtistVersionOrDuration() {
        #expect(score(title: "Blue Moon (Live)", artist: "Another Artist") == nil)
        #expect(score(title: "Blue Moon (Remix)", artist: "Example Artist") == nil)
        #expect(score(title: "Blue Moon (Live)", artist: "Example Artist", durationMS: 186_000) == nil)
        #expect(score(title: "Blue Moon (Live)", artist: "Example Artist", durationMS: 0) == nil)
    }

    @Test func ignoresBracketedAnnotationsButKeepsVersions() {
        let plain = UnblockQuery(origin: .netease, title: "晴天", artists: ["周杰伦"], album: "", durationMS: 269_000)
        #expect(AudioSourceTrackMatcher.score(plain, candidate("晴天 (电影《不能说的秘密》插曲)", "周杰伦", 269_000)) != nil)
        #expect(AudioSourceTrackMatcher.score(plain, candidate("晴天 (Live)", "周杰伦", 269_000)) == nil)
        #expect(AudioSourceTrackMatcher.score(plain, candidate("晴天 (伴奏)", "周杰伦", 269_000)) == nil)
    }

    @Test func prefersTheClosestCandidate() {
        let candidates = [
            UnblockCandidate(title: "Blue Moon (Live)", artist: "Example Artist", album: "Other", durationMS: 184_000, payload: 1),
            UnblockCandidate(title: "Blue Moon (Live)", artist: "Example Artist", album: "Album", durationMS: 180_200, payload: 2),
            UnblockCandidate(title: "Blue Moon (Live)", artist: "Someone Else", album: "Album", durationMS: 180_000, payload: 3),
        ]
        #expect(AudioSourceTrackMatcher.best(query, in: candidates) == 2)
    }

    @Test func onlyLooksAtTheTopResults() {
        let misses = (0..<AudioSourceTrackMatcher.candidateLimit).map {
            UnblockCandidate(title: "Other \($0)", artist: "Example Artist", album: "", durationMS: 180_000, payload: $0)
        }
        let late = UnblockCandidate(title: "Blue Moon (Live)", artist: "Example Artist", album: "", durationMS: 180_000, payload: 99)
        #expect(AudioSourceTrackMatcher.best(query, in: misses + [late]) == nil)
    }

    @Test func sourcesMapToPlatforms() {
        #expect(AudioSourceID(platform: .kugou) == .kugou)
        #expect(AudioSourceID.mirror.platform == nil)
        #expect(!AudioSourceID.allCases.map(\.rawValue).contains("kuwo"))
    }

    @Test func mirrorRequestsTheTierThePlayerWants() async {
        #expect(MirrorUnblockSource.requestedBitrate(for: .standard) == 128)
        #expect(MirrorUnblockSource.requestedBitrate(for: .exhigh) == 320)
        #expect(MirrorUnblockSource.requestedBitrate(for: .lossless) == 999)
        #expect(MirrorUnblockSource.requestedBitrate(for: .jymaster) == 999)
        #expect(await MirrorUnblockSource.tier(bitrateKbps: 128, address: "") == .standard)
        #expect(await MirrorUnblockSource.tier(bitrateKbps: 320, address: "") == .exhigh)
    }

    private func score(title: String, artist: String, durationMS: Int = 180_000) -> Int? {
        AudioSourceTrackMatcher.score(query, candidate(title, artist, durationMS))
    }

    private func candidate(_ title: String, _ artist: String, _ durationMS: Int) -> UnblockCandidate<Int> {
        UnblockCandidate(title: title, artist: artist, album: "", durationMS: durationMS, payload: 0)
    }
}
