import Foundation

/// The chosen source configuration snapshot, not the stores that hold logins,
/// cookies or rule runtime state. Resolve the snapshot only when the menu row is tapped.
struct BookSourceExportRequest: Identifiable, Sendable {
    let id = UUID()
    let title: String
    let filename: String
    let sources: [BookSource]

    init(title: String, filenameLabel: String, sources: [BookSource]) {
        self.title = title
        self.filename = BookSourceExportFile.filename(for: filenameLabel)
        self.sources = sources
    }
}

/// Owns one real, atomically written JSON file. A unique parent directory preserves
/// the display filename without colliding with a second export of the same name.
final class BookSourceExportFile: Sendable {
    let url: URL
    private let directory: URL

    private init(url: URL, directory: URL) {
        self.url = url
        self.directory = directory
    }

    static func write(
        _ request: BookSourceExportRequest,
        in temporaryDirectory: URL = FileManager.default.temporaryDirectory
    ) throws -> BookSourceExportFile {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        let data = try encoder.encode(request.sources)
        let directory = temporaryDirectory.appendingPathComponent(
            "book-source-export-\(UUID().uuidString)", isDirectory: true)
        let url = directory.appendingPathComponent(request.filename, isDirectory: false)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        let file = BookSourceExportFile(url: url, directory: directory)
        // If the atomic write throws, `file` releases its directory on unwind.
        try data.write(to: url, options: .atomic)
        return file
    }

    // Called after the activity completes/cancels. deinit also handles failed presentation.
    func remove() { try? FileManager.default.removeItem(at: directory) }
    deinit { remove() }

    /// Imported group/source names can contain characters invalid in a filename.
    static func filename(for label: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|")
            .union(.newlines).union(.controlCharacters)
        let cleaned = label.components(separatedBy: invalid).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var base = ""
        for character in cleaned.prefix(60) {
            // 60 graphemes need not fit within the filesystem's component byte limit.
            guard base.utf8.count + String(character).utf8.count <= 240 else { break }
            base.append(character)
        }
        return "\(base.isEmpty ? "book-sources" : base).json"
    }
}
