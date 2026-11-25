import Foundation
@preconcurrency import WebKit

enum MusicJSError: LocalizedError {
    case unsupported, invalidScript, timeout, sourceFailed, invalidResponse, removed
    var errorDescription: String? {
        switch self {
        case .unsupported: return localized("目前只接受 LX 格式的 JS 音源。")
        case .invalidScript: return localized("音源無法初始化，請檢查 JS 格式。")
        case .timeout: return localized("音源執行逾時，請重試或切換音源。")
        case .sourceFailed: return localized("音源請求失敗，請重試或切換平台。")
        case .invalidResponse: return localized("音源沒有返回有效的歌曲或播放地址。")
        case .removed: return localized("此 JS 音源已移除，請重新導入。")
        }
    }
}

@MainActor
private final class MusicJSMessageProxy: NSObject, WKScriptMessageHandler {
    weak var owner: MusicJSRuntime?
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let text = message.body as? String else { return }
        owner?.receive(text)
    }
}

/// User JS runs in a separate, nonpersistent WebKit content process, never on the native UI
/// thread. CSP blocks script-controlled networking; only the explicit LX HTTP bridge is allowed.
@MainActor
final class MusicJSRuntime: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let bridge: MusicJSMessageProxy
    private var script = ""
    private var pending: [String: CheckedContinuation<String, Error>] = [:]
    private var deadlines: [String: Task<Void, Never>] = [:]
    private var http: [String: Task<Void, Never>] = [:]
    private var closed = false
    var isUsable: Bool { !closed }
    var activeHTTPCount: Int { http.count }
    private var scriptEvaluated = false
    private var initializationPayload: String?
    private(set) var initializationJSON = "{}"
    private let session: URLSession

    private init(networkConfiguration: URLSessionConfiguration?) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        bridge = MusicJSMessageProxy()
        configuration.userContentController.add(bridge, name: "readccMusic")
        webView = WKWebView(frame: .zero, configuration: configuration)
        let network = networkConfiguration ?? URLSessionConfiguration.ephemeral
        network.httpCookieStorage = nil
        network.urlCredentialStorage = nil
        network.httpShouldSetCookies = false
        network.timeoutIntervalForRequest = 20
        session = URLSession(configuration: network, delegate: MusicJSRedirectGate(), delegateQueue: nil)
        super.init()
        bridge.owner = self
        webView.navigationDelegate = self
    }

    static func load(script: String, networkConfiguration: URLSessionConfiguration? = nil) async throws -> MusicJSRuntime {
        let runtime = MusicJSRuntime(networkConfiguration: networkConfiguration)
        runtime.script = script
        do {
            runtime.initializationJSON = try await runtime.wait(id: "ready") {
                runtime.webView.loadHTMLString("<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; script-src 'unsafe-inline' 'unsafe-eval'; connect-src 'none'\"><title>Music source</title>", baseURL: nil)
            }
            try Task.checkCancellation()
            guard runtime.isUsable else { throw MusicJSError.sourceFailed }
            return runtime
        } catch { runtime.close(); throw error }
    }

    func invoke(action: String, provider: String, infoJSON: String) async throws -> String {
        guard !closed, let info = try? JSONSerialization.jsonObject(with: Data(infoJSON.utf8)),
              let payload = try? JSONSerialization.data(withJSONObject: ["action": action, "source": provider, "info": info]),
              let text = String(data: payload, encoding: .utf8) else { throw MusicJSError.invalidResponse }
        let id = UUID().uuidString
        return try await wait(id: id) {
            self.evaluate("__readccMusicInvoke(\(Self.literal(id)),\(text))", requestID: id)
        }
    }

    private func wait(id: String, start: () -> Void) async throws -> String {
        if Task.isCancelled { close(); throw CancellationError() }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending[id] = continuation
                deadlines[id] = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(30)) } catch { return }
                    self?.finish(id, .failure(MusicJSError.timeout))
                    self?.close()
                }
                start()
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.finish(id, .failure(CancellationError()))
                self?.close()
            }
        }
    }

    private func finish(_ id: String, _ result: Result<String, Error>) {
        deadlines.removeValue(forKey: id)?.cancel()
        pending.removeValue(forKey: id)?.resume(with: result)
    }

    private func evaluate(_ text: String, requestID: String?) {
        guard !closed else { return }
        webView.evaluateJavaScript(text) { [weak self] _, error in
            guard error != nil else { return }
            if let requestID { self?.finish(requestID, .failure(MusicJSError.invalidScript)) }
            self?.close()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !closed, pending["ready"] != nil else { return }
        webView.evaluateJavaScript(MusicJSBootstrap.source) { [weak self] _, error in
            guard let self else { return }
            if error != nil { self.finish("ready", .failure(MusicJSError.invalidScript)); return }
            self.webView.evaluateJavaScript(self.script + "\n;void 0;") { [weak self] _, error in
                guard let self, !self.closed else { return }
                if error != nil {
                    self.finish("ready", .failure(MusicJSError.invalidScript)); self.close(); return
                }
                self.scriptEvaluated = true
                self.finishInitializationIfReady()
            }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                 decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        decisionHandler(navigationAction.request.url?.scheme == "about" ? .allow : .cancel)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { close() }

    func close() {
        guard !closed else { return }; closed = true
        for task in http.values { task.cancel() }; http.removeAll()
        for task in deadlines.values { task.cancel() }; deadlines.removeAll()
        let waiting = pending; pending.removeAll()
        for continuation in waiting.values { continuation.resume(throwing: MusicJSError.sourceFailed) }
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "readccMusic")
        webView.stopLoading()
        webView.navigationDelegate = nil
        session.invalidateAndCancel()
    }

    nonisolated static func literal(_ string: String) -> String {
        let data = try? JSONSerialization.data(withJSONObject: string, options: [.fragmentsAllowed])
        return data.flatMap { String(data: $0, encoding: .utf8) } ?? "\"\""
    }

    fileprivate func receive(_ text: String) {
        guard !closed, text.utf8.count <= 4 * 1024 * 1024,
              let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any],
              let kind = value["kind"] as? String else { return }
        let id = value["id"] as? String ?? ""
        switch kind {
        case "inited", "result":
            guard let payload = value["data"],
                  let data = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed, .sortedKeys]),
                  let json = String(data: data, encoding: .utf8) else {
                finish(kind == "inited" ? "ready" : id, .failure(MusicJSError.invalidResponse)); return
            }
            if kind == "inited" {
                guard initializationPayload == nil else { return }
                initializationPayload = json
                finishInitializationIfReady()
            } else { finish(id, .success(json)) }
        case "failure": finish(id, .failure(MusicJSError.sourceFailed))
        case "cancelHTTP": http.removeValue(forKey: id)?.cancel()
        case "http": startHTTP(id, value)
        default: break
        }
    }

    private func finishInitializationIfReady() {
        if scriptEvaluated, let initializationPayload {
            finish("ready", .success(initializationPayload))
        }
    }

    private func startHTTP(_ id: String, _ value: [String: Any]) {
        guard http.count < 32, http[id] == nil, let address = value["url"] as? String,
              let url = URL(string: address), Self.allowedRemoteURL(url) else {
            replyHTTP(id, error: "HTTP request rejected", response: nil); return
        }
        let options = value["options"] as? [String: Any] ?? [:]
        let method = (options["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST", "HEAD"].contains(method) else {
            replyHTTP(id, error: "Unsupported HTTP method", response: nil); return
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = min(20, max(1, (options["timeout"] as? Double ?? 10000) / 1000))
        if let headers = options["headers"] as? [String: String] {
            for (key, value) in headers where Self.safeHeader(key, value) { request.setValue(value, forHTTPHeaderField: key) }
        }
        if method == "POST" {
            if let body = options["body"] as? String { request.httpBody = Data(body.utf8) }
            else if let body = options["body"], JSONSerialization.isValidJSONObject(body) {
                request.httpBody = try? JSONSerialization.data(withJSONObject: body)
            }
        }
        http[id] = Task { @MainActor [weak self, request] in
            guard let self else { return }
            defer { self.http.removeValue(forKey: id) }
            do {
                let response = try await MusicJSHTTPTransport.shared.perform(request, session: self.session)
                try Task.checkCancellation()
                self.replyHTTP(id, error: nil, response: ["statusCode": response.statusCode,
                    "status": response.statusCode, "headers": response.headers, "body": response.body])
            } catch {
                if !Task.isCancelled { self.replyHTTP(id, error: "HTTP request failed", response: nil) }
            }
        }
    }

    private func replyHTTP(_ id: String, error: String?, response: [String: Any]?) {
        guard !closed else { return }
        let json = response.flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        evaluate("__readccMusicHTTP(\(Self.literal(id)),\(error.map(Self.literal) ?? "null"),\(json))", requestID: nil)
    }

    nonisolated static func allowedRemoteURL(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host?.lowercased(), !host.isEmpty, url.user == nil, url.password == nil else { return false }
        let value = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]."))
        // Reject noncanonical numeric/hex hosts instead of trusting URL loading normalization.
        if !value.contains("."), value.allSatisfy({ $0.isNumber }) { return false }
        if value.split(separator: ".").contains(where: { $0.hasPrefix("0x") }) { return false }
        if value == "localhost" || value.hasSuffix(".localhost") || value.contains(":")
            || value.hasPrefix("127.") || value.hasPrefix("0.") || value.hasPrefix("10.")
            || value.hasPrefix("192.168.") || value.hasPrefix("169.254.") { return false }
        let parts = value.split(separator: ".")
        if parts.count == 4, parts[0] == "172", let subnet = Int(parts[1]), (16...31).contains(subnet) { return false }
        return true
    }

    nonisolated static func redirectedRequest(_ request: URLRequest, from origin: URL?) -> URLRequest? {
        guard let url = request.url, allowedRemoteURL(url) else { return nil }
        let changedOrigin = origin?.host?.lowercased() != url.host?.lowercased()
            || origin?.scheme != url.scheme || origin?.port != url.port
        guard changedOrigin else { return request }
        // Arbitrary custom headers, cookie/auth defaults and POST bodies may contain
        // source credentials. Build a clean request for the new origin rather than
        // clearing a copied URLRequest (Foundation can retain synthesized defaults).
        guard ["GET", "HEAD"].contains((request.httpMethod ?? "GET").uppercased()),
              request.httpBody == nil, request.httpBodyStream == nil else { return nil }
        var clean = URLRequest(url: url, cachePolicy: request.cachePolicy, timeoutInterval: request.timeoutInterval)
        clean.httpMethod = request.httpMethod
        return clean
    }

    nonisolated static func safeHeader(_ key: String, _ value: String) -> Bool {
        let lower = key.lowercased()
        return !["host", "content-length", "connection"].contains(lower) && !lower.hasPrefix("x-readcc-")
            && !key.isEmpty && key.utf8.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }
            && value.utf8.count <= 16384 && value.utf8.allSatisfy { ($0 == 9 || $0 >= 32) && $0 != 127 }
    }
}

/// Bounded buffering runs on this actor, not on the UI executor. Response fields are Sendable.
actor MusicJSHTTPTransport {
    static let shared = MusicJSHTTPTransport()
    static let bodyLimit = 2 * 1024 * 1024
    struct Response: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: String
    }

    func perform(_ request: URLRequest, session: URLSession) async throws -> Response {
        let (bytes, response) = try await session.bytes(for: request)
        defer { bytes.task.cancel() }
        if request.httpMethod != "HEAD", response.expectedContentLength > Int64(Self.bodyLimit) {
            throw MusicJSError.invalidResponse
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < Self.bodyLimit else { throw MusicJSError.invalidResponse }
            data.append(byte)
        }
        try Task.checkCancellation()
        guard let response = response as? HTTPURLResponse,
              let body = String(data: data, encoding: .utf8) else { throw MusicJSError.invalidResponse }
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, item in
            result[String(describing: item.key).lowercased()] = String(describing: item.value)
        }
        return Response(statusCode: response.statusCode, headers: headers, body: body)
    }
}

/// Stateless URLSession delegate: recheck redirects and never carry source bearer credentials
/// to a different origin. No app cookie store or other source credentials are consulted.
private final class MusicJSRedirectGate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(MusicJSRuntime.redirectedRequest(request, from: response.url))
    }
}
