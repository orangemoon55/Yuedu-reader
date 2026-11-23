import Foundation
import CryptoKit
import Combine

/// One imported MD5 source: a CatVod-style JS bundle plus the checksum its `.js.md5` companion
/// publishes. It is NOT a rule module (JSON): the two are listed apart in 模組, and nothing here
/// is decoded as `RuleModule`.
struct Md5Source: Codable, Identifiable, Hashable, Sendable {
    /// SHA-256 of the bundle bytes: the folder, and what makes two imports of one file one source.
    let id: String
    var title: String
    /// The address the reader typed, e.g. `https://host/cat/index.js.md5`.
    let address: String
    /// Where the bundle itself was read (`address` without its `.md5`).
    let bundleAddress: String
    /// The 32 hex characters the `.md5` companion returned, lowercase; empty when none was offered.
    let checksum: String
    let byteCount: Int
    let importedAt: Date

    var host: String {
        URL(string: bundleAddress)?.host ?? bundleAddress
    }

    var isChecksumVerified: Bool { !checksum.isEmpty }
}

enum Md5SourceError: Error, Equatable, Sendable {
    case emptyAddress
    case unsupportedAddress
    case download(String)
    case tooLarge(Int)
    case checksumMismatch(expected: String, actual: String)
    case alreadyInstalled(String)
    case notInstalled(String)
    case write(String)

    var message: String {
        switch self {
        case .emptyAddress: localized("請先輸入 MD5 源網址。")
        case .unsupportedAddress: localized("只支援 http 或 https 的 .js.md5 網址。")
        case .download(let reason): localized("無法下載 MD5 源：\(reason)")
        case .tooLarge(let bytes): localized("MD5 源太大（\(bytes) 位元組），上限 64 MB。")
        case .checksumMismatch(let expected, let actual):
            localized("MD5 校驗不符：.md5 為 \(expected)，下載檔案為 \(actual)。")
        case .alreadyInstalled(let id): localized("這個 MD5 源已經加入（\(String(id.prefix(12)))。")
        case .notInstalled(let id): localized("找不到 MD5 源 \(id)。")
        case .write(let reason): localized("無法寫入 MD5 源：\(reason)")
        }
    }
}

/// `Application Support/Md5Sources/<sha256>/` holds `bundle.js`, `source.json` and the runtime's
/// own state folder. Each call reads the disk; removing a source deletes its folder.
struct Md5SourceStore: Sendable {
    let directory: URL

    static var defaultDirectory: URL {
        URL.applicationSupportDirectory.appendingPathComponent("Md5Sources", isDirectory: true)
    }

    init(directory: URL = Md5SourceStore.defaultDirectory) {
        self.directory = directory
    }

    struct Listing: Sendable {
        var sources: [Md5Source]
        var failures: [String]
    }

    func list() -> Listing {
        let manager = FileManager.default
        guard let folders = try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return Listing(sources: [], failures: [])
        }
        var sources: [Md5Source] = []
        var failures: [String] = []
        for folder in folders where !folder.lastPathComponent.hasPrefix(".") {
            guard let data = try? Data(contentsOf: folder.appendingPathComponent("source.json")),
                  let source = try? JSONDecoder().decode(Md5Source.self, from: data),
                  manager.fileExists(atPath: bundleURL(for: source.id).path) else {
                failures.append(folder.lastPathComponent)
                continue
            }
            sources.append(source)
        }
        sources.sort { $0.importedAt < $1.importedAt }
        return Listing(sources: sources, failures: failures)
    }

    func folder(for id: String) -> URL { directory.appendingPathComponent(id, isDirectory: true) }

    func bundleURL(for id: String) -> URL { folder(for: id).appendingPathComponent("bundle.js") }

    func dataDirectory(for id: String) -> URL { folder(for: id).appendingPathComponent("state", isDirectory: true) }

    /// Adds a bundle whole or not at all: a staging folder is moved into place once every byte is
    /// written, so a crash cannot leave half a source.
    @discardableResult
    func install(bundle: Data, source: Md5Source) throws(Md5SourceError) -> Md5Source {
        let manager = FileManager.default
        let destination = folder(for: source.id)
        guard !manager.fileExists(atPath: destination.path) else { throw .alreadyInstalled(source.id) }
        let staging = directory.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        do {
            try manager.createDirectory(at: staging, withIntermediateDirectories: true)
            try bundle.write(to: staging.appendingPathComponent("bundle.js"), options: .atomic)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(source).write(to: staging.appendingPathComponent("source.json"), options: .atomic)
            try manager.createDirectory(at: staging.appendingPathComponent("state", isDirectory: true),
                                        withIntermediateDirectories: true)
            try manager.moveItem(at: staging, to: destination)
            return source
        } catch {
            try? manager.removeItem(at: staging)
            throw .write(error.localizedDescription)
        }
    }

    func remove(_ source: Md5Source) throws(Md5SourceError) {
        do {
            try FileManager.default.removeItem(at: folder(for: source.id))
        } catch {
            throw .write(error.localizedDescription)
        }
    }
}

/// The installed MD5 sources, as the UI sees them.
@MainActor
final class Md5SourceLibrary: ObservableObject {
    static let shared = Md5SourceLibrary()

    @Published private(set) var sources: [Md5Source] = []
    @Published private(set) var failures: [String] = []
    @Published private(set) var isLoaded = false

    private let store: Md5SourceStore

    init(store: Md5SourceStore = Md5SourceStore()) {
        self.store = store
    }

    func loadIfNeeded() {
        guard !isLoaded else { return }
        reload()
    }

    func reload() {
        let listing = store.list()
        sources = listing.sources
        failures = listing.failures
        isLoaded = true
    }

    func install(bundle: Data, source: Md5Source) throws {
        try store.install(bundle: bundle, source: source)
        reload()
    }

    func remove(_ source: Md5Source) throws {
        try store.remove(source)
        reload()
    }

    func bundleURL(for source: Md5Source) -> URL { store.bundleURL(for: source.id) }
    func dataDirectory(for source: Md5Source) -> URL { store.dataDirectory(for: source.id) }
}
