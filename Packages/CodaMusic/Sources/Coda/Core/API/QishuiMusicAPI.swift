// Protocol reference: guowenye/qishui-api (MIT), e409c10; see ThirdPartyNotices/Qishui-API.md.
import Foundation
import Combine
import WebKit

struct QishuiTrackReference: Codable, Hashable, Sendable {
    let trackID: String
    var albumID: String? = nil
    var artists: [ProviderArtist]? = nil
}

struct QishuiPlaylistReference: Codable, Hashable, Sendable {
    let playlistID: String
    let type: Int
    var radio: QishuiRadioReference? = nil
}

struct QishuiRadioReference: Codable, Hashable, Sendable {
    let flowType: Int
    let triggerInfo: String
}

enum QishuiError: LocalizedError {
    case business(Int), invalidResponse, expiredLogin, previewOnly, encryptedAudio, unavailable
    case signerFailed
    case invalidPlaylistName
    case loginRejected(code: Int, detail: String)
    var errorDescription: String? {
        switch self {
        case .business(let code): return "汽水音乐请求被拒绝（\(code)），请检查登录状态或稍后重试"
        case .loginRejected(let code, let detail): return "汽水音乐登录未完成（\(code)）：\(detail)"
        case .invalidResponse: return "汽水音乐返回了无法识别的数据，请稍后重试"
        case .expiredLogin: return "汽水音乐登录已失效，请使用汽水音乐 App 重新扫码"
        case .previewOnly: return "汽水音乐当前仅返回试听片段，暂时无法播放完整歌曲"
        case .encryptedAudio: return "汽水音乐返回的音频密钥或加密文件无法读取"
        case .signerFailed: return "汽水音乐请求签名失败，请检查签名服务、访问令牌和设备参数"
        case .invalidPlaylistName: return String(localized: "汽水歌单名称须为 1 到 30 个字符")
        case .unavailable: return "汽水音乐当前未提供可用的完整音频"
        }
    }

    /// Qishui answered but will not serve the full song (no membership or no
    /// rights), so the same recording may still play from another source.
    /// Login and signing failures are the user's to fix and stay as they are.
    var invitesUnblock: Bool {
        switch self {
        case .previewOnly, .unavailable: return true
        default: return false
        }
    }
}

/// Direct native transport with the SodaM signer for PC playback requests.
/// Ephemeral cookie storage belongs to this QR flow; account cookies are explicit.
@MainActor
final class QishuiMusicAPI: ObservableObject {
    static let shared = QishuiMusicAPI(persistsSession: true)
    let session: URLSession
    private let persistsSession: Bool
    let now: () -> Date
    private let usesSignedPassport: Bool
    private let diagnostics: Bool
    private var diagnosticEvents: [[String: Any]] = []
    typealias VerificationHandler = ([String: Any]) async throws -> Void
    private let verificationHandler: VerificationHandler?
    @Published private(set) var verificationWebView: WKWebView?
    private var passportSession: QishuiPassportSession?
    private(set) var passportSignatureLength: Int?
    private(set) var passportMSLength: Int?
    private(set) var passportBrowserInfoLength: Int?
    private(set) var passportTokenMatches: Bool?
    private let credentialKey = "qishui.session.v1"
    var playbackJobs: [PlaybackRequest: PlaybackJob] = [:]
    var preparedPlayback: [PlaybackRequest: PreparedPlayback] = [:]
    private(set) var credentials: [String: String] = [:]
    var userID: String { credentials["userid"] ?? "" }
    var nickname: String { credentials["nickname"] ?? "汽水音乐用户" }
    var isLoggedIn: Bool { !userID.isEmpty && Self.validSessionID(credentials["sessionid"] ?? "") }

    init(configuration: URLSessionConfiguration = .ephemeral, persistsSession: Bool = false, now: @escaping () -> Date = Date.init, usesSignedPassport: Bool = true, verificationHandler: VerificationHandler? = nil, diagnostics: Bool = false) {
        self.persistsSession = persistsSession
        self.now = now
        self.usesSignedPassport = usesSignedPassport
        self.diagnostics = diagnostics
        self.verificationHandler = verificationHandler
        configuration.timeoutIntervalForRequest = 20
        configuration.urlCache = nil
        // Manual cookies prevent requests made while validating another account
        // from replacing the active account's session.
        configuration.httpShouldSetCookies = false
        session = URLSession(configuration: configuration)
        if persistsSession, let saved = ProviderCredentialDefaults.shared.dictionary(forKey: credentialKey) as? [String: String] {
            credentials = saved
        }
    }

    static func validSessionID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 4096 && !value.contains { $0.isWhitespace || $0 == ";" || $0.asciiValue.map { $0 < 32 || $0 == 127 } == true }
    }
    func restore(_ value: [String: String]) throws {
        guard Self.validSessionID(value["sessionid"] ?? ""), value["userid"]?.isEmpty == false else { throw QishuiError.expiredLogin }
        if persistsSession, !ProviderCredentialDefaults.shared.set(value, forKey: credentialKey) {
            throw MusicProviderError.storage(ProviderCredentialDefaults.shared.lastError ?? -1)
        }
        if Self.session(credentials) != Self.session(value) { resetPlaybackPreparation() }
        credentials = value
    }
    /// The credential fields that authenticate requests. A profile refresh only
    /// rewrites the display fields, so in-flight work for the same session stays valid.
    static func session(_ account: [String: String]) -> [String: String] {
        account.filter { $0.key != "nickname" && $0.key != "avatar" }
    }
    func isCurrentSession(_ account: [String: String]) -> Bool {
        Self.session(credentials) == Self.session(account)
    }
    func logout() throws {
        if persistsSession {
            ProviderCredentialDefaults.shared.removeObject(forKey: credentialKey)
            if let error = ProviderCredentialDefaults.shared.lastError { throw MusicProviderError.storage(error) }
        }
        resetPlaybackPreparation()
        credentials = [:]
        searchPages = [:]; artistPages = [:]; commentPages = [:]; qrCookies = [:]
        cancelLogin()
    }

    private struct QRFlow {
        var cookies: [String: String]
        var expiresAt: Date
        var scanned = false
        var transientFailures = 0
        var nextPollAt = Date.distantPast
    }
    private var qrCookies: [String: QRFlow] = [:]
    private var qrGeneration = UUID()
    private var passportDeviceID = String(UInt64.random(in: 1_000_000_000_000_000...9_999_999_999_999_999))
    private var passportInstallID = String(UInt64.random(in: 100_000_000_000_000...999_999_999_999_999))
    private var passportPortraitID = UUID().uuidString.lowercased() + ".login"
    struct QRCode { let token: String; let image: String; let expiresAt: Double; let scanURL: URL }
    enum QRStatus { case waiting, scanned, processing, expired, confirmed([String: String]) }

    func qrCode() async throws -> QRCode {
        cancelLogin()
        diagnosticEvents = []
        let generation = qrGeneration
        if usesSignedPassport { restorePassportIdentity() }
        let query = ["aid": "386088", "passport_jssdk_version": "2.4.13", "passport_jssdk_type": "normal", "is_from_ttaccountsdk": "1", "next": "https://api.qishui.com", "need_logo": "false", "need_short_url": "false", "is_new_login": "1"]
        let (body, cookie) = try await send(host: .pc, path: "/passport/web/get_qrcode/", query: query, cookie: "")
        guard generation == qrGeneration else { throw CancellationError() }
        let data = body["data"] as? [String: Any] ?? body
        let token = Self.string(data["token"]), image = Self.string(data["qrcode"])
        guard !token.isEmpty else { throw QishuiError.invalidResponse }
        let scanURL = try Self.scanLoginURL(indexURL: Self.string(data["qrcode_index_url"]))
        let expiry = Self.qrExpiration(data["expire_time"], now: now())
        qrCookies = [token: QRFlow(cookies: Self.cookieDictionary(cookie), expiresAt: expiry)]
        return .init(token: token, image: image, expiresAt: expiry.timeIntervalSince1970, scanURL: scanURL)
    }

    /// These are client/device identifiers, not account credentials. Reusing
    /// them matches the reference client's identity across app restarts.
    private func restorePassportIdentity() {
        let defaults = UserDefaults.standard
        func digits(_ key: String, count: Int, fallback: String) -> String {
            let saved = defaults.string(forKey: key) ?? ""
            if saved.count == count, saved.allSatisfy(\.isNumber) { return saved }
            defaults.set(fallback, forKey: key)
            return fallback
        }
        passportDeviceID = digits("qishui.passport.deviceID", count: 16, fallback: passportDeviceID)
        passportInstallID = digits("qishui.passport.installID", count: 15, fallback: passportInstallID)
        if let value = defaults.string(forKey: "qishui.passport.portraitID"), value.hasSuffix(".login"), UUID(uuidString: String(value.dropLast(6))) != nil {
            passportPortraitID = value
        } else { defaults.set(passportPortraitID, forKey: "qishui.passport.portraitID") }
    }

    func cancelLogin() {
        qrGeneration = UUID()
        qrCookies = [:]
        verificationWebView = nil
        passportSession?.close()
        passportSession = nil
        passportSignatureLength = nil
        passportMSLength = nil
        passportBrowserInfoLength = nil
        passportTokenMatches = nil
    }

    func cancelVerification() { passportSession?.cancelVerification(); verificationWebView = nil }
    func isQRCodeExpired(token: String) -> Bool { qrCookies[token].map { now() >= $0.expiresAt } ?? true }
    static func qrExpiration(_ value: Any?, now: Date) -> Date {
        let expiry = number(value)
        return expiry > 1_000_000_000 ? Date(timeIntervalSince1970: expiry) : now.addingTimeInterval(expiry > 0 ? min(expiry, 600) : 180)
    }

    /// The Passport bitmap encodes a retired sdk-next webpage (HTTP 404).
    /// The mobile Qishui scanner recognizes this PC login route instead.
    /// Its scan token is separate from the Passport token used for polling.
    static func scanLoginURL(indexURL: String) throws -> URL {
        guard let source = URLComponents(string: indexURL), source.scheme == "https",
              source.host == "bff-pc.qishui.com",
              let token = source.queryItems?.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else { throw QishuiError.invalidResponse }
        var destination = URLComponents()
        destination.scheme = "https"
        destination.host = "bff-pc.qishui.com"
        destination.path = "/light/invoke/scan_login"
        destination.queryItems = [.init(name: "token", value: token), .init(name: "os", value: "Windows"), .init(name: "computer_name", value: "Coda Dev")]
        // A token containing '+' must round-trip through form-style URL parsers.
        destination.percentEncodedQuery = destination.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = destination.url else { throw QishuiError.invalidResponse }
        return url
    }
    func pollQRCode(token: String) async throws -> QRStatus {
        guard var flow = qrCookies[token] else { return .expired }
        guard now() < flow.expiresAt else { qrCookies[token] = nil; return .expired }
        let generation = qrGeneration
        if now() < flow.nextPollAt { return .processing }
        let cookie = Self.cookieHeader(flow.cookies)
        let query = ["aid": "386088", "passport_jssdk_version": "2.4.13", "passport_jssdk_type": "normal", "is_from_ttaccountsdk": "1"]
        let form = ["token": token, "need_logo": "false", "need_short_url": "false", "is_frontier": "true", "is_new_login": "1", "next": "https://api.qishui.com"]
        var (body, received) = try await send(host: .pc, path: "/passport/web/check_qrconnect/", query: query, form: form, cookie: cookie, validatesBusiness: false)
        try requireQR(token: token, generation: generation)
        if Int(Self.number((body["data"] as? [String: Any])?["error_code"] ?? body["error_code"])) == 2046 {
            flow.cookies.merge(Self.cookieDictionary(received)) { _, new in new }
            flow.expiresAt = now().addingTimeInterval(600)
            qrCookies[token] = flow
            var decision = body.merging(body["data"] as? [String: Any] ?? [:]) { _, data in data }
            decision["data"] = nil
            decision["verify_portrait_id"] = decision["verify_portrait_id"] ?? passportPortraitID
            let general = ["device_id": passportDeviceID, "install_id": passportInstallID, "did": passportDeviceID, "iid": passportInstallID, "device_platform": "PC", "version_code": "3.5.2"]
            if Self.string(decision["verify_from"]) == "verify_center" {
                var payload = decision
                payload["aid"] = "386088"
                payload["is_login"] = nil
                for (key, value) in general { payload[key] = value }
                let expanded = try await send(host: .pc, path: "/passport/safe/pack_verify_ways_data/", query: ["aid": "386088"], form: try Self.verificationParameters(payload, protectingIdentity: false), cookie: Self.cookieHeader(flow.cookies))
                decision.merge(expanded.0["data"] as? [String: Any] ?? expanded.0) { _, value in value }
            }
            try requireQR(token: token, generation: generation)
            let business = try Self.verificationParameters(decision["biz_params"])
            if let verificationHandler { try await verificationHandler(decision) }
            else {
                guard let transport = passportSession else { throw QishuiPassportError.verificationUnavailable }
                verificationWebView = transport.verificationView
                defer { verificationWebView = nil }
                do {
                    try await transport.verify(decision, generalParameters: general)
                    recordVerificationDiagnostic(transport.verificationDiagnostic)
                } catch {
                    recordVerificationDiagnostic(transport.verificationDiagnostic)
                    throw error
                }
            }
            try requireQR(token: token, generation: generation)
            var retryForm = form
            retryForm.merge(business) { old, _ in old }
            var retryQuery = query
            retryQuery["isResend"] = "true"
            (body, received) = try await send(host: .pc, path: "/passport/web/check_qrconnect/", query: retryQuery, form: retryForm, cookie: Self.cookieHeader(flow.cookies), validatesBusiness: false)
            try requireQR(token: token, generation: generation)
        }
        let data = body["data"] as? [String: Any] ?? body
        let error = Int(Self.number(data["error_code"] ?? body["error_code"] ?? body["status_code"]))
        let status = Self.string(data["status"] ?? data["qr_status"] ?? body["status"]).lowercased()
        if ["expired", "cancelled", "canceled", "timeout", "-1"].contains(status) || [2, 10001].contains(error) {
            qrCookies[token] = nil; return .expired
        }
        // Response cookies can rotate even while the business result is pending.
        flow.cookies.merge(Self.cookieDictionary(received)) { _, new in new }
        flow.cookies.merge(Self.cookieDictionary(Self.string(data["session_cookie"]))) { _, new in new }
        let observedScan = ["1", "scanned", "scaned", "confirmed", "3", "success", "confirm"].contains(status)
        flow.scanned = flow.scanned || observedScan
        if error != 0 {
            // 1049 is only recoverable within a known scanned flow. Bound the
            // retry window so a persistent client/security rejection is visible.
            if error == 7 || (error == 1049 && flow.scanned) {
                flow.transientFailures += 1
                if flow.transientFailures <= 3 {
                    flow.nextPollAt = now().addingTimeInterval(5)
                    qrCookies[token] = flow
                    return .processing
                }
            }
            qrCookies[token] = nil
            throw Self.loginError(code: error, body: data, secrets: [token] + Array(flow.cookies.values))
        }
        flow.transientFailures = 0
        flow.nextPollAt = .distantPast
        qrCookies[token] = flow
        switch status {
        case "new", "unscanned": return .waiting
        case "1", "scanned", "scaned": return .scanned
        case "confirmed", "3", "success", "confirm":
            // Confirmation may precede issuance of the session cookie. Keep
            // polling this same QR flow; never save an unverified account.
            guard let sessionID = flow.cookies["sessionid"] ?? flow.cookies["sessionid_ss"], Self.validSessionID(sessionID) else { return .processing }
            let accountCookie = Self.cookieHeader(Self.accountCookies(flow.cookies))
            let profile = try await profile(sessionID: sessionID, cookie: accountCookie)
            try requireQR(token: token, generation: generation)
            qrCookies[token] = nil
            passportSession?.close()
            passportSession = nil
            return .confirmed(Self.loginCredentials(sessionID: sessionID, profile: profile, cookie: accountCookie))
        default: throw QishuiError.invalidResponse
        }
    }
    private func requireQR(token: String, generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == qrGeneration, qrCookies[token] != nil else { throw CancellationError() }
    }
    static func verificationParameters(_ input: Any?, protectingIdentity: Bool = true) throws -> [String: String] {
        guard let input else { return [:] }
        let object: [String: Any]
        if let values = input as? [String: Any] { object = values }
        else if let text = input as? String {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
            if let data = text.data(using: .utf8), let values = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { object = values }
            else {
                guard text.contains("="), !text.trimmingCharacters(in: .whitespaces).hasPrefix("{") else { throw QishuiPassportError.invalidResponse }
                guard let items = URLComponents(string: "https://api.qishui.com/?" + text)?.queryItems, !items.isEmpty else { throw QishuiPassportError.invalidResponse }
                object = items.reduce(into: [:]) { $0[$1.name] = $1.value ?? "" }
            }
        } else { throw QishuiPassportError.invalidResponse }
        let protected: Set<String> = ["token", "aid", "cookie", "sessionid", "sessionid_ss", "next", "device_id", "did", "install_id", "iid", "mstoken", "account_sdk_source_info"]
        return try object.reduce(into: [:]) { result, entry in
            guard !protectingIdentity || !protected.contains(entry.key.lowercased()) else { return }
            if JSONSerialization.isValidJSONObject(entry.value) {
                result[entry.key] = String(decoding: try JSONSerialization.data(withJSONObject: entry.value), as: UTF8.self)
            } else { result[entry.key] = Self.string(entry.value) }
        }
    }
    static func loginError(code: Int, body: [String: Any], secrets: [String]) -> QishuiError {
        var detail = string(body["description"] ?? body["status_msg"]).trimmingCharacters(in: .whitespacesAndNewlines)
        for secret in secrets.filter({ $0.count >= 4 }).sorted(by: { $0.count > $1.count }) {
            detail = detail.replacingOccurrences(of: secret, with: "[已隐藏]")
        }
        detail = detail.replacingOccurrences(of: "https?://[^\\s]+", with: "[链接已隐藏]", options: .regularExpression)
        detail = detail.replacingOccurrences(of: "(?i)(sessionid(?:_ss)?|token|cookie|authorization)\\s*[=:]\\s*[^\\s;,]+", with: "$1=[已隐藏]", options: .regularExpression)
        if detail.isEmpty {
            switch code {
            case 1049: detail = "平台未接受本次登录请求，请刷新二维码；若仍失败，需要继续核对客户端校验"
            case 7: detail = "平台持续限制登录请求，请稍后刷新二维码"
            case 2046: detail = "平台要求额外安全验证，当前扫码流程尚未完成该验证"
            default: detail = "平台拒绝本次登录，请刷新二维码后重试"
            }
        }
        return .loginRejected(code: code, detail: String(detail.prefix(180)))
    }

    private static func cookieHeader(_ cookies: [String: String]) -> String {
        cookies.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }
    static func loginCredentials(sessionID: String, profile: [String: Any], cookie: String? = nil) -> [String: String] {
        var result = ["sessionid": sessionID, "userid": string(profile["id"]), "nickname": string(profile["nickname"] ?? profile["name"]), "avatar": profileAvatar(profile)]
        if let cookie { result["cookie"] = Self.cookieHeader(accountCookies(cookieDictionary(cookie))) }
        return result
    }
    /// Profile payloads vary between `medium_avatar_url`, `avatar_url`,
    /// `avatar_thumb` and similar keys, as strings or `{urls, uri}` objects.
    static func profileAvatar(_ profile: [String: Any]) -> String {
        let preferred = ["medium_avatar_url", "large_avatar_url", "avatar_url", "avatar_medium", "avatar_larger", "avatar_large",
                         "thumb_avatar_url", "avatar_thumb", "url_avatar", "avatar"]
        let others = profile.keys.filter { $0.lowercased().contains("avatar") && !preferred.contains($0) }.sorted()
        for key in preferred + others {
            let url = imageURL(profile[key])
            if url.hasPrefix("https://") || url.hasPrefix("http://") { return url }
        }
        return ""
    }
    /// Refreshes the stored nickname and avatar of the active account.
    /// Returns true when the saved credentials changed.
    @discardableResult
    func refreshProfile() async -> Bool {
        let current = credentials
        guard isLoggedIn, let info = try? await profile(credentials: current),
              Self.string(info["id"]) == current["userid"], credentials == current else { return false }
        var next = current
        let avatar = Self.profileAvatar(info), nickname = Self.string(info["nickname"] ?? info["name"])
        if !avatar.isEmpty { next["avatar"] = avatar }
        if !nickname.isEmpty { next["nickname"] = nickname }
        guard next != current else { return false }
        do { try restore(next); return true } catch { return false }
    }
    func profile(credentials: [String: String]) async throws -> [String: Any] {
        try await profile(sessionID: credentials["sessionid"] ?? "", cookie: Self.accountCookie(credentials))
    }
    func profile(sessionID: String, cookie: String? = nil) async throws -> [String: Any] {
        guard Self.validSessionID(sessionID) else { throw QishuiError.expiredLogin }
        let body = try await request(host: .pc, path: "/luna/pc/me", query: ["aid": "386088"], cookie: cookie ?? "sessionid=\(sessionID);")
        let profile = body["my_info"] as? [String: Any] ?? body["user"] as? [String: Any] ?? body
        guard !Self.string(profile["id"]).isEmpty else { throw QishuiError.expiredLogin }
        return profile
    }
    func membership(credentials: [String: String]) async throws -> MusicMembership {
        let info = try await profile(credentials: credentials)
        guard Self.string(info["id"]) == credentials["userid"] else { throw QishuiError.expiredLogin }
        return Self.membership(info)
    }
    static func membership(_ info: [String: Any]) -> MusicMembership {
        guard let value = info["is_vip"] else { return .unknown }
        switch string(value).lowercased() {
        case "true", "1": return .qishuiVIP
        case "false", "0": return .none
        default: return .unknown
        }
    }

    func recommendedPlaylists(limit: Int) async throws -> [ProviderPlaylist] {
        let body = try await request(path: "/luna/discover/mix", payload: ["count": min(50, max(1, limit))])
        return try Self.discoveryPlaylists(in: body, limit: limit)
    }

    private static let chartQuery = [
        "aid": "386088", "app_name": "luna_pc", "device_platform": "windows",
        "version_code": "30030000", "region": "cn"
    ]

    private static let knownCharts: [ProviderPlaylist] = [
        (7_036_274_230_471_712_007, "热歌榜", "tos-cn-i-b829550vbb/discover-mix-tophits"),
        (7_060_812_597_884_869_927, "新歌榜", "tos-cn-i-b829550vbb/discover-mix-newcharts"),
        (7_061_475_546_400_005_410, "欧美榜", "tos-cn-i-b829550vbb/discover-mix-ushits"),
        (7_415_959_718_721_494_311, "音乐人歌曲榜", "tos-cn-v-2774c002/o8FQKiQQBxHWa2hzsBNAgYOX6iEHEAibADAbfB")
    ].map { (id: Int, name: String, uri: String) in
        ProviderPlaylist(id: id, name: name,
                         coverURL: URL(string: "https://p3-luna.douyinpic.com/img/\(uri)~tplv-b829550vbb-resize:960:960.png"),
                         source: .qishui)
    }

    func charts() async throws -> [ProviderPlaylist] {
        let body = try? await request(host: .pc, path: "/luna/pc/discover", query: Self.chartQuery,
                                      payload: [:], cookie: "")
        try Task.checkCancellation()
        let blocks = body?["blocks"] as? [[String: Any]] ?? []
        let charts = blocks.filter { Self.string($0["type"]) == "discover_top_song_list" }
            .flatMap { $0["inner_block"] as? [[String: Any]] ?? [] }
        let discovered = charts.compactMap { block -> ProviderPlaylist? in
            guard Self.string(block["type"]) == "discover_track_top_list",
                  let id = Int(Self.string(block["inner_block_id"])), id > 0,
                  let title = block["title"] as? String, !title.isEmpty else { return nil }
            let resources = Self.discoveryResources(block)
            let cover = Self.knownCharts.first { $0.id == id }?.coverURL ?? resources.lazy.compactMap { resource in
                let entity = resource["entity"] as? [String: Any]
                let ranked = entity?["ranked_track"] as? [String: Any]
                return Self.song(ranked?["track"] as? [String: Any])?.coverURL
            }.first
            return ProviderPlaylist(id: id, name: title, coverURL: cover, trackCount: resources.count, source: .qishui)
        }
        var seen = Set<Int>()
        return (discovered + Self.knownCharts).filter { seen.insert($0.id).inserted }
    }

    struct ChartEntry {
        let song: ProviderSong
        let previousRank: Int?
    }

    func chartEntries(id: Int) async throws -> [ChartEntry] {
        let body = try await request(host: .pc, path: "/luna/pc/charts/\(id)", query: Self.chartQuery, cookie: "")
        guard let chart = body["chart"] as? [String: Any],
              let rows = chart["track_ranks"] as? [[String: Any]] else { throw QishuiError.invalidResponse }
        return rows.enumerated().compactMap { index, row in
            guard let song = Self.song(row["track"] as? [String: Any]) else { return nil }
            let rank = row["rank"] as? [String: Any]
            let delta = Int(Self.string(rank?["rank_delta"])).flatMap { (0...rows.count).contains($0) ? $0 : nil } ?? 0
            let position = index + 1
            let previousRank: Int?
            switch Self.string(rank?["rank_type"]) {
            case "up": previousRank = position + delta
            case "down": previousRank = max(1, position - delta)
            case "equal": previousRank = position
            case "new": previousRank = 0
            default: previousRank = nil
            }
            return ChartEntry(song: song, previousRank: previousRank)
        }
    }

    func discoveryRadios() async throws -> [ProviderPlaylist] {
        let (blocks, _) = try await pcDiscoveryMix(channel: -2)
        var seen = Set<Int>()
        return blocks.flatMap(Self.discoveryResources).compactMap(Self.radioCard)
            .filter { seen.insert($0.id).inserted }
    }

    func discoveryPlaylists(excluding exposureIDs: [UInt64]) async throws
        -> (items: [ProviderPlaylist], exposureIDs: [UInt64], hasMore: Bool) {
        let (blocks, hasMore) = try await pcDiscoveryMix(channel: 0, exposureIDs: exposureIDs)
        var seen = Set<Int>()
        let items = blocks.flatMap { [$0] + Self.discoveryResources($0) }.compactMap { resource in
            Self.playlist((resource["entity"] as? [String: Any])?["playlist"] as? [String: Any])
        }.filter { seen.insert($0.id).inserted }
        let ids = blocks.compactMap { UInt64(Self.string($0["inner_block_id"])) }
        return (items, ids, hasMore)
    }

    private func pcDiscoveryMix(channel: Int, exposureIDs: [UInt64] = []) async throws
        -> (blocks: [[String: Any]], hasMore: Bool) {
        let body = try await request(host: .pc, path: "/luna/pc/discover/mix", query: [
            "aid": "386088", "app_name": "luna_pc", "device_platform": "windows",
            "version_code": "30030000", "region": "cn"
        ], payload: [
            "block_type": "discover_playlist_mix", "sub_channel_id": channel,
            "exposure_radio_list": exposureIDs
        ], cookie: "")
        guard let blocks = body["inner_block"] as? [[String: Any]] else { throw QishuiError.invalidResponse }
        return (blocks, Self.boolean(body["has_more"]))
    }

    private static func discoveryResources(_ block: [String: Any]) -> [[String: Any]] {
        block["resources"] as? [[String: Any]] ?? []
    }

    private static func discoveryPlaylists(in body: [String: Any], limit: Int) throws -> [ProviderPlaylist] {
        guard let blocks = body["inner_block"] as? [[String: Any]] else { throw QishuiError.invalidResponse }
        var seen = Set<Int>()
        return Array(blocks.flatMap { $0["resources"] as? [[String: Any]] ?? [] }.compactMap {
            Self.playlist(($0["entity"] as? [String: Any])?["playlist"] as? [String: Any])
        }.filter { seen.insert($0.id).inserted }.prefix(limit))
    }
    func userPlaylists() async throws -> [ProviderPlaylist] {
        guard isLoggedIn else { throw QishuiError.expiredLogin }
        let account = credentials
        var cursor = "", cursors = Set<String>(), seen = Set<String>(), playlists: [ProviderPlaylist] = []
        repeat {
            let body = try await request(host: .pc, path: "/luna/pc/me/playlist", query: [
                "aid": "386088", "iid": "27960026095955", "version_code": "30020100", "cursor": cursor, "count": "50"
            ], cookie: Self.accountCookie(account))
            guard isCurrentSession(account) else { throw CancellationError() }
            for item in body["playlists"] as? [[String: Any]] ?? [] {
                if var playlist = Self.playlist(item), let id = playlist.qishui?.playlistID, seen.insert(id).inserted {
                    playlist.ownerID = account["userid"]
                    playlists.append(playlist)
                }
            }
            if !Self.boolean(body["has_more"]) { return playlists }
            cursor = Self.string(body["next_cursor"])
            guard !cursor.isEmpty, cursors.insert(cursor).inserted, cursors.count < 200 else { throw QishuiError.invalidResponse }
        } while true
    }

    // Protocol: libresoda playlist_edit.rs, 0c6f4df; see qishui-integration.md.
    func createPlaylist(name: String, isPrivate: Bool) async throws -> ProviderPlaylist {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.unicodeScalars.count <= 30 else { throw QishuiError.invalidPlaylistName }
        let body = try await signedPCPost(path: "/luna/pc/me/playlist", payload: ["name": name, "is_private": isPrivate])
        let data = body["data"] as? [String: Any] ?? [:]
        var fields = (data["playlist"] ?? body["playlist"]) as? [String: Any] ?? [:]
        // Success can omit status_code. Require the returned ID before
        // publishing the playlist, and keep it as a string.
        let ids = [fields["id"], data["playlist_id"], data["id"], body["playlist_id"]]
        guard let id = ids.lazy.map({ Self.string($0).trimmingCharacters(in: .whitespacesAndNewlines) })
            .first(where: { !$0.isEmpty && $0 != "0" }) else { throw QishuiError.invalidResponse }
        fields["id"] = id
        if Self.string(fields["name"]).isEmpty { fields["name"] = name }
        guard var playlist = Self.playlist(fields) else { throw QishuiError.invalidResponse }
        playlist.ownerID = userID
        playlist.isOwned = true
        return playlist
    }

    func setLiked(trackID: String, liked: Bool) async throws {
        var payload: [String: Any] = ["media": [["type": "track", "id": trackID]]]
        if liked { payload["scene"] = "" }
        try await writeCollection("media", payload: payload, save: liked)
    }

    enum CollectionKind: String { case playlist, album, artist }

    func setCollection(_ kind: CollectionKind, id: String, saved: Bool) async throws {
        guard !id.isEmpty else { throw MusicProviderError.missingTrack }
        try await writeCollection(kind.rawValue, payload: ["\(kind.rawValue)_ids": [id]], save: saved)
    }

    private func writeCollection(_ kind: String, payload: [String: Any], save: Bool) async throws {
        let path = "/luna/pc/me/collection/\(kind)" + (save ? "" : "/delete")
        let body = try await signedPCPost(path: path, payload: payload)
        guard Self.string(body["status_code"]) == "0" ||
              (body["status_code"] == nil && body["status_info"] is [String: Any]) else {
            throw QishuiError.invalidResponse
        }
    }

    func collectionItems(_ kind: CollectionKind) async throws -> [[String: Any]] {
        guard isLoggedIn else { throw QishuiError.expiredLogin }
        let account = credentials
        let key = kind.rawValue
        let path = kind == .artist ? "/luna/me/collection/artist" : "/luna/me/collection/mixed"
        var query = ["aid": "386088", "app_name": "luna_pc", "device_platform": "windows",
                     "version_code": "30030000", "cursor": "", "count": "100"]
        if kind != .artist { query["item_types"] = key }
        var items: [[String: Any]] = [], ids = Set<String>(), cursors = Set<String>()
        repeat {
            let body: [String: Any]
            do {
                body = try await send(host: .pc, path: path, query: query, cookie: Self.accountCookie(account),
                                      userAgent: "LunaPC/3.3.0(359450208)", protectsAccount: true).0
            } catch QishuiError.business(1000016) {
                throw QishuiError.expiredLogin
            }
            try Task.checkCancellation()
            guard isCurrentSession(account) else { throw CancellationError() }
            let hasMore = Self.boolean(body["has_more"])
            let rows = kind == .artist ? body["artists"] ?? body["artist_collections"] : body["mixed_collections"]
            if let rows = rows as? [[String: Any]] {
                for row in rows {
                    guard let item = row[key] as? [String: Any] ?? (kind == .artist ? row : nil) else { continue }
                    let id = Self.string(item["id"])
                    if !id.isEmpty, ids.insert(id).inserted { items.append(item) }
                }
            } else if rows != nil || hasMore || (body["status_info"] == nil && Self.string(body["status_code"]) != "0") {
                throw QishuiError.invalidResponse
            }
            if !hasMore { return items }
            let cursor = Self.string(body["next_cursor"])
            guard !cursor.isEmpty, cursors.insert(cursor).inserted, cursors.count < 200 else { throw QishuiError.invalidResponse }
            query["cursor"] = cursor
        } while true
    }

    private static let historyPath = "/luna/pc/me/recently-played-media"

    func recentSongPlays(limit: Int) async throws -> [(song: ProviderSong, playedAt: Date)] {
        guard isLoggedIn else { throw QishuiError.expiredLogin }
        guard limit > 0 else { return [] }
        let account = credentials
        let ticket = MusicProviderContext.shared.ticket
        var cursor = ""
        var cursors = Set<String>()
        var seen = Set<String>()
        var entries: [(song: ProviderSong, playedAt: Date)] = []
        repeat {
            guard cursors.count < 20, cursors.insert(cursor).inserted else { throw QishuiError.invalidResponse }
            let body = try await historyRequest(account: account, query: [
                "cursor": cursor, "count": String(min(50, limit)), "media_type": "track", "scene": ""
            ])
            try MusicProviderContext.shared.check(ticket)
            guard isCurrentSession(account) else { throw CancellationError() }
            guard let rows = body["media"] as? [[String: Any]] else {
                // The service omits default-valued fields, including an empty media list.
                if body["media"] == nil, Self.number(body["total_num"]) == 0,
                   Self.string(body["next_cursor"]).isEmpty, !Self.boolean(body["has_more"]),
                   body["status_info"] is [String: Any] || Self.string(body["status_code"]) == "0" {
                    return entries
                }
                throw QishuiError.invalidResponse
            }
            for row in rows {
                let time = Self.number(row["play_start_timestamp"])
                guard time.isFinite, time > 0, time < 100_000_000_000_000,
                      let song = Self.song(Self.trackEntity(row)), let id = song.qishui?.trackID,
                      seen.insert(id).inserted else { continue }
                entries.append((song, Date(timeIntervalSince1970: time > 10_000_000_000 ? time / 1_000 : time)))
                if entries.count == limit { return entries }
            }
            if !Self.boolean(body["has_more"]) { return entries }
            cursor = Self.string(body["next_cursor"])
            guard !cursor.isEmpty else { throw QishuiError.invalidResponse }
        } while true
    }

    func appendRecentPlay(trackID: String) async throws {
        guard isLoggedIn else { throw QishuiError.expiredLogin }
        guard !trackID.isEmpty, trackID.utf8.allSatisfy({ (48...57).contains($0) }) else {
            throw MusicProviderError.missingTrack
        }
        let account = credentials
        let body = try await historyRequest(account: account, payload: ["media": [["id": trackID, "type": "track"]]])
        guard isCurrentSession(account) else { throw CancellationError() }
        guard Self.string(body["status_code"]) == "0" ||
              (body["status_code"] == nil && body["status_info"] is [String: Any]) else {
            throw QishuiError.invalidResponse
        }
    }

    private func historyRequest(account: [String: String], query: [String: String] = [:],
                                payload: [String: Any]? = nil) async throws -> [String: Any] {
        let parameters = query.merging([
            "aid": "386088", "iid": "27960026095955", "version_code": "30030000", "device_platform": "windows"
        ]) { first, _ in first }
        do {
            return try await send(host: .pc, path: Self.historyPath, query: parameters, payload: payload,
                                  cookie: Self.accountCookie(account), userAgent: "LunaPC/3.3.0(359450208)",
                                  protectsAccount: true).0
        } catch QishuiError.business(1000016) {
            throw QishuiError.expiredLogin
        }
    }

    func playlistSongs(_ reference: QishuiPlaylistReference) async throws -> [ProviderSong] {
        if let radio = reference.radio {
            return try await feedPage(feedState(.radio(id: reference.playlistID, radio))).songs
        }
        return try await playlistDetail(reference).songs
    }

    func playlistDetail(_ reference: QishuiPlaylistReference) async throws -> (playlist: ProviderPlaylist?, songs: [ProviderSong]) {
        do {
            return try await loadPlaylist(reference, host: .pc)
        } catch QishuiError.invalidResponse {
            // The app route also accepts the playlist's type. Restart from its
            // first page because cursors are specific to the original route.
            try Task.checkCancellation()
            return try await loadPlaylist(reference, host: .app)
        }
    }

    private func loadPlaylist(_ reference: QishuiPlaylistReference, host: Host) async throws
        -> (playlist: ProviderPlaylist?, songs: [ProviderSong]) {
        let account = credentials
        let cookie = isLoggedIn ? Self.accountCookie(account) : ""
        var cursor = "", visited = Set<String>(), songs: [ProviderSong] = [], seen = Set<String>()
        var trackCount: Int?
        var playlist: ProviderPlaylist?
        var hasNonTrackMedia = false
        repeat {
            try Task.checkCancellation()
            let response: [String: Any]
            if host == .pc {
                response = try await send(host: .pc, path: "/luna/pc/playlist/detail", query: [
                    "aid": "386088", "playlist_id": reference.playlistID, "cursor": cursor, "count": "50",
                    "app_name": "luna_pc", "device_platform": "windows", "version_code": "30030000"
                ], cookie: cookie, userAgent: "LunaPC/3.3.0(359450208)", protectsAccount: true).0
            } else {
                response = try await send(host: .app, path: "/luna/playlist/detail", payload: [
                    "playlist_id": reference.playlistID, "playlist_type": reference.type, "cursor": cursor, "count": 50
                ], cookie: cookie, protectsAccount: true).0
            }
            try Task.checkCancellation()
            guard isCurrentSession(account) else { throw CancellationError() }
            let body = response["data"] as? [String: Any] ?? response
            if let metadata = body["playlist"] as? [String: Any] {
                trackCount = Int(Self.string(metadata["count_tracks"] ?? metadata["track_count"])) ?? trackCount
                if let item = Self.playlist(metadata), item.qishui?.playlistID == reference.playlistID {
                    playlist = playlist ?? item
                }
            }
            let hasMore = Self.boolean(body["has_more"])
            guard let resources = body["media_resources"] as? [[String: Any]] else {
                if body["media_resources"] == nil || body["media_resources"] is NSNull,
                   !hasMore, trackCount == 0 || (!cursor.isEmpty && !songs.isEmpty) { return (playlist, songs) }
                throw QishuiError.invalidResponse
            }
            for resource in resources {
                let entity = resource["entity"] as? [String: Any] ?? resource
                hasNonTrackMedia = hasNonTrackMedia || entity["video"] is [String: Any] || entity["ugc_video"] is [String: Any]
                if let song = Self.song(Self.trackEntity(resource)), let id = song.qishui?.trackID, seen.insert(id).inserted { songs.append(song) }
            }
            if !hasMore {
                guard !songs.isEmpty || trackCount == 0 || hasNonTrackMedia ||
                        (resources.isEmpty && trackCount == nil) else { throw QishuiError.invalidResponse }
                return (playlist, songs)
            }
            let next = Self.string(body["next_cursor"])
            guard !next.isEmpty, next != cursor, visited.insert(next).inserted else { throw QishuiError.invalidResponse }
            cursor = next
            // Protect against a server that returns an unbounded stream as a playlist.
            guard visited.count < 200 else { throw QishuiError.invalidResponse }
        } while true
    }

    private struct CursorPage {
        var resources: [[String: Any]] = []
        var cursor = "0"
        var more = true
        var seen: Set<String> = []
        var cursors: Set<String> = []
    }
    private var searchPages: [String: CursorPage] = [:]
    struct SearchResult {
        var songs: [ProviderSong] = []
        var playlists: [ProviderPlaylist] = []
        var albums: [ProviderAlbum] = []
        var artists: [ProviderArtist] = []
        var total: Int?
    }
    func search(keyword: String, playlists: Bool, limit: Int, offset: Int) async throws -> SearchResult {
        try await search(keyword: keyword, type: playlists ? .playlists : .songs, limit: limit, offset: offset)
    }

    func search(keyword: String, type: NeteaseAPI.SearchType, limit: Int, offset: Int) async throws -> SearchResult {
        let entityType: String
        switch type {
        case .songs: entityType = "track"
        case .playlists: entityType = "playlist"
        case .albums: entityType = "album"
        case .artists: entityType = "artist"
        }
        let revision = MusicProviderContext.shared.ticket
        let key = "\(revision):\(keyword):\(entityType)"
        var page = offset == 0 ? CursorPage() : searchPages[key] ?? CursorPage()
        // Fill the shared offset/limit contract using the actual server cursor.
        while page.resources.count < offset + limit, page.more {
            guard page.cursors.count < 200, page.cursors.insert(page.cursor).inserted else { throw QishuiError.invalidResponse }
            let body = try await signedPCRequest(path: "/luna/pc/search/\(entityType)",
                parameters: ["q": keyword, "cursor": page.cursor, "count": "20"])
            guard let groups = body["result_groups"] as? [[String: Any]] else { throw QishuiError.invalidResponse }
            let resources = groups.flatMap { $0["data"] as? [[String: Any]] ?? [] }
            for resource in resources {
                let entity = resource["entity"] as? [String: Any] ?? resource
                let object = type == .songs ? Self.trackEntity(resource) : entity[entityType] as? [String: Any]
                if let object, !Self.string(object["id"]).isEmpty, page.seen.insert(Self.string(object["id"])).inserted { page.resources.append(object) }
            }
            let pagination = groups.first { Self.boolean($0["has_more"]) } ?? groups.first
            let next = Self.string(pagination?["next_cursor"] ?? body["next_cursor"] ?? body["cursor"])
            page.more = Self.boolean(pagination?["has_more"] ?? body["has_more"]) && !next.isEmpty && next != page.cursor
            page.cursor = next
            try MusicProviderContext.shared.check(revision)
        }
        try MusicProviderContext.shared.check(revision)
        if searchPages.count > 30 { searchPages = [:] }
        searchPages[key] = page
        let objects = Array(page.resources.dropFirst(offset).prefix(limit))
        let total = page.more ? nil : page.resources.count
        switch type {
        case .songs: return .init(songs: objects.compactMap(Self.song), total: total)
        case .playlists: return .init(playlists: objects.compactMap(Self.playlist), total: total)
        case .albums: return .init(albums: objects.compactMap(Self.albumMetadata), total: total)
        case .artists: return .init(artists: objects.compactMap(Self.artistMetadata), total: total)
        }
    }

    private struct CommentPage { var items: [[String: Any]] = []; var cursor = ""; var more = true; var seen: Set<String> = []; var cursors: Set<String> = []; var total = 0 }
    private var commentPages: [String: CommentPage] = [:]
    func comments(trackID: String, sort: SongCommentSort, offset: Int, limit: Int) async throws -> SongCommentsPage {
        let revision = MusicProviderContext.shared.ticket
        let key = "\(revision):\(trackID):\(sort.rawValue)"
        var page = offset == 0 ? CommentPage() : commentPages[key] ?? CommentPage()
        while page.items.count < offset + limit, page.more {
            guard page.cursors.count < 200, page.cursors.insert(page.cursor).inserted else { throw QishuiError.invalidResponse }
            let body = try await request(host: .pc, path: "/luna/pc/comments", query: [
                "aid": "386088", "group_id": trackID, "group_type": "0", "count": "20",
                "cursor": page.cursor, "sort_type": sort == .latest ? "time" : "hot", "image_strategy": "2"
            ])
            let total = Int(Self.string(body["count"]))
            let hasMore = Self.boolean(body["has_more"])
            let items: [[String: Any]]
            if let comments = body["comments"] as? [[String: Any]] { items = comments }
            else if body["comments"] == nil, total == 0, !hasMore { items = [] }
            else { throw QishuiError.invalidResponse }
            for item in items {
                let id = Self.string(item["id"])
                if !id.isEmpty, page.seen.insert(id).inserted { page.items.append(Self.comment(item)) }
            }
            page.total = total ?? page.total
            let next = Self.string(body["cursor"])
            guard !hasMore || (!next.isEmpty && !page.cursors.contains(next)) else { throw QishuiError.invalidResponse }
            page.more = hasMore
            page.cursor = next
            try MusicProviderContext.shared.check(revision)
        }
        try MusicProviderContext.shared.check(revision)
        if commentPages.count > 30 { commentPages = [:] }
        commentPages[key] = page
        let items = Array(page.items.dropFirst(offset).prefix(limit))
        return try PlatformMusicAPI.decode(SongCommentsPage.self, ["comments": items, "hotComments": items, "total": max(page.total, page.items.count), "more": page.more || page.items.count > offset + items.count])
    }
    static func comment(_ item: [String: Any]) -> [String: Any] {
        let user = item["user"] as? [String: Any] ?? [:]
        let nickname = string(user["nickname"])
        return [
            "commentId": PlatformMusicAPI.identifier(provider: .qishui, kind: "comment", value: string(item["id"])),
            "content": string(item["content"]), "time": number(item["time_created"]) * 1000,
            "likedCount": Int(string(item["count_digged"])) ?? 0, "liked": boolean(item["user_digged"]),
            "user": [
                "userId": PlatformMusicAPI.identifier(provider: .qishui, kind: "user", value: string(user["id"])),
                "nickname": nickname.isEmpty ? "汽水音乐用户" : nickname,
                "avatarUrl": imageURL(user["thumb_avatar_url"] ?? user["medium_avatar_url"])
            ]
        ]
    }

    static func song(_ object: [String: Any]?) -> ProviderSong? {
        guard let object, !string(object["id"]).isEmpty else { return nil }
        let id = string(object["id"])
        let album = albumMetadata(object["album"] as? [String: Any])
        let artistObjects = object["artists"] as? [[String: Any]] ?? []
        let artists = artistObjects.compactMap(artistMetadata)
        let names = artistObjects.map(artistName).filter { !$0.isEmpty }
        let cover = album?.coverURL ?? URL(string: imageURL(object["url_cover"] ?? object["cover_url"]))
        return ProviderSong(id: PlatformMusicAPI.identifier(provider: .qishui, kind: "song", value: id),
            name: string(object["name"]), artists: names.joined(separator: " / "), album: album?.name ?? "",
            coverURL: cover, duration: number(object["duration"] ?? object["duration_ms"]) / 1000,
            source: .qishui, qishui: .init(trackID: id, albumID: album?.id, artists: artists))
    }

    private static func artistName(_ artist: [String: Any]) -> String {
        string(artist["name"] ?? artist["simple_display_name"] ?? (artist["user_info"] as? [String: Any])?["nickname"])
    }

    static func artistMetadata(_ object: [String: Any]) -> ProviderArtist? {
        let id = string(object["id"]), name = artistName(object)
        guard !id.isEmpty, !name.isEmpty else { return nil }
        let image = imageURL(object["url_avatar"] ?? object["avatar_url"])
        return .init(id: id, name: name, coverURL: URL(string: image), source: .qishui)
    }

    static func albumMetadata(_ object: [String: Any]?) -> ProviderAlbum? {
        guard let object else { return nil }
        let image = imageURL(object["url_cover"] ?? object["cover_url"])
        let artists = (object["artists"] as? [[String: Any]] ?? []).map(artistName).filter { !$0.isEmpty }
        let releaseDate = number(object["release_date"])
        let milliseconds = releaseDate < 10_000_000_000 ? releaseDate * 1000 : releaseDate
        return .init(id: string(object["id"]), name: string(object["name"]), artistName: artists.joined(separator: " / "),
                     coverURL: URL(string: image), source: .qishui, trackCount: Int(number(object["count_tracks"])),
                     releaseDateMS: milliseconds > 0 && milliseconds < Double(Int.max) ? Int(milliseconds) : nil)
    }

    func artistDetail(_ id: String) async throws -> (ProviderArtist?, [ProviderSong]) {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { throw QishuiError.unavailable }
        let limit = 50
        async let page = try? artistContent(id, kind: .tracks, limit: limit, offset: 0)
        let body = try await send(host: .pc, path: "/luna/pc/artists/\(id)", query: ["aid": "386088"],
                                  cookie: nil, userAgent: "LunaPC/3.3.0(359450208)").0
        let tracks = body["hot_tracks"] as? [[String: Any]] ?? []
        let metadata = (body["artist_info"] as? [String: Any]).flatMap(Self.artistMetadata)
        guard metadata != nil || body["hot_tracks"] != nil else { throw QishuiError.invalidResponse }
        let additionalTracks = await page?.items ?? []
        try Task.checkCancellation()
        var seen = Set<Int>()
        let songs = (tracks + additionalTracks).compactMap(Self.song).filter { seen.insert($0.id).inserted }
        return (metadata, Array(songs.prefix(limit)))
    }

    enum ArtistContent: String {
        case tracks, albums
    }

    private var artistPages: [String: CursorPage] = [:]

    func artistContent(_ id: String, kind: ArtistContent, limit: Int, offset: Int) async throws -> (items: [[String: Any]], hasMore: Bool) {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { throw QishuiError.unavailable }
        let revision = MusicProviderContext.shared.ticket
        let key = "\(revision):\(id):\(kind.rawValue)"
        var page = offset == 0 ? CursorPage(cursor: "") : artistPages[key] ?? CursorPage(cursor: "")
        while page.resources.count < offset + limit, page.more {
            guard page.cursors.count < 200, page.cursors.insert(page.cursor).inserted else { throw QishuiError.invalidResponse }
            let body = try await send(host: .pc, path: "/luna/pc/artists/\(id)/\(kind.rawValue)",
                query: ["aid": "386088", "cursor": page.cursor, "count": String(min(100, max(1, limit)))],
                cookie: nil, userAgent: "LunaPC/3.3.0(359450208)").0
            try MusicProviderContext.shared.check(revision)
            let items = body[kind.rawValue] as? [[String: Any]] ?? []
            for item in items {
                let id = Self.string(item["id"])
                if !id.isEmpty, page.seen.insert(id).inserted { page.resources.append(item) }
            }
            let next = Self.string(body["next_cursor"])
            page.more = !items.isEmpty && !next.isEmpty && !page.cursors.contains(next)
                && (body["has_more"].map(Self.boolean) ?? true)
            page.cursor = next
        }
        try MusicProviderContext.shared.check(revision)
        if artistPages.count > 30 { artistPages.removeAll() }
        artistPages[key] = page
        return (Array(page.resources.dropFirst(offset).prefix(limit)),
                page.more || page.resources.count > offset + limit)
    }

    func albumDetail(_ id: String) async throws -> (ProviderAlbum?, ProviderArtist?, [ProviderSong]) {
        guard !id.isEmpty, id.utf8.allSatisfy({ (48...57).contains($0) }) else { throw QishuiError.unavailable }
        let body = try await send(host: .pc, path: "/luna/pc/albums/\(id)", query: ["aid": "386088"],
                                  cookie: nil, userAgent: "LunaPC/3.3.0(359450208)").0
        guard let tracks = body["tracks"] as? [[String: Any]] else { throw QishuiError.invalidResponse }
        let album = body["album_info"] as? [String: Any]
        let artist = (album?["artists"] as? [[String: Any]])?.compactMap(Self.artistMetadata).first
        return (Self.albumMetadata(album), artist, tracks.compactMap { track in
            var track = track
            if track["album"] == nil { track["album"] = album }
            return Self.song(track)
        })
    }
    static func playlist(_ object: [String: Any]?) -> ProviderPlaylist? {
        guard let object, !string(object["id"]).isEmpty else { return nil }
        let id = string(object["id"])
        let name = ["public_title", "title", "name"].lazy.map { string(object[$0]) }.first { !$0.isEmpty } ?? ""
        let owner = object["owner"] as? [String: Any]
        var playlist = ProviderPlaylist(id: PlatformMusicAPI.identifier(provider: .qishui, kind: "playlist", value: id),
            name: name, coverURL: URL(string: imageURL(object["url_cover"] ?? object["cover_url"])),
            trackCount: Int(number(object["count_tracks"] ?? object["track_count"])), source: .qishui)
        playlist.ownerID = owner.map { string($0["id"]) }
        playlist.qishui = .init(playlistID: id, type: Int(number(object["type"] ?? object["playlist_type"])))
        return playlist
    }
    static func trackEntity(_ resource: [String: Any]) -> [String: Any]? {
        let entity = resource["entity"] as? [String: Any] ?? resource
        return (entity["track_wrapper"] as? [String: Any])?["track"] as? [String: Any] ?? entity["track"] as? [String: Any]
    }
    static func string(_ value: Any?) -> String { value as? String ?? (value as? NSNumber)?.stringValue ?? "" }
    static func number(_ value: Any?) -> Double { (value as? NSNumber)?.doubleValue ?? Double(value as? String ?? "") ?? 0 }
    static func boolean(_ value: Any?) -> Bool { ["1", "true"].contains(string(value).lowercased()) }
    static func imageURL(_ value: Any?) -> String {
        if let text = value as? String { return text }
        guard let object = value as? [String: Any] else { return (value as? [String])?.first ?? "" }
        let uri = string(object["uri"])
        let template = string(object["template_prefix"])
        if !uri.isEmpty, !template.isEmpty, !uri.contains("://") {
            return "https://p3-luna.douyinpic.com/img/\(uri)~\(template)-resize:960:960.png"
        }
        if let urls = object["urls"] as? [String], let first = urls.first(where: { !$0.isEmpty }) {
            return uri.isEmpty || first.contains(uri) || !first.hasSuffix("/") ? first : first + uri
        }
        return string(object["url"] ?? object["uri"])
    }

    enum Host: String { case app = "https://beta-luna.douyin.com", pc = "https://api.qishui.com" }
    func request(host: Host = .app, path: String, query: [String: String] = [:], payload: [String: Any]? = nil, cookie: String? = nil) async throws -> [String: Any] {
        try await send(host: host, path: path, query: query, payload: payload, cookie: cookie).0
    }
    func send(host: Host, path: String, query: [String: String] = [:], payload: [String: Any]? = nil, form: [String: String]? = nil, cookie: String?, validatesBusiness: Bool = true, userAgent: String? = nil, timeout: TimeInterval? = nil, protectsAccount: Bool = false) async throws -> ([String: Any], String) {
        let passport = host == .pc && QishuiPassportSession.supportsPath(path)
        var parameters = query
        if passport {
            parameters.merge([
                "aid": "386088", "passport_jssdk_version": "2.4.13", "passport_jssdk_type": "normal", "is_from_ttaccountsdk": "1",
                "language": "zh", "account_sdk_source": "web", "p_js_v": "2.4.13", "p_js_t": "pro", "p_zt": "3.3.5", "p_ver": "1.0.29", "p_bd": "1.0.0.41",
                "is_from_iesaccountsaas": "1", "request_host": "app%3A%2F%2Fresources", "is_new_login": "1", "device_platform": "PC", "version_code": "3.5.2",
                "device_id": passportDeviceID, "did": passportDeviceID, "install_id": passportInstallID, "iid": passportInstallID,
                "biz_trace_id": String(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(8))
            ]) { _, current in current }
        }
        var components = URLComponents(string: host.rawValue + path)!
        components.queryItems = parameters.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        var request = URLRequest(url: components.url!)
        if let timeout { request.timeoutInterval = timeout }
        request.setValue(userAgent ?? (host == .pc ? "LunaPC/3.0.0(290101097)" : "Luna/19.1.0 Android"), forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(cookie ?? (isLoggedIn ? Self.accountCookie(credentials) : ""), forHTTPHeaderField: "Cookie")
        if let payload { request.httpMethod = "POST"; request.httpBody = try JSONSerialization.data(withJSONObject: payload); request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type") }
        if let form {
            var encoded = URLComponents(); encoded.queryItems = form.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
            request.httpMethod = "POST"; request.httpBody = encoded.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B").data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        }
        if passport {
            request.setValue("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) SodaMusic/3.5.2 Chrome/136.0.7103.59 Electron/36.4.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
            request.setValue("application/json, text/javascript", forHTTPHeaderField: "Accept")
            request.setValue("app://resources/", forHTTPHeaderField: "Referer")
            request.setValue(passportPortraitID, forHTTPHeaderField: "X-Tt-Passport-Verify-Portrait")
            request.setValue(parameters["biz_trace_id"], forHTTPHeaderField: "X-Tt-Passport-Trace-Id")
            let trace = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
            request.setValue("00-\(trace)-\(trace.prefix(16))-01", forHTTPHeaderField: "X-Tt-Trace-Id")
            let cookies = Self.cookieDictionary(cookie ?? "")
            request.setValue(cookies["passport_csrf_token"] ?? cookies["passport_csrf_token_default"], forHTTPHeaderField: "X-Tt-Passport-Csrf-Token")
            if let body = request.httpBody { request.setValue(body.md5Hex().uppercased(), forHTTPHeaderField: "X-Ss-Stub") }
        }
        if passport && usesSignedPassport {
            let transport = passportSession ?? QishuiPassportSession()
            passportSession = transport
            let result = try await transport.send(request)
            try Task.checkCancellation()
            passportSignatureLength = result.signatureLength
            passportMSLength = result.msTokenLength
            passportBrowserInfoLength = result.browserInfoLength
            passportTokenMatches = result.sessionTokenMatches
            recordPassportDiagnostic(path: path, body: result.body, cookie: result.cookieHeader)
            if validatesBusiness { try Self.validate(result.body) }
            return (result.body, result.cookieHeader)
        }
        if protectsAccount, let body = request.httpBody {
            request.setValue(body.md5Hex().uppercased(), forHTTPHeaderField: "X-SS-STUB")
        }
        let (data, response) = try await session.data(for: request, delegate: protectsAccount ? QishuiNoRedirect() : nil)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw QishuiError.invalidResponse }
        if [401, 403].contains(http.statusCode) { throw QishuiError.expiredLogin }
        guard (200..<300).contains(http.statusCode) else { throw QishuiError.business(http.statusCode) }
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw QishuiError.invalidResponse }
        if validatesBusiness { try Self.validate(body) }
        let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
        let cookie = HTTPCookie.cookies(withResponseHeaderFields: headers, for: request.url!).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return (body, cookie)
    }
    /// Only field presence, lengths and known state/code values are retained.
    /// No token, cookie value, account identity, SDK payload or signed URL.
    private func recordPassportDiagnostic(path: String, body: [String: Any], cookie: String) {
        guard diagnostics else { return }
        var entry = Self.passportDiagnostic(path: path, body: body, cookie: cookie)
        entry["time"] = ISO8601DateFormatter().string(from: now())
        entry["signatureLength"] = passportSignatureLength ?? 0
        entry["msTokenLength"] = passportMSLength ?? 0
        entry["browserInfoPresent"] = (passportBrowserInfoLength ?? 0) > 0
        entry["sessionTokenMatches"] = passportTokenMatches ?? false
        appendDiagnostic(entry)
    }
    private func recordVerificationDiagnostic(_ detail: [String: Any]) {
        guard diagnostics, !detail.isEmpty else { return }
        var entry = detail
        entry["stage"] = "verify-component"
        entry["step"] = detail["stage"] ?? "unknown"
        entry["time"] = ISO8601DateFormatter().string(from: now())
        appendDiagnostic(entry)
    }
    private func appendDiagnostic(_ entry: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(entry) else { return }
        diagnosticEvents.append(entry)
        diagnosticEvents = Array(diagnosticEvents.suffix(60))
        let url = CodaPaths.applicationSupport.appendingPathComponent("Diagnostics/qishui-login.json")
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONSerialization.data(withJSONObject: ["events": diagnosticEvents], options: [.prettyPrinted, .sortedKeys]).write(to: url, options: .atomic)
        } catch { /* Diagnostics must never alter the login result. */ }
    }
    static func passportDiagnostic(path: String, body: [String: Any], cookie: String) -> [String: Any] {
        let data = body["data"] as? [String: Any] ?? body
        let raw = string(data["status"]).lowercased()
        let statuses: Set<String> = ["new", "unscanned", "scanned", "scaned", "confirmed", "confirm", "success", "expired", "timeout", "cancelled", "canceled", "1", "3", "-1"]
        let stage = path.contains("get_qrcode") ? "create" : path.contains("check_qrconnect") ? "poll" : "verification"
        let cookies = cookieDictionary(cookie)
        return ["stage": stage, "status": statuses.contains(raw) ? raw : raw.isEmpty ? "empty" : "unrecognized",
            "code": Int(number(data["error_code"] ?? body["error_code"] ?? body["status_code"])),
            "hasSession": cookies["sessionid"] != nil || cookies["sessionid_ss"] != nil,
            "hasCSRF": cookies["passport_csrf_token"] != nil || cookies["passport_csrf_token_default"] != nil]
    }
    static func validate(_ body: [String: Any]) throws {
        for name in ["status_code", "error_code"] {
            if let code = body[name], number(code) != 0 { throw QishuiError.business(Int(number(code))) }
        }
        if let data = body["data"] as? [String: Any], let code = data["error_code"], number(code) != 0 { throw QishuiError.business(Int(number(code))) }
    }
    private static func cookieDictionary(_ header: String) -> [String: String] {
        header.split(separator: ";").reduce(into: [:]) { result, part in
            let pair = part.split(separator: "=", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            if pair.count == 2 { result[pair[0]] = pair[1] }
        }
    }
    private static func accountCookies(_ values: [String: String]) -> [String: String] {
        let allowed: Set<String> = ["sessionid", "sessionid_ss", "sid_guard", "sid_tt", "uid_tt", "uid_tt_ss", "ssid_ucp_v1", "session_tlb_tag", "passport_csrf_token", "passport_csrf_token_default"]
        return values.filter { allowed.contains($0.key) && validSessionID($0.value) }
    }
    static func accountCookie(_ credentials: [String: String]) -> String {
        let stored = accountCookies(cookieDictionary(credentials["cookie"] ?? ""))
        if !stored.isEmpty { return cookieHeader(stored) }
        return validSessionID(credentials["sessionid"] ?? "") ? "sessionid=\(credentials["sessionid"] ?? "");" : ""
    }
}
