import Foundation

/// A clean-room music track record. Sources are either user-authorized HTTP(S) URLs or
/// files copied into the app's Application Support directory; no provider or paywall logic
/// is implied by this model.
struct MusicTrackDescriptor: Codable, Hashable, Identifiable, Sendable {
    let title: String
    let artist: String
    let album: String
    let urlString: String
    let headers: [String: String]

    var id: String { urlString + "\u{001F}" + title }

    var isLocal: Bool { urlString.hasPrefix("local:") }

    func resolvedURL() -> URL? {
        if isLocal {
            let name = String(urlString.dropFirst("local:".count))
            guard !name.isEmpty, !name.contains(".."), !name.contains("/") else { return nil }
            return MusicStorage.directory.appendingPathComponent(name, isDirectory: false)
        }
        return URL(string: urlString)
    }

    func libraryItem(sourceID: String = MusicImportService.sourceID,
                    siteKey: String = MusicImportService.siteKey) -> MediaHubLibraryItem {
        MediaHubLibraryItem(sourceID: sourceID, siteKey: siteKey, videoID: id,
            title: title, poster: "", kind: .music, siteName: "本机音乐",
            categoryName: album.isEmpty ? nil : album,
            remarks: artist.isEmpty ? nil : artist,
            musicURL: urlString, musicHeaders: headers.isEmpty ? nil : headers)
    }

    static func from(_ item: MediaHubLibraryItem) -> MusicTrackDescriptor? {
        guard item.kind == .music, let urlString = item.musicURL,
              !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let parsedURL = URL(string: urlString)
        guard urlString.hasPrefix("local:")
                || parsedURL?.scheme?.lowercased() == "http"
                || parsedURL?.scheme?.lowercased() == "https" else { return nil }
        return MusicTrackDescriptor(title: item.title,
            artist: item.remarks ?? "", album: item.categoryName ?? "",
            urlString: urlString, headers: item.musicHeaders ?? [:])
    }
}

enum MusicStorage {
    static var directory: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("MediaHub", isDirectory: true)
            .appendingPathComponent("Music", isDirectory: true)
    }
}

enum MusicImportError: LocalizedError, Equatable {
    case unsupportedFile
    case invalidURL
    case emptyPlaylist
    case cannotCopy(String)
    case malformedHeaders

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return localized("不支援的音讯或播放列表格式。")
        case .invalidURL: return localized("只接受有效的 http(s) 音乐直链；不会代替来源绕过授权。")
        case .emptyPlaylist: return localized("播放列表没有可播放的音讯项。")
        case .cannotCopy(let reason): return String(format: localized("无法导入音讯：%@"), reason)
        case .malformedHeaders: return localized("请求头必须是 JSON 对象，例如 {\"Referer\":\"https://example.com\"}。")
        }
    }
}

/// Imports only explicit user input. The parser does not contact remote services and does not
/// execute playlist contents. Playback later goes through AVFoundation with the supplied headers.
enum MusicImportService {
    static let sourceID = "readcc.music.local"
    static let siteKey = "imported"

    static func parseHeaders(_ text: String) throws -> [String: String] {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            throw MusicImportError.malformedHeaders
        }
        let allowed = Set(["user-agent", "referer", "origin", "accept"])
        var result: [String: String] = [:]
        for (key, value) in object {
            guard allowed.contains(key.lowercased()), !value.contains("\\r"), !value.contains("\\n"),
                  value.utf8.count <= 2048 else { throw MusicImportError.malformedHeaders }
            let canonical = ["user-agent": "User-Agent", "referer": "Referer",
                             "origin": "Origin", "accept": "Accept"][key.lowercased()]!
            result[canonical] = value
        }
        return result
    }

    static func remotePlaylist(url: URL, headers: [String: String] = [:]) async throws -> [MediaHubLibraryItem] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 20
        for (key, value) in headers { request.setValue(value, forHTTPHeaderField: key) }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              data.count <= 2 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8) else {
            throw MusicImportError.emptyPlaylist
        }
        return try await importPlaylist(text: text, baseURL: url.deletingLastPathComponent())
    }

    static func remote(title: String, urlString: String,
                       artist: String = "", album: String = "",
                       headers: [String: String] = [:]) throws -> MediaHubLibraryItem {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme), url.host != nil,
              url.user == nil, url.password == nil else { throw MusicImportError.invalidURL }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? titleFromURL(url) : cleanTitle
        guard !finalTitle.isEmpty else { throw MusicImportError.invalidURL }
        return MusicTrackDescriptor(title: finalTitle, artist: artist, album: album,
            urlString: trimmed, headers: headers).libraryItem()
    }

    /// Imports one local audio file or one local M3U/M3U8 playlist. Files are copied into
    /// app-owned storage so playback does not depend on a stale security-scoped URL.
    static func localFile(_ url: URL) async throws -> [MediaHubLibraryItem] {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let ext = url.pathExtension.lowercased()
        if ["m3u", "m3u8"].contains(ext) {
            let data = try Data(contentsOf: url)
            let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) ?? ""
            return try await importPlaylist(text: text, baseURL: url.deletingLastPathComponent())
        }
        guard ["mp3", "m4a", "m4b", "aac", "flac", "wav", "caf", "aiff", "aif"].contains(ext) else {
            throw MusicImportError.unsupportedFile
        }
        let copied = try copyToMusicStorage(url)
        return [MusicTrackDescriptor(title: titleFromURL(url), artist: "", album: "",
            urlString: "local:" + copied.lastPathComponent, headers: [:]).libraryItem()]
    }

    static func importPlaylist(text: String, baseURL: URL? = nil) async throws -> [MediaHubLibraryItem] {
        var result: [MediaHubLibraryItem] = []
        var pendingTitle: String?
        var pendingArtist = ""
        var headers: [String: String] = [:]
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if line.uppercased().hasPrefix("#EXTINF:") {
                let value = String(line.dropFirst("#EXTINF:".count))
                let parts = value.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
                if parts.count == 2 {
                    let label = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
                    let artistTitle = label.split(separator: " - ", maxSplits: 1).map(String.init)
                    if artistTitle.count == 2 { pendingArtist = artistTitle[0]; pendingTitle = artistTitle[1] }
                    else { pendingTitle = label }
                }
                continue
            }
            if line.uppercased().hasPrefix("#EXTVLCOPT:HTTP-REFERRER=") {
                headers["Referer"] = String(line.split(separator: "=", maxSplits: 1)[1])
                continue
            }
            if line.uppercased().hasPrefix("#EXTVLCOPT:HTTP-USER-AGENT=") {
                headers["User-Agent"] = String(line.split(separator: "=", maxSplits: 1)[1])
                continue
            }
            if line.hasPrefix("#") { continue }
            let target: URL
            if let parsed = URL(string: line), parsed.scheme != nil { target = parsed }
            else if let baseURL, let resolved = URL(string: line, relativeTo: baseURL)?.standardizedFileURL { target = resolved }
            else { continue }
            if target.isFileURL {
                let copied = try copyToMusicStorage(target)
                result.append(MusicTrackDescriptor(title: pendingTitle ?? titleFromURL(target),
                    artist: pendingArtist, album: "", urlString: "local:" + copied.lastPathComponent,
                    headers: [:]).libraryItem())
            } else if let scheme = target.scheme?.lowercased(), ["http", "https"].contains(scheme), target.host != nil {
                let item = try remote(title: pendingTitle ?? titleFromURL(target), urlString: target.absoluteString,
                    artist: pendingArtist, headers: headers)
                result.append(item)
            }
            pendingTitle = nil; pendingArtist = ""; headers = [:]
        }
        guard !result.isEmpty else { throw MusicImportError.emptyPlaylist }
        return result
    }

    private static func copyToMusicStorage(_ source: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: MusicStorage.directory, withIntermediateDirectories: true)
        let ext = source.pathExtension.isEmpty ? "audio" : source.pathExtension.lowercased()
        let destination = MusicStorage.directory.appendingPathComponent(UUID().uuidString + "." + ext)
        do { try fm.copyItem(at: source, to: destination) }
        catch { throw MusicImportError.cannotCopy(error.localizedDescription) }
        return destination
    }

    private static func titleFromURL(_ url: URL) -> String {
        let raw = url.deletingPathExtension().lastPathComponent
        let value = raw.removingPercentEncoding ?? raw
        return value.isEmpty ? localized("未命名音讯") : value
    }
}
