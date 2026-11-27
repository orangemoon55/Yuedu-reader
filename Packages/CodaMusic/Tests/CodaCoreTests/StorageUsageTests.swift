import Foundation
import Testing
@testable import CodaCore

@Suite("Storage accounting")
struct StorageUsageTests {
    private func root() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("coda-storage-\(UUID())") }

    private func addDownload(_ store: OfflineStore, id: Int, scope: String = "account-a") async throws -> OfflineAudioDescriptor {
        let fixture = try OfflineAudioFixture()
        let identity = OfflineAudioIdentity(accountScope: scope, trackID: id, source: "netease", quality: "exhigh", format: .mp3,
                                            contentMD5: fixture.descriptor.identity.contentMD5)
        let descriptor = OfflineAudioDescriptor(identity: identity, byteCount: fixture.descriptor.byteCount, duration: 3)
        try await store.importFixture(fixture.data, descriptor: descriptor)
        try await store.retain(id: identity.id, owner: "download:\(id)")
        return descriptor
    }

    private func size(_ url: URL) throws -> Int64 {
        let info = try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey])
        return Int64(info.totalFileAllocatedSize ?? info.fileAllocatedSize ?? info.fileSize ?? 0)
    }

    @Test func storageBarUsesOneCapacityAndClampsInvalidInputs() {
        let capacity = DeviceStorageCapacity(total: 100, available: 20)
        #expect(capacity.fractions(appBytes: 10) == [0.1, 0.7, 0.2])
        #expect(capacity.fractions(appBytes: 200) == [0.8, 0, 0.2])
        #expect(DeviceStorageCapacity(total: 100, available: 200).fractions(appBytes: 50) == [0, 0, 1])
        #expect(DeviceStorageCapacity(total: 0, available: 0).fractions(appBytes: 1) == [0, 0, 1])
        #expect(DeviceStorageCapacity(total: 100, available: -10).fractions(appBytes: 25) == [0.25, 0.75, 0])
    }

    @Test func separatesStorageWithoutCountingOverlappingRootsOrSymlinks() async throws {
        let base = root()
        defer { try? FileManager.default.removeItem(at: base) }
        let support = base.appendingPathComponent("support")
        let images = support.appendingPathComponent("images")
        let musicCache = support.appendingPathComponent("audio-cache")
        let bundle = base.appendingPathComponent("app")
        for directory in [images, musicCache, bundle] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let image = images.appendingPathComponent("image")
        try Data(repeating: 1, count: 5_000).write(to: image)
        let cached = musicCache.appendingPathComponent("song.mp3")
        try Data(repeating: 4, count: 6_000).write(to: cached)
        try Data(repeating: 2, count: 8_000).write(to: bundle.appendingPathComponent("binary"))
        let outside = base.appendingPathComponent("outside")
        try Data(repeating: 3, count: 100_000).write(to: outside)
        try FileManager.default.createSymbolicLink(at: images.appendingPathComponent("linked-file"), withDestinationURL: outside)
        let store = OfflineStore(directory: support.appendingPathComponent("Offline"), minimumFreeBytes: 0)
        let mine = try await addDownload(store, id: 1)
        let theirs = try await addDownload(store, id: 2, scope: "account-b")
        let files = try await store.storageFiles()
        let mineURL = try #require(files.first { $0.url.lastPathComponent.hasPrefix(mine.identity.id) && $0.url.path.contains("/audio/") }?.url)
        let theirsURL = try #require(files.first { $0.url.lastPathComponent.hasPrefix(theirs.identity.id) && $0.url.path.contains("/audio/") }?.url)
        let reader = StorageUsageReader(roots: [support, images, bundle, support], imageDirectory: images, musicCacheDirectories: [musicCache],
                                        downloadDirectory: store.directory.appendingPathComponent("downloads"), volumeURL: support)
        let usage = await reader.read(audioFiles: files, accountScope: "account-a")
        #expect(usage[.imageCache] == (try size(image)))
        #expect(usage[.musicCache] == (try size(cached)))
        #expect(usage[.downloads] == (try size(mineURL) + size(theirsURL)))
        #expect(usage.otherAccountDownloads == (try size(theirsURL)))
        #expect(!usage.partial)
        let simple = StorageUsageReader(roots: [support, bundle], imageDirectory: images, musicCacheDirectories: [musicCache],
                                        downloadDirectory: store.directory.appendingPathComponent("downloads"), volumeURL: support)
        let withoutOverlap = await simple.read(audioFiles: files, accountScope: "account-a")
        #expect(usage.bytes == withoutOverlap.bytes)
    }

    @Test func appDataIsBrokenDownByLocation() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let support = base.appendingPathComponent("support")
        let taps = support.appendingPathComponent("taps")
        try FileManager.default.createDirectory(at: taps, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 3_000).write(to: taps.appendingPathComponent("a.caf"))
        try Data(repeating: 2, count: 2_000).write(to: support.appendingPathComponent("cookies.json"))
        try Data(repeating: 3, count: 1_000).write(to: support.appendingPathComponent("player-state.json"))
        let reader = StorageUsageReader(roots: [support], imageDirectory: base.appendingPathComponent("images"),
                                        musicCacheDirectories: [], downloadDirectory: base.appendingPathComponent("downloads"),
                                        volumeURL: support,
                                        appDataLocations: [.init(kind: .diagnostics, url: taps),
                                                           .init(kind: .account, url: support.appendingPathComponent("cookies.json"))])
        let usage = await reader.read(audioFiles: [], accountScope: nil)
        #expect(usage.appData[.diagnostics] ?? 0 >= 3_000)
        #expect(usage.appData[.account] ?? 0 >= 2_000)
        #expect(usage.appData[.other] ?? 0 > 0)
        #expect(usage.appData.values.reduce(0, +) == usage[.appData])
    }

    @Test func clearingKeepsRecentFilesAndSparedFolders() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: base) }
        let spared = base.appendingPathComponent("spared")
        let nested = base.appendingPathComponent("nested")
        for directory in [spared, nested] { try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
        let old = base.appendingPathComponent("old.tmp"), fresh = base.appendingPathComponent("fresh.tmp")
        let oldNested = nested.appendingPathComponent("old"), keep = spared.appendingPathComponent("song.m4a")
        for file in [old, fresh, oldNested, keep] { try Data([1]).write(to: file) }
        let past = Date().addingTimeInterval(-3_600)
        for file in [old, oldNested, keep] { try FileManager.default.setAttributes([.modificationDate: past], ofItemAtPath: file.path) }
        let failed = StorageSpaceModel.remove([base], keepingModifiedAfter: Date().addingTimeInterval(-600), sparing: [spared])
        #expect(!failed)
        #expect(!FileManager.default.fileExists(atPath: old.path))
        #expect(!FileManager.default.fileExists(atPath: nested.path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
        #expect(FileManager.default.fileExists(atPath: keep.path))
        #expect(FileManager.default.fileExists(atPath: base.path))
    }
}
