import Foundation
import Testing
@testable import CodaCore

@Suite("Playlist artwork precedence")
struct PlaylistArtworkTests {
    private func summary(_ json: String) throws -> PlaylistSummary {
        try JSONDecoder().decode(PlaylistSummary.self, from: Data(json.utf8))
    }
    private func detail(_ json: String) throws -> PlaylistDetail {
        try JSONDecoder().decode(PlaylistDetail.self, from: Data(json.utf8))
    }

    @Test func ownCoverWinsOverFirstSong() throws {
        let playlist = try summary(#"{"id":1,"coverImgUrl":"https://example.com/own.jpg","tracks":[{"id":2,"al":{"picUrl":"https://example.com/song.jpg"}}]}"#)
        #expect(playlist.coverURL == "https://example.com/own.jpg")
        let restored = try JSONDecoder().decode(PlaylistSummary.self, from: JSONEncoder().encode(playlist))
        #expect(restored.coverURL == playlist.coverURL)
    }

    @Test func blankCoverDoesNotMaskAlternateField() throws {
        let playlist = try summary(#"{"id":1,"picUrl":"  ","coverImgUrl":"https://example.com/own.jpg"}"#)
        #expect(playlist.coverURL == "https://example.com/own.jpg")
        let alternate = try summary(#"{"id":1,"coverImgUrl":"","picUrl":"https://example.com/alternate.jpg"}"#)
        #expect(alternate.coverURL == "https://example.com/alternate.jpg")
    }

    @Test func missingOrInvalidCoverUsesFirstSong() throws {
        for cover in ["", "  ", "not-a-url"] {
            let playlist = try summary("{\"id\":1,\"coverImgUrl\":\"\(cover)\",\"tracks\":[{\"id\":2,\"album\":{\"picUrl\":\"https://example.com/first.jpg\"}},{\"id\":3,\"al\":{\"picUrl\":\"https://example.com/second.jpg\"}}]}")
            #expect(playlist.coverURL == "https://example.com/first.jpg")
        }
    }

    @Test func doesNotSubstituteLaterSongsForMissingFirstCover() throws {
        let playlist = try summary(#"{"id":1,"tracks":[{"id":2},{"id":3,"al":{"picUrl":"https://example.com/second.jpg"}}]}"#)
        #expect(playlist.coverURL == nil)
        #expect(try summary(#"{"id":1}"#).coverURL == nil)
    }

    @Test func detailUsesPlaylistOrderAndTracksChanges() throws {
        var playlist = try detail(#"{"id":1,"trackIds":[{"id":2},{"id":3}],"tracks":[{"id":3,"al":{"picUrl":"https://example.com/second.jpg"}},{"id":2,"al":{"picUrl":"https://example.com/first.jpg"}}]}"#)
        #expect(playlist.coverURL == "https://example.com/first.jpg")
        playlist.trackIds.removeFirst()
        #expect(playlist.coverURL == "https://example.com/second.jpg")
        playlist.trackIds = [TrackIDRef(id: 99)]
        #expect(playlist.coverURL == nil)
    }

    @Test func detailOwnCoverSurvivesMissingSongs() throws {
        let playlist = try detail(#"{"id":1,"coverImgUrl":"https://example.com/own.jpg","trackIds":[{"id":2}]}"#)
        #expect(playlist.coverURL == "https://example.com/own.jpg")
    }
}
