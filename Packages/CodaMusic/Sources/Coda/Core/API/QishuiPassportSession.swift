import CryptoKit
import Foundation
import Security
import WebKit

enum QishuiPassportError: LocalizedError {
    case initialization, missingSignature, network, invalidResponse, verificationCancelled, verificationUnavailable
    var errorDescription: String? {
        switch self {
        case .initialization: return "汽水登录安全组件未能加载，请稍后重试"
        case .missingSignature: return "汽水登录安全校验未就绪，已停止请求，请稍后重试"
        case .network: return "汽水登录连接失败，请检查网络后重试"
        case .invalidResponse: return "汽水登录返回了无法识别的数据"
        case .verificationCancelled: return "安全验证未完成，可以刷新二维码后重新登录"
        case .verificationUnavailable: return "汽水安全验证组件暂时不可用，请稍后重试"
        }
    }
}

/// One isolated WebKit cookie jar and official SDK instance per QR flow.
/// No external browser, helper server, copied SDK bundle, or relaxed CORS/TLS.
@MainActor
final class QishuiPassportSession: NSObject, WKNavigationDelegate {
    struct Response {
        let body: [String: Any]
        let cookieHeader: String
        let signatureLength: Int
        let msTokenLength: Int
        let browserInfoLength: Int
        let sessionTokenMatches: Bool
    }
    private let web: WKWebView
    private var initialization: Task<Void, Error>?
    private var navigation: CheckedContinuation<Void, Error>?
    private var navigationTimeout: Task<Void, Never>?
    private var closed = false
    var verificationView: WKWebView { web }

    static func supportsPath(_ path: String) -> Bool {
        path.hasPrefix("/passport/web/") || path.trimmingCharacters(in: CharacterSet(charactersIn: "/")) == "passport/safe/pack_verify_ways_data"
    }

    static func isOfficialVerificationURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, let host = url.host?.lowercased() else { return false }
        return ["qishui.com", "zijieapi.com", "yhgfb-cn-static.com", "bytetos.com", "bytegoofy.com", "bytegecko.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// The 2046 decision's `url` is either an address string or `{host, path}`
    /// (the reference client accepts both). Only official HTTPS origins pass.
    static func verificationURL(_ value: Any?) -> URL? {
        var address: String
        if let text = value as? String {
            address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        } else if let object = value as? [String: Any] {
            var host = (object["host"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if host.lowercased().hasPrefix("https://") { host = String(host.dropFirst(8)) }
            guard !host.isEmpty, !host.contains("/"), !host.contains("@"), !host.contains("?"), !host.contains("#") else { return nil }
            var path = (object["path"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.hasPrefix("/") { path = "/" + path }
            address = "https://" + host + path
        } else { return nil }
        guard !address.isEmpty, let url = URL(string: address, relativeTo: URL(string: "https://api.qishui.com/"))?.absoluteURL,
              isOfficialVerificationURL(url) else { return nil }
        return url
    }

    /// Cross-origin hosts the official verification component calls while it
    /// runs on api.qishui.com. Their requests go through the native bridge.
    static func isBridgeableVerificationURL(_ url: URL) -> Bool {
        guard url.scheme == "https", url.user == nil, url.password == nil, url.port == nil || url.port == 443,
              let host = url.host?.lowercased() else { return false }
        return ["auth.zijieapi.com", "bff-pc.qishui.com"].contains(host)
    }

    /// React 17.0.2 UMD builds shipped with the app (unpkg is often unreachable
    /// from mainland China). Hashes equal the former Subresource Integrity pins.
    static let reactAssets: [(name: String, sha256: String)] = [
        ("react.production.min", "Ipu/TQ50iCCVZBUsZyNJfxrDk0E2yhaEIz0vqI+kFG8="),
        ("react-dom.production.min", "nbMykgB6tsOFJ7OdVmPpdqMFVk4ZsqWocT6issAPUF0="),
    ]

    static func bundledScript(_ name: String, sha256: String) throws -> String {
        // The macOS packaging script embeds SwiftPM bundles in Contents/Resources.
        let bundle = Bundle.main.url(forResource: "Coda_CodaCore", withExtension: "bundle").flatMap(Bundle.init(url:)) ?? .module
        guard let url = bundle.url(forResource: name, withExtension: "js", subdirectory: "QishuiVerificationAssets"),
              let data = try? Data(contentsOf: url),
              Data(SHA256.hash(data: data)).base64EncodedString() == sha256,
              let text = String(data: data, encoding: .utf8) else { throw QishuiPassportError.verificationUnavailable }
        return text
    }

    private let bridge: QishuiVerificationBridge
    private static let bridgeName = "codaVerificationBridge"

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let bridge = QishuiVerificationBridge()
        configuration.userContentController.addScriptMessageHandler(bridge, contentWorld: .page, name: Self.bridgeName)
        self.bridge = bridge
        web = WKWebView(frame: CGRect(x: 0, y: 0, width: 900, height: 600), configuration: configuration)
        super.init()
        bridge.web = web
        web.navigationDelegate = self
        #if DEBUG
        if #available(macOS 13.3, iOS 16.4, *) { web.isInspectable = true }
        #endif
    }

    /// A per-flow client security seed, not an account credential. Initialize
    /// storage before loading the official SDK, then reuse it on every request.
    static func securitySeed() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 88)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw QishuiPassportError.initialization }
        return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
    }

    func close() {
        closed = true
        initialization?.cancel()
        initialization = nil
        navigationTimeout?.cancel()
        bridge.isActive = false
        web.evaluateJavaScript("window.codaCancelVerification?.(); window.codaActivePassportRequest?.abort()", completionHandler: nil)
        web.stopLoading()
        web.configuration.userContentController.removeScriptMessageHandler(forName: Self.bridgeName, contentWorld: .page)
        finishNavigation(.failure(CancellationError()))
    }

    private func prepare() async throws {
        guard !closed else { throw CancellationError() }
        if let initialization { try await initialization.value; return }
        let task = Task { @MainActor [self] in
            // The origin is the official API itself. A non-200 root document is
            // acceptable; all authentication XHRs remain same-origin.
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                navigation = continuation
                navigationTimeout = Task { @MainActor [weak self] in
                    do { try await Task.sleep(for: .seconds(20)) } catch { return }
                    self?.web.stopLoading()
                    self?.finishNavigation(.failure(QishuiPassportError.initialization))
                }
                web.load(URLRequest(url: URL(string: "https://api.qishui.com/")!))
            }
            try Task.checkCancellation()
            do {
                let ready = try await web.callAsyncJavaScript(Self.bootstrap, arguments: ["securitySeed": try Self.securitySeed()], in: nil, contentWorld: .page)
                guard ready as? Bool == true else { throw QishuiPassportError.initialization }
            } catch is CancellationError { throw CancellationError() }
            catch { throw QishuiPassportError.initialization }
        }
        initialization = task
        try await task.value
    }

    func send(_ request: URLRequest) async throws -> Response {
        guard let url = request.url, url.scheme == "https", url.host == "api.qishui.com",
              Self.supportsPath(url.path) else { throw QishuiPassportError.invalidResponse }
        try await prepare()
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        var headers = request.allHTTPHeaderFields ?? [:]
        // The browser owns cookies and its real User-Agent. Never inject a
        // simulated browser fingerprint or reuse another account's cookie jar.
        headers = headers.filter { !["cookie", "user-agent", "referer", "origin", "host", "content-length"].contains($0.key.lowercased()) }
        let cookies = await allCookies()
        let csrf = cookies.first { $0.name == "passport_csrf_token" } ?? cookies.first { $0.name == "passport_csrf_token_default" }
        headers["X-Tt-Passport-Csrf-Token"] = csrf?.value
        let arguments: [String: Any] = ["address": url.absoluteString, "method": request.httpMethod ?? "GET", "headers": headers,
            "body": request.httpBody.flatMap { String(data: $0, encoding: .utf8) } as Any? ?? NSNull()]
        let value: Any?
        do { value = try await web.callAsyncJavaScript(Self.sendScript, arguments: arguments, in: nil, contentWorld: .page) }
        catch is CancellationError { throw CancellationError() }
        catch { throw QishuiPassportError.network }
        try Task.checkCancellation()
        guard !closed else { throw CancellationError() }
        guard let response = value as? [String: Any] else { throw QishuiPassportError.invalidResponse }
        let signatureLength = (response["signatureLength"] as? NSNumber)?.intValue ?? 0
        // Only inspect field length, never expose/log the signed URL or SDK state.
        let msTokenLength = (response["msTokenLength"] as? NSNumber)?.intValue ?? 0
        let browserInfoLength = (response["browserInfoLength"] as? NSNumber)?.intValue ?? 0
        let tokenMatches = response["sessionTokenMatches"] as? Bool == true
        guard signatureLength == 44, msTokenLength == 120, browserInfoLength > 0, tokenMatches else { throw QishuiPassportError.missingSignature }
        let status = (response["status"] as? NSNumber)?.intValue ?? 0
        guard (200..<300).contains(status) else { throw QishuiPassportError.network }
        guard let text = response["text"] as? String, let bytes = text.data(using: .utf8),
              let object = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else { throw QishuiPassportError.invalidResponse }
        let stored = await allCookies()
        let header = stored.filter { cookie in
            let domain = cookie.domain.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            return domain == "qishui.com" || domain.hasSuffix(".qishui.com")
        }.sorted { $0.name < $1.name }.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        return .init(body: object, cookieHeader: header, signatureLength: signatureLength, msTokenLength: msTokenLength, browserInfoLength: browserInfoLength, sessionTokenMatches: tokenMatches)
    }

    func cancelVerification() {
        web.evaluateJavaScript("window.codaVerificationCancelled=true; window.codaCancelVerification?.()", completionHandler: nil)
    }

    /// Sanitized description of the last verification attempt (field names,
    /// component host/path, stage, error text). No token, cookie or query value.
    private(set) var verificationDiagnostic: [String: Any] = [:]

    func verify(_ decision: [String: Any], generalParameters: [String: String]) async throws {
        verificationDiagnostic = Self.decisionDiagnostic(decision)
        guard let url = Self.verificationURL(decision["url"]) else {
            verificationDiagnostic["stage"] = "url"
            throw QishuiPassportError.verificationUnavailable
        }
        var decision = decision
        decision["url"] = url.absoluteString
        verificationDiagnostic["stage"] = "prepare"
        do { try await prepare() } catch {
            verificationDiagnostic["error"] = Self.diagnosticText(error)
            throw error
        }
        guard !closed else { throw CancellationError() }
        do {
            verificationDiagnostic["stage"] = "react-inject"
            try await installReact()
            guard !closed else { throw CancellationError() }
            verificationDiagnostic["stage"] = "script"
            bridge.isActive = true
            defer { bridge.isActive = false }
            let result = try await web.callAsyncJavaScript(Self.verificationScript, arguments: ["decision": decision, "general": generalParameters], in: nil, contentWorld: .page)
            try Task.checkCancellation()
            guard !closed else { throw CancellationError() }
            await collectPageDiagnostic()
            guard let object = result as? [String: Any], object["status"] as? Bool == true else {
                verificationDiagnostic["stage"] = "unfinished"
                throw QishuiPassportError.verificationCancelled
            }
            verificationDiagnostic["stage"] = "completed"
        } catch is CancellationError { throw CancellationError() }
        catch QishuiPassportError.verificationCancelled { throw QishuiPassportError.verificationCancelled }
        catch {
            verificationDiagnostic["error"] = Self.diagnosticText(error)
            await collectPageDiagnostic()
            throw QishuiPassportError.verificationUnavailable
        }
    }

    static func decisionDiagnostic(_ decision: [String: Any]) -> [String: Any] {
        var result: [String: Any] = ["keys": decision.keys.sorted().map { String($0.prefix(48)) }]
        let raw = decision["url"]
        switch raw {
        case let text as String:
            result["urlType"] = "string"
            let url = URL(string: text, relativeTo: URL(string: "https://api.qishui.com/"))?.absoluteURL
            result["urlHost"] = url?.host ?? ""
            result["urlPath"] = String((url?.path ?? "").prefix(160))
        case let object as [String: Any]:
            result["urlType"] = "object"
            result["urlKeys"] = object.keys.sorted()
            result["urlHost"] = String((object["host"] as? String ?? "").prefix(120))
            result["urlPath"] = String((object["path"] as? String ?? "").split(separator: "?").first.map(String.init)?.prefix(160) ?? "")
        case nil: result["urlType"] = "missing"
        default: result["urlType"] = String(describing: type(of: raw!))
        }
        if let from = decision["verify_from"] as? String { result["verifyFrom"] = String(from.prefix(40)) }
        result["urlAccepted"] = verificationURL(raw) != nil
        return result
    }

    static func diagnosticText(_ error: Error) -> String {
        let info = (error as NSError).userInfo
        let message = info["WKJavaScriptExceptionMessage"] as? String ?? error.localizedDescription
        let stripped = message.replacingOccurrences(of: "(https?://[^\\s?#\"'<>]+)[?#][^\\s\"'<>]*", with: "$1", options: .regularExpression)
        return String(stripped.prefix(300))
    }

    private func collectPageDiagnostic() async {
        let script = """
        JSON.stringify({stage: window.codaVerifyStage || '', errors: window.codaVerifyErrors || [],
            hasComponent: typeof window.ucWebSecondVerify === 'function', hasReact: typeof window.React === 'object',
            resources: performance.getEntriesByType('resource').filter(e => !e.name.startsWith('https://api.qishui.com/passport/')).slice(-25)
                .map(e => { try { const u = new URL(e.name); return u.host + u.pathname + ' ' + (e.responseStatus || 0) + ' ' + Math.round(e.duration); } catch (_) { return ''; } })})
        """
        guard let text = try? await web.evaluateJavaScript(script) as? String, let data = text.data(using: .utf8),
              let page = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        verificationDiagnostic["page"] = page
    }

    /// Evaluated as page scripts, so the page's network policy cannot block them.
    private func installReact() async throws {
        let ready = "typeof window.React === 'object' && typeof window.ReactDOM === 'object'"
        if try await web.evaluateJavaScript(ready) as? Bool == true { return }
        for asset in Self.reactAssets {
            let source = try Self.bundledScript(asset.name, sha256: asset.sha256)
            _ = try await web.evaluateJavaScript(source + "\n;true")
        }
        guard try await web.evaluateJavaScript(ready) as? Bool == true else { throw QishuiPassportError.verificationUnavailable }
    }

    private func allCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            web.configuration.websiteDataStore.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }
    private func finishNavigation(_ result: Result<Void, Error>) {
        navigationTimeout?.cancel()
        navigationTimeout = nil
        let continuation = navigation
        navigation = nil
        continuation?.resume(with: result)
    }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { finishNavigation(.success(())) }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { finishNavigation(.failure(QishuiPassportError.initialization)) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { finishNavigation(.failure(QishuiPassportError.initialization)) }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finishNavigation(.failure(QishuiPassportError.initialization))
        initialization = nil
    }
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        if navigationAction.targetFrame?.isMainFrame == false, let url = navigationAction.request.url, url.absoluteString == "about:blank" || Self.isOfficialVerificationURL(url) {
            decisionHandler(.allow); return
        }
        guard let url = navigationAction.request.url, url.scheme == "https", url.host == "api.qishui.com" else {
            decisionHandler(.cancel); return
        }
        decisionHandler(.allow)
    }

    private static let bootstrap = #"""
    if (location.origin !== 'https://api.qishui.com') throw new Error('origin');
    if (!/^[A-Za-z0-9_-]{118}==$/.test(securitySeed)) throw new Error('security context');
    localStorage.setItem('xmst', securitySeed);
    localStorage.setItem('xmsty', securitySeed);
    window.codaPassportToken = securitySeed;
    let estimate = {};
    try { estimate = await navigator.storage.estimate(); } catch (_) {}
    let storageSize = 0;
    for (let i = 0; i < localStorage.length; i++) storageSize += (localStorage.getItem(localStorage.key(i)) || '').length;
    let permissions = [];
    try {
        const permission = await navigator.permissions.query({name:'notifications'});
        permissions = [{name:'notifications',state:permission.state}];
    } catch (_) {}
    let graphics = {};
    try {
        const canvas = document.createElement('canvas');
        const gl = canvas.getContext('webgl');
        const extension = gl?.getExtension('WEBGL_debug_renderer_info');
        if (extension) graphics = {vendor:gl.getParameter(extension.UNMASKED_VENDOR_WEBGL),renderer:gl.getParameter(extension.UNMASKED_RENDERER_WEBGL)};
    } catch (_) {}
    const timing = performance.getEntriesByType('navigation')[0] || {};
    const context = {
        hardwareConcurrency:navigator.hardwareConcurrency, webdriver:Boolean(navigator.webdriver),
        chromedriver:typeof window.chromedriver !== 'undefined', shelldriver:typeof window.shelldriver !== 'undefined',
        plugins:navigator.plugins?.length || 0, permissions,
        innerHeight:window.innerHeight, innerWidth:window.innerWidth, outerHeight:window.outerHeight, outerWidth:window.outerWidth,
        stoargeStatus:{
            indexedDB:{idb:typeof indexedDB,open:typeof indexedDB?.open,indexedDB:typeof indexedDB,IDBKeyRange:typeof IDBKeyRange,
                openDatabase:typeof window.openDatabase,isSafari:/Safari/.test(navigator.userAgent) && !/Chrome/.test(navigator.userAgent),hasFetch:typeof fetch === 'function'},
            localStorage:{isSupportLStorage:true,size:storageSize,write:true},
            storageQuotaStatus:{usage:estimate.usage,quota:estimate.quota,isPrivate:Boolean(estimate.quota && estimate.quota < 120000000)}
        },
        webgl:graphics, notificationPermission:window.Notification?.permission || 'none',
        performance:{timeOrigin:performance.timeOrigin,usedJSHeapSize:performance.memory?.usedJSHeapSize || 'unsupport',
            navigationTiming:{decodedBodySize:timing.decodedBodySize,entryType:timing.entryType,initiatorType:timing.initiatorType,
                name:timing.name,renderBlockingStatus:timing.renderBlockingStatus,serverTiming:(timing.serverTiming||[]).map(t=>t.name).join(','),guleStart:'none',guleDuration:'none'}},
        request_host:'resources', request_pathname:'/main.asar/main.html',
        browser:{t:String(Date.now()).split('').reverse().join(''),bit_protocol:'false',bit_helper:false}
    };
    const bytes = new TextEncoder().encode(JSON.stringify(context));
    window.codaPassportSourceInfo = Array.from(bytes,b=>(b^5).toString(16)).join('');
    window.codaPassportSignatureLength = 0;
    // Diagnostics: error text and resource host/path only, never query values.
    window.codaVerifyErrors = [];
    const codaStrip = text => String(text || '').replace(/(https?:\/\/[^\s?#"'<>]+)[?#][^\s"'<>]*/g, '$1').slice(0, 240);
    const codaNote = (kind, text) => { if (window.codaVerifyErrors.length < 30) window.codaVerifyErrors.push(kind + ': ' + codaStrip(text)); };
    window.addEventListener('error', event => {
        const target = event.target;
        if (target && target !== window && (target.src || target.href)) codaNote('resource', target.src || target.href);
        else codaNote('error', (event.message || '') + ' @ ' + (event.filename || '') + ':' + (event.lineno || 0));
    }, true);
    window.addEventListener('unhandledrejection', event => codaNote('rejection', event.reason?.message || event.reason));
    const nativeConsoleError = console.error;
    console.error = function(...items) {
        codaNote('console', items.map(item => item?.message || (typeof item === 'string' ? item : (() => { try { return JSON.stringify(item); } catch (_) { return String(item); } })())).join(' '));
        return nativeConsoleError.apply(this, items);
    };
    // The official verification component also calls auth.zijieapi.com and
    // bff-pc.qishui.com, which CORS blocks from this origin. Those requests go
    // through the native bridge (fixed host allowlist, same cookie jar).
    const bridgeHosts = new Set(['auth.zijieapi.com','bff-pc.qishui.com']);
    const bridgeTarget = address => {
        try {
            const parsed = new URL(String(address), location.href);
            return parsed.protocol === 'https:' && !parsed.username && !parsed.password && bridgeHosts.has(parsed.hostname) ? parsed.href : null;
        } catch (_) { return null; }
    };
    const bridgeSend = request => {
        const handler = window.webkit?.messageHandlers?.codaVerificationBridge;
        if (!handler) return Promise.reject(new Error('bridge unavailable'));
        return handler.postMessage({...request, userAgent:navigator.userAgent});
    };
    const nativeOpen = XMLHttpRequest.prototype.open;
    const nativeSetHeader = XMLHttpRequest.prototype.setRequestHeader;
    const nativeSend = XMLHttpRequest.prototype.send;
    XMLHttpRequest.prototype.open = function(method, address) {
        const parsed = new URL(address, location.href);
        if (parsed.origin === location.origin && (parsed.pathname.startsWith('/passport/web/') || parsed.pathname.startsWith('/passport/safe/pack_verify_ways_data'))) {
            window.codaPassportSignatureLength = (parsed.searchParams.get('a_bogus') || '').length;
            window.codaPassportTokenLength = (parsed.searchParams.get('msToken') || '').length;
            window.codaPassportTokenMatches = parsed.searchParams.get('msToken') === window.codaPassportToken;
        }
        this.codaBridgeTarget = bridgeTarget(address);
        this.codaBridgeMethod = String(method || 'GET').toUpperCase();
        this.codaBridgeHeaders = {};
        return nativeOpen.apply(this, arguments);
    };
    XMLHttpRequest.prototype.setRequestHeader = function(name, value) {
        if (this.codaBridgeTarget) this.codaBridgeHeaders[String(name)] = String(value);
        return nativeSetHeader.apply(this, arguments);
    };
    XMLHttpRequest.prototype.send = function(body) {
        if (!this.codaBridgeTarget) return nativeSend.apply(this, arguments);
        const xhr = this;
        const define = (name, value) => { try { Object.defineProperty(xhr, name, {configurable:true, value}); } catch (_) {} };
        const emit = name => { try { xhr.dispatchEvent(new Event(name)); } catch (_) {} };
        bridgeSend({method:xhr.codaBridgeMethod, url:xhr.codaBridgeTarget, headers:xhr.codaBridgeHeaders, body:body == null ? null : String(body)}).then(response => {
            const text = String(response.body || '');
            let parsed = text;
            if (xhr.responseType === 'json') { try { parsed = JSON.parse(text); } catch (_) { parsed = null; } }
            const headers = String(response.headers || '');
            define('status', Number(response.status) || 0);
            define('statusText', '');
            define('responseText', text);
            define('response', parsed);
            define('responseURL', String(response.url || xhr.codaBridgeTarget));
            define('readyState', 4);
            xhr.getAllResponseHeaders = () => headers;
            xhr.getResponseHeader = name => {
                const wanted = String(name || '').toLowerCase();
                const line = headers.split(/\r?\n/).find(item => item.toLowerCase().startsWith(wanted + ':'));
                return line ? line.slice(line.indexOf(':') + 1).trim() : null;
            };
            emit('readystatechange'); emit('load'); emit('loadend');
        }).catch(() => {
            define('status', 0);
            define('readyState', 4);
            emit('readystatechange'); emit('error'); emit('loadend');
        });
    };
    const nativeFetch = window.fetch;
    window.fetch = function(input, init) {
        const address = typeof input === 'string' || input instanceof URL ? String(input) : input?.url;
        const target = bridgeTarget(address);
        if (!target) return nativeFetch.apply(this, arguments);
        const request = new Request(input, init);
        const method = request.method.toUpperCase();
        return (method === 'GET' || method === 'HEAD' ? Promise.resolve(null) : request.text()).then(body =>
            bridgeSend({method, url:target, headers:Object.fromEntries(request.headers.entries()), body})
        ).then(response => {
            const status = Number(response.status) || 0;
            if (status < 200 || status > 599) throw new TypeError('Failed to fetch');
            const headers = new Headers();
            for (const line of String(response.headers || '').split(/\r?\n/)) {
                const index = line.indexOf(':');
                if (index > 0) { try { headers.append(line.slice(0, index).trim(), line.slice(index + 1).trim()); } catch (_) {} }
            }
            const empty = [101, 204, 205, 304].includes(status) || method === 'HEAD';
            return new Response(empty ? null : String(response.body || ''), {status, headers});
        }, () => { throw new TypeError('Failed to fetch'); });
    };
    await new Promise((resolve, reject) => {
        const script = document.createElement('script');
        script.charset = 'utf-8';
        const timeout = setTimeout(() => reject(new Error('sdk timeout')), 15000);
        script.src = 'https://lf-headquarters-speed.yhgfb-cn-static.com/obj/rc-client-security/web/stable/1.0.0.41/bdms.js';
        script.onload = () => { clearTimeout(timeout); resolve(); };
        script.onerror = () => { clearTimeout(timeout); reject(new Error('sdk unavailable')); };
        document.head.appendChild(script);
    });
    if (typeof window.bdms?.init !== 'function') throw new Error('sdk unavailable');
    await window.bdms.init({aid: 386088, paths: ['/passport']});
    return true;
    """#

    private static let sendScript = #"""
    const destination = new URL(address);
    if (destination.origin !== location.origin || !(destination.pathname.startsWith('/passport/web/') || destination.pathname.startsWith('/passport/safe/pack_verify_ways_data'))) throw new Error('destination');
    if (!window.codaPassportToken || !window.codaPassportSourceInfo) throw new Error('security context');
    destination.searchParams.set('msToken',window.codaPassportToken);
    destination.searchParams.set('account_sdk_source_info',window.codaPassportSourceInfo);
    window.codaPassportSignatureLength = 0;
    window.codaPassportTokenLength = 0;
    window.codaPassportTokenMatches = false;
    return await new Promise((resolve, reject) => {
        const xhr = new XMLHttpRequest();
        window.codaActivePassportRequest = xhr;
        xhr.open(method, destination.href, true);
        xhr.withCredentials = true;
        xhr.timeout = 20000;
        for (const [name, value] of Object.entries(headers)) xhr.setRequestHeader(name, String(value));
        xhr.onload = () => resolve({status:xhr.status,text:xhr.responseText,signatureLength:window.codaPassportSignatureLength,
            msTokenLength:window.codaPassportTokenLength,browserInfoLength:window.codaPassportSourceInfo.length,sessionTokenMatches:window.codaPassportTokenMatches});
        xhr.onerror = () => reject(new Error('network'));
        xhr.onabort = () => reject(new Error('cancelled'));
        xhr.ontimeout = () => reject(new Error('timeout'));
        xhr.send(body === null ? null : body);
    });
    """#

    /// Official verification UI executes in the same origin and cookie jar as
    /// the QR flow. Only the user can complete its CAPTCHA/SMS/other challenge.
    private static let verificationScript = #"""
    window.codaVerificationCancelled=false;
    window.codaVerifyStage='origin';
    // The host is api.qishui.com's bare 404 page: no viewport (iOS renders it
    // 980px wide and scales the mobile component down) and no charset.
    const setMeta = (selector, create) => { document.head.querySelectorAll(selector).forEach(n=>n.remove()); document.head.prepend(create()); };
    setMeta('meta[name="viewport"]', () => Object.assign(document.createElement('meta'), {name:'viewport', content:'width=device-width,initial-scale=1,viewport-fit=cover'}));
    setMeta('meta[charset]', () => { const m = document.createElement('meta'); m.setAttribute('charset','utf-8'); return m; });
    if (!document.getElementById('coda-verify-style')) {
        const style = document.createElement('style');
        style.id = 'coda-verify-style';
        style.textContent = 'html,body{margin:0;padding:0;width:100%;height:100%;}';
        document.head.appendChild(style);
    }
    const resource = new URL(decision.url);
    const allowed = ['qishui.com','zijieapi.com','yhgfb-cn-static.com','bytetos.com','bytegoofy.com','bytegecko.com'];
    if (resource.protocol !== 'https:' || !allowed.some(h=>resource.hostname===h || resource.hostname.endsWith('.'+h))) throw new Error('verification origin');
    const load = address => new Promise((resolve,reject)=>{
        const script = document.createElement('script');
        // The host page has no declared encoding (Chinese systems decode it as
        // GB18030) and the component is served without a charset: force UTF-8.
        script.charset='utf-8';
        // Served with Access-Control-Allow-Origin: *, so errors stay readable.
        script.crossOrigin='anonymous';
        script.src=address;
        const timeout=setTimeout(()=>reject(new Error('component timeout')),15000);
        script.onload=()=>{clearTimeout(timeout);resolve();};
        script.onerror=()=>{clearTimeout(timeout);reject(new Error('component unavailable'));};
        document.head.appendChild(script);
    });
    window.codaVerifyStage='react';
    if (!window.React || !window.ReactDOM) throw new Error('react unavailable');
    window.ucSecondVerifyReact=window.React;
    window.ucSecondVerifyReactDom=window.ReactDOM;
    let event={};
    if (typeof decision.event_params==='string') {try{event=JSON.parse(decision.event_params);}catch(_){}}
    else if (decision.event_params && typeof decision.event_params==='object') event=decision.event_params;
    resource.searchParams.set('aid','386088');
    resource.searchParams.set('verify_reason',String(event.verify_reason||''));
    resource.searchParams.set('verify_scene',String(event.verify_scene||''));
    window.$$account_verify_portrait_id=String(decision.verify_portrait_id||'');
    window.codaVerifyStage='component-load';
    if (typeof window.ucWebSecondVerify!=='function') await load(resource.href);
    window.codaVerifyStage='component-export';
    if (typeof window.ucWebSecondVerify!=='function') throw new Error('verification unavailable');
    window.codaVerifyStage='component-run';
    if (window.codaVerificationCancelled) return {status:false};
    document.body.replaceChildren();
    return await new Promise(resolve=>{
        let finished=false;
        const timer=setTimeout(()=>finish({status:false}),600000);
        const finish=result=>{
            if(finished)return;
            finished=true;clearTimeout(timer);window.codaCancelVerification=null;
            resolve({status:result?.status===true});
        };
        window.codaCancelVerification=()=>finish({status:false});
        window.ucWebSecondVerify({
            ...decision,aid:386088,isNewVerifyUI:true,event_params:event,generalParams:general,
            verifyFinishCallback:finish,
            newSecondVerifyWebOptions:{host:'https://api.qishui.com',verifyAppName:'汽水音乐移动端'},
            newSecondVerificationCall:{reportAppLog:()=>{}},
            fun:decision.verify_from==='verify_center'?'verify_center':'verify',uc_account_verify_version:'1.0.29',
            monitorTime:{startTime:Date.now(),fetchEndTime:Date.now(),scriptLoadStartTime:0,scriptLoadEndTime:Date.now(),renderStartTime:Date.now()}
        });
    });
    """#
}

/// Sends the verification component's cross-origin requests natively, using
/// the QR flow's isolated WebKit cookie jar. Accepts messages only from the
/// api.qishui.com main frame, only while a verification is running, and only
/// for `QishuiPassportSession.isBridgeableVerificationURL` destinations.
@MainActor
final class QishuiVerificationBridge: NSObject, WKScriptMessageHandlerWithReply {
    weak var web: WKWebView?
    var isActive = false

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        return URLSession(configuration: configuration)
    }()

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping @MainActor @Sendable (Any?, String?) -> Void) {
        let origin = message.frameInfo.securityOrigin
        guard isActive, let web, message.webView === web, message.frameInfo.isMainFrame,
              origin.protocol == "https", origin.host == "api.qishui.com", origin.port == 0 || origin.port == 443,
              let request = Self.request(from: message.body) else {
            replyHandler(nil, "rejected"); return
        }
        let store = web.configuration.websiteDataStore.httpCookieStore
        Task { @MainActor in
            do { replyHandler(try await Self.perform(request, store: store), nil) }
            catch { replyHandler(nil, "network") }
        }
    }

    static func request(from body: Any) -> URLRequest? {
        guard let object = body as? [String: Any], let address = object["url"] as? String, let url = URL(string: address),
              QishuiPassportSession.isBridgeableVerificationURL(url) else { return nil }
        let method = (object["method"] as? String ?? "GET").uppercased()
        guard ["GET", "POST"].contains(method) else { return nil }
        var request = URLRequest(url: url)
        request.httpMethod = method
        let blocked: Set<String> = ["cookie", "cookie2", "host", "origin", "referer", "content-length", "connection", "user-agent"]
        for (name, value) in object["headers"] as? [String: Any] ?? [:] where !blocked.contains(name.lowercased()) && !name.lowercased().hasPrefix("sec-") {
            request.setValue(String(describing: value), forHTTPHeaderField: name)
        }
        if method == "POST", let text = object["body"] as? String { request.httpBody = Data(text.utf8) }
        if let agent = object["userAgent"] as? String, !agent.isEmpty { request.setValue(agent, forHTTPHeaderField: "User-Agent") }
        request.setValue("https://api.qishui.com", forHTTPHeaderField: "Origin")
        request.setValue("https://api.qishui.com/", forHTTPHeaderField: "Referer")
        return request
    }

    static func cookies(_ cookies: [HTTPCookie], matching url: URL) -> [HTTPCookie] {
        guard let host = url.host?.lowercased() else { return [] }
        let path = url.path.isEmpty ? "/" : url.path
        return cookies.filter { cookie in
            let domain = cookie.domain.lowercased()
            let bare = domain.hasPrefix(".") ? String(domain.dropFirst()) : domain
            let domainMatches = host == bare || (domain.hasPrefix(".") && host.hasSuffix("." + bare))
            let expired = cookie.expiresDate.map { $0 < Date() } ?? false
            return domainMatches && path.hasPrefix(cookie.path) && !expired
        }
    }

    private static func perform(_ request: URLRequest, store: WKHTTPCookieStore) async throws -> [String: Any] {
        guard let url = request.url else { throw URLError(.badURL) }
        var request = request
        let jar = await withCheckedContinuation { continuation in store.getAllCookies { continuation.resume(returning: $0) } }
        let header = cookies(jar, matching: url).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
        if !header.isEmpty { request.setValue(header, forHTTPHeaderField: "Cookie") }
        // Never follow redirects: the cookie header must not reach another host.
        let (data, response) = try await session.data(for: request, delegate: QishuiNoRedirect())
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        let fields = http.allHeaderFields.reduce(into: [String: String]()) { $0[String(describing: $1.key)] = String(describing: $1.value) }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: http.url ?? url) {
            await withCheckedContinuation { continuation in store.setCookie(cookie) { continuation.resume() } }
        }
        let headers = fields.filter { $0.key.lowercased() != "set-cookie" }.map { "\($0.key): \($0.value)" }.joined(separator: "\r\n")
        return ["status": http.statusCode, "body": String(decoding: data, as: UTF8.self), "headers": headers, "url": (http.url ?? url).absoluteString]
    }
}
