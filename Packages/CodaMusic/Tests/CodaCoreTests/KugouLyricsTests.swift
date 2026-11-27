import Foundation
import Testing
@testable import CodaCore

private final class KugouLyricsFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let body: [String: Any]
        if url.path == "/v1/search" {
            body = ["candidates": [["id": "bad", "accesskey": "a"], ["id": "good", "accesskey": "b"]]]
        } else if query.first(where: { $0.name == "id" })?.value == "good" {
            body = ["content": Data("[00:01.00]测试歌词".utf8).base64EncodedString()]
        } else { body = ["content": ""] }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: try! JSONSerialization.data(withJSONObject: body))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Kugou lyrics recovery")
struct KugouLyricsTests {
    @Test func skipsEmptyDownloadAndTriesNextCandidate() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [KugouLyricsFixture.self]
        let api = KugouMusicAPI(configuration: configuration)
        let lyric = await api.lyric(hash: "fixture", duration: 193)
        #expect(lyric == "[00:01.00]测试歌词")
    }
}
