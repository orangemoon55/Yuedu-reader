import Combine
import Foundation

/// A separate local registry; never changes JSON modules, CatVod bundles, or music JS sources.
/// Writes the complete bounded archive atomically BEFORE publishing an update.
@MainActor
final class ModuleMediaImportStore: ObservableObject {
    static let shared = ModuleMediaImportStore()
    static let archiveByteLimit = 24 * 1024 * 1024
    static let subtitleFileLimit = 50

    struct Archive: Codable, Equatable {
        var version = 1
        var danmaku: [ModuleRegisteredMediaSource] = []
        var subtitle: [ModuleRegisteredMediaSource] = []
        var files: [ModuleLocalSubtitle] = []
    }

    @Published private(set) var archive = Archive()
    @Published private(set) var loadFailure: String?
    @Published private(set) var isLoaded = false
    let directory: URL
    private var archiveURL: URL { directory.appendingPathComponent("registry-v1.json") }

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ModuleMediaImports", isDirectory: true)
    }

    func loadIfNeeded() {
        guard !isLoaded else { return }
        defer { isLoaded = true }
        guard FileManager.default.fileExists(atPath: archiveURL.path) else { return }
        do {
            let data = try Self.readBounded(archiveURL, limit: Self.archiveByteLimit)
            let value = try JSONDecoder().decode(Archive.self, from: data)
            try validate(value)
            archive = value
        } catch {
            // Do not silently replace a corrupt/unknown-version archive on the next import.
            loadFailure = "無法讀取已保存的媒體匯入資料；原檔已保留，暫停寫入。\n" + error.localizedDescription
        }
    }

    func sources(_ kind: ModuleMediaRegistryKind) -> [ModuleRegisteredMediaSource] {
        kind == .danmaku ? archive.danmaku : archive.subtitle
    }

    @discardableResult
    func importRegistry(_ data: Data, kind: ModuleMediaRegistryKind) throws -> Int {
        loadIfNeeded()
        let incoming = try ModuleMediaImportParser.registry(data, kind: kind)
        var next = archive
        var sources = sources(kind)
        for source in incoming {
            if let index = sources.firstIndex(where: { $0.id == source.id }) { sources[index] = source }
            else { sources.append(source) }
        }
        if kind == .danmaku { next.danmaku = sources } else { next.subtitle = sources }
        try save(next)
        return incoming.count
    }

    @discardableResult
    func importSubtitle(_ data: Data, filename: String) throws -> ModuleLocalSubtitle {
        loadIfNeeded()
        let file = try ModuleMediaImportParser.subtitle(data, filename: filename)
        var next = archive
        next.files.append(file)
        try save(next)
        return file
    }

    func removeSource(id: String, kind: ModuleMediaRegistryKind) throws {
        loadIfNeeded()
        var next = archive
        if kind == .danmaku { next.danmaku.removeAll { $0.id == id } }
        else { next.subtitle.removeAll { $0.id == id } }
        try save(next)
    }

    func removeSubtitle(id: UUID) throws {
        loadIfNeeded()
        var next = archive
        next.files.removeAll { $0.id == id }
        try save(next)
    }

    private func save(_ next: Archive) throws {
        guard loadFailure == nil else { throw ModuleMediaImportError.invalid(loadFailure!) }
        try validate(next)
        let data = try JSONEncoder().encode(next)
        guard data.count <= Self.archiveByteLimit else { throw ModuleMediaImportError.invalid("本機匯入資料總量超過 24 MB，請先移除不需要的字幕。") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: archiveURL, options: .atomic)
        archive = next
    }

    private func validate(_ value: Archive) throws {
        guard value.version == 1 else { throw ModuleMediaImportError.invalid("不支援的媒體匯入資料版本。") }
        for list in [value.danmaku, value.subtitle] {
            guard list.count <= ModuleMediaImportParser.sourceLimit, Set(list.map(\.id)).count == list.count else {
                throw ModuleMediaImportError.invalid("每類最多保存 100 個來源，id 不可重複。")
            }
            for source in list { try ModuleMediaImportParser.validate(source) }
        }
        guard value.files.count <= Self.subtitleFileLimit, Set(value.files.map(\.id)).count == value.files.count else {
            throw ModuleMediaImportError.invalid("最多保存 50 份本地字幕。")
        }
        for file in value.files {
            guard file.filename.count <= 255, ["srt", "vtt"].contains((file.filename as NSString).pathExtension.lowercased()),
                  !file.cues.isEmpty, file.cues.count <= ModuleMediaImportParser.cueLimit else {
                throw ModuleMediaImportError.invalid("保存的字幕資料無效。")
            }
            for cue in file.cues {
                guard cue.start.isFinite, cue.end.isFinite, cue.start >= 0, cue.end > cue.start,
                      cue.end <= 7 * 24 * 3600, !cue.text.isEmpty,
                      cue.text.utf8.count <= ModuleMediaImportParser.cueTextLimit else {
                    throw ModuleMediaImportError.invalid("保存的字幕時間軸無效。")
                }
            }
        }
    }

    /// A limited read, including provider-backed files. Never loads an unbounded file first.
    static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var data = Data()
        while data.count <= limit {
            let chunk = try handle.read(upToCount: min(64 * 1024, limit + 1 - data.count)) ?? Data()
            if chunk.isEmpty { break }
            data.append(chunk)
        }
        guard data.count <= limit else { throw ModuleMediaImportError.invalid("匯入檔案超過大小限制。") }
        return data
    }
}
