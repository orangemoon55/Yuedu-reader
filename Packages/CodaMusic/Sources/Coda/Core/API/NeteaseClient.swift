import Foundation
import CryptoKit
import os.log

enum NeteaseAPIError: LocalizedError {
    case http(Int)
    case business(code: Int, message: String?)
    case needLogin
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .http(let status): return String(localized: "网络错误 (\(status))")
        case .business(let code, let message): return message ?? String(localized: "接口错误 (\(code))")
        case .needLogin: return String(localized: "需要登录")
        case .decoding: return String(localized: "数据加载失败，请稍后重试")
        }
    }
}

/// Transport layer for NetEase Cloud Music. Owns the cookie jar and performs
/// weapi / eapi encrypted requests.
final class NeteaseClient: @unchecked Sendable {
    static let shared: NeteaseClient = {
        #if DEBUG
        if CodaPaths.isOfflineUITest {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [OfflineUITestProtocol.self]
            return NeteaseClient(configuration: configuration)
        }
        #endif
        return NeteaseClient()
    }()

    private static let log = Logger(subsystem: "wow.caicai.coda", category: "api")
    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125.0.0.0 Safari/537.36"

    private static let eapiUserAgent = "NeteaseMusic 9.0.90/5038 (iPhone; iOS 16.2; zh_CN)"
    private static let deviceIDLock = NSLock()
    private static let installationDeviceID = loadDeviceID(in: CodaPaths.applicationSupport)
    private let deviceID: String

    /// One identity per installation, shared by API requests and playback logs.
    static func loadDeviceID(in directory: URL?) -> String {
        deviceIDLock.lock(); defer { deviceIDLock.unlock() }
        let url = directory?.appendingPathComponent("device-id")
        if let url, let data = try? Data(contentsOf: url),
           let stored = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           stored.count == 52, stored.utf8.allSatisfy({ (48...57).contains($0) || (65...70).contains($0) }) {
            return stored
        }
        let id = String((UUID().uuidString + UUID().uuidString).replacingOccurrences(of: "-", with: "").prefix(52))
        if let url {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? Data(id.utf8).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        return id
    }

    private let session: URLSession

    func playbackMediaTier(url: String, bitrate: Double?) async -> AudioQuality? {
        await AudioQualityCheck.remoteTier(url: url, session: session, bitrate: bitrate)
    }

    private let cookieLock = NSLock()
    // Serialize mutations and disk snapshots without blocking cookie readers.
    private let cookieWriteLock = NSLock()
    private var cookies: [String: String] = [:]
    private static let bindingKey = "__coda_session_binding"
    private var sessionBinding: String?
    private var authEpoch: UInt64 = 0
    private let cookieFileURL: URL?

    init(cookieDirectory: URL? = nil, configuration: URLSessionConfiguration? = nil, persistsCookies: Bool = true) {
        deviceID = cookieDirectory.map { Self.loadDeviceID(in: $0) } ?? Self.installationDeviceID
        let config = configuration ?? URLSessionConfiguration.default
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)

        guard persistsCookies else { cookieFileURL = nil; return }

        let support = cookieDirectory ?? CodaPaths.applicationSupport
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        let url = support.appendingPathComponent("cookies.json")
        cookieFileURL = url
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode([String: String].self, from: data) {
            cookies = stored
            let savedBinding = cookies.removeValue(forKey: Self.bindingKey)
            sessionBinding = cookies["MUSIC_U"].map { savedBinding ?? Self.fingerprint($0) }
        }
    }

    // MARK: - Cookies

    var isLoggedIn: Bool { cookie(named: "MUSIC_U") != nil }

    /// Identifies the login across token renewals; a new sign-in gets a new binding.
    var authenticationFingerprint: String? {
        cookieLock.lock(); defer { cookieLock.unlock() }
        return sessionBinding
    }

    private static func fingerprint(_ token: String) -> String {
        SHA256.hash(data: Data(token.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private var authenticationState: (epoch: UInt64, binding: String?) {
        cookieLock.lock(); defer { cookieLock.unlock() }
        return (authEpoch, sessionBinding)
    }

    private func isCurrent(_ authentication: (epoch: UInt64, binding: String?)) -> Bool {
        cookieLock.lock(); defer { cookieLock.unlock() }
        return authentication.epoch == authEpoch || (authentication.binding != nil && authentication.binding == sessionBinding)
    }

    func authenticationCookies() -> [String: String] {
        cookieLock.lock(); defer { cookieLock.unlock() }
        return cookies.filter { ["MUSIC_U", "__csrf"].contains($0.key) }
    }

    func cookie(named name: String) -> String? {
        cookieLock.lock(); defer { cookieLock.unlock() }
        return cookies[name]
    }

    @discardableResult
    func setCookies(_ new: [String: String], expectedEpoch: UInt64? = nil, preservingSession: Bool = false) -> Bool {
        cookieWriteLock.lock(); defer { cookieWriteLock.unlock() }
        cookieLock.lock()
        if let expectedEpoch, expectedEpoch != authEpoch { cookieLock.unlock(); return false }
        if let token = new["MUSIC_U"], token != cookies["MUSIC_U"] {
            authEpoch += 1
            if !preservingSession || sessionBinding == nil { sessionBinding = Self.fingerprint(token) }
        }
        for (k, v) in new where k != Self.bindingKey { cookies[k] = v }
        var snapshot = cookies
        snapshot[Self.bindingKey] = sessionBinding
        cookieLock.unlock()
        persist(snapshot)
        return true
    }

    /// Commit a verified sign-in durably before changing the live cookie jar.
    /// Disk failures leave the current authentication untouched.
    func replaceAuthentication(with authentication: [String: String]) throws {
        guard let token = authentication["MUSIC_U"], !token.isEmpty else { throw NeteaseAPIError.needLogin }
        cookieWriteLock.lock(); defer { cookieWriteLock.unlock() }
        cookieLock.lock()
        var snapshot = cookies
        cookieLock.unlock()
        snapshot.removeValue(forKey: "MUSIC_U")
        snapshot.removeValue(forKey: "__csrf")
        snapshot.merge(authentication.filter { ["MUSIC_U", "__csrf"].contains($0.key) }) { _, new in new }
        try commitAuthentication(snapshot, binding: Self.fingerprint(token))
    }

    /// The caller holds cookieWriteLock so a failed disk write cannot leave the
    /// persisted and live authentication states disagreeing.
    private func commitAuthentication(_ snapshot: [String: String], binding: String?) throws {
        if let cookieFileURL {
            var stored = snapshot
            stored[Self.bindingKey] = binding
            try JSONEncoder().encode(stored).write(to: cookieFileURL, options: .atomic)
        }
        cookieLock.lock()
        cookies = snapshot
        sessionBinding = binding
        authEpoch += 1
        cookieLock.unlock()
    }

    func clearAuthCookies() throws {
        cookieWriteLock.lock(); defer { cookieWriteLock.unlock() }
        cookieLock.lock()
        var snapshot = cookies
        cookieLock.unlock()
        snapshot.removeValue(forKey: "MUSIC_U")
        snapshot.removeValue(forKey: "__csrf")
        try commitAuthentication(snapshot, binding: nil)
    }

    private func persist(_ snapshot: [String: String]) {
        guard let cookieFileURL else { return }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: cookieFileURL, options: .atomic)
        }
    }

    private func cookieHeader(extra: [String: String], overrides: [String: String] = [:]) -> String {
        cookieLock.lock()
        var all = cookies
        cookieLock.unlock()
        for (k, v) in extra where all[k] == nil { all[k] = v }
        for (k, v) in overrides { all[k] = v }
        return all.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    private func absorbSetCookies(from response: HTTPURLResponse, url: URL, epoch: UInt64, preservingSession: Bool) -> Bool {
        guard let fields = response.allHeaderFields as? [String: String] else { return true }
        let parsed = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url)
        guard !parsed.isEmpty else { return true }
        var new: [String: String] = [:]
        for c in parsed where !c.value.isEmpty && c.value != "\"\"" {
            new[c.name] = c.value
        }
        return setCookies(new, expectedEpoch: epoch, preservingSession: preservingSession)
    }

    // MARK: - Requests

    /// POST to `https://music.163.com/weapi<path>` with weapi encryption.
    func weapi(_ path: String, _ payload: [String: Any] = [:],
               cookieOverrides: [String: String] = [:], absorbResponseCookies: Bool = true) async throws -> Data {
        let authentication = authenticationState
        var body = payload
        let csrf = cookieOverrides["__csrf"] ?? cookie(named: "__csrf")
        body["csrf_token"] = csrf ?? ""
        let json = try JSONSerialization.data(withJSONObject: body)
        let form = NeteaseCrypto.weapi(payload: json)

        var fullPath = path
        if let csrf, !csrf.isEmpty {
            fullPath += (fullPath.contains("?") ? "&" : "?") + "csrf_token=\(csrf)"
        }
        let url = URL(string: "https://music.163.com/weapi\(fullPath)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookieHeader(extra: ["os": "pc", "appver": "3.1.17"], overrides: cookieOverrides),
                         forHTTPHeaderField: "Cookie")
        request.httpBody = Self.encodeForm(form)
        return try await perform(request, authentication: authentication, absorbResponseCookies: absorbResponseCookies)
    }

    /// These endpoints reject EAPI with -460; send an ordinary HTTPS web form.
    func api(_ path: String, _ form: [String: String] = [:],
             cookieOverrides: [String: String] = [:]) async throws -> Data {
        let authentication = authenticationState
        var request = URLRequest(url: URL(string: "https://music.163.com/api\(path)")!)
        request.httpMethod = "POST"
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com/", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(cookieHeader(extra: [:], overrides: cookieOverrides), forHTTPHeaderField: "Cookie")
        request.httpBody = Self.encodeForm(form)
        return try await perform(request, authentication: authentication)
    }

    /// Desktop EAPI profile; explicit overrides apply to both encrypted header and Cookie.
    func eapi(_ path: String, _ payload: [String: Any] = [:],
              cookieOverrides: [String: String] = [:], absorbResponseCookies: Bool = true) async throws -> Data {
        let authentication = authenticationState
        let now = Date().timeIntervalSince1970
        var header: [String: String] = [
            "os": "pc", "appver": "3.1.17.204416",
            "osver": "Microsoft-Windows-10-Professional-build-19045-64bit",
            "deviceId": deviceID, "versioncode": "140", "mobilename": "",
            "buildver": String(Int(now)), "resolution": "1920x1080", "channel": "netease",
            "requestId": String(format: "%lld_%04d", Int64(now * 1000), Int.random(in: 0...9999)),
            "__csrf": cookie(named: "__csrf") ?? ""
        ]
        if let musicU = cookie(named: "MUSIC_U") { header["MUSIC_U"] = musicU }
        if let nmtid = cookie(named: "NMTID") { header["NMTID"] = nmtid }
        header.merge(cookieOverrides) { _, new in new }
        var body = payload
        body["header"] = header
        body["e_r"] = false
        let json = try JSONSerialization.data(withJSONObject: body)
        let form = NeteaseCrypto.eapi(apiPath: "/api" + path, payload: json)
        var request = URLRequest(url: URL(string: "https://interface.music.163.com/eapi\(path)")!)
        request.httpMethod = "POST"
        request.setValue(Self.eapiUserAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        // Profile fields must replace stale profile cookies imported from another client.
        request.setValue(cookieHeader(extra: [:], overrides: header), forHTTPHeaderField: "Cookie")
        request.httpBody = Self.encodeForm(form)
        return try await perform(request, authentication: authentication, absorbResponseCookies: absorbResponseCookies)
    }

    /// A log acknowledgement is not a guarantee that listening history changed.
    /// Validate the uploaded filename, not merely the endpoint's top-level 200.
    func uploadPlaybackLog(song: NeteasePlaybackLog.Song, event: NeteasePlaybackLog.Event,
                           seconds: Int = 0, completed: Bool = false) async throws {
        let authentication = authenticationState
        guard authentication.binding != nil else { throw NeteaseAPIError.needLogin }
        let values = playbackCookies()
        let upload = try NeteasePlaybackLog.upload(song: song, event: event, seconds: seconds,
            completed: completed, cookies: values, deviceID: deviceID)
        let data: Data
        do {
            data = try await perform(upload.request, authentication: authentication, absorbResponseCookies: false)
        } catch let error as URLError where [.secureConnectionFailed, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed].contains(error.code) {
            // Some networks reject the clientlog hostname before any TLS data
            // is sent. NetEase's desktop bundle also configures this first-party
            // upload route on music.163.com. Keep certificate validation, the
            // packet and filename unchanged; never retry a received rejection.
            Self.log.notice("Playback log TLS/connection failed; retrying official music upload endpoint")
            var fallback = upload.request
            fallback.url = URL(string: "https://music.163.com/api/clientlog/encrypt/upload?multiupload=true")!
            data = try await perform(fallback, authentication: authentication, absorbResponseCookies: false)
        }
        struct Acknowledgement: Decodable {
            struct Files: Decodable { let successfiles: [String]?; let rate: Int? }
            let code: Int
            let data: Files?
        }
        let response = try decoded(Acknowledgement.self, from: data)
        Self.log.notice("Playback log receipt: files=\(response.data?.successfiles?.count ?? 0), matched=\(response.data?.successfiles?.contains(upload.filename) == true), rate=\(response.data?.rate ?? -1)")
        guard response.data?.successfiles?.contains(upload.filename) == true else {
            throw NeteaseAPIError.business(code: -1, message: "播放记录日志未被服务器接收")
        }
    }

    private func playbackCookies() -> [String: String] {
        cookieLock.lock(); defer { cookieLock.unlock() }
        return cookies
    }

    /// MeloX's lyric transport profile (GPL-3.0-only; see ThirdPartyNotices/MeloX.md).
    /// Kept separate so lyric endpoint parity does not change account/playback requests.
    func lyricsEAPI(_ path: String, _ payload: [String: Any]) async throws -> Data {
        let authentication = authenticationState
        var header = [
            "os": "ios", "appver": "9.0.90", "osver": "18.0",
            "buildver": String(Int(Date().timeIntervalSince1970)),
            "channel": "distribution",
            "requestId": "\(Int(Date().timeIntervalSince1970 * 1000))_0000",
            "__csrf": cookie(named: "__csrf") ?? ""
        ]
        if let musicU = cookie(named: "MUSIC_U") { header["MUSIC_U"] = musicU }
        var body = payload
        body["header"] = header
        body["e_r"] = false
        let json = try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
        let form = NeteaseCrypto.eapi(apiPath: "/api" + path, payload: json)
        let url = URL(string: "https://interface.music.163.com/eapi\(path)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.httpShouldHandleCookies = false
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 Mobile/15E148", forHTTPHeaderField: "User-Agent")
        request.setValue("https://music.163.com", forHTTPHeaderField: "Referer")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        request.setValue(cookieHeader(extra: [:]), forHTTPHeaderField: "Cookie")
        request.httpBody = Self.encodeForm(form)
        return try await perform(request, authentication: authentication)
    }

    private func perform(_ request: URLRequest, authentication: (epoch: UInt64, binding: String?), absorbResponseCookies: Bool = true) async throws -> Data {
        try Task.checkCancellation()
        // A request sent without a login carries no account's data, so a login
        // finishing while it is in flight does not make its answer stale.
        let anonymous = authentication.binding == nil
        guard anonymous || isCurrent(authentication) else { throw CancellationError() }
        let (data, response) = try await session.data(for: request)
        guard anonymous || isCurrent(authentication) else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw NeteaseAPIError.http(-1) }
        let refreshSucceeded = ["/weapi/login/token/refresh", "/eapi/login/token/refresh"].contains(request.url?.path ?? "")
            && (200..<300).contains(http.statusCode)
            && (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["code"] as? Int == 200
        if absorbResponseCookies,
           !absorbSetCookies(from: http, url: request.url!, epoch: authentication.epoch, preservingSession: refreshSucceeded) {
            // A reply from before a token renewal still belongs to this login,
            // but its older Set-Cookie must not roll back the renewed credentials.
            guard isCurrent(authentication) else { throw CancellationError() }
        }
        guard (200..<300).contains(http.statusCode) else {
            Self.log.error("HTTP \(http.statusCode) for \(request.url?.path ?? "?")")
            throw NeteaseAPIError.http(http.statusCode)
        }
        return data
    }

    /// NOS transfer uses a file stream, without sending the account cookie jar.
    func uploadCloudFile(_ file: URL, bucket: String, objectKey: String,
                         token: String, md5: String, size: Int64) async throws {
        let authentication = authenticationState
        guard authentication.binding != nil else { throw NeteaseAPIError.needLogin }
        var discovery = URLComponents(string: "https://wanproxy.127.net/lbs")!
        discovery.queryItems = [URLQueryItem(name: "version", value: "1.0"),
                                URLQueryItem(name: "bucketname", value: bucket)]
        let data = try await perform(URLRequest(url: discovery.url!), authentication: authentication,
                                     absorbResponseCookies: false)
        struct Hosts: Decodable { let upload: [String] }
        let hosts = try JSONDecoder().decode(Hosts.self, from: data)
        guard let host = hosts.upload.first, var components = URLComponents(string: host),
              let hostname = components.host,
              hostname == "127.net" || hostname.hasSuffix(".127.net") || hostname.hasSuffix(".netease.com") else {
            throw NeteaseAPIError.business(code: -1, message: String(localized: "无法获取云盘上传服务器"))
        }
        components.scheme = "https"
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#%")
        guard let key = objectKey.addingPercentEncoding(withAllowedCharacters: allowed) else {
            throw NeteaseAPIError.decoding("Invalid NOS object key")
        }
        components.percentEncodedPath = "/\(bucket)/\(key)"
        components.queryItems = [URLQueryItem(name: "offset", value: "0"),
                                 URLQueryItem(name: "complete", value: "true"),
                                 URLQueryItem(name: "version", value: "1.0")]
        guard let url = components.url else { throw NeteaseAPIError.decoding("Invalid NOS URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 600
        request.httpShouldHandleCookies = false
        request.setValue(token, forHTTPHeaderField: "x-nos-token")
        request.setValue(md5, forHTTPHeaderField: "Content-MD5")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue(String(size), forHTTPHeaderField: "Content-Length")
        try Task.checkCancellation()
        guard isCurrent(authentication) else { throw CancellationError() }
        let (receipt, response) = try await session.upload(for: request, fromFile: file)
        guard isCurrent(authentication) else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw NeteaseAPIError.http(-1) }
        guard (200..<300).contains(http.statusCode) else { throw NeteaseAPIError.http(http.statusCode) }
        // NOS can also return a structured error with a successful HTTP status.
        if let object = try? JSONSerialization.jsonObject(with: receipt) as? [String: Any],
           let code = object["errCode"] as? Int, code != 0 {
            throw NeteaseAPIError.business(code: -1, message: String(localized: "云盘文件传输失败"))
        }
    }

    /// Performs a request and decodes the response, surfacing business-level errors.
    func decoded<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["code"] as? Int, code != 200 {
            if code == 301 { throw NeteaseAPIError.needLogin }
            let message = (obj["message"] as? String) ?? (obj["msg"] as? String)
            throw NeteaseAPIError.business(code: code, message: message)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            Self.log.error("Decoding \(String(describing: T.self)) failed: \(error)")
            throw NeteaseAPIError.decoding(String(describing: error))
        }
    }

    private static func encodeForm(_ fields: [String: String]) -> Data {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let encoded = fields.map { key, value in
            let v = value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
            return "\(key)=\(v)"
        }.joined(separator: "&")
        return Data(encoded.utf8)
    }
}

#if DEBUG
private final class OfflineUITestProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() { client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet)) }
    override func stopLoading() {}
}
#endif
