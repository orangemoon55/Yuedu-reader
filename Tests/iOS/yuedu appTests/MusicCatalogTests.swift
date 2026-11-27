import Foundation
import Testing
@testable import yuedu_app

struct MusicCatalogTests {
    @Test func parsesRealShapedSongAndPlaylistMetadata() throws {
        let song = #"{"code":200,"result":{"songCount":1,"songs":[{"id":123,"name":"Fixture Song","dt":90000,"ar":[{"name":"Fixture Artist"}],"al":{"name":"Fixture Album","picUrl":"https://p1.music.126.net/a.jpg"}}]}}"#
        let tracks = try MusicCatalogParser.search(Data(song.utf8), kind: .song)
        #expect(tracks.count == 1)
        #expect(tracks[0].track?.title == "Fixture Song")
        #expect(tracks[0].track?.durationMilliseconds == 90_000)
        #expect(tracks[0].track?.poster == "https://p1.music.126.net/a.jpg")
        let playlists = #"{"code":200,"playlists":[{"id":7,"name":"Public list","creator":{"nickname":"Author"},"coverImgUrl":"http://p1.music.126.net/list.jpg"}]}"#
        let entries = try MusicCatalogParser.collection(Data(playlists.utf8), key: "playlists")
        #expect(entries.first?.subtitle == "Author")
        #expect(entries.first?.poster == "https://p1.music.126.net/list.jpg")
    }

    @Test func rejectsUnsupportedDataUnsafeArtworkAndLoginFailure() throws {
        #expect(throws: MusicCatalogError.self) { try MusicCatalogParser.root(Data(repeating: 0, count: MusicCatalogParser.bodyLimit + 1)) }
        #expect(throws: MusicCatalogError.rejected(301)) { try MusicCatalogParser.root(Data(#"{"code":301}"#.utf8)) }
        #expect(MusicCatalogParser.artwork("https://user:pass@p1.music.126.net/a.jpg") == "")
        #expect(MusicCatalogParser.artwork("https://p1.music.126.net/a.jpg?token=1") == "")
        let result = #"{"code":200,"result":{"songCount":0,"songs":[]}}"#
        #expect(try MusicCatalogParser.search(Data(result.utf8), kind: .song).isEmpty)
    }

    @Test func neteaseTrackOnlyMapsToAnActualWyResolver() throws {
        let track = MusicCatalogTrack(identifier: "123", title: "Fixture", artist: "Artist", album: "Album",
                                      poster: "", durationMilliseconds: 15_000)
        let wy = MusicJSSource(id: "fixture", name: "Fixture", version: "1", providers: [
            MusicJSProvider(id: "wy", name: "NetEase resolver", actions: ["musicUrl"], qualities: ["128k"])
        ])
        let mapped = try MusicCatalogResolverMapping.song(track, source: wy, providerID: "wy")
        #expect(mapped.provider == "wy")
        #expect(mapped.musicInfoJSON.contains("\"source\":\"wy\""))
        let tx = MusicJSSource(id: "fixture", name: "Fixture", version: "1", providers: [
            MusicJSProvider(id: "tx", name: "QQ", actions: ["musicUrl"], qualities: ["128k"])
        ])
        #expect(throws: MusicCatalogError.unsupportedResolver) {
            try MusicCatalogResolverMapping.song(track, source: tx, providerID: "tx")
        }
    }

    @Test func homeRailsShowCatalogOriginAndPreservePlaylistCreator() {
        let playlist = MusicCatalogEntry(identifier: "7", kind: .playlist, title: "Fixture list",
                                         subtitle: "Fixture creator", poster: "", track: nil)
        #expect(MusicHomePresentation.catalogCaption(for: playlist, showingOrigin: true) == localized("网易云音乐"))
        #expect(MusicHomePresentation.catalogCaption(for: playlist, showingOrigin: false) == "Fixture creator")
        let anonymous = MusicCatalogEntry(identifier: "8", kind: .playlist, title: "Fixture list",
                                          subtitle: " \n ", poster: "", track: nil)
        #expect(MusicHomePresentation.catalogCaption(for: anonymous, showingOrigin: false) == localized("网易云音乐"))
    }

    @Test func continuationOnlyUsesRealMusicPlayerState() {
        #expect(MusicHomePresentation.continuation(currentTrack: nil) == nil)
        let music = MediaHubLibraryItem(sourceID: "fixture", siteKey: "site", videoID: "music", title: "Fixture track",
                                       poster: "", kind: .music, siteName: "fixture")
        #expect(MusicHomePresentation.continuation(currentTrack: music)?.id == music.id)
        #expect(MusicHomePresentation.time(.nan) == "0:00")
        #expect(MusicHomePresentation.time(.infinity) == "0:00")
        #expect(MusicHomePresentation.time(-1) == "0:00")
        #expect(MusicHomePresentation.time(86_400_000) == "0:00")
        #expect(MusicHomePresentation.time(61) == "1:01")
    }
}
