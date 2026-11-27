import CryptoKit
import Foundation
import Testing
@testable import CodaCore

private final class KugouLibraryFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = request.url!
            let query = Dictionary(uniqueKeysWithValues: URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
            var bytes = request.httpBody ?? Data()
            if let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    if count <= 0 { break }; bytes.append(contentsOf: buffer.prefix(count))
                }
            }
            let body = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any] ?? [:]
            var payload: [String: Any] = [:]
            switch url.path {
            case "/playhistory/v1/get_songs":
                #expect(body["token"] as? String == "fixture")
                #expect(query["appid"] == "3116")
                let cursor = body["bp"] as? String
                let songs: [[String: Any]] = cursor == nil
                    ? [["info": Self.song("a"), "ot": 1_790_000_030], ["info": Self.song("b"), "ot": 1_790_000_020_000]]
                    : [["info": Self.song("a"), "ot": 1_790_000_000], ["info": Self.song("c"), "ot": 1_790_000_010]]
                payload = ["songs": songs, "has_more": 1, "bp": "next"]
            case "/v2/get_list":
                #expect(url.host == "listenservice.kugou.com")
                #expect(query["plat"] == "0")
                #expect((body["p"] as? String)?.count == 256)
                let type = (body["list_type"] as? NSNumber)?.intValue
                #expect(type == 0 || type == 1)
                var row = Self.song(type == 0 ? "week" : "all")
                row["listen_count"] = type == 0 ? 2 : 223
                row["duration"] = 202_000
                payload = ["lists": [row]]
            case "/v1/get_list":
                #expect(url.host == "mcloudservice.kugou.com")
                #expect(query["signature"] == nil)
                #expect(query["token"] == nil)
                #expect(query["p"]?.count == 256)
                #expect(bytes.count > 0 && bytes.count % 16 == 0)
                payload = ["list": [["hash": "cloudhash", "name": "Private.flac", "author_name": "Singer", "timelen": 213_315,
                    "size": "12345", "kv_id": "9", "audio_id": "100", "album_audio_id": "200"]],
                    "list_count": 1, "used_size": "12345", "max_size": 1_099_511_627_776 as Int64]
            case "/bsstrackercdngz/v2/query_musicclound_url":
                #expect(query["audio_id"] == "100")
                #expect(query["album_audio_id"] == "200")
                #expect(query["name"] == "Private.flac")
                payload = ["url": "https://audio.example/private.flac"]
            default: throw URLError(.unsupportedURL)
            }
            let data = try JSONSerialization.data(withJSONObject: ["status": 1, "error_code": 0, "data": payload])
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
    static func song(_ hash: String) -> [String: Any] {
        ["hash": hash, "name": "Song \(hash)", "singername": "Singer", "timelen": 213_315,
         "mixsongid": 300, "albuminfo": ["name": "Album", "id": 100], "cover": "https://image.example/{size}.jpg"]
    }
}

@Suite("Kugou cloud history, ranking and library")
struct KugouCloudLibraryTests {
    private func api() -> KugouMusicAPI {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [KugouLibraryFixture.self]
        return KugouMusicAPI(configuration: config, playlistCredentials: ["userid": "12345", "token": "fixture", "KUGOU_API_MID": "device"])
    }

    @Test func historyFollowsCursorDeduplicatesAndStopsARepeatedCursor() async throws {
        let history = try await api().recentSongPlays()
        #expect(history.map { $0.song.kugouHash } == ["a", "b", "c"])
        #expect(history.map { $0.playedAt.timeIntervalSince1970 } == [1_790_000_030, 1_790_000_020, 1_790_000_010])
        #expect(history.first?.song.duration == 213.315)
        #expect(history.first?.song.album == "Album")
        #expect(history.first?.song.kugouAlbumId == "100")
        #expect(try await api().recentSongPlays(limit: 1).count == 1)
    }

    @Test func rankingUsesRemoteCountsAndPreservesWeekAndAllPeriods() async throws {
        let week = try await api().listeningRanking(week: true)
        let all = try await api().listeningRanking(week: false)
        #expect(week.first?.count == 2)
        #expect(all.first?.count == 223)
        #expect(week.first?.song.kugouHash == "week")
        #expect(all.first?.song.kugouHash == "all")
        #expect(week.first?.song.duration == 202)
    }

    @Test func cloudReadPreservesCapacityAndBothAudioIDsAndRejectsAnotherOwner() async throws {
        let api = api()
        let library = try await api.cloudLibrary()
        #expect(library.usedBytes == 12345)
        #expect(library.maxBytes == 1_099_511_627_776)
        let song = try #require(library.songs.first)
        #expect(song.name == "Private")
        #expect(song.kugouCloud?.name == "Private.flac")
        #expect(song.kugouCloud?.audioID == "100")
        #expect(song.kugouAlbumAudioId == "200")
        #expect(try await api.userCloudURL(song: song) == "https://audio.example/private.flac")
        #expect(try JSONDecoder().decode(ProviderSong.self, from: JSONEncoder().encode(song)) == song)
        let other = KugouMusicAPI(playlistCredentials: ["userid": "other", "token": "fixture"])
        await #expect(throws: MusicProviderError.self) { try await other.userCloudURL(song: song) }
    }

    @Test func failureIsNotAnEmptyLibraryAndMillisecondsAreUnambiguous() throws {
        #expect(throws: (any Error).self) { try KugouMusicAPI.validateLibraryResponse(["status": 0, "error_code": 20018]) }
        #expect(KugouMusicAPI.mapAccountSong(["hash": "a", "name": "Long", "duration": 3_600_000])?.duration == 3600)
        #expect(KugouMusicAPI.mapAccountSong(["hash": "a", "name": "Short", "timelen": 900])?.duration == 0.9)
    }

    @Test @MainActor func privateCloudIdentitySurvivesTrackPersistenceAndCannotReplaceCatalogSong() throws {
        let cloud = try #require(KugouMusicAPI.mapCloudSong(["hash": "same", "name": "Cloud.mp3", "kv_id": 10], ownerID: "12345"))
        let normal = try #require(KugouMusicAPI.mapAccountSong(["hash": "same", "name": "Cloud"]))
        let privateTrack = try PlatformMusicAPI.shared.register(cloud)
        let catalogTrack = try PlatformMusicAPI.shared.register(normal)
        #expect(privateTrack.id != catalogTrack.id)
        #expect(privateTrack.isCloud)
        let restored = try JSONDecoder().decode(Track.self, from: JSONEncoder().encode(privateTrack))
        #expect(restored.platformSong?.kugouCloud?.ownerID == "12345")
        #expect(restored.isCloud)
        #expect(!MusicProvider.kugou.supports(.profileStatistics))
        #expect(MusicProvider.kugou.supports(.playRanking))
        #expect(MusicProvider.kugou.supports(.playbackReporting))
        #expect(MusicProvider.kugou.supports(.cloud))
        #expect(MusicProvider.kugou.supports(.cloudChanges))
    }

    private func downloadTrack() throws -> Track {
        let song = ProviderSong(id: 1, name: "Fixture", artists: "Singer", album: "Album", coverURL: nil, duration: 202,
            source: .kugou, kugouHash: String(repeating: "a", count: 32))
        var object: [String: Any] = ["id": -123, "name": song.name, "dt": 202000]
        object["platformSong"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(song))
        return try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: object))
    }

    @Test func downloadRequiresCompleteResourceMetadataAndRejectsTrials() throws {
        let track = try downloadTrack()
        let valid: [String: Any] = ["status": 1, "hash": String(repeating: "a", count: 32), "fileSize": 3238553,
            "timeLength": 202, "extName": "mp3", "bitRate": 128000, "url": ["https://audio.example/full.mp3"]]
        let resource = try KugouMusicAPI.downloadResource(json: valid, track: track, accountScope: "kugou:12345")
        #expect(resource.descriptor.identity.source == "kugou")
        #expect(resource.descriptor.identity.trackID == -123)
        #expect(resource.descriptor.identity.quality == "standard")
        for mutation: [String: Any] in [["timeLength": 30], ["is_free_part": 1], ["hash": ""], ["fileSize": 0], ["status": 3], ["url": ["file:///private.mp3"]]] {
            let invalid = valid.merging(mutation) { _, new in new }
            #expect(throws: (any Error).self) { try KugouMusicAPI.downloadResource(json: invalid, track: track, accountScope: "kugou:12345") }
        }
        #expect(throws: OfflineAudioError.invalidResource) { try KugouMusicAPI.downloadResource(json: valid, track: track, accountScope: "netease:12345") }
    }

    @Test func kugouDownloadsCanBeAcquiredOfflineOnlyByTheirAccount() async throws {
        let fixture = try OfflineAudioFixture()
        let store = fixture.store()
        defer { try? FileManager.default.removeItem(at: store.directory) }
        let descriptor = OfflineAudioDescriptor(identity: .init(accountScope: "kugou:12345", trackID: -123, source: "kugou",
            quality: "exhigh", format: fixture.descriptor.identity.format, contentMD5: fixture.descriptor.identity.contentMD5),
            byteCount: fixture.descriptor.byteCount, duration: fixture.descriptor.duration)
        try await store.importFixture(fixture.data, descriptor: descriptor)
        let lease = try #require(try await store.acquire(accountScope: "kugou:12345", trackID: -123, preferredQuality: "exhigh"))
        #expect(try Data(contentsOf: lease.url) == fixture.data)
        #expect(try await store.acquire(accountScope: "kugou:other", trackID: -123, preferredQuality: "exhigh") == nil)
        #expect(try await store.reusableDescriptor(accountScope: "kugou:12345", trackID: -123, quality: "standard") == descriptor)
        try await store.release(lease)
    }
}

@Suite("Kugou cloud changes")
struct KugouCloudChangeParsingTests {
    @Test func parsesLibraryMatchAndIgnoresEmptyCandidates() throws {
        #expect(KugouMusicAPI.CloudMatch([String: Any]()) == nil)
        #expect(KugouMusicAPI.CloudMatch(nil) == nil)
        let nested: [Any] = [["album_audio_id": "32042828", "author_name": "周杰伦", "ori_audio_name": "最长的电影",
                              "audio_info": ["audio_id": 1234, "hash": "ABCDEF"]]]
        let match = try #require(KugouMusicAPI.CloudMatch(nested))
        #expect(match.albumAudioID == 32042828 && match.audioID == 1234)
        #expect(match.hashStd == "abcdef" && match.authorName == "周杰伦" && match.audioName == "最长的电影")
    }

    @Test func rejectsFailedCloudChanges() throws {
        try KugouMusicAPI.validateCloudChange(["status": 1, "error_code": 0], action: "删除")
        #expect(throws: (any Error).self) { try KugouMusicAPI.validateCloudChange(["status": 0, "error_code": 20018], action: "上传") }
    }

    @Test func cloudChangesAreAvailableForKugouOnlyAlongsideNetease() {
        #expect(MusicProvider.kugou.supports(.cloudChanges))
        #expect(MusicProvider.netease.supports(.cloudChanges))
        #expect(!MusicProvider.qq.supports(.cloudChanges))
    }
}
