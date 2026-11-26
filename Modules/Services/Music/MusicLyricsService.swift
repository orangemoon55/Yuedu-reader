import Combine
import CoreFoundation
import Foundation

// Provider endpoint/response adaptation derived from Yingxia / TVBox-Silicon
// Sources/TVCore/MusicLyrics.swift:107-127 at jo32/tvbox-silicon
// a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c. GPL-3.0-only.
// See LICENSES/Yingxia-GPL-3.0-only.txt, NOTICE and MusicLyricsService.NOTICE.md.
// No companion/title search, JS execution, source headers or credentials are used.

struct MusicLyricsIdentity: Hashable, Sendable {
    let trackID: String
    let provider: String
    let songID: String

    static func from(_ item: MediaHubLibraryItem) -> Self? {
        guard let song = MusicJSSong.from(item) else { return nil }
        return from(trackID: item.id, provider: song.provider, musicInfoJSON: song.musicInfoJSON)
    }

    static func from(trackID: String, provider: String, musicInfoJSON: String) -> Self? {
        guard musicInfoJSON.utf8.count <= 64 * 1024,
              let root = try? JSONSerialization.jsonObject(with: Data(musicInfoJSON.utf8)) as? [String: Any] else { return nil }
        let meta = root["meta"] as? [String: Any]
        let candidates: [Any?]
        switch provider {
        case "wy": candidates = [meta?["songId"], root["songId"], root["id"], root["songmid"]]
        // QQ songid is numeric and is NOT interchangeable with songmid.
        case "tx": candidates = [root["mid"], root["songmid"], root["songMid"], meta?["songmid"], meta?["mid"]]
        default: return nil
        }
        for value in candidates {
            let text: String
            if let string = value as? String { text = string }
            else if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { text = number.stringValue }
            else { continue }
            if validID(text, provider: provider) { return Self(trackID: trackID, provider: provider, songID: text) }
        }
        return nil
    }

    static func validID(_ value: String, provider: String) -> Bool {
        let ascii = value.utf8
        guard !ascii.isEmpty else { return false }
        if provider == "wy" {
            return ascii.count <= 20 && ascii.allSatisfy { (48...57).contains($0) } && UInt64(value).map { $0 > 0 } == true
        }
        if provider == "tx" {
            return ascii.count <= 64 && ascii.allSatisfy { (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) }
        }
        return false
    }
}

enum MusicLyricsResult: Equatable, Sendable {
    case lyrics(YingxiaMusicLyrics)
    case instrumental
    case unavailable
}

enum MusicOnlineLyricsError: LocalizedError {
    case invalidIdentity, invalidResponse, responseTooLarge, httpStatus
    var errorDescription: String? {
        switch self {
        case .invalidIdentity: return localized("此曲缺少可用的原平台歌曲識別碼。")
        case .invalidResponse: return localized("線上歌詞回應格式無效，請重試或匯入本地 LRC。")
        case .responseTooLarge: return localized("線上歌詞超過大小限制。")
        case .httpStatus: return localized("歌詞平台暫時無法提供此曲歌詞。")
        }
    }
}

enum MusicLyricsService {
    static let maximumResponseBytes = 512 * 1024
    static let timeout: TimeInterval = 10

    static func request(for identity: MusicLyricsIdentity) throws -> URLRequest {
        guard MusicLyricsIdentity.validID(identity.songID, provider: identity.provider) else { throw MusicOnlineLyricsError.invalidIdentity }
        let endpoint: String
        let query: [URLQueryItem]
        switch identity.provider {
        case "wy":
            endpoint = "https://music.163.com/api/song/lyric"
            query = [("id", identity.songID), ("lv", "1"), ("tv", "1")].map { URLQueryItem(name: $0.0, value: $0.1) }
        case "tx":
            endpoint = "https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg"
            query = [("songmid", identity.songID), ("format", "json"), ("nobase64", "1")].map { URLQueryItem(name: $0.0, value: $0.1) }
        default: throw MusicOnlineLyricsError.invalidIdentity
        }
        var components = URLComponents(string: endpoint)!
        components.queryItems = query
        var request = URLRequest(url: components.url!, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: timeout)
        request.httpShouldHandleCookies = false
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if identity.provider == "tx" { request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer") }
        return request
    }

    static func decode(_ data: Data, provider: String) throws -> MusicLyricsResult {
        guard data.count <= maximumResponseBytes else { throw MusicOnlineLyricsError.responseTooLarge }
        guard !data.isEmpty, String(data: data, encoding: .utf8) != nil,
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw MusicOnlineLyricsError.invalidResponse }
        let original: String?
        let translated: String?
        switch provider {
        case "wy":
            if let code = root["code"], integer(code) != 200 { throw MusicOnlineLyricsError.httpStatus }
            if flag(root["nolyric"]) { return .instrumental }
            if flag(root["uncollected"]) { return .unavailable }
            original = try field((root["lrc"] as? [String: Any])?["lyric"])
            translated = try field((root["tlyric"] as? [String: Any])?["lyric"])
        case "tx":
            for key in ["code", "retcode"] {
                if let value = root[key], integer(value) != 0 { throw MusicOnlineLyricsError.httpStatus }
            }
            original = try qqText(root["lyric"])
            translated = try qqText(root["trans"])
        default: throw MusicOnlineLyricsError.invalidIdentity
        }
        guard let original, !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return .unavailable }
        guard let lyrics = YingxiaMusicLyrics.parse(original, translation: translated) else { return .unavailable }
        return .lyrics(lyrics)
    }

    private static func integer(_ value: Any) -> Int? {
        if let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID() { return Int(number.stringValue) }
        if let string = value as? String { return Int(string) }
        return nil
    }
    private static func flag(_ value: Any?) -> Bool {
        if let number = value as? NSNumber, CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue }
        return (value as? String)?.lowercased() == "true"
    }
    private static func field(_ value: Any?) throws -> String? {
        guard let value, !(value is NSNull) else { return nil }
        guard let text = value as? String else { throw MusicOnlineLyricsError.invalidResponse }
        return text
    }
    private static func qqText(_ value: Any?) throws -> String? {
        guard let raw = try field(value), !raw.isEmpty else { return nil }
        let text: String
        // The endpoint may ignore nobase64. Decode only canonical base64; no unknown-character skipping.
        if let data = Data(base64Encoded: raw), data.base64EncodedString() == raw {
            guard let decoded = String(data: data, encoding: .utf8), !decoded.unicodeScalars.contains(where: { $0.value < 32 && ![9, 10, 13].contains($0.value) }) else { throw MusicOnlineLyricsError.invalidResponse }
            text = decoded
        } else { text = raw }
        return entities(text)
    }
    private static func entities(_ value: String) -> String {
        // Decode entities once, without loading HTML/WebKit or evaluating any returned content.
        guard let regex = try? NSRegularExpression(pattern: "&(#x[0-9a-fA-F]{1,6}|#[0-9]{1,7}|amp|lt|gt|quot|apos);?") else { return value }
        let matches = regex.matches(in: value, range: NSRange(value.startIndex..., in: value))
        var output = value
        for match in matches.reversed() {
            guard let range = Range(match.range, in: output), let keyRange = Range(match.range(at: 1), in: value) else { continue }
            let key = String(value[keyRange])
            let named = ["amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'"]
            let scalar: UInt32? = key.hasPrefix("#x") ? UInt32(key.dropFirst(2), radix: 16) : (key.hasPrefix("#") ? UInt32(key.dropFirst()) : nil)
            if let replacement = named[key] ?? scalar.flatMap(UnicodeScalar.init).map(String.init) { output.replaceSubrange(range, with: replacement) }
        }
        return output
    }
}

private final class MusicLyricsRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(MusicLyricsService.allows(request.url, host: host) ? request : nil)
    }
}

extension MusicLyricsService {
    static func allows(_ url: URL?, host: String) -> Bool {
        guard let url else { return false }
        return ["music.163.com", "c.y.qq.com"].contains(host)
            && url.scheme?.lowercased() == "https" && url.host?.lowercased() == host
            && (url.port == nil || url.port == 443) && url.user == nil && url.password == nil
    }

    static func fetch(_ identity: MusicLyricsIdentity) async throws -> MusicLyricsResult {
        let request = try request(for: identity)
        let host = request.url!.host!
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = timeout
        configuration.timeoutIntervalForResource = timeout + 2
        let session = URLSession(configuration: configuration, delegate: MusicLyricsRedirectGuard(host: host), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse, allows(response.url, host: host),
              (200...299).contains(response.statusCode) else { throw MusicOnlineLyricsError.httpStatus }
        guard response.expectedContentLength <= Int64(maximumResponseBytes) else { throw MusicOnlineLyricsError.responseTooLarge }
        var data = Data()
        data.reserveCapacity(min(maximumResponseBytes, max(0, Int(response.expectedContentLength))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumResponseBytes else { throw MusicOnlineLyricsError.responseTooLarge }
            data.append(byte)
        }
        try Task.checkCancellation()
        return try decode(data, provider: identity.provider)
    }
}

/// Shared between the persistent capsule and the detail sheet. Requests belong to this model,
/// never to a view task. Repeated publication of the exactly equal selected item is idempotent;
/// a changed playback URL/headers or different selected track creates a new generation. Late
/// completions cannot restore old/automatically replaced/local-imported text.
@MainActor
final class MusicLyricsModel: ObservableObject {
    enum State: Equatable {
        case idle, loading, ready, instrumental, unavailable, unsupported
        case failed(String)
    }
    typealias Loader = @Sendable (MusicLyricsIdentity) async throws -> MusicLyricsResult
    static let shared = MusicLyricsModel(player: MusicPlayer.shared)
    @Published private(set) var lyrics: YingxiaMusicLyrics?
    @Published private(set) var trackID: String?
    @Published private(set) var state: State = .idle
    @Published private(set) var generation = UUID()
    private var identity: MusicLyricsIdentity?
    private var selectedTrack: MediaHubLibraryItem?
    private var loadTask: Task<Void, Never>?
    private var observation: AnyCancellable?
    private weak var player: MusicPlayer?
    private let loader: Loader
    private var localLyrics: [String: YingxiaMusicLyrics] = [:]
    private var localOrder: [String] = []

    /// Pass no player and a fixture loader for isolated offline tests.
    init(player: MusicPlayer? = nil, loader: @escaping Loader = { try await MusicLyricsService.fetch($0) }) {
        self.player = player
        self.loader = loader
        if let player {
            observation = player.$currentTrack.sink { [weak self] track in
                self?.select(track)
            }
        }
    }

    func load(for track: MediaHubLibraryItem?) async {
        // A cancelled/outdated view must not select an old track after the player moved on.
        if let player, track != player.currentTrack { return }
        select(track)
        let pending = loadTask
        await pending?.value
    }

    private func select(_ track: MediaHubLibraryItem?) {
        let next = track.flatMap(MusicLyricsIdentity.from)
        if selectedTrack == track, trackID == track?.id, identity == next { return }
        selectedTrack = track
        loadTask?.cancel()
        loadTask = nil
        generation = UUID()
        trackID = track?.id
        identity = next
        lyrics = nil
        guard let track else { state = .idle; return }
        if let imported = localLyrics[track.id] { lyrics = imported; state = .ready; return }
        guard let next else { state = .unsupported; return }
        start(next)
    }

    private func start(_ target: MusicLyricsIdentity) {
        state = .loading
        let token = generation
        let loader = loader
        loadTask = Task { [weak self] in
            do {
                let result = try await loader(target)
                guard !Task.isCancelled, let self,
                      self.generation == token, self.identity == target, self.trackID == target.trackID else { return }
                switch result {
                case .lyrics(let value): self.lyrics = value; self.state = .ready
                case .instrumental: self.state = .instrumental
                case .unavailable: self.state = .unavailable
                }
                self.loadTask = nil
            } catch {
                guard !Task.isCancelled, let self,
                      self.generation == token, self.identity == target else { return }
                self.lyrics = nil
                self.state = .failed((error as? MusicOnlineLyricsError)?.localizedDescription
                    ?? localized("無法載入線上歌詞，請檢查連線後重試。"))
                self.loadTask = nil
            }
        }
    }

    func retry() async {
        guard let identity else { return }
        // Imports always win, including retry initiated from another surface.
        guard localLyrics[identity.trackID] == nil else { return }
        loadTask?.cancel()
        generation = UUID()
        lyrics = nil
        start(identity)
        let pending = loadTask
        await pending?.value
    }

    @discardableResult
    func importLyrics(_ value: YingxiaMusicLyrics, trackID targetID: String, generation targetGeneration: UUID) -> Bool {
        guard MusicLyricsImportOwnership.accepts(targetTrackID: targetID, targetGeneration: targetGeneration,
                                                 currentTrackID: trackID ?? "", currentGeneration: generation) else { return false }
        loadTask?.cancel()
        loadTask = nil
        generation = UUID()
        localLyrics[targetID] = value
        localOrder.removeAll { $0 == targetID }
        localOrder.append(targetID)
        if localOrder.count > 64 { localLyrics[localOrder.removeFirst()] = nil }
        lyrics = value
        state = .ready
        return true
    }

    func currentLine(at time: TimeInterval) -> YingxiaLyricLine? {
        guard time.isFinite, let lyrics, let index = lyrics.index(at: time) else { return nil }
        return lyrics.lines[index]
    }
}
