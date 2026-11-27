import CryptoKit
import Foundation
import Testing
@testable import CodaCore

@Suite("Kugou playlist writes")
struct KugouPlaylistMutationTests {
    @Test func cloudOwnershipKeepsCollectedListsOutOfWritablePlaylists() throws {
        let owned = try #require(KugouMusicAPI.mapPlaylist([
            "listid": 12, "name": "Created", "type": 0
        ], accountUserID: "100"))
        let collected = try #require(KugouMusicAPI.mapPlaylist([
            "listid": 13, "name": "Collected", "type": 1,
            "list_create_userid": 200, "list_create_listid": 12,
            "global_collection_id": "gcid_fixture", "list_create_gid": "source-gid"
        ], accountUserID: "100"))
        #expect(owned.isOwned == true)
        #expect(owned.isSubscribed == false)
        #expect(collected.id == 13)
        #expect(collected.ownerID == "100")
        #expect(collected.isOwned == false)
        #expect(collected.isSubscribed == true)
        #expect(collected.kugouCreateUserID == "200")
        #expect(collected.kugouCreateListID == "12")
        #expect(collected.kugouGlobalCollectionID == "gcid_fixture")
        #expect(collected.kugouCreateGID == "source-gid")
    }

    @Test func addingSongsUsesRecordingIdentifiersRatherThanSyntheticTrackIDs() throws {
        let song = ProviderSong(id: -123, name: "Title, with | punctuation", artists: "Singer", album: "Album", coverURL: nil,
                             duration: 200, source: .kugou, kugouHash: "HASH", kugouAlbumAudioId: "477417208", kugouAlbumId: "67026620")
        let resource = try KugouMusicAPI.playlistSongResource(song)
        #expect(resource["hash"] as? String == "HASH")
        #expect(resource["name"] as? String == "Singer - Title, with | punctuation")
        #expect(resource["album_id"] as? Int == 67026620)
        #expect(resource["mixsongid"] as? Int == 477417208)
        #expect(throws: (any Error).self) {
            try KugouMusicAPI.playlistSongResource(ProviderSong(id: 1, name: "Other", artists: "", album: "", coverURL: nil, duration: 0))
        }
    }

    @Test func businessFailuresAndEmptyResponsesAreNeverReportedAsSuccess() throws {
        try KugouMusicAPI.validatePlaylistMutation(["status": 1, "error_code": 0])
        for response: [String: Any] in [[:], ["status": 0, "error_code": 0], ["status": 1, "error_code": 20001, "error_msg": "登录失效"]] {
            #expect(throws: (any Error).self) { try KugouMusicAPI.validatePlaylistMutation(response) }
        }
    }

    @Test @MainActor func capabilitiesExposeOnlyImplementedWrites() {
        #expect(MusicProvider.kugou.supports(.playlistCreation))
        #expect(MusicProvider.kugou.supports(.playlistDeletion))
        #expect(MusicProvider.kugou.supports(.playlistTrackAddition))
        #expect(MusicProvider.kugou.supports(.playlistSubscriptions))
        #expect(MusicProvider.kugou.supports(.playlistChanges))
        #expect(MusicProvider.qq.supports(.playlistTrackAddition))
    }

    @Test @MainActor func pendingPlaylistDisappearsWhenCloudReturnsItsRealID() {
        var item = ProviderPlaylist(id: 12, name: "Created", coverURL: nil, source: .kugou)
        item.ownerID = "100"
        let key = PlatformMusicAPI.identifier(provider: .kugou, kind: "playlist", value: "12")
        let result = PlatformMusicAPI.mergePendingPlaylists(remote: [item], pending: [key: item], ownerID: "100")
        #expect(result.visible.count == 1)
        #expect(result.remaining.isEmpty)
    }
}

private final class KugouPlaylistWriteFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try #require(request.url)
            var params = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            let signature = params.removeValue(forKey: "signature")
            #expect(params["appid"] == "3116")
            #expect(params["clientver"] == "11440")
            #expect(params["userid"] == "123")
            #expect(params["token"] == "fixture-token")
            let registration = url.path == "/risk/v2/r_register_dev"
            #expect(params["dfid"] == (registration ? "-" : "fixture-dfid"))
            #expect(params["mid"] == "fixture-mid")
            #expect(request.value(forHTTPHeaderField: "x-router") == (registration ? "userservice.kugou.com" : "cloudlist.service.kugou.com"))
            #expect(request.value(forHTTPHeaderField: "dfid") == params["dfid"])
            #expect(request.value(forHTTPHeaderField: "clienttime") == params["clienttime"])
            #expect(request.httpMethod == "POST")
            var body = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }
                    body.append(contentsOf: buffer.prefix(count))
                }
            }
            let salt = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
            let signedText = salt + params.keys.sorted().map { "\($0)=\(params[$0]!)" }.joined() + String(decoding: body, as: UTF8.self) + salt
            let expected = Insecure.MD5.hash(data: Data(signedText.utf8)).map { String(format: "%02x", $0) }.joined()
            #expect(signature == expected)
            if registration {
                let encrypted = try #require(Data(base64Encoded: String(decoding: body, as: UTF8.self)))
                #expect(!encrypted.isEmpty && encrypted.count % 16 == 0)
                #expect(params["p"]?.count == 256)
                client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: ["status": 1, "data": ["dfid": "fixture-dfid"]]))
                client?.urlProtocolDidFinishLoading(self)
                return
            }
            let payload = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(payload["userid"] as? Int == 123)
            let response: [String: Any]
            if url.path == "/v5/add_list" {
                #expect(payload["name"] as? String == "测试")
                if payload["type"] as? Int == 1 {
                    #expect(payload["is_pri"] as? Int == 0)
                    #expect(payload["list_create_userid"] as? String == "98350951")
                    #expect(payload["list_create_listid"] as? String == "801")
                    #expect(payload["list_create_gid"] as? String == "collection_3_98350951_801_0")
                } else {
                    #expect(payload["type"] as? Int == 0)
                    #expect(payload["is_pri"] as? Int == 1)
                }
                response = ["status": 1, "error_code": 0, "data": ["info": [["listid": 17]], "userid": 123]]
            } else {
                #expect(url.path == "/v6/add_song")
                #expect(payload["listid"] as? Int == 17)
                let song = try #require((payload["data"] as? [[String: Any]])?.first)
                #expect(song["hash"] as? String == "fixture-hash")
                response = ["status": 1, "error_code": 0]
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: try JSONSerialization.data(withJSONObject: response))
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension KugouPlaylistMutationTests {
    @Test func createThenAddPreservesTheLoggedInClientIdentityAndSignsActualBody() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KugouPlaylistWriteFixture.self]
        let api = KugouMusicAPI(configuration: config, playlistCredentials: [
            "userid": "123", "token": "fixture-token", "KUGOU_API_MID": "fixture-mid", "dfid": "fixture-dfid"
        ])
        let playlist = try await api.createPlaylist(name: "测试", isPrivate: true)
        #expect(playlist.id == 17)
        #expect(playlist.isOwned == true)
        try await api.addSongs(listID: playlist.id, songs: [ProviderSong(id: -1, name: "Fixture", artists: "Artist", album: "", coverURL: nil,
            duration: 10, source: .kugou, kugouHash: "fixture-hash")])
    }

    @Test func missingDeviceIsRegisteredBeforeWritingAndTheReturnedDFIDIsUsed() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KugouPlaylistWriteFixture.self]
        let api = KugouMusicAPI(configuration: config, playlistCredentials: [
            "userid": "123", "token": "fixture-token", "KUGOU_API_MID": "fixture-mid"
        ])
        let playlist = try await api.createPlaylist(name: "测试", isPrivate: true)
        #expect(playlist.id == 17)
    }

    @Test func creationReadsTheNestedCloudListInfoRatherThanAnUnrelatedID() throws {
        #expect(try KugouMusicAPI.createdPlaylistID(["status": 1, "data": ["userid": 123, "info": ["listid": 17]]]) == 17)
        #expect(throws: (any Error).self) { try KugouMusicAPI.createdPlaylistID(["status": 1, "data": ["userid": 123]]) }
        #expect(throws: (any Error).self) { try KugouMusicAPI.createdPlaylistID(["status": 0, "error_code": 20017, "data": ["listid": 17]]) }
    }
}

extension KugouPlaylistMutationTests {
    @Test @MainActor func deletedPlaylistStaysHiddenUntilCloudCatchesUp() {
        let removed = ProviderPlaylist(id: 12, name: "Removed", coverURL: nil, source: .kugou)
        let kept = ProviderPlaylist(id: 13, name: "Kept", coverURL: nil, source: .kugou)
        let stale = PlatformMusicAPI.reconcileDeletedPlaylists(remote: [removed, kept], pending: [12])
        #expect(stale.visible.map(\.id) == [13])
        #expect(stale.remaining == [12])
        let fresh = PlatformMusicAPI.reconcileDeletedPlaylists(remote: [kept], pending: stale.remaining)
        #expect(fresh.visible.map(\.id) == [13])
        #expect(fresh.remaining.isEmpty)
    }
}

private final class KugouCollectionSourceFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try #require(request.url)
            let body: Data
            let contentType: String
            if url.host == "www.kugou.com" {
                #expect(url.path == "/yy/special/single/3947131.html")
                // Include braces and escaped quotes inside a string and nested
                // objects: parsing must stop at the end of the JSON object.
                body = Data(#"var specialInfo = {"intro":"a } and \"quoted\" title","plist":{"nested":{}},"global_collection_id":"collection_3_98350951_801_0","encode_gcid":"gcid_fixture"};"#.utf8)
                contentType = "text/html"
            } else {
                #expect(url.path == "/v3/get_list_info")
                var bytes = request.httpBody ?? Data()
                if let stream = request.httpBodyStream {
                    stream.open(); defer { stream.close() }
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    while stream.hasBytesAvailable {
                        let count = stream.read(&buffer, maxLength: buffer.count)
                        if count <= 0 { break }
                        bytes.append(contentsOf: buffer.prefix(count))
                    }
                }
                let payload = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                let id = try #require((payload["data"] as? [[String: String]])?.first?["global_collection_id"])
                #expect(!id.hasPrefix("gcid_"))
                let response: [String: Any]
                switch id {
                case "collection_empty": response = ["status": 1, "data": [:]]
                case "collection_error": response = ["status": 0, "error_code": 20001, "error_msg": "登录失效"]
                default:
                    #expect(id == "collection_3_98350951_801_0")
                    response = ["status": 1, "error_code": 0, "data": [[
                        "global_collection_id": id, "list_create_userid": 98350951,
                        "list_create_listid": 801, "list_create_gid": id
                    ]]]
                }
                body = try JSONSerialization.data(withJSONObject: response)
                contentType = "application/json"
            }
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil,
                headerFields: ["Content-Type": contentType])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

extension KugouPlaylistMutationTests {
    private func collectionAPI() -> KugouMusicAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KugouCollectionSourceFixture.self]
        return KugouMusicAPI(configuration: config)
    }

    @Test func collectionResolvesEncodedAndMissingWebsiteIDsBeforeRequestingMetadata() async throws {
        for id: String? in ["gcid_fixture", nil] {
            var item = ProviderPlaylist(id: 3947131, name: "Fixture", coverURL: nil, source: .kugou)
            item.kugouGlobalCollectionID = id
            let source = try await collectionAPI().collectionSource(item)
            #expect(source.id == item.id)
            #expect(source.kugouGlobalCollectionID == "collection_3_98350951_801_0")
            #expect(source.kugouCreateUserID == "98350951")
            #expect(source.kugouCreateListID == "801")
            #expect(source.kugouCreateGID == "collection_3_98350951_801_0")
        }
    }

    @Test func collectionKeepsCanonicalIDsAndRejectsEmptyOrFailedMetadata() async throws {
        var item = ProviderPlaylist(id: 1, name: "Fixture", coverURL: nil, source: .kugou)
        item.kugouGlobalCollectionID = "collection_3_98350951_801_0"
        let source = try await collectionAPI().collectionSource(item)
        #expect(source.kugouCreateListID == "801")
        for id in ["collection_empty", "collection_error"] {
            item.kugouGlobalCollectionID = id
            await #expect(throws: Error.self) { try await collectionAPI().collectionSource(item) }
        }
    }
}


extension KugouPlaylistMutationTests {
    @Test func collectionCreatesAServerManagedReferenceWithSourceIdentity() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KugouPlaylistWriteFixture.self]
        let api = KugouMusicAPI(configuration: config, playlistCredentials: [
            "userid": "123", "token": "fixture-token", "KUGOU_API_MID": "fixture-mid", "dfid": "fixture-dfid"
        ])
        var source = ProviderPlaylist(id: 3947131, name: "测试", coverURL: nil, trackCount: 87, source: .kugou)
        source.kugouGlobalCollectionID = "collection_3_98350951_801_0"
        source.kugouCreateUserID = "98350951"
        source.kugouCreateListID = "801"
        source.kugouCreateGID = source.kugouGlobalCollectionID
        let saved = try await api.createPlaylist(name: source.name, isPrivate: false, source: source)
        #expect(saved.id == 17)
        #expect(saved.isSubscribed == true)
        #expect(saved.isOwned == false)
        #expect(saved.trackCount == 87)
        #expect(saved.kugouCreateListID == "801")
    }

    @Test @MainActor func completedCollectionMatchesDespiteDifferentPublicAndAccountIDs() {
        var source = ProviderPlaylist(id: 3947131, name: "Fixture", coverURL: nil, source: .kugou)
        source.kugouGlobalCollectionID = "collection_3_98350951_801_0"
        source.kugouCreateUserID = "98350951"
        source.kugouCreateListID = "801"
        var saved = ProviderPlaylist(id: 27, name: "Fixture", coverURL: nil, source: .kugou)
        saved.ownerID = "123"
        saved.isSubscribed = true
        saved.kugouGlobalCollectionID = "collection_3_123_27_0"
        saved.kugouCreateUserID = source.kugouCreateUserID
        saved.kugouCreateListID = source.kugouCreateListID
        saved.kugouCreateGID = source.kugouGlobalCollectionID
        #expect(PlatformMusicAPI.matchingKugouCollection(source: source, lists: [saved], ownerID: "123")?.id == 27)
        #expect(PlatformMusicAPI.matchingKugouCollection(source: source, lists: [saved], ownerID: "other") == nil)
        // Creator identity alone also matches older cached metadata.
        saved.kugouCreateGID = nil
        #expect(PlatformMusicAPI.matchingKugouCollection(source: source, lists: [saved], ownerID: "123")?.id == 27)
        // Same titles are not evidence of a collection.
        saved.kugouCreateListID = "802"
        #expect(PlatformMusicAPI.matchingKugouCollection(source: source, lists: [saved], ownerID: "123") == nil)
        saved.kugouCreateGID = source.kugouGlobalCollectionID
        saved.isSubscribed = false
        #expect(PlatformMusicAPI.matchingKugouCollection(source: source, lists: [saved], ownerID: "123") == nil)
    }
}
