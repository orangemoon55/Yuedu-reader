import Foundation
import Testing
@testable import yuedu_app

/// MD5 源 (CatVod JS bundles): address pairing, checksum, and the store that keeps them apart
/// from JSON 模組.
@MainActor
@Suite("MD5 source import", .serialized)
struct Md5SourceTests {
    @Test("a .js.md5 address pairs the bundle with its checksum")
    func jsMd5Address() throws {
        let targets = try #require(Md5SourceImportModel.targets(for: "https://host/cat/index.js.md5"))
        #expect(targets.bundle.absoluteString == "https://host/cat/index.js")
        #expect(targets.checksum?.absoluteString == "https://host/cat/index.js.md5")
    }

    @Test("a .js address looks for a checksum beside it")
    func jsAddress() throws {
        let targets = try #require(Md5SourceImportModel.targets(for: "https://host/cat/index.js"))
        #expect(targets.bundle.absoluteString == "https://host/cat/index.js")
        #expect(targets.checksum?.absoluteString == "https://host/cat/index.js.md5")
    }

    @Test("other file names are refused")
    func otherNamesRefused() {
        #expect(Md5SourceImportModel.targets(for: "https://host/config.json") == nil)
        #expect(Md5SourceImportModel.targets(for: "file:///tmp/index.js.md5") == nil)
    }

    @Test("MD5 and SHA-256 are lowercase hex")
    func digests() {
        #expect(Md5SourceImportModel.md5(of: Data("hello".utf8)) == "5d41402abc4b2a76b9719d911017c592")
        let sha = Md5SourceImportModel.sha256(of: Data("hello".utf8))
        #expect(sha.count == 64)
        #expect(sha == sha.lowercased())
    }

    @Test("installing writes bundle and record, listing reads them, removing deletes the folder")
    func storeRoundTrip() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("md5-source-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = Md5SourceStore(directory: root)
        let bundle = Data("// fixture bundle".utf8)
        let source = Md5Source(id: Md5SourceImportModel.sha256(of: bundle), title: "Fixture",
                               address: "https://host/index.js.md5", bundleAddress: "https://host/index.js",
                               checksum: Md5SourceImportModel.md5(of: bundle), byteCount: bundle.count,
                               importedAt: .now)
        _ = try store.install(bundle: bundle, source: source)
        let listing = store.list()
        #expect(listing.sources.map(\.id) == [source.id])
        #expect(listing.failures.isEmpty)
        #expect(try Data(contentsOf: store.bundleURL(for: source.id)) == bundle)
        #expect(throws: Md5SourceError.alreadyInstalled(source.id)) {
            _ = try store.install(bundle: bundle, source: source)
        }
        try store.remove(source)
        #expect(store.list().sources.isEmpty)
    }

    @Test("a folder without its bundle is reported, not listed")
    func brokenFolderReported() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("md5-source-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("broken", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let store = Md5SourceStore(directory: root)
        let listing = store.list()
        #expect(listing.sources.isEmpty)
        #expect(listing.failures == ["broken"])
    }
}
