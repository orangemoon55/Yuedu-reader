import Foundation
import Combine

/// A saved music track. Keep this record free of runtime ports and credentials.
/// The legacy `videoID` storage key is retained so existing music bookmarks stay readable.
struct MediaHubLibraryItem: Codable, Hashable, Identifiable, Sendable {
    let sourceID: String
    let siteKey: String
    let videoID: String
    var title: String
    var poster: String
    let kind: MediaHubKind
    var siteName: String
    // Optional source facts keep pre-existing library.json records decodable.
    var categoryName: String?
    var year: String?
    var area: String?
    var remarks: String?
    /// A user-authorized playable URL or an app-owned copied local file URL.
    var musicURL: String?
    /// Request headers supplied by the user in an imported playlist. Never logged.
    var musicHeaders: [String: String]?
    /// Requested source-declared quality only, not a measured bitrate or lossless guarantee.
    var musicQuality: String? = nil

    private enum CodingKeys: String, CodingKey {
        case sourceID, siteKey, videoID, title, poster, kind, siteName
        case categoryName, year, area, remarks, musicURL, musicHeaders, musicQuality
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceID = try container.decode(String.self, forKey: .sourceID)
        siteKey = try container.decode(String.self, forKey: .siteKey)
        videoID = try container.decode(String.self, forKey: .videoID)
        title = try container.decode(String.self, forKey: .title)
        poster = try container.decode(String.self, forKey: .poster)
        kind = try container.decode(MediaHubKind.self, forKey: .kind)
        siteName = try container.decode(String.self, forKey: .siteName)
        categoryName = try container.decodeIfPresent(String.self, forKey: .categoryName)
        year = try container.decodeIfPresent(String.self, forKey: .year)
        area = try container.decodeIfPresent(String.self, forKey: .area)
        remarks = try container.decodeIfPresent(String.self, forKey: .remarks)
        musicURL = try container.decodeIfPresent(String.self, forKey: .musicURL)
        musicHeaders = try container.decodeIfPresent([String: String].self, forKey: .musicHeaders)
        musicQuality = try container.decodeIfPresent(String.self, forKey: .musicQuality)
    }
    var id: String {
        [sourceID, siteKey, videoID]
            .map { Data($0.utf8).base64EncodedString() }
            .joined(separator: ".")
    }

    init(sourceID: String, siteKey: String, videoID: String, title: String,
         poster: String, kind: MediaHubKind, siteName: String,
         categoryName: String? = nil, year: String? = nil,
         area: String? = nil, remarks: String? = nil,
         musicURL: String? = nil, musicHeaders: [String: String]? = nil) {
        self.sourceID = sourceID
        self.siteKey = siteKey
        self.videoID = videoID
        self.title = title
        self.poster = Self.persistablePoster(poster)
        self.kind = kind
        self.siteName = siteName
        self.categoryName = categoryName
        self.year = year
        self.area = area
        self.remarks = remarks
        self.musicURL = musicURL
        self.musicHeaders = musicHeaders
    }

    /// Keep source-relative artwork/public HTTP(S) artwork, not a runtime proxy or bearer URL.
    /// Playback is intentionally not recorded here: bookmarks are not watch history.
    static func persistablePoster(_ raw: String) -> String {
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !value.contains("\r"), !value.contains("\n"),
              let components = URLComponents(string: value),
              components.user == nil, components.password == nil else { return "" }
        if let scheme = components.scheme?.lowercased(), !["http", "https"].contains(scheme) { return "" }
        let host = (components.host ?? "").lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        if host == "localhost" || host.hasSuffix(".localhost") || host == "::1"
            || host == "0.0.0.0" || host.hasPrefix("127.") { return "" }
        let secretKeys = ["token", "authorization", "auth", "cookie", "password", "secret", "signature", "sign", "api_key", "apikey", "key"]
        if components.queryItems?.contains(where: { item in
            let key = item.name.lowercased()
            return secretKeys.contains { key == $0 || key.hasSuffix("_" + $0) || key.hasSuffix("-" + $0) }
        }) == true { return "" }
        return value
    }
}

enum MediaHubLibraryError: LocalizedError {
    case invalidItem
    case persistence(String)

    var errorDescription: String? {
        switch self {
        case .invalidItem: return localized("无法保存：内容识别资讯不完整。")
        case .persistence(let reason): return String(format: localized("媒体库保存失败：%@"), reason)
        }
    }
}

/// JSON-backed library for independent media discovery. Writes are atomic and idempotent.
@MainActor
final class MediaHubLibrary: ObservableObject {
    static let shared = MediaHubLibrary()

    @Published private(set) var items: [MediaHubLibraryItem] = []
    @Published private(set) var loadFailure: String?

    private let fileURL: URL

    static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("MediaHub", isDirectory: true)
            .appendingPathComponent("library.json", isDirectory: false)
    }

    init(fileURL: URL = MediaHubLibrary.defaultFileURL) {
        self.fileURL = fileURL
        reload()
    }

    func reload() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            items = []
            loadFailure = nil
            return
        }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoded = try Self.decodeMusicRecords(data)
            var seen = Set<String>()
            items = decoded.filter { seen.insert($0.id).inserted }.map { item in
                var safe = item
                safe.poster = MediaHubLibraryItem.persistablePoster(item.poster)
                return safe
            }
            loadFailure = nil
        } catch {
            // Preserve the original file until an explicit successful save/remove.
            items = []
            loadFailure = error.localizedDescription
        }
    }

    /// Read music out of the legacy mixed archive without changing the archive on disk.
    /// Unsupported historical records do not stop valid music from loading.
    static func decodeMusicRecords(_ data: Data) throws -> [MediaHubLibraryItem] {
        try JSONDecoder().decode([StoredMusicRecord].self, from: data).compactMap(\.item)
    }

    private struct StoredMusicRecord: Decodable {
        private enum Key: String, CodingKey { case kind }
        let item: MediaHubLibraryItem?

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            let kind = try container.decode(String.self, forKey: .kind)
            item = kind == MediaHubKind.music.rawValue ? try MediaHubLibraryItem(from: decoder) : nil
        }
    }

    /// Add or update the exact identity without creating duplicates.
    func save(_ item: MediaHubLibraryItem) throws {
        guard !item.sourceID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.siteKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.videoID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MediaHubLibraryError.invalidItem
        }
        var safe = item
        safe.poster = MediaHubLibraryItem.persistablePoster(item.poster)
        var next = items
        if let index = next.firstIndex(where: { $0.id == item.id }) {
            let existing = next[index]
            safe.categoryName = item.categoryName ?? existing.categoryName
            safe.year = item.year ?? existing.year
            safe.area = item.area ?? existing.area
            safe.remarks = item.remarks ?? existing.remarks
            next[index] = safe
        } else {
            next.insert(safe, at: 0)
        }
        try persist(next)
    }

    func remove(_ item: MediaHubLibraryItem) throws {
        try remove(id: item.id)
    }

    func remove(id: String) throws {
        let next = items.filter { $0.id != id }
        guard next.count != items.count else { return }
        try persist(next)
    }

    func contains(sourceID: String, siteKey: String, videoID: String) -> Bool {
        items.contains { $0.sourceID == sourceID && $0.siteKey == siteKey && $0.videoID == videoID }
    }

    private func persist(_ value: [MediaHubLibraryItem]) throws {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            let data = try encoder.encode(value)
            try data.write(to: fileURL, options: .atomic)
            items = value
            loadFailure = nil
        } catch {
            throw MediaHubLibraryError.persistence(error.localizedDescription)
        }
    }
}
