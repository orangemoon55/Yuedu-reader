import Foundation
import Testing
@testable import CodaCore

@Suite("Kugou served playback quality")
struct KugouPlaybackQualityTests {
    @Test func cloudAndSearchCollaboratorSeparatorsMatch() {
        #expect(KugouMusicAPI.playbackArtistsMatch("G-DRAGON / 김종완 of NELL", "G-DRAGON、김종완 of NELL"))
        #expect(!KugouMusicAPI.playbackArtistsMatch("G-DRAGON / 김종완 of NELL", "G-DRAGON"))
        #expect(!KugouMusicAPI.playbackArtistsMatch("G-DRAGON", ""))
    }

    @Test func returnedEncodingTakesPrecedenceOverRequestedOrEchoedQuality() {
        #expect(KugouMusicAPI.playbackQuality(in: ["quality": "high", "extName": "mp3", "bitRate": 128000]) == .standard)
        #expect(KugouMusicAPI.playbackQuality(in: ["data": ["extName": "mp3", "bitrate": "320"]]) == .exhigh)
        #expect(KugouMusicAPI.playbackQuality(in: ["extName": "flac", "bitRate": 900000]) == .lossless)
        #expect(KugouMusicAPI.playbackQuality(in: ["extName": "flac", "sample_rate": 96000, "bit_depth": 24]) == .hires)
        #expect(KugouMusicAPI.playbackQuality(in: ["extName": "flac", "quality": "high", "sample_rate": 44100, "bit_depth": 16]) == .lossless)
        #expect(KugouMusicAPI.playbackQuality(in: ["url": "https://fixture.invalid/unknown"]) == nil)
    }

    @Test func playbackURLSkipsEmptyAndInvalidFieldsInStableOrder() {
        #expect(KugouMusicAPI.playbackURL(in: ["url": [], "backup_url": ["", "https://audio.example/song.flac"]]) == "https://audio.example/song.flac")
        #expect(KugouMusicAPI.playbackURL(in: ["data": ["play_url": "https://audio.example/primary", "url": ["https://audio.example/secondary"]]]) == "https://audio.example/primary")
        #expect(KugouMusicAPI.playbackURL(in: ["url": ["invalid", "https://audio.example/valid"]]) == "https://audio.example/valid")
    }

    @Test func standardHashDoesNotMasqueradeAsHighQualityMetadata() throws {
        let song = try #require(KugouMusicAPI.mapCloudPlaylistTrack(["hash": "standard-hash", "songname": "Song"]))
        #expect(song.kugouQualityHashes?["standard"] == "standard-hash")
        #expect(song.kugouQualityHashes?["lossless"] == nil)
        #expect(song.kugouQualityHashes?["hires"] == nil)
    }

    @Test func serviceQualityWordingIsPreservedAndEncodingIsUsedWhenNoNameExists() {
        #expect(AudioQualityOption.responseTitle(name: "接口原名 · SQ", format: "flac", bitrate: 900000, fallback: "lossless") == "接口原名 · SQ")
        #expect(AudioQualityOption.responseTitle(name: nil, format: "mp3", bitrate: 320000, fallback: "exhigh") == "mp3 · 320 kbps")
        #expect(AudioQualityOption.responseTitle(name: nil, fallback: "hr") == "hr")
    }

    @Test func legacyRepeatedHashDoesNotCreateFourSelectableQualities() {
        let song = ProviderSong(id: 1, name: "Fixture", artists: "Singer", album: "", coverURL: nil, duration: 277,
            source: .kugou, kugouHash: "standard", kugouQualityHashes: ["standard": "standard", "exhigh": "standard", "lossless": "standard", "hires": "standard"])
        #expect(KugouMusicAPI.hasAliasedQualityHashes(song.kugouQualityHashes))
        #expect(KugouMusicAPI.metadataQualities(song) == [.standard])
    }

    @MainActor @Test func kugouCDNSchemeIsPreservedForPlaybackSwitchingAndPrefetch() throws {
        let song = ProviderSong(id: 1, name: "Fixture", artists: "Singer", album: "", coverURL: nil, duration: 277, source: .kugou, kugouHash: "hash")
        let bytes = try JSONEncoder().encode(song)
        let track = try PlatformMusicAPI.decode(Track.self, ["id": -1, "name": "Fixture", "platformSong": try JSONSerialization.jsonObject(with: bytes)])
        #expect(track.remotePlaybackURL("http://fs.youthandroid2.kugou.com/audio.mp3")?.scheme == "http")
        #expect(track.remotePlaybackURL("https://audio.kugou.com/audio.flac")?.scheme == "https")
        #expect(track.remotePlaybackURL("file:///tmp/audio.mp3") == nil)
    }

}
