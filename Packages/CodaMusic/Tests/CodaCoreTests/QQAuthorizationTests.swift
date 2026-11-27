import Foundation
import Testing
@testable import CodaCore

/// Simulates QQ's full QR → check_sig → OAuth → music-session exchange. The
/// server deliberately withholds the code when the submitted form is malformed.
private final class QQAuthorizationFixture: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let mode = request.value(forHTTPHeaderField: "X-QQ-Fixture") ?? "normal"
        var status = 200
        var headers: [String: String] = [:]
        var body = ""
        switch url.path {
        case "/ptqrshow":
            headers["Set-Cookie"] = "qrsig=fixture-qr; Domain=.ptlogin2.qq.com; Path=/; Secure"
            body = "fixture-image"
        case "/ptqrlogin":
            body = "ptuiCB('0','0','https://ssl.ptlogin2.graph.qq.com/check_sig?ticket=fixture','0','登录成功！','Fixture, Nick');"
        case "/check_sig":
            status = 302
            headers["Set-Cookie"] = "p_skey=graph-session; Domain=.graph.qq.com; Path=/; Secure"
            headers["Location"] = mode == "domain" ? "https://y.qq.com/fixture-hop" : "https://graph.qq.com/fixture-final"
        case "/fixture-hop":
            status = 302
            headers["Set-Cookie"] = "p_skey=music-domain-session; Domain=.y.qq.com; Path=/; Secure"
            headers["Location"] = "https://graph.qq.com/fixture-final"
        case "/fixture-final":
            headers["Set-Cookie"] = "uin=o12345; Domain=.qq.com; Path=/; Secure"
        case "/oauth2.0/authorize":
            let form = Self.decodeForm(Self.body(request))
            let expectedRedirect = "https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/"
            let graphCookie = request.value(forHTTPHeaderField: "Cookie") ?? ""
            let valid = form["redirect_uri"] == expectedRedirect && form["surl"] == nil
                && form["g_tk"] == String(QQMusicAuth.hash5381("graph-session"))
                && graphCookie.contains("p_skey=graph-session")
                && !graphCookie.contains("music-domain-session")
            if valid {
                status = 302
                headers["Location"] = "https://y.qq.com/portal/wx_redirect.html?code=fixture-code&state=state"
            } else { body = "<html>Authorization form or session rejected</html>" }
        case "/cgi-bin/musicu.fcg":
            if mode == "denyExchange" { body = #"{"code":0,"req":{"code":1000,"data":{}}}"# }
            else if mode == "missingMusicKey" { body = #"{"code":0,"req":{"code":0,"data":{"musicid":12345}}}"# }
            else { body = #"{"code":0,"req":{"code":0,"data":{"musickey":"fixture-music-key","musicid":12345,"openid":"fixture-openid","refresh_token":"fixture-refresh-token","refresh_key":"fixture-refresh-key","musickeyCreateTime":1700000000,"keyExpiresIn":259200}}}"# }
        default: status = 404
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
    private static func body(_ request: URLRequest) -> String {
        if let data = request.httpBody { return String(decoding: data, as: UTF8.self) }
        guard let stream = request.httpBodyStream else { return "" }
        stream.open(); defer { stream.close() }
        var bytes = [UInt8](repeating: 0, count: 4096)
        var data = Data()
        while stream.hasBytesAvailable {
            let count = stream.read(&bytes, maxLength: bytes.count)
            if count <= 0 { break }
            data.append(contentsOf: bytes.prefix(count))
        }
        return String(decoding: data, as: UTF8.self)
    }
    private static func decodeForm(_ body: String) -> [String: String] {
        var fields: [String: String] = [:]
        for part in body.split(separator: "&") {
            let pair = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else { continue }
            func decode(_ value: Substring) -> String {
                let escaped = value.replacingOccurrences(of: "+", with: " ")
                return escaped.removingPercentEncoding ?? escaped
            }
            fields[decode(pair[0])] = decode(pair[1])
        }
        return fields
    }
}

@Suite("QQ authorization")
struct QQAuthorizationTests {
    private func auth(mode: String = "normal") -> QQMusicAuth {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [QQAuthorizationFixture.self]
        config.httpAdditionalHeaders = ["X-QQ-Fixture": mode]
        return QQMusicAuth(persistsSession: false, configuration: config)
    }
    @Test func formPreservesTheNestedRedirectURLAndCompletesMusicLogin() async throws {
        let candidate = auth()
        _ = try await candidate.fetchQRCode()
        let state = try await candidate.poll()
        #expect(state == .success("Fixture, Nick"))
        #expect(candidate.isLoggedIn)
        #expect(candidate.exportedCredentials["qqmusic_key"] == "fixture-music-key")
        #expect(candidate.uin == "12345")
        // The renewal fields must survive, or the session dies once musickey expires.
        #expect(candidate.exportedCredentials["refresh_token"] == "fixture-refresh-token")
        #expect(candidate.exportedCredentials["refresh_key"] == "fixture-refresh-key")
        #expect(candidate.exportedCredentials["openid"] == "fixture-openid")
        #expect(candidate.exportedCredentials["musickeyCreateTime"] == "1700000000")
        #expect(candidate.exportedCredentials["keyExpiresIn"] == "259200")
    }
    @Test func sameNamedCookiesFromDifferentDomainsRemainIsolated() async throws {
        let candidate = auth(mode: "domain")
        _ = try await candidate.fetchQRCode()
        let state = try await candidate.poll()
        #expect(state == .success("Fixture, Nick"))
    }
    @Test(arguments: ["denyExchange", "missingMusicKey"])
    func rejectedMusicExchangeNeverBecomesASuccessfulLogin(mode: String) async throws {
        let candidate = auth(mode: mode)
        _ = try await candidate.fetchQRCode()
        let state = try await candidate.poll()
        guard case .error = state else { Issue.record("Rejected exchange became a successful login"); return }
        #expect(!candidate.isLoggedIn)
        #expect(candidate.exportedCredentials["qqmusic_key"] == nil)
    }
}
