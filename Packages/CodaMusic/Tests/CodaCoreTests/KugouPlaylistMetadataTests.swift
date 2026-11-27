import Foundation
import Testing
@testable import CodaCore

@Suite("Kugou cloud playlist metadata")
struct KugouPlaylistMetadataTests {
    @Test func cloudDisplayNameSeparatesArtistAndTitleAndKeepsAlbum() throws {
        let song = try #require(KugouMusicAPI.mapCloudPlaylistTrack([
            "hash": "fixture-hash", "name": "周杰伦 - 七日的极光",
            "albuminfo": ["name": "太阳之子"], "timelen": 193
        ]))
        #expect(song.name == "七日的极光")
        #expect(song.artists == "周杰伦")
        #expect(song.album == "太阳之子")
        #expect(song.duration == 193)
        #expect(song.kugouHash == "fixture-hash")
    }

    @Test func filenameFallbackPreservesMultipleArtistsAndDashesInTitle() throws {
        let song = try #require(KugouMusicAPI.mapCloudPlaylistTrack([
            "hash": "fixture-hash", "name": "连麻Swimming、JinJiBeWater_隼 - 数钱的女孩 - Live",
            "singername": "", "filename": "", "album_name": "真假美猴王 (Explicit)"
        ]))
        #expect(song.name == "数钱的女孩 - Live")
        #expect(song.artists == "连麻Swimming、JinJiBeWater_隼")
        #expect(song.album == "真假美猴王 (Explicit)")
    }

    @Test func structuredMetadataWinsOverDisplayFilename() throws {
        let song = try #require(KugouMusicAPI.mapCloudPlaylistTrack([
            "hash": "fixture-hash", "name": "旧歌手 - 旧标题", "songname": "Two - Worlds",
            "singerinfo": [["name": "Layla"], ["name": "Guest"]],
            "album_name": "Quiet Organism", "albuminfo": ["name": "旧专辑"]
        ]))
        #expect(song.name == "Two - Worlds")
        #expect(song.artists == "Layla / Guest")
        #expect(song.album == "Quiet Organism")
    }

    @Test func standaloneNameWithoutSeparatorRemainsIntact() throws {
        let song = try #require(KugouMusicAPI.mapCloudPlaylistTrack([
            "hash": "fixture-hash", "name": "Only One", "singername": "Alex Band", "albumname": "Alex Band"
        ]))
        #expect(song.name == "Only One")
        #expect(song.artists == "Alex Band")
        #expect(song.album == "Alex Band")
    }
}

private final class KugouCollectedTracksFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try #require(request.url)
            #expect(url.path == "/pubsongs/v2/get_other_list_file_nofilt")
            #expect(request.httpMethod == "GET")
            let query = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let globalID = try #require(query["global_collection_id"])
            #expect(globalID != "collection_3_fixture-owner_29_0")
            let response: [String: Any]
            if globalID == "collection_error" {
                response = ["status": 0, "error_code": 30203, "data": [:]]
            } else {
                #expect(globalID == "collection_3_1049244401_2005_0")
                let start = Int(query["begin_idx"] ?? "") ?? -1
                #expect(start == 0 || start == 30)
                let indices = start == 0 ? Array(0..<30) : [30]
                let songs: [[String: Any]] = indices.map {
                    ["hash": "hash-\($0)", "name": "Artist - Song \($0)", "timelen": 247040,
                     "albuminfo": ["name": "Album"], "album_id": "965221", "mixsongid": 32086078 + $0]
                }
                response = ["status": 1, "error_code": 0, "data": ["count": 31, "songs": songs,
                    "list_info": ["musiclib_tags": [["name": "Not a song"]]]]]
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: response))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension KugouPlaylistMetadataTests {
    private func collectedPlaylist() -> ProviderPlaylist {
        var item = ProviderPlaylist(id: 29, name: "Collected", coverURL: nil, trackCount: 31, source: .kugou)
        item.ownerID = "fixture-owner"
        item.isOwned = false
        item.isSubscribed = true
        item.kugouGlobalCollectionID = "collection_3_fixture-owner_29_0"
        item.kugouCreateGID = "collection_3_1049244401_2005_0"
        return item
    }

    @Test func collectedTracksUseOriginalPublicIDAndReadEveryPage() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KugouCollectedTracksFixture.self]
        let api = KugouMusicAPI(configuration: config, playlistCredentials: ["userid": "fixture-owner"])
        let tracks = try await api.playlistSongs(playlist: collectedPlaylist())
        #expect(tracks.count == 31)
        #expect(tracks.first?.name == "Song 0")
        #expect(tracks.last?.name == "Song 30")
        #expect(tracks.first?.artists == "Artist")
        #expect(tracks.first?.duration == 247.04)
    }

    @Test func missingSourceAndServerErrorsDoNotBecomeEmptyCollections() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KugouCollectedTracksFixture.self]
        let api = KugouMusicAPI(configuration: config, playlistCredentials: ["userid": "fixture-owner"])
        var item = collectedPlaylist()
        item.kugouCreateGID = nil
        #expect(KugouMusicAPI.collectionTrackID(item) == nil)
        await #expect(throws: Error.self) { try await api.playlistSongs(playlist: item) }
        item.kugouCreateGID = "collection_error"
        await #expect(throws: Error.self) { try await api.playlistSongs(playlist: item) }
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_LIVE_COLLECTION_READ"] == "1"))
    func liveCollectedPlaylistReturnsActualTracksWithoutWritingToTheAccount() async throws {
        let api = KugouMusicAPI(playlistCredentials: ["userid": "fixture-owner"])
        let tracks = try await api.playlistSongs(playlist: collectedPlaylist())
        #expect(tracks.count == 31)
        #expect(tracks.first?.kugouHash?.uppercased() == "24E89719264E73D48C1C26AC2A47C5F5")
        #expect(tracks.first?.name.contains("For The Love Of God") == true)
    }
}
