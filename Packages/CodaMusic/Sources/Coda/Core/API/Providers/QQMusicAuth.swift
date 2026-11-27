// Adapted from XIaodou0416/Beans-Music (MIT); see ThirdPartyNotices/Beans-Music.md.
import Foundation
import Combine

/// QQ 音乐扫码登录（逆向自 wp_MusicApi util/login_qq_scan.js，仅供学习交流）
/// 流程：ptqrshow 生成二维码 -> ptqrlogin 轮询扫码状态 -> check_sig 拿 skey/p_skey
///      -> graph.qq.com oauth2 authorize 换 code -> musicu.fcg QQConnectLogin 换 musickey
/// 登录后播放请求携带 qq.com 域 Cookie（p_skey / qqmusic_key），QQ 歌曲播放成功率显著提升。
final class QQMusicAuth: ObservableObject {
    static let shared = QQMusicAuth()

    @Published private(set) var isLoggedIn = false
    @Published private(set) var nickname = ""

    private var cookies: [String: String] = [:]
    private var qrsig = ""
    private var qrGeneration = UUID()
    private var handshakeCookies: [HTTPCookie] = []
    @MainActor private var refreshTask: Task<Bool, Never>?

    private let defaults = ProviderCredentialDefaults.shared
    private let cookieKey = "beans.qqmusic.cookie.v1"
    private let nickKey = "beans.qqmusic.nickname.v1"
    /// 旧版会员标识缓存，已不再使用，启动时清理
    private let legacyVIPKey = "beans.qqmusic.vip.v1"
    private let session: URLSession
    private let redirectBlocker = ProviderNoRedirectDelegate()

    private let persistsSession: Bool

    init(persistsSession: Bool = true, configuration: URLSessionConfiguration? = nil) {
        self.persistsSession = persistsSession
        let config = configuration ?? URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        config.httpCookieStorage = nil
        session = URLSession(configuration: config, delegate: redirectBlocker, delegateQueue: nil)
        if persistsSession { defaults.removeObject(forKey: legacyVIPKey) }
        if persistsSession, let saved = defaults.dictionary(forKey: cookieKey) as? [String: String], !saved.isEmpty {
            cookies = saved
            let savedNickname = defaults.string(forKey: nickKey) ?? ""
            updatePublishedState {
                self.isLoggedIn = true
                self.nickname = savedNickname
            }
        }
    }

    var exportedCredentials: [String: String] { cookies }

    // MARK: - 登录状态

    /// 登录账号 ID。QQ 登录通常使用 uin，微信登录通常使用 wxuin。
    var uin: String {
        Self.normalizedUIN(Self.accountID(from: cookies))
    }

    var isWeChatLogin: Bool {
        Self.hasUsableAccountID(cookies["wxuin"]) || !(cookies["wxopenid"] ?? "").isEmpty
    }

    /// QQ 歌单接口使用的 QQ 账号 ID。微信登录通常没有可用的 QQ uin，
    /// 此时返回 0，让官方接口根据 wxuin / wxopenid Cookie 识别账号。
    var playlistUin: String {
        if isWeChatLogin,
           !Self.hasUsableAccountID(cookies["p_uin"]),
           !Self.hasUsableAccountID(cookies["pt2gguin"]) {
            return Self.normalizedUIN(cookies["wxuin"] ?? "0")
        }
        for key in ["uin", "p_uin", "pt2gguin"] {
            guard let value = cookies[key],
                  Self.hasUsableAccountID(value) else { continue }
            return Self.normalizedUIN(value)
        }
        return "0"
    }

    /// QQ/微信登录态可用于歌单接口的身份候选。微信登录时 wxuin 也必须尝试；
    /// 部分账号的歌单/喜欢接口不会仅凭 uin=0 + Cookie 返回数据。
    var playlistIdentityCandidates: [String] {
        let rawValues = [
            cookies["p_uin"],
            cookies["pt2gguin"],
            cookies["uin"],
            cookies["wxuin"],
            playlistUin,
            "0",
        ]
        return rawValues.compactMap { value -> String? in
            guard let value, Self.hasUsableAccountID(value) || value == "0" else { return nil }
            return Self.normalizedUIN(value)
        }.reduce(into: [String]()) { result, value in
            if !result.contains(value) { result.append(value) }
        }
    }

    /// g_tk（写操作接口签名；QQ/微信登录均优先使用音乐域凭证）。
    var gtk: Int {
        let key = cookies["qqmusic_key"]
            ?? cookies["qm_keyst"]
            ?? cookies["wxskey"]
            ?? cookies["p_skey"]
            ?? cookies["skey"]
            ?? ""
        return key.isEmpty ? 5381 : Self.hash5381(key)
    }

    /// 播放接口 authst。QQ vkey 优先识别音乐域凭证，p_skey 仅作旧登录态兜底。
    var loginKey: String {
        cookies["qm_keyst"] ?? cookies["qqmusic_key"] ?? cookies["music_key"]
            ?? cookies["wxskey"] ?? cookies["musickey"] ?? cookies["p_skey"] ?? ""
    }

    var collectionCredential: QQMusicCollectionCredential? {
        let rawID = ["str_musicid", "qqmusic_uin", "uin", "wxuin", "pt2gguin"]
            .compactMap { cookies[$0] }.map(Self.normalizedUIN)
            .first { $0.utf8.count <= 19 && $0.utf8.allSatisfy { (48...57).contains($0) } && $0.contains { $0 != "0" } }
        let key = ["musickey", "qqmusic_key", "qm_keyst", "music_key", "wxskey", "wx_skey"]
            .compactMap { cookies[$0] }.first { !$0.isEmpty }
        guard let rawID, let key else { return nil }
        let id = String(rawID.drop(while: { $0 == "0" }))
        let loginType = (cookies["music_login_type"] ?? cookies["tmeLoginType"]).flatMap(Int.init) ?? (isWeChatLogin || cookies["login_type"] == "2" ? 1 : 2)
        let encryptedID = cookies["encryptUin"] ?? cookies["encrypt_uin"] ?? ""
        return QQMusicCollectionCredential(id: id, key: key, loginType: loginType, encryptedID: encryptedID)
    }

    /// 发给 u.y.qq.com 的 Cookie 串（含 qqmusic_key 时 VIP 歌曲播放成功率最高）
    var cookieHeader: String {
        makeCookieHeader(includeCompatibilityUIN: true)
    }

    /// 不注入兼容用的 uin=wxuin，给微信登录的歌单接口使用。
    /// 部分 QQ 接口会优先读取 uin，误把 wxuin 当成 QQ uin 后会返回空歌单。
    var playlistCookieHeader: String {
        makeCookieHeader(includeCompatibilityUIN: false)
    }

    private func makeCookieHeader(includeCompatibilityUIN: Bool) -> String {
        let order = [
            "uin", "wxuin", "p_uin", "wxopenid",
            "qm_keyst", "qqmusic_key", "music_key", "wxskey", "wx_skey",
            "musickey", "p_skey", "skey", "pt4_token"
        ]
        var pairs: [String] = order.compactMap { key in
            guard let value = cookies[key], !value.isEmpty else { return nil }
            return "\(key)=\(value)"
        }
        // 旧版保存的微信登录态可能只有 wxuin；部分 QQ 接口仍只读取 uin。
        if includeCompatibilityUIN,
           !Self.hasUsableAccountID(cookies["uin"]),
           let wxuin = cookies["wxuin"],
           !wxuin.isEmpty {
            pairs.insert("uin=\(wxuin)", at: 0)
        }
        return pairs.joined(separator: "; ")
    }

    func logout() {
        renewalRetryAt = nil
        qrGeneration = UUID()
        handshakeCookies = []
        cookies = [:]
        qrsig = ""
        if persistsSession { defaults.removeObject(forKey: cookieKey) }
        if persistsSession { defaults.removeObject(forKey: nickKey) }
        updatePublishedState {
            self.isLoggedIn = false
            self.nickname = ""
        }
    }

    // MARK: - 网页登录 / Cookie 导入

    /// 网页登录（WKWebView 读取）或手动粘贴 Cookie 导入登录态
    func importCookies(_ dict: [String: String], nickname: String?) {
        guard !dict.isEmpty else { return }
        cookies = dict
        renewalRetryAt = nil
        let resolvedNickname = nickname ?? Self.fallbackNickname(dict)
        updatePublishedState {
            self.isLoggedIn = true
            self.nickname = resolvedNickname
        }
        if persistsSession { defaults.set(cookies, forKey: cookieKey) }
        if persistsSession { defaults.set(resolvedNickname, forKey: nickKey) }
        if persistsSession {
            updatePublishedState {
                NotificationCenter.default.post(name: .qqLoginDidUpdate, object: nil)
            }
        }
    }

    /// 返回网页登录 Cookie 缺少哪一部分，便于区分 QQ 登录和微信登录失败原因。
    static func loginValidationMessage(_ dict: [String: String]) -> String? {
        guard hasUsableAccountID(accountID(from: dict)) else {
            return "未读取到 QQ/微信账号标识，请确认网页登录已经完成"
        }

        let credentialKeys = [
            "p_skey", "skey", "qqmusic_key", "qm_keyst",
            "music_key", "wxskey", "wx_skey", "musickey"
        ]
        guard credentialKeys.contains(where: { !(dict[$0] ?? "").isEmpty }) else {
            return "已读取到账号，但缺少 QQ 音乐登录凭证，请在网页中重新登录后再同步"
        }
        return nil
    }

    /// 解析浏览器复制出来的完整 Cookie 字符串："a=b; c=d"
    static func parseCookieHeader(_ header: String) -> [String: String] {
        var dict: [String: String] = [:]
        for part in header.split(separator: ";") {
            let kv = part.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard kv.count == 2 else { continue }
            let key = kv[0].trimmingCharacters(in: .whitespacesAndNewlines)
            let value = kv[1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !key.isEmpty, !value.isEmpty {
                dict[key] = value
            }
        }
        return dict
    }

    /// QQ/微信账号 ID 转显示昵称；优先 ptlogin 下发的 ptnick_* / nick Cookie。
    static func fallbackNickname(_ dict: [String: String]) -> String {
        if let nick = ptNickname(dict) { return nick }
        // Older builds saved the undecoded ptnick hex as "nick"; never show that again.
        let rawPTNicks = Set(dict.filter { $0.key.hasPrefix("ptnick") }.map(\.value))
        if let nick = usableNickname(dict["nick"]), !rawPTNicks.contains(nick) { return nick }
        let clean = normalizedUIN(accountID(from: dict))
        return clean.isEmpty ? "QQ音乐用户" : "QQ音乐用户 \(clean)"
    }

    private static func accountID(from cookies: [String: String]) -> String {
        for key in ["str_musicid", "qqmusic_uin", "uin", "wxuin", "pt2gguin"] {
            guard let value = cookies[key],
                  hasUsableAccountID(value) else { continue }
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "0"
    }

    private static func hasUsableAccountID(_ raw: String?) -> Bool {
        guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty else { return false }
        return value != "0" && value != "o0"
    }

    private static func normalizedUIN(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return "" }
        return value.hasPrefix("o") ? String(value.dropFirst()) : value
    }
    // MARK: - 扫码登录

    enum ScanState: Equatable {
        case waiting
        case scanned
        case success(String)   // 昵称
        case expired
        case error(String)
    }

    /// 获取二维码图片（PNG），并保存 qrsig 供轮询使用
    func fetchQRCode() async throws -> Data {
        qrsig = ""
        cookies = [:]
        handshakeCookies = []
        qrGeneration = UUID()
        let generation = qrGeneration
        var comps = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrshow")!
        comps.queryItems = [
            URLQueryItem(name: "appid", value: "716027609"),
            URLQueryItem(name: "e", value: "2"),
            URLQueryItem(name: "l", value: "M"),
            URLQueryItem(name: "s", value: "3"),
            URLQueryItem(name: "d", value: "72"),
            URLQueryItem(name: "v", value: "4"),
            URLQueryItem(name: "t", value: String(format: "%.6f", Double.random(in: 0...1))),
            URLQueryItem(name: "daid", value: "383"),
            URLQueryItem(name: "pt_3rd_aid", value: "100497308"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://xui.ptlogin2.qq.com/", forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        try checkQR(generation)
        collectCookies(from: response)
        guard let qr = cookies["qrsig"], !qr.isEmpty else {
            throw ProviderRequestError.unknown("获取 QQ 二维码失败，请检查网络后重试")
        }
        qrsig = qr
        return data
    }

    /// 单次轮询扫码状态（调用方以 3 秒间隔重复调用）
    func poll() async throws -> ScanState {
        guard !qrsig.isEmpty else { return .expired }
        let generation = qrGeneration
        var comps = URLComponents(string: "https://ssl.ptlogin2.qq.com/ptqrlogin")!
        comps.queryItems = [
            URLQueryItem(name: "u1", value: "https://graph.qq.com/oauth2.0/login_jump"),
            URLQueryItem(name: "ptqrtoken", value: "\(Self.hash33(qrsig))"),
            URLQueryItem(name: "ptredirect", value: "0"),
            URLQueryItem(name: "h", value: "1"),
            URLQueryItem(name: "t", value: "1"),
            URLQueryItem(name: "g", value: "1"),
            URLQueryItem(name: "from_ui", value: "1"),
            URLQueryItem(name: "ptlang", value: "2052"),
            URLQueryItem(name: "action", value: "0-0-\(Int(Date().timeIntervalSince1970 * 1000))"),
            URLQueryItem(name: "js_ver", value: "22080914"),
            URLQueryItem(name: "js_type", value: "1"),
            URLQueryItem(name: "login_sig", value: ""),
            URLQueryItem(name: "pt_uistyle", value: "40"),
            URLQueryItem(name: "aid", value: "716027609"),
            URLQueryItem(name: "daid", value: "383"),
            URLQueryItem(name: "pt_3rd_aid", value: "100497308"),
            URLQueryItem(name: "o1vId", value: "49283d5cbb01a744d46314da4608d929"),
        ]
        var request = URLRequest(url: comps.url!)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://xui.ptlogin2.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("qrsig=\(qrsig)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        try checkQR(generation)
        collectCookies(from: response)
        guard let text = String(data: data, encoding: .utf8),
              let parsed = Self.parsePTUI(text) else {
            return .error("QQ 登录接口异常，请重试")
        }
        switch parsed.code {
        case "0":
            guard let url = parsed.url else { return .error("登录成功但凭证获取失败") }
            do {
                try await completeOAuth(redirectURL: url, generation: generation)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                return .error(error.localizedDescription)
            }
            try checkQR(generation)
            let resolvedNickname = Self.usableNickname(parsed.nickname) ?? Self.fallbackNickname(cookies)
            updatePublishedState {
                self.nickname = resolvedNickname
                self.isLoggedIn = true
            }
            if persistsSession { defaults.set(cookies, forKey: cookieKey) }
            if persistsSession { defaults.set(resolvedNickname, forKey: nickKey) }


            return .success(resolvedNickname)
        case "65", "68":
            return .expired
        case "67":
            return .scanned
        case "66":
            return .waiting
        default:
            return .waiting
        }
    }

    // MARK: - 授权换 musickey

    private func checkQR(_ generation: UUID) throws {
        try Task.checkCancellation()
        guard generation == qrGeneration else { throw CancellationError() }
    }

    private func completeOAuth(redirectURL: String, generation: UUID) async throws {
        try checkQR(generation)
        // Retain domain/path metadata: graph.qq.com and y.qq.com both issue
        // p_skey, but only the graph cookie can sign the OAuth authorization.
        var current = redirectURL
        for _ in 0..<6 {
            try checkQR(generation)
            guard let url = URL(string: current), Self.isQQURL(url) else {
                throw ProviderRequestError.unknown("QQ 登录跳转地址无效，请重新扫码")
            }
            var request = URLRequest(url: url)
            request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
            request.setValue("https://xui.ptlogin2.qq.com/", forHTTPHeaderField: "Referer")
            request.setValue(handshakeCookieHeader(for: url, includeQRSignature: url.path == "/check_sig"), forHTTPHeaderField: "Cookie")
            let (_, response) = try await session.data(for: request)
            try checkQR(generation)
            collectCookies(from: response)
            guard let http = response as? HTTPURLResponse, http.statusCode < 400 else {
                throw ProviderRequestError.unknown("QQ 扫码已确认，但登录会话建立失败，请重新扫码")
            }
            guard (300...399).contains(http.statusCode),
                  let location = http.value(forHTTPHeaderField: "Location"),
                  let next = URL(string: location, relativeTo: url)?.absoluteURL else { break }
            current = next.absoluteString
        }

        let authURL = URL(string: "https://graph.qq.com/oauth2.0/authorize")!
        let graphCookies = handshakeCookies(for: authURL)
        let graphKey = graphCookies.first(where: { $0.name == "p_skey" })?.value
            ?? graphCookies.first(where: { $0.name == "skey" })?.value ?? ""
        guard !graphKey.isEmpty else {
            throw ProviderRequestError.unknown("QQ 扫码已确认，但未取得授权会话，请重新扫码")
        }
        let fields: [String: String] = [
            "response_type": "code",
            "client_id": "100497308",
            "redirect_uri": "https://y.qq.com/portal/wx_redirect.html?login_type=1&surl=https://y.qq.com/",
            "scope": "all", "state": "state", "switch": "", "from_ptlogin": "1",
            "src": "1", "update_auth": "1", "openapi": "80901010_1030",
            "g_tk": "\(Self.hash5381(graphKey))",
            "auth_time": "\(Int(Date().timeIntervalSince1970 * 1000))",
            "ui": "DFEC5395-9E69-4D3E-96A6-300BB770874D",
        ]
        var authRequest = URLRequest(url: authURL)
        authRequest.httpMethod = "POST"
        authRequest.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        authRequest.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        authRequest.setValue("https://graph.qq.com/", forHTTPHeaderField: "Referer")
        authRequest.setValue(handshakeCookieHeader(for: authURL), forHTTPHeaderField: "Cookie")
        authRequest.httpBody = Self.formEncode(fields).data(using: .utf8)
        let (_, authResponse) = try await session.data(for: authRequest)
        try checkQR(generation)
        collectCookies(from: authResponse)
        guard let http = authResponse as? HTTPURLResponse,
              (300...399).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let callback = URL(string: location, relativeTo: authURL)?.absoluteURL,
              Self.isQQURL(callback),
              let code = Self.extractCode(from: callback.absoluteString), !code.isEmpty else {
            let status = (authResponse as? HTTPURLResponse)?.statusCode ?? -1
            throw ProviderRequestError.unknown("QQ 授权未返回凭证（HTTP \(status)），请重新扫码")
        }

        let loginURL = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!
        let body: [String: Any] = [
            "comm": ["g_tk": 5381, "platform": "yqq", "ct": 24, "cv": 0],
            "req": ["module": "QQConnectLogin.LoginServer", "method": "QQLogin", "param": ["code": code]],
        ]
        var loginRequest = URLRequest(url: loginURL)
        loginRequest.httpMethod = "POST"
        loginRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        loginRequest.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        loginRequest.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        loginRequest.setValue(handshakeCookieHeader(for: loginURL), forHTTPHeaderField: "Cookie")
        loginRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (loginData, loginResponse) = try await session.data(for: loginRequest)
        try checkQR(generation)
        guard let loginHTTP = loginResponse as? HTTPURLResponse, (200..<300).contains(loginHTTP.statusCode) else {
            throw ProviderRequestError.unknown("QQ 授权已完成，但 QQ 音乐登录失败，请重试")
        }
        let json = (try? JSONSerialization.jsonObject(with: loginData)) as? [String: Any]
        let req = json?["req"] as? [String: Any]
        if let code = (json?["code"] as? Int), code != 0 {
            throw ProviderRequestError.unknown("QQ 音乐拒绝登录（\(code)），请重新扫码")
        }
        if let code = req?["code"] as? Int, code != 0 {
            throw ProviderRequestError.unknown("QQ 音乐凭证换取失败（\(code)），请重新扫码")
        }
        collectCookies(from: loginResponse)
        if let data = req?["data"] as? [String: Any] {
            if let musicKey = data["musickey"] as? String, !musicKey.isEmpty {
                cookies["musickey"] = musicKey
                cookies["qm_keyst"] = musicKey
                cookies["qqmusic_key"] = musicKey
            }
            let exactID = data["str_musicid"] as? String
            if Self.hasUsableAccountID(exactID) {
                cookies["str_musicid"] = exactID
                cookies["uin"] = exactID
            } else if let musicID = data["musicid"] as? NSNumber, musicID.int64Value > 0 {
                cookies["uin"] = musicID.stringValue
            } else if let musicID = data["musicid"] as? String, Self.hasUsableAccountID(musicID) {
                cookies["uin"] = musicID
            }
            if let encryptedID = data["encryptUin"] as? String, !encryptedID.isEmpty {
                cookies["encryptUin"] = encryptedID
            }
            if let loginType = data["loginType"] as? Int, (1...2).contains(loginType) {
                cookies["music_login_type"] = String(loginType)
            }
            // Keep what QQ needs to renew musickey; without these the session dies when the key expires.
            for key in ["openid", "unionid", "refresh_token", "refresh_key", "musickeyCreateTime", "keyExpiresIn"] {
                let value = (data[key] as? String) ?? (data[key] as? NSNumber)?.stringValue ?? ""
                if !value.isEmpty { cookies[key] = value }
            }
        }
        let hasMusicKey = ["musickey", "qqmusic_key", "qm_keyst", "music_key"].contains { !(cookies[$0] ?? "").isEmpty }
        guard Self.hasUsableAccountID(Self.accountID(from: cookies)), hasMusicKey else {
            throw ProviderRequestError.unknown("QQ 已授权，但未取得 QQ 音乐登录凭证，请重新扫码")
        }
    }

    // MARK: - 会员状态

    /// Query the authenticated user, rather than a public profile or VIP entitlement.
    /// Renews musickey with the saved refresh token. Without `force`, only when the key is
    /// about to expire; with `force` (after QQ rejected the key), regardless of its age.
    /// Concurrent callers share one request. Returns whether a renewed key was saved.
    @MainActor
    @discardableResult
    func refreshCredentialIfNeeded(force: Bool = false, api: QQMusicAPI = .shared) async -> Bool {
        if let refreshTask { return await refreshTask.value }
        let task = Task { @MainActor in await self.renewCredential(force: force, api: api) }
        refreshTask = task
        defer { refreshTask = nil }
        return await task.value
    }

    /// Renew this long before musickey expires; the old key keeps working meanwhile.
    static let renewalLeadTime: TimeInterval = 6 * 60 * 60
    /// After a failed renewal, wait this long instead of retrying on every request.
    static let renewalRetryDelay: TimeInterval = 5 * 60

    /// Main-thread only, like the published login state.
    private var renewalRetryAt: Date?

    /// When the saved musickey expires, from QQ's `musickeyCreateTime` + `keyExpiresIn`.
    var credentialExpiry: Date? {
        guard let created = cookies["musickeyCreateTime"].flatMap(Double.init), created > 0,
              let lifetime = cookies["keyExpiresIn"].flatMap(Double.init), lifetime > 0 else { return nil }
        return Date(timeIntervalSince1970: created + lifetime)
    }

    /// QQ (ptlogin) scans return an empty `refresh_key` and renew with `openid` + `refresh_token`;
    /// WeChat / QQ Music App logins carry `refresh_key`. Web-imported cookies have neither.
    var canRenewCredential: Bool {
        collectionCredential != nil
            && !((cookies["refresh_token"] ?? "").isEmpty && (cookies["refresh_key"] ?? "").isEmpty)
    }

    /// Seconds until the next renewal check is worthwhile, or nil when this login cannot renew.
    @MainActor
    func nextRenewalCheckDelay(now: Date = Date()) -> TimeInterval? {
        guard isLoggedIn, canRenewCredential else { return nil }
        var due = credentialExpiry.map { $0.addingTimeInterval(-Self.renewalLeadTime) } ?? now.addingTimeInterval(3600)
        if let retry = renewalRetryAt, retry > due { due = retry }
        return min(max(due.timeIntervalSince(now), 60), 3600)
    }

    @MainActor
    private func renewCredential(force: Bool, api: QQMusicAPI) async -> Bool {
        let saved = cookies
        guard let credential = collectionCredential, canRenewCredential else { return false }
        let now = Date()
        if let retry = renewalRetryAt, retry > now { return false }
        if !force {
            guard let expiry = credentialExpiry,
                  expiry.addingTimeInterval(-Self.renewalLeadTime) <= now else { return false }
        }
        let fields: [String: Any] = ["openid": saved["openid"] ?? "", "refresh_token": saved["refresh_token"] ?? "",
            "str_musicid": credential.id, "musickey": credential.key, "unionid": saved["unionid"] ?? "",
            "refresh_key": saved["refresh_key"] ?? "", "loginMode": 2]
        let data: [String: Any]
        do {
            data = try await api.loginCall("Login", params: fields, credential: credential)
        } catch is CancellationError {
            return false
        } catch {
            if cookies == saved { renewalRetryAt = Date().addingTimeInterval(Self.renewalRetryDelay) }
            return false
        }
        guard !Task.isCancelled, cookies == saved else { return false }
        guard let renewed = try? QQMusicAdditionalLogin.credentials(data, defaultLoginType: credential.loginType),
              renewed.credentials["str_musicid"] == credential.id else {
            renewalRetryAt = Date().addingTimeInterval(Self.renewalRetryDelay)
            return false
        }
        renewalRetryAt = nil
        var next = saved.merging(renewed.credentials) { _, new in new }
        // A renewal that omits the new key's age would look expiring forever; date it from now.
        if renewed.credentials["musickeyCreateTime"] == nil, next["keyExpiresIn"] != nil {
            next["musickeyCreateTime"] = String(Int(Date().timeIntervalSince1970))
        }
        importCookies(next, nickname: saved["nick"] ?? nickname)
        return true
    }

    func membershipStatus() async throws -> MusicMembership {
        guard isLoggedIn, !uin.isEmpty else { return .unknown }
        let json = try await musicu([
            "comm": ["ct": 24, "cv": 0, "uin": Int(uin) ?? 0, "format": "json"],
            "req_0": ["module": "VipLogin.VipLoginInter", "method": "vip_login_base", "param": [:]]
        ])
        return MusicMembership.qq(json)
    }

    /// 拉取 QQ 音乐账号资料（昵称 + 头像）。失败时静默保留已有资料。
    /// 依次尝试：App 会话 GetHomepageHeader -> musicu GetLoginUserInfo -> fcg_get_profile_homepage -> ptnick Cookie / QQ 头像兜底。
    @MainActor
    func fetchProfile() async {
        guard isLoggedIn, !uin.isEmpty, uin != "0" else { return }
        let snapshot = cookies
        var nick: String?
        var logo: String?

        if let header = try? await QQMusicAPI.shared.loginProfileHeader() {
            nick = Self.usableNickname(header.name)
            logo = header.avatar.flatMap { Self.avatarURL(in: ["logo": $0]) }
        }

        if nick == nil || logo == nil, let json = try? await musicu([
            "comm": ["ct": 24, "cv": 0, "uin": Int(uin) ?? 0, "format": "json"],
            "req_0": ["module": "music.UserInfo.userInfoServer", "method": "GetLoginUserInfo", "param": [:]]
        ]), let rpc = json["req_0"] as? [String: Any], (rpc["code"] as? Int) == 0,
           let info = (rpc["data"] as? [String: Any])?["info"] as? [String: Any] {
            nick = nick ?? Self.usableNickname(info["nick"]) ?? Self.usableNickname(info["nickname"])
            logo = logo ?? Self.avatarURL(in: info)
        }

        if nick == nil || logo == nil, let home = await homepageProfile() {
            nick = nick ?? home.nick
            logo = logo ?? home.logo
        }

        guard cookies == snapshot, isLoggedIn else { return }

        // 资料接口拿不到昵称时，用 ptlogin 下发的 ptnick_* Cookie 兜底
        // A blank-looking QQ nickname is unusable, so show the account ID instead.
        if nick == nil { nick = Self.fallbackNickname(cookies) }
        // QQ 号登录的公开头像兜底（微信登录没有 QQ 号，不能使用）
        if logo == nil, (cookies["logo"] ?? "").isEmpty, !isWeChatLogin,
           uin.utf8.allSatisfy({ (48...57).contains($0) }) {
            logo = "https://q.qlogo.cn/headimg_dl?dst_uin=\(uin)&spec=640"
        }

        var credentialsChanged = false
        if let logo, cookies["logo"] != logo {
            cookies["logo"] = logo
            credentialsChanged = true
        }
        if let nick {
            if cookies["nick"] != nick { cookies["nick"] = nick; credentialsChanged = true }
            if nick != nickname {
                nickname = nick
                if persistsSession { defaults.set(nick, forKey: nickKey) }
            }
        }
        if credentialsChanged, persistsSession { defaults.set(cookies, forKey: cookieKey) }
    }

    /// 个人主页接口（data.creator.nick / headpic）
    private func homepageProfile() async -> (nick: String?, logo: String?)? {
        let urlString = "https://c.y.qq.com/rsc/fcgi-bin/fcg_get_profile_homepage.fcg?cid=205360838&userid=\(uin)&reqfrom=1&g_tk=\(gtk)&loginUin=\(uin)&hostUin=0&format=json&inCharset=utf8&outCharset=utf-8&notice=0&platform=yqq.json&needNewCode=0"
        guard let url = URL(string: urlString) else { return nil }
        var request = URLRequest(url: url)
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (obj["code"] as? Int) == 0,
              let payload = obj["data"] as? [String: Any] else { return nil }
        if let creator = payload["creator"] as? [String: Any] {
            let nick = Self.usableNickname(creator["nick"]) ?? Self.usableNickname(creator["nickname"])
            let logo = Self.avatarURL(in: creator)
            if nick != nil || logo != nil { return (nick, logo) }
        }
        return (Self.extractNickname(obj), nil)
    }

    /// ptlogin 的 ptnick_* Cookie 是昵称 UTF-8 字节的十六进制编码。
    private static func ptNickname(_ cookies: [String: String]) -> String? {
        guard let key = cookies.keys.sorted().first(where: { $0.hasPrefix("ptnick") }),
              let raw = cookies[key], !raw.isEmpty else { return nil }
        let text = raw.removingPercentEncoding ?? raw
        let bytes = text.utf8.map { $0 }
        if bytes.count.isMultiple(of: 2), bytes.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) || (65...70).contains($0) }) {
            let data = Data(stride(from: 0, to: bytes.count, by: 2).compactMap { UInt8(String(decoding: bytes[$0...$0 + 1], as: UTF8.self), radix: 16) })
            if let decoded = String(data: data, encoding: .utf8),
               !decoded.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) {
                return usableNickname(decoded)
            }
        }
        return usableNickname(text)
    }

    /// 过滤空值和「QQ音乐用户」之类的占位昵称
    private static func usableNickname(_ value: Any?) -> String? {
        guard let raw = value as? String else { return nil }
        let nick = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !nick.isEmpty, !nick.replacingOccurrences(of: " ", with: "").hasPrefix("QQ音乐用户") else { return nil }
        return nick
    }

    /// 资料字典里的头像地址，统一为 https
    private static func avatarURL(in info: [String: Any]) -> String? {
        for key in ["logo", "headpic", "headurl", "avatar", "avatarUrl", "avatarurl", "pic"] {
            guard var url = (info[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !url.isEmpty else { continue }
            if url.hasPrefix("//") { url = "https:" + url }
            if url.hasPrefix("http://") { url = "https://" + url.dropFirst("http://".count) }
            if url.hasPrefix("https://") { return url }
        }
        return nil
    }

    /// 递归找 nick/nickname（个人主页结构变动时兜底）
    private static func extractNickname(_ json: [String: Any]) -> String? {
        var found: String?
        func walk(_ value: Any) {
            if found != nil { return }
            if let dict = value as? [String: Any] {
                if let nick = usableNickname(dict["nick"]) ?? usableNickname(dict["nickname"]) { found = nick; return }
                for (_, v) in dict { walk(v) }
            } else if let arr = value as? [Any] {
                for v in arr { walk(v) }
            }
        }
        walk(json)
        return found
    }

    /// musicu.fcg 统一 POST（携带当前登录 Cookie）
    private func musicu(_ payload: [String: Any]) async throws -> [String: Any] {
        guard let body = try? JSONSerialization.data(withJSONObject: payload),
              let url = URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg") else {
            throw ProviderRequestError.unknown("请求参数错误")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(Self.ua, forHTTPHeaderField: "User-Agent")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        request.httpBody = body
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderRequestError.network
        }
        return obj
    }

    // MARK: - 工具

    private static let ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"

    private static func isQQURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "qq.com" || host.hasSuffix(".qq.com")
    }

    private func handshakeCookies(for url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        return handshakeCookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let matchesHost = host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare))
            let matchesPath = path == cookie.path || (path.hasPrefix(cookie.path) && (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).hasPrefix("/")))
            return matchesHost && matchesPath && (!cookie.isSecure || url.scheme == "https")
                && (cookie.expiresDate.map { $0 > Date() } ?? true)
        }.sorted { $0.path.count > $1.path.count }
    }

    private func handshakeCookieHeader(for url: URL, includeQRSignature: Bool = false) -> String {
        var pairs = handshakeCookies(for: url).filter { !includeQRSignature || $0.name != "qrsig" }
            .map { "\($0.name)=\($0.value)" }
        if includeQRSignature, !qrsig.isEmpty { pairs.append("qrsig=\(qrsig)") }
        return pairs.joined(separator: "; ")
    }

    private func collectCookies(from response: URLResponse) {
        guard let http = response as? HTTPURLResponse, let url = http.url else { return }
        var headers: [String: String] = [:]
        for (key, value) in http.allHeaderFields {
            headers[String(describing: key)] = (value as? [String])?.joined(separator: ", ") ?? String(describing: value)
        }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: headers, for: url) where !cookie.name.isEmpty {
            handshakeCookies.removeAll { $0.name == cookie.name && $0.domain == cookie.domain && $0.path == cookie.path }
            if let expires = cookie.expiresDate, expires <= Date() { continue }
            handshakeCookies.append(cookie)
            cookies[cookie.name] = cookie.value
        }
    }

    /// Parse quoted JSONP arguments without splitting commas inside nicknames.
    private static func parsePTUI(_ text: String) -> (code: String, url: String?, nickname: String)? {
        guard let open = text.firstIndex(of: "("), let close = text.lastIndex(of: ")") else { return nil }
        let inner = String(text[text.index(after: open)..<close])
        let pattern = #"'((?:\\.|[^'\\])*)'|"((?:\\.|[^"\\])*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let parts = regex.matches(in: inner, range: NSRange(inner.startIndex..., in: inner)).compactMap { match -> String? in
            let index = match.range(at: 1).location != NSNotFound ? 1 : 2
            guard let range = Range(match.range(at: index), in: inner) else { return nil }
            return String(inner[range]).replacingOccurrences(of: "\\'", with: "'")
                .replacingOccurrences(of: "\\\"", with: "\"")
                .replacingOccurrences(of: "\\\\", with: "\\")
        }
        guard parts.count >= 5 else { return nil }
        let url = parts.dropFirst().first { $0.hasPrefix("https://") || $0.hasPrefix("http://") }
        return (parts[0], url, parts.last ?? "")
    }

    private static func extractCode(from urlString: String) -> String? {
        guard let url = URL(string: urlString),
              let comps = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = comps.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value else { return nil }
        return code
    }

    private static func formEncode(_ fields: [String: String]) -> String {
        // urlQueryAllowed includes '&', '=' and '+', which corrupt a form value
        // containing a nested URL. Encode each key/value as a form component.
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return fields.keys.sorted().map { key in
            let k = key.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            let v = (fields[key] ?? "").addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    /// 对应 JS: e += (e << 5) + t.charCodeAt(n); return 2147483647 & e（e 初始 0）—— ptqrtoken 用
    /// JS 的 e 是 IEEE-754 double（累加不截断 32 位），必须用 Double 精确模拟，
    /// 否则长 qrsig 在 Int64 中溢出导致 ptqrtoken 错误、登录接口返回异常。
    static func hash33(_ t: String) -> Int {
        var e: Double = 0
        for unit in t.utf16 {
            e = e + Double(Self.toInt32Shift(e)) + Double(unit)
        }
        return Int(Self.toInt32(e) & 0x7FFF_FFFF)
    }

    /// 对应 wp_MusicApi 的 f()：n 初始 5381，key 取 skey/qqmusic_key —— oauth g_tk 用
    static func hash5381(_ t: String) -> Int {
        var e: Double = 5381
        for unit in t.utf16 {
            e = e + Double(Self.toInt32Shift(e)) + Double(unit)
        }
        return Int(Self.toInt32(e) & 0x7FFF_FFFF)
    }

    /// JS ToInt32(d) << 5（32 位有符号截断）
    private static func toInt32Shift(_ d: Double) -> Int32 {
        let u = Self.toUInt32(d)
        return Int32(bitPattern: u &* 32)
    }

    /// JS ToInt32(d)：对 2^32 取模后转有符号 32 位
    private static func toInt32(_ d: Double) -> Int32 {
        Int32(bitPattern: Self.toUInt32(d))
    }

    private static func toUInt32(_ d: Double) -> UInt32 {
        var r = d.truncatingRemainder(dividingBy: 4294967296.0)
        if r < 0 { r += 4294967296.0 }
        return UInt32(r)
    }

    /// URLSession and cookie callbacks are not guaranteed to run on the main
    /// thread. Keep Combine/SwiftUI-visible state changes on the main thread.
    private func updatePublishedState(_ update: @escaping () -> Void) {
        if Thread.isMainThread {
            update()
        } else {
            DispatchQueue.main.sync(execute: update)
        }
    }

}

/// 拦截自动重定向，手动处理 302（oauth authorize 需要从 Location 拿 code）
final class ProviderNoRedirectDelegate: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}
