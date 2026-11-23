import Foundation
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
        case .frameworkMissing: localized("這一版沒有帶 Node 執行環境，MD5 源無法執行。")
        case .startTimeout: localized("Node 執行環境啟動逾時。")
        case .notLoaded: localized("請先啟動一個 MD5 源。")
        case .sourceFailed(let reason): String(format: localized("源執行失敗：%@"), reason)
        case .badResponse(let reason): String(format: localized("源回應無法讀取：%@"), reason)
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
            throw CatVodRuntimeError.sourceFailed("Node 結束代碼 \(nodeExit)")
        }
        guard nodeStarted || Self.frameworkAvailable else { throw CatVodRuntimeError.frameworkMissing }
        isStarting = true
        defer { isStarting = false }
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true)
        try CatVodHostScript.source.write(to: hostURL, atomically: true, encoding: .utf8)
        try? manager.removeItem(at: readyURL)

        if !nodeStarted {
            guard let nodeStart = Self.nodeStartBox else { throw CatVodRuntimeError.frameworkMissing }
            nodeStarted = true
            let hostPath = hostURL.path
            let readyPath = readyURL.path
            let thread = Thread {
                let arguments = ["node", hostPath, readyPath]
                let pointers = arguments.map { strdup($0) }
                let status = pointers.withUnsafeMutableBufferPointer { buffer in
                    nodeStart.call(Int32(buffer.count), buffer.baseAddress)
                }
                for pointer in pointers where pointer != nil { free(pointer) }
                Task { @MainActor in
                    CatVodRuntime.shared.noteNodeExit(status)
                }
            }
            thread.name = "readcc.catvod.node"
            thread.stackSize = 4 << 20
            thread.start()
        }

        for _ in 0..<150 {
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
        try await startNodeIfNeeded()
        let result = try await control("/load", method: "POST",
                                      body: ["path": bundleURL.path, "data": dataDirectory.path])
        let parsed = try parseSites(result)
        activeSourceID = source.id
        sites = parsed
        return parsed
    }

    func deactivate() {
        activeSourceID = nil
        sites = []
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
        guard activeSourceID != nil else { throw CatVodRuntimeError.notLoaded }
        let result = try await control("/invoke", method: "POST",
                                      body: ["api": site.api, "action": action, "arguments": arguments])
        guard let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
              let body = object["body"] as? String else {
            throw CatVodRuntimeError.badResponse("invoke")
        }
        return Data(body.utf8)
    }

    func credentials() async throws -> CatVodCredentials {
        guard activeSourceID != nil else { throw CatVodRuntimeError.notLoaded }
        let result = try await control("/proxy", method: "POST",
                                      body: ["path": "/website/api/credentials", "method": "GET"])
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
        guard activeSourceID != nil else { throw CatVodRuntimeError.notLoaded }
        let escaped = "/website/api/credential/\(provider)/\(field)"
        _ = try await control("/proxy", method: "POST",
                              body: ["path": escaped, "method": "PUT", "body": ["value": value]])
    }

    func clearCredential(provider: String, field: String = "cookie") async throws {
        guard activeSourceID != nil else { throw CatVodRuntimeError.notLoaded }
        _ = try await control("/proxy", method: "POST",
                              body: ["path": "/website/api/credential/\(provider)/\(field)", "method": "DELETE"])
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
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw CatVodRuntimeError.badResponse("HTTP \(http.statusCode)")
        }
        return data
    }
}

/// Node's entry point (`node_start`) is resolved at run time from the embedded
/// NodeMobile.framework, so the app links without it and reports a missing runtime instead of
/// failing to launch.
