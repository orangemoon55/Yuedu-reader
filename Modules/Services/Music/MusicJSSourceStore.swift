import Combine
import CryptoKit
import Foundation

struct MusicJSProvider: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let actions: [String]
    let qualities: [String]
    var canSearch: Bool { actions.contains("search") }
}

struct MusicJSSource: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let name: String
    let version: String
    let providers: [MusicJSProvider]
}

struct MusicJSSong: Hashable, Identifiable, Sendable {
    let sourceID: String
    let provider: String
    let title: String
    let artist: String
    let album: String
    let poster: String
    let musicInfoJSON: String
    var id: String { sourceID + "." + provider + "." + Self.digest(musicInfoJSON) }
    static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    /// Reject unsafe bookmarks, rather than silently removing fields a resolver may need.
    static func canPersistMusicInfo(_ text: String) -> Bool {
        guard let value = try? JSONSerialization.jsonObject(with: Data(text.utf8)) else { return false }
        let forbidden: Set<String> = ["url", "musicurl", "headers", "header", "cookie", "cookies", "authorization", "auth",
            "token", "accesstoken", "refreshtoken", "signature", "sign", "apikey", "key", "secret", "password",
            "credential", "credentials", "securitytoken", "sessionid", "hdnts", "hdnea", "wssecret", "authkey"]
        func safe(_ value: Any) -> Bool {
            if let object = value as? [String: Any] {
                return object.allSatisfy { key, value in
                    let canonical = key.lowercased().filter { $0.isLetter || $0.isNumber }
                    return !forbidden.contains(canonical) && safe(value)
                }
            }
            if let array = value as? [Any] { return array.allSatisfy(safe) }
            if let text = value as? String, let url = URLComponents(string: text),
               ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                if url.user != nil || url.password != nil { return false }
                if url.queryItems?.contains(where: {
                    let key = $0.name.lowercased().filter { $0.isLetter || $0.isNumber }
                    return forbidden.contains(key) || key.hasSuffix("token") || key.hasSuffix("signature") || key.hasSuffix("credential")
                }) == true { return false }
            }
            return true
        }
        return safe(value)
    }

    func savedItem(sourceName: String) throws -> MediaHubLibraryItem {
        guard Self.canPersistMusicInfo(musicInfoJSON) else { throw MusicJSError.invalidResponse }
        return MediaHubLibraryItem(sourceID: sourceID, siteKey: provider,
            videoID: "lx:" + Data(musicInfoJSON.utf8).base64EncodedString(), title: title,
            poster: poster, kind: .music, siteName: sourceName, categoryName: album, remarks: artist)
    }

    /// Volatile resolver input stays in memory; the player identity contains only its digest.
    func playbackItem(sourceName: String) -> MediaHubLibraryItem {
        if let safe = try? savedItem(sourceName: sourceName) { return safe }
        return MediaHubLibraryItem(sourceID: sourceID, siteKey: provider,
            videoID: "lx-volatile:" + Self.digest(musicInfoJSON), title: title,
            poster: poster, kind: .music, siteName: sourceName, categoryName: album, remarks: artist)
    }
    static func from(_ item: MediaHubLibraryItem) -> MusicJSSong? {
        guard item.kind == .music, item.sourceID.hasPrefix("readcc.music.js."),
              item.videoID.hasPrefix("lx:"), let raw = Data(base64Encoded: String(item.videoID.dropFirst(3))),
              let text = String(data: raw, encoding: .utf8), Self.canPersistMusicInfo(text) else { return nil }
        return MusicJSSong(sourceID: item.sourceID, provider: item.siteKey, title: item.title,
            artist: item.remarks ?? "", album: item.categoryName ?? "", poster: item.poster, musicInfoJSON: text)
    }
}

@MainActor
final class MusicJSSourceStore: ObservableObject {
    static let shared = MusicJSSourceStore()
    @Published private(set) var sources: [MusicJSSource] = []
    @Published private(set) var loadFailure: String?
    private let directory: URL
    private var cached: (id: String, runtime: MusicJSRuntime)?
    private var activation = UUID()

    init(directory: URL? = nil) {
        self.directory = directory ?? URL.applicationSupportDirectory.appendingPathComponent("MediaHub/MusicJS", isDirectory: true)
        reload()
    }

    func reload() {
        let file = directory.appendingPathComponent("sources.json")
        guard FileManager.default.fileExists(atPath: file.path) else { sources = []; return }
        do {
            let loaded = try JSONDecoder().decode([MusicJSSource].self, from: Data(contentsOf: file))
            guard loaded.allSatisfy({ Self.validID($0.id) }) else { throw MusicJSError.invalidResponse }
            sources = loaded; loadFailure = nil
        } catch { loadFailure = MusicJSError.invalidResponse.localizedDescription }
    }

    func importFile(_ file: URL) async throws -> MusicJSSource {
        guard file.pathExtension.lowercased() == "js" else { throw MusicJSError.unsupported }
        let access = file.startAccessingSecurityScopedResource()
        defer { if access { file.stopAccessingSecurityScopedResource() } }
        let data = try Self.readScript(file)
        guard let text = String(data: data, encoding: .utf8) else { throw MusicJSError.unsupported }
        let runtime = try await MusicJSRuntime.load(script: text)
        do {
            try Task.checkCancellation()
            let providers = try Self.providers(runtime.initializationJSON)
            let source = MusicJSSource(id: "readcc.music.js." + MusicJSSong.digest(text),
                name: Self.metadata("name", in: text) ?? file.deletingPathExtension().lastPathComponent,
                version: Self.metadata("version", in: text) ?? "", providers: providers)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let scriptFile = directory.appendingPathComponent(source.id + ".js")
            try data.write(to: scriptFile, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: scriptFile.path)
            let next = sources.filter { $0.id != source.id } + [source]
            try save(next)
            cached?.runtime.close(); cached = (source.id, runtime); sources = next
            return source
        } catch { runtime.close(); throw error }
    }

    func remove(_ source: MusicJSSource) throws {
        let next = sources.filter { $0.id != source.id }
        try save(next)
        if cached?.id == source.id { cached?.runtime.close(); cached = nil }
        sources = next
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(source.id + ".js"))
    }

    private func save(_ values: [MusicJSSource]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(values).write(to: directory.appendingPathComponent("sources.json"), options: .atomic)
    }

    private func engine(_ id: String) async throws -> MusicJSRuntime {
        try Task.checkCancellation()
        guard sources.contains(where: { $0.id == id }) else { throw MusicJSError.removed }
        if let cached, cached.id == id, cached.runtime.isUsable { return cached.runtime }
        let token = UUID(); activation = token
        let text = String(decoding: try Self.readScript(directory.appendingPathComponent(id + ".js")), as: UTF8.self)
        let next = try await MusicJSRuntime.load(script: text)
        guard !Task.isCancelled, activation == token, sources.contains(where: { $0.id == id }) else { next.close(); throw CancellationError() }
        cached?.runtime.close(); cached = (id, next); return next
    }

    static func readScript(_ file: URL) throws -> Data {
        let limit = 512 * 1024
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard !data.isEmpty, data.count <= limit, String(data: data, encoding: .utf8) != nil else {
            throw MusicJSError.unsupported
        }
        return data
    }

    private static func validID(_ id: String) -> Bool {
        let prefix = "readcc.music.js."
        return id.hasPrefix(prefix) && id.count == prefix.count + 64
            && id.dropFirst(prefix.count).allSatisfy { $0.isHexDigit && !$0.isUppercase }
    }

    private static func metadata(_ key: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: "@" + key + "[ \\t]+([^\\r\\n*]+)"),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func providers(_ json: String) throws -> [MusicJSProvider] {
        guard let root = try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let values = root["sources"] as? [String: [String: Any]] else { throw MusicJSError.unsupported }
        let result = values.sorted(by: { $0.key < $1.key }).compactMap { key, value -> MusicJSProvider? in
            guard !key.isEmpty, key.utf8.count <= 64,
                  let actions = value["actions"] as? [String], actions.contains("musicUrl"),
                  (value["type"] as? String ?? "music") == "music" else { return nil }
            let qualities = value["qualitys"] as? [String] ?? value["qualities"] as? [String] ?? ["128k"]
            return MusicJSProvider(id: key, name: value["name"] as? String ?? key,
                actions: actions, qualities: qualities.isEmpty ? ["128k"] : Array(qualities.prefix(20)))
        }
        guard !result.isEmpty, result.count <= 30 else { throw MusicJSError.unsupported }
        return result
    }

    func search(sourceID: String, provider: String, query: String) async throws -> [MusicJSSong] {
        guard let source = sources.first(where: { $0.id == sourceID }),
              source.providers.contains(where: { $0.id == provider && $0.canSearch }) else { throw MusicJSError.unsupported }
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, keyword.count <= 300 else { throw MusicJSError.invalidResponse }
        let info = try JSONSerialization.data(withJSONObject: ["keyword": keyword, "limit": 20])
        let runtime = try await engine(sourceID)
        let raw = try await runtime.invoke(action: "search", provider: provider, infoJSON: String(decoding: info, as: UTF8.self))
        let parsed = try JSONSerialization.jsonObject(with: Data(raw.utf8))
        let object = parsed as? [String: Any]
        let values = parsed as? [[String: Any]] ?? object?["list"] as? [[String: Any]]
            ?? object?["data"] as? [[String: Any]] ?? []
        var seen = Set<String>()
        return try values.prefix(100).compactMap { value in
            let title = value["name"] as? String ?? value["title"] as? String ?? ""
            guard !title.isEmpty else { return nil }
            let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
            guard data.count <= 32 * 1024 else { return nil }
            let meta = value["meta"] as? [String: Any]
            let song = MusicJSSong(sourceID: sourceID, provider: provider, title: String(title.prefix(500)),
                artist: value["singer"] as? String ?? value["artist"] as? String ?? "",
                album: value["albumName"] as? String ?? value["album"] as? String ?? "",
                poster: value["img"] as? String ?? meta?["picture"] as? String ?? "",
                musicInfoJSON: String(decoding: data, as: UTF8.self))
            return seen.insert(song.id).inserted ? song : nil
        }
    }

    /// Resolve at every user play, never persist the resulting signed URL or request headers.
    func resolve(_ song: MusicJSSong, quality: String) async throws -> MediaHubLibraryItem {
        guard let source = sources.first(where: { $0.id == song.sourceID }),
              let provider = source.providers.first(where: { $0.id == song.provider }),
              provider.actions.contains("musicUrl"), provider.qualities.contains(quality) else { throw MusicJSError.removed }
        let musicInfo = try JSONSerialization.jsonObject(with: Data(song.musicInfoJSON.utf8))
        let info = try JSONSerialization.data(withJSONObject: ["musicInfo": musicInfo, "type": quality])
        let runtime = try await engine(song.sourceID)
        let raw = try await runtime.invoke(action: "musicUrl", provider: song.provider, infoJSON: String(decoding: info, as: UTF8.self))
        let result = try JSONSerialization.jsonObject(with: Data(raw.utf8), options: [.fragmentsAllowed])
        let object = result as? [String: Any]
        let address = result as? String ?? object?["url"] as? String ?? ""
        guard let url = URL(string: address), MusicJSRuntime.allowedRemoteURL(url) else { throw MusicJSError.invalidResponse }
        let headers = (object?["headers"] as? [String: String] ?? object?["header"] as? [String: String] ?? [:])
            .filter { MusicJSRuntime.safeHeader($0.key, $0.value) }
        var item = song.playbackItem(sourceName: source.name)
        item.musicURL = address; item.musicHeaders = headers.isEmpty ? nil : headers
        item.musicQuality = quality
        return item
    }
}
