import Foundation
import Testing
@testable import CodaCore

private final class ArtistSubscriptionProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var code = 200
    static func reset(code: Int = 200) {
        lock.lock(); defer { lock.unlock() }
        requests = []; self.code = code
    }
    static func snapshot() -> [String] {
        lock.lock(); defer { lock.unlock() }; return requests.map { $0.url!.path }
    }
    static func recordedRequests() -> [URLRequest] {
        lock.lock(); defer { lock.unlock() }; return requests
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        Self.requests.append(request)
        let code = Self.code
        Self.lock.unlock()
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200,
            httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{\"code\":\(code),\"message\":\"参数错误\"}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Suite("Artist subscriptions", .serialized)
struct ArtistSubscriptionTests {
    private func client(loggedIn: Bool = true) -> NeteaseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ArtistSubscriptionProtocol.self]
        let client = NeteaseClient(configuration: config, persistsCookies: false)
        if loggedIn { client.setCookies(["MUSIC_U": "synthetic-artist-session"]) }
        return client
    }

    @Test func webParametersKeepScalarIDAsStringAndIDsAsJSONList() throws {
        let parameters = NeteaseAPI.artistSubscriptionParameters(id: 12345)
        #expect(parameters["artistId"] == "12345")
        let ids = try JSONDecoder().decode([Int].self, from: Data(try #require(parameters["artistIds"]).utf8))
        #expect(ids == [12345])
    }

    @Test func followAndUnfollowUseDistinctEndpointsAndPropagateServerErrors() async throws {
        ArtistSubscriptionProtocol.reset()
        let client = client()
        try await NeteaseAPI.subscribeArtist(id: 12345, subscribe: true, using: client)
        try await NeteaseAPI.subscribeArtist(id: 12345, subscribe: false, using: client)
        #expect(ArtistSubscriptionProtocol.snapshot() == ["/api/artist/sub", "/api/artist/unsub"])
        ArtistSubscriptionProtocol.reset(code: 400)
        await #expect(throws: NeteaseAPIError.self) {
            try await NeteaseAPI.subscribeArtist(id: 12345, subscribe: true, using: client)
        }
    }

    @Test func followAndUnfollowOverridePCProfileWithoutChangingTheCookieJar() async throws {
        ArtistSubscriptionProtocol.reset()
        let client = client()
        client.setCookies(["os": "pc", "appver": "3.1.17", "__csrf": "synthetic-csrf"])
        try await NeteaseAPI.subscribeArtist(id: 12345, subscribe: true, using: client)
        try await NeteaseAPI.subscribeArtist(id: 12345, subscribe: false, using: client)
        let requests = ArtistSubscriptionProtocol.recordedRequests()
        #expect(requests.count == 2)
        for request in requests {
            let header = try #require(request.value(forHTTPHeaderField: "Cookie"))
            let fields = header.components(separatedBy: "; ")
            // Live regression: os=pc returns 250/参数错误; the identical
            // payload with os=web succeeds for both endpoints.
            #expect(fields.contains("os=web"))
            #expect(!fields.contains("os=pc"))
            #expect(fields.contains("MUSIC_U=synthetic-artist-session"))
            #expect(fields.contains("__csrf=synthetic-csrf"))
            #expect(fields.contains("appver=3.1.17"))
        }
        #expect(client.cookie(named: "os") == "pc")
        // The override is specific to artist mutations; general requests
        // should retain their existing PC profile.
        _ = try await client.eapi("/artist/sublist")
        let ordinary = try #require(ArtistSubscriptionProtocol.recordedRequests().last)
        #expect(ordinary.value(forHTTPHeaderField: "Cookie")?.components(separatedBy: "; ").contains("os=pc") == true)
    }

    @Test func rejectedWebRequestIsNotRetriedOrReportedAsSuccess() async throws {
        ArtistSubscriptionProtocol.reset(code: 250)
        do {
            try await NeteaseAPI.subscribeArtist(id: 12345, subscribe: true, using: client())
            Issue.record("A rejected follow must not report success")
        } catch NeteaseAPIError.business(let code, let message) {
            #expect(code == 250)
            #expect(message == "参数错误")
        }
        #expect(ArtistSubscriptionProtocol.snapshot() == ["/api/artist/sub"])
    }

    @Test func guestsAndInvalidArtistsCannotSendFollowRequests() async throws {
        ArtistSubscriptionProtocol.reset()
        await #expect(throws: NeteaseAPIError.self) {
            try await NeteaseAPI.subscribeArtist(id: 12345, subscribe: true, using: client(loggedIn: false))
        }
        await #expect(throws: NeteaseAPIError.self) {
            try await NeteaseAPI.subscribeArtist(id: 0, subscribe: true, using: client())
        }
        #expect(ArtistSubscriptionProtocol.snapshot().isEmpty)
    }
}
