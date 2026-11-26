import Foundation
import Combine
import os

/// A site a loaded bundle publishes in `/config`: its key is what `/spider/...` answers under.
struct CatVodSite: Hashable, Sendable, Identifiable {
    let key: String
    let name: String
    let api: String
    let type: Int
    let searchable: Bool
    let filterable: Bool
    let indexs: Bool

    var id: String { key }
}

/// A pan credential as the bundle's 配置中心 stores it (`GET /website/api/credentials`).
struct CatVodCredentials: Sendable {
    /// provider → field → value, e.g. `quark.cookie`, `uc.token`, `pan115.cookie`.
    let values: [String: [String: String]]

    static let empty = CatVodCredentials(values: [:])

    func value(_ provider: String, _ field: String = "cookie") -> String {
        values[provider]?[field] ?? ""
    }
}

enum CatVodRuntimeError: Error, Sendable {
    case frameworkMissing
    case startTimeout
    case notLoaded
    case sourceFailed(String)
    case badResponse(String)

    var message: String {
        switch self {
        case .frameworkMissing: localized("此版本未包含 Node 运行环境，无法执行 MD5 源。")
        case .startTimeout: localized("Node 运行环境启动超时。")
        case .notLoaded: localized("请先启动一个 MD5 源。")
        case .sourceFailed(let reason): String(format: localized("源执行失败：%@"), reason)
        case .badResponse(let reason): String(format: localized("无法读取源响应：%@"), reason)
        }
    }
}

/// Runs downloaded CatVod bundles. One Node process per app run hosts the control server; each
/// activation loads one bundle into it (the previous one is stopped first). The bundle never
/// talks to the network directly from Swift: all its answers arrive over 127.0.0.1 with the
/// launch token, and only `home/category/search/detail/play` plus the credential routes are
/// forwarded.
@MainActor
final class CatVodRuntime: ObservableObject {
    static let shared = CatVodRuntime()

    struct Ready: Sendable {
        let port: Int
        let token: String
    }

    @Published private(set) var activeSourceID: String?
    @Published private(set) var sites: [CatVodSite] = []
    @Published private(set) var isStarting = false

    private var ready: Ready?
    private var nodeStarted = false
    private var nodeExit: Int32?
    private var activation = UUID()
    private struct SourceLocation: Equatable {
        let id: String
        let bundlePath: String
        let dataPath: String
    }
    private var location: SourceLocation?
    private var mediaScope: String?
    private(set) var bundleOrigin: URL?
    private(set) var allowedLoopbackPorts: Set<Int> = []

    private let root: URL
    private let hostURL: URL
    private let readyURL: URL

    init(root: URL? = nil) {
        let base = root ?? URL.applicationSupportDirectory.appendingPathComponent("CatVod", isDirectory: true)
        self.root = base
        self.hostURL = base.appendingPathComponent("host.js")
        self.readyURL = base.appendingPathComponent("control.json")
    }

    // MARK: - Node

    /// Starts Node once per launch. `node_start` owns the process; it is never called twice,
    /// because Node's globals and signal handlers belong to the whole process.
    func startNodeIfNeeded() async throws {
        if ready != nil { return }
        if let nodeExit {
            throw CatVodRuntimeError.sourceFailed("Node 结束代码 \(nodeExit)")
        }
        guard nodeStarted || Self.frameworkAvailable else { throw CatVodRuntimeError.frameworkMissing }
        isStarting = true
        defer { isStarting = false }
        if !nodeStarted {
            let manager = FileManager.default
            try manager.createDirectory(at: root, withIntermediateDirectories: true)
            try CatVodHostScript.source.write(to: hostURL, atomically: true, encoding: .utf8)
            try? manager.removeItem(at: readyURL)
            guard let nodeStart = Self.nodeStartBox else { throw CatVodRuntimeError.frameworkMissing }
            nodeStarted = true
            let hostPath = hostURL.path
            let readyPath = readyURL.path
            let thread = Thread { [weak self] in
                let arguments = ["node", hostPath, readyPath]
                var pointers = arguments.map { strdup($0) }
                let status = pointers.withUnsafeMutableBufferPointer { buffer in
                    nodeStart.call(Int32(buffer.count), buffer.baseAddress)
                }
                for pointer in pointers where pointer != nil { free(pointer) }
                Task { @MainActor [weak self] in self?.noteNodeExit(status) }
            }
            thread.name = "readcc.catvod.node"
            thread.stackSize = 4 << 20
            thread.start()
        }

        for _ in 0..<150 {
            if let nodeExit { throw CatVodRuntimeError.sourceFailed("Node 结束代码 \(nodeExit)") }
            if let data = try? Data(contentsOf: readyURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let port = object["port"] as? Int, let token = object["token"] as? String {
                ready = Ready(port: port, token: token)
                return
            }
            try? await Task.sleep(nanoseconds: 200_000_000)
        }
        throw CatVodRuntimeError.startTimeout
    }

    private func noteNodeExit(_ status: Int32) {
        nodeExit = status
        ready = nil
        deactivate()
    }

    /// Whether this run can reach NodeMobile. The framework is shipped inside the app
    /// (`Frameworks/NodeMobile.framework`) rather than linked, so a build without it still
    /// opens, and only MD5 sources report that the runtime is absent.
    static var frameworkAvailable: Bool { nodeStartBox != nil }

    private typealias NodeStart = @convention(c) (Int32, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?) -> Int32

    private struct NodeStartBox: @unchecked Sendable {
        let call: NodeStart
    }

    nonisolated(unsafe) private static let nodeStartBox: NodeStartBox? = {
        if let main = dlopen(nil, RTLD_NOW), let symbol = dlsym(main, "node_start") {
            return NodeStartBox(call: unsafeBitCast(symbol, to: NodeStart.self))
        }
        let frameworks = Bundle.main.privateFrameworksPath ?? ""
        let path = (frameworks as NSString).appendingPathComponent("NodeMobile.framework/NodeMobile")
        guard let handle = dlopen(path, RTLD_NOW), let symbol = dlsym(handle, "node_start") else { return nil }
        return NodeStartBox(call: unsafeBitCast(symbol, to: NodeStart.self))
    }()

    // MARK: - Sources

    @discardableResult
    func activate(source: Md5Source, bundleURL: URL, dataDirectory: URL) async throws -> [CatVodSite] {
        let requested = SourceLocation(id: source.id, bundlePath: bundleURL.standardizedFileURL.path,
                                       dataPath: dataDirectory.standardizedFileURL.path)
        // Browsing and opening an episode may both activate the same installed source.
        if location == requested, activeSourceID == source.id, mediaScope != nil, ready != nil { return sites }
        deactivate()
        let generation = activation
        try await startNodeIfNeeded()
        guard activation == generation else { throw CatVodRuntimeError.notLoaded }
        let result = try await control("/load", method: "POST",
                                      body: ["sourceID": source.id, "path": bundleURL.path, "data": dataDirectory.path])
        guard activation == generation else { throw CatVodRuntimeError.notLoaded }
        let parsed = try parseSites(result)
        guard let object = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              object["sourceID"] as? String == source.id,
              let port = object["port"] as? Int, (1...65535).contains(port),
              let ports = object["ports"] as? [Int], ports.contains(port),
              ports.allSatisfy({ (1...65535).contains($0) }),
              let scope = object["mediaScope"] as? String, scope.utf8.count == 48,
              scope.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }),
              let originText = object["origin"] as? String,
              originText == "http://127.0.0.1:\(port)", let origin = URL(string: originText) else {
            throw CatVodRuntimeError.badResponse("source origin")
        }
        activeSourceID = source.id
        bundleOrigin = origin
        location = requested
        mediaScope = scope
        allowedLoopbackPorts = Set(ports)
        sites = parsed
        return parsed
    }

    func deactivate() {
        activation = UUID()
        activeSourceID = nil
        sites = []
        bundleOrigin = nil
        mediaScope = nil
        location = nil
        allowedLoopbackPorts = []
    }

    /// Resolve bundle-relative media and authenticate only this source's owned loopback ports.
    /// Use the returned URL for AsyncImage/URLRequest/AVURLAsset; HLS children are rewritten by Node.
    func mediaURL(_ text: String, sourceID: String) throws -> URL {
        guard !text.isEmpty, activeSourceID == sourceID, let mediaScope, let bundleOrigin else { throw CatVodRuntimeError.notLoaded }
        guard let input = URL(string: text, relativeTo: bundleOrigin)?.absoluteURL,
              var components = URLComponents(url: input, resolvingAgainstBaseURL: true),
              let scheme = components.scheme?.lowercased(), ["http", "https"].contains(scheme),
              let rawHost = components.host?.lowercased(), components.user == nil, components.password == nil else {
            throw CatVodRuntimeError.badResponse("media URL")
        }
        let host = rawHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        let local = ["localhost", "127.0.0.1", "::1"].contains(host)
        if !local {
            guard !host.hasPrefix("127."), host != "0.0.0.0", host != "::", !host.hasSuffix(".localhost") else {
                throw CatVodRuntimeError.badResponse("unowned loopback URL")
            }
            // Never append a host credential to a remote URL or change its signed query string.
            return input
        }
        guard scheme == "http", let port = components.port, allowedLoopbackPorts.contains(port) else {
            throw CatVodRuntimeError.badResponse("unowned loopback port")
        }
        // Preserve the original signed query verbatim. The host will serve only media
        // paths that the active site's own response has granted (GET/HEAD only).
        components.host = "127.0.0.1"
        components.percentEncodedPath = "/.readcc-media/" + mediaScope + (components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath)
        guard let url = components.url else { throw CatVodRuntimeError.badResponse("media URL") }
        return url
    }

    private func parseSites(_ data: Data) throws -> [CatVodSite] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CatVodRuntimeError.badResponse("not JSON")
        }
        if let error = object["error"] as? String {
            throw CatVodRuntimeError.sourceFailed(error)
        }
        guard let rows = object["sites"] as? [[String: Any]] else {
            throw CatVodRuntimeError.badResponse("no sites")
        }
        return rows.compactMap { row in
            guard let key = row["key"] as? String, let api = row["api"] as? String,
                  let name = row["name"] as? String else { return nil }
            return CatVodSite(key: key, name: name, api: api, type: (row["type"] as? NSNumber)?.intValue ?? 0,
                              searchable: row["searchable"] as? Bool ?? false,
                              filterable: row["filterable"] as? Bool ?? false,
                              indexs: row["indexs"] as? Bool ?? false)
        }
    }

    // MARK: - Calls

    /// One site action: `home`, `category`, `search`, `detail`, `play` — args are the bundle's
    /// own (`{"filter":true}`, `{"wd":"…","pg":"1"}`, `{"ids":"…"}`, `{"flag":"…","id":"…"}`).
    func invoke(_ site: CatVodSite, action: String, arguments: [String: Any] = [:]) async throws -> Data {
        guard let sourceID = activeSourceID else { throw CatVodRuntimeError.notLoaded }
        return try await invoke(sourceID: sourceID, site: site, action: action, arguments: arguments)
    }

    func invoke(sourceID: String, site: CatVodSite, action: String, arguments: [String: Any] = [:]) async throws -> Data {
        guard activeSourceID == sourceID, sites.contains(where: { $0.key == site.key && $0.api == site.api }) else {
            throw CatVodRuntimeError.notLoaded
        }
        let generation = activation
        let result = try await control("/invoke", method: "POST",
                                      body: ["sourceID": sourceID, "site": site.key, "api": site.api, "action": action, "arguments": arguments])
        guard activeSourceID == sourceID, activation == generation else { throw CatVodRuntimeError.notLoaded }
        guard let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
              let body = object["body"] as? String else {
            throw CatVodRuntimeError.badResponse("invoke")
        }
        // Keep source headers (object or JSON string) intact for the content parser.
        // The private control header is never supplied to an image loader or AVPlayer.
        return Data(body.utf8)
    }

    func credentials() async throws -> CatVodCredentials {
        guard let sourceID = activeSourceID else { throw CatVodRuntimeError.notLoaded }
        let result = try await control("/proxy", method: "POST",
                                      body: ["sourceID": sourceID, "path": "/website/api/credentials", "method": "GET"])
        guard let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
              let body = object["body"] as? String,
              let payload = try? JSONSerialization.jsonObject(with: Data(body.utf8)) as? [String: Any] else {
            throw CatVodRuntimeError.badResponse("credentials")
        }
        let data = payload["data"] as? [String: Any] ?? [:]
        var values: [String: [String: String]] = [:]
        for (provider, fields) in data {
            guard let fields = fields as? [String: Any] else { continue }
            values[provider] = fields.compactMapValues { $0 as? String }
        }
        return CatVodCredentials(values: values)
    }

    /// `PUT /website/api/credential/<provider>/<field>` with `{"value": …}` — the same route the
    /// bundle's 配置中心 page uses for every pan cookie and token.
    func saveCredential(provider: String, field: String = "cookie", value: String) async throws {
        guard let sourceID = activeSourceID else { throw CatVodRuntimeError.notLoaded }
        let escaped = "/website/api/credential/\(provider)/\(field)"
        _ = try await control("/proxy", method: "POST",
                              body: ["sourceID": sourceID, "path": escaped, "method": "PUT", "body": ["value": value]])
    }

    func clearCredential(provider: String, field: String = "cookie") async throws {
        guard let sourceID = activeSourceID else { throw CatVodRuntimeError.notLoaded }
        _ = try await control("/proxy", method: "POST",
                              body: ["sourceID": sourceID, "path": "/website/api/credential/\(provider)/\(field)", "method": "DELETE"])
    }

    private func control(_ path: String, method: String, body: [String: Any]? = nil) async throws -> Data {
        guard let ready else { throw CatVodRuntimeError.notLoaded }
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(ready.port)\(path)")!)
        request.httpMethod = method
        request.timeoutInterval = 90
        request.setValue(ready.token, forHTTPHeaderField: "x-readcc-token")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, response) = try await BoundedResponseLoader.load(request, session: .shared, limit: 12 * 1024 * 1024,
                                                                    redirect: { _ in false }, transport: "catvod-local")
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatVodRuntimeError.badResponse("HTTP \(http.statusCode)")
        }
        if ["/invoke", "/proxy"].contains(path) {
            guard let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let status = envelope["status"] as? Int else { throw CatVodRuntimeError.badResponse("missing upstream status") }
            guard (200..<300).contains(status) else { throw CatVodRuntimeError.badResponse("upstream HTTP \(status)") }
        }
        return data
    }
}

/// Node's entry point (`node_start`) is resolved at run time from the embedded
/// NodeMobile.framework, so the app links without it and reports a missing runtime instead of
/// failing to launch.
