import CommonCrypto
import Foundation
import Testing
@testable import CodaCore

@Suite("Coda explicit NetEase search credential isolation", .serialized)
struct CodaExplicitNetEaseSearchTransportFixtureTests {
    private func makeClient() -> NeteaseClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CodaExplicitSearchURLProtocol.self]
        return NeteaseClient(configuration: config, persistsCookies: false)
    }
    private func makeContext() -> (MusicProviderContext, UserDefaults, String) {
        let name = "CodaExplicitNetEaseSearch.\(UUID())"
        let defaults = UserDefaults(suiteName: name)!
        return (MusicProviderContext(provider: .qq, defaults: defaults), defaults, name)
    }

    @Test func explicitNetEaseUsesNetEaseJarEvenWhileQQIsSelectedAndRequestsOnlySongs() async throws {
        let (context, defaults, name) = makeContext()
        defer { defaults.removePersistentDomain(forName: name) }
        let client = makeClient()
        client.setCookies(["MUSIC_U": "synthetic-netease-only", "__csrf": "synthetic-csrf"])
        let ticket = context.ticket
        CodaExplicitSearchURLProtocol.prepare(body: #"{"code":200,"result":{"songs":[{"id":77,"name":"fixture"}],"songCount":9}}"#)
        let result = try await NeteaseAPI.explicitNeteaseSearch("fixture", type: .songs, limit: 2, offset: 3,
                                                               using: client, context: context)
        #expect(result.songs?.map(\.id) == [77] && result.songCount == 9)
        #expect(context.current == .qq && context.ticket == ticket)
        let request = try #require(CodaExplicitSearchURLProtocol.requests.first)
        #expect(request.url?.absoluteString == "https://interface.music.163.com/eapi/cloudsearch/pc")
        let cookies = request.value(forHTTPHeaderField: "Cookie") ?? ""
        #expect(cookies.contains("MUSIC_U=synthetic-netease-only"))
        #expect(!cookies.contains("qqmusic_key") && !cookies.contains("uin="))
        let (path, body) = try payload(request)
        #expect(path == "/api/cloudsearch/pc")
        #expect(body["s"] as? String == "fixture" && body["type"] as? Int == 1)
        #expect(body["limit"] as? Int == 2 && body["offset"] as? Int == 3)
        let header = try #require(body["header"] as? [String: String])
        #expect(header["MUSIC_U"] == "synthetic-netease-only" && header["__csrf"] == "synthetic-csrf")
    }

    @Test func contextTicketChangeRejectsInFlightReply() async throws {
        let (context, defaults, name) = makeContext()
        defer { defaults.removePersistentDomain(forName: name) }
        CodaExplicitSearchURLProtocol.prepare(onRequest: { context.activate(.kugou) })
        do {
            _ = try await NeteaseAPI.explicitNeteaseSearch("fixture", type: .songs, limit: 1, offset: 0,
                                                         using: makeClient(), context: context)
            Issue.record("A changed context ticket must reject the response")
        } catch is CancellationError { }
    }

    @Test func netEaseLogoutAndGuestToLoginAlsoRejectReplies() async throws {
        let (context, defaults, name) = makeContext()
        defer { defaults.removePersistentDomain(forName: name) }
        let authenticated = makeClient()
        authenticated.setCookies(["MUSIC_U": "synthetic-old"])
        CodaExplicitSearchURLProtocol.prepare(onRequest: { try? authenticated.clearAuthCookies() })
        do {
            _ = try await NeteaseAPI.explicitNeteaseSearch("fixture", type: .songs, limit: 1, offset: 0,
                                                         using: authenticated, context: context)
            Issue.record("A signed-out NetEase session must reject the response")
        } catch is CancellationError { }
        let guest = makeClient()
        CodaExplicitSearchURLProtocol.prepare(onRequest: { guest.setCookies(["MUSIC_U": "synthetic-new"]) })
        do {
            _ = try await NeteaseAPI.explicitNeteaseSearch("fixture", type: .songs, limit: 1, offset: 0,
                                                         using: guest, context: context)
            Issue.record("Explicit search also rejects guest -> login responses")
        } catch is CancellationError { }
    }

    @Test func explicitSearchPreservesHTTPAndLoginBusinessErrors() async throws {
        let (context, defaults, name) = makeContext()
        defer { defaults.removePersistentDomain(forName: name) }
        CodaExplicitSearchURLProtocol.prepare(status: 503)
        do {
            _ = try await NeteaseAPI.explicitNeteaseSearch("fixture", type: .songs, limit: 1, offset: 0,
                                                         using: makeClient(), context: context)
            Issue.record("HTTP status validation must not be bypassed")
        } catch NeteaseAPIError.http(let status) { #expect(status == 503) }
        CodaExplicitSearchURLProtocol.prepare(body: #"{"code":301,"message":"fixture login required"}"#)
        do {
            _ = try await NeteaseAPI.explicitNeteaseSearch("fixture", type: .songs, limit: 1, offset: 0,
                                                         using: makeClient(), context: context)
            Issue.record("Login business errors must not become empty success")
        } catch NeteaseAPIError.needLogin { }
    }

    private func payload(_ request: URLRequest) throws -> (String, [String: Any]) {
        var body = request.httpBody ?? Data()
        if body.isEmpty, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var buffer = [UInt8](repeating: 0, count: 4096)
            while true {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(contentsOf: buffer.prefix(count))
            }
        }
        let form = try #require(String(data: body, encoding: .utf8))
        let field = try #require(form.split(separator: "&").first { $0.hasPrefix("params=") })
        let hex = String(field.dropFirst(7)).removingPercentEncoding ?? ""
        let bytes = stride(from: 0, to: hex.count, by: 2).compactMap { offset -> UInt8? in
            let start = hex.index(hex.startIndex, offsetBy: offset)
            return UInt8(hex[start..<hex.index(start, offsetBy: 2)], radix: 16)
        }
        let encrypted = Data(bytes)
        let key = Array("e82ckenh8dichen8".utf8)
        var output = [UInt8](repeating: 0, count: bytes.count + kCCBlockSizeAES128)
        let capacity = output.count
        var written = 0
        let status = encrypted.withUnsafeBytes { input in
            key.withUnsafeBytes { key in
                output.withUnsafeMutableBytes { destination in
                    CCCrypt(CCOperation(kCCDecrypt), CCAlgorithm(kCCAlgorithmAES),
                        CCOptions(kCCOptionECBMode | kCCOptionPKCS7Padding), key.baseAddress,
                        kCCKeySizeAES128, nil, input.baseAddress, encrypted.count,
                        destination.baseAddress, capacity, &written)
                }
            }
        }
        #expect(status == kCCSuccess)
        let text = try #require(String(bytes: output.prefix(written), encoding: .utf8))
        let parts = text.components(separatedBy: "-36cd479b6b5-")
        #expect(parts.count == 3)
        let data = try #require(parts[1].data(using: .utf8))
        return (parts[0], try #require(JSONSerialization.jsonObject(with: data) as? [String: Any]))
    }
}

private final class CodaExplicitSearchURLProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var status = 200
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var callback: (@Sendable () -> Void)?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func prepare(status: Int = 200,
                        body: String = #"{"code":200,"result":{"songs":[],"songCount":0}}"#,
                        onRequest: (@Sendable () -> Void)? = nil) {
        lock.withLock {
            self.status = status
            self.body = Data(body.utf8)
            callback = onRequest
            recorded = []
        }
    }
    static var requests: [URLRequest] { lock.withLock { recorded } }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let (status, body, callback) = Self.lock.withLock {
            Self.recorded.append(request)
            return (Self.status, Self.body, Self.callback)
        }
        callback?()
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil,
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}
