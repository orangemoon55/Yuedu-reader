import Foundation
import Testing
@testable import CodaCore

private final class KugouAlbumFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let bytes: Data
        if url.path == "/v2/search/song" {
            bytes = try! JSONSerialization.data(withJSONObject: ["status": 1, "data": ["lists": [
                ["FileHash": "correct", "SongName": "名字", "SingerName": "李荣浩", "AlbumName": "黑马", "AlbumID": "106374641"],
                ["FileHash": "wrong", "SongName": "卖火柴的小女孩", "SingerName": "马思唯", "AlbumName": "黑马", "AlbumID": "41734257"]
            ]]])
        } else {
            #expect(url.path == "/v1/album_audio/lite")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "x-router") == "openapi.kugou.com")
            var body = request.httpBody
            if body == nil, let stream = request.httpBodyStream {
                stream.open(); defer { stream.close() }
                var result = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable { let n = stream.read(&buffer, maxLength: buffer.count); if n <= 0 { break }; result.append(contentsOf: buffer.prefix(n)) }
                body = result
            }
            let json = (try? JSONSerialization.jsonObject(with: body ?? Data())) as? [String: Any]
            #expect((json?["album_id"] as? NSNumber)?.intValue == 106374641)
            let path = Bundle.module.url(forResource: "kugou-album-black-horse", withExtension: "json", subdirectory: "Fixtures")!
            bytes = try! Data(contentsOf: path)
        }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: bytes)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Kugou album identity")
struct KugouAlbumTests {
    @Test(arguments: ["106374641", "黑马|李荣浩"])
    func albumTracksUseExactIDIncludingLegacyAlbumLinks(id: String) async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KugouAlbumFixture.self]
        let api = KugouMusicAPI(configuration: configuration)
        let album = ProviderAlbum(id: id, name: "黑马", artistName: "李荣浩", coverURL: nil, source: .kugou)
        let songs = try await api.albumSongs(album: album)
        #expect(songs.map(\.name) == ["名字", "黑马", "另一端", "一百", "恋人", "走走", "轻轻田园系", "海陆风", "鸿门宴", "假面"])
        #expect(songs.allSatisfy { $0.artists == "李荣浩" && $0.kugouAlbumId == "106374641" })
        #expect(songs.first?.duration == 266.37)
        #expect(songs.first?.kugouAlbumAudioId == "621442433")
        #expect(songs.first?.kugouQualityHashes?["lossless"] == "1EBA76A06C2021ABDDD5AB6CA7EC56DD")
    }

    @Test func foreignAlbumRowsAreRejectedEvenWithTheSameTitle() {
        #expect(KugouMusicAPI.mapAlbumTrack(["base": ["album_id": 41734257], "audio_info": ["hash": "wrong"]], albumID: "106374641") == nil)
    }
}
