import Foundation
import Testing
@testable import CodaCore

struct AudioStreamCacheCommitTests {
    @Test func responseTypeSuppliesTheExtensionForAnOpaqueStreamURL() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AudioCache(cacheDirectory: directory)
        let session = try await cache.beginWrite(trackID: 123, requestedQuality: "lossless",
            servedQuality: "lossless", source: .netease, fileExtension: "audio", maximumSizeMB: 100)
        let bytes = Data(0..<32)
        try bytes.write(to: session.partialFileURL)
        let result = try await cache.commitAndRetain(session, byteCount: 32,
            contentType: "audio/flac", fileExtension: "flac")
        guard case let .retained(entry, lease) = result else {
            Issue.record("A complete stream should be retained")
            return
        }
        #expect(entry.fileURL.pathExtension == "flac")
        #expect(entry.metadata.fileName == entry.fileURL.lastPathComponent)
        #expect(try Data(contentsOf: entry.fileURL) == bytes)
        try await cache.release(lease)
        #expect(try await cache.entry(for: 123, requestedQuality: "lossless")?.fileURL == entry.fileURL)
    }

    @Test func clearingTheCacheDuringStreamingPreventsItsPromotion() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = AudioCache(cacheDirectory: directory)
        let session = try await cache.beginWrite(trackID: 123, requestedQuality: "exhigh",
            servedQuality: "exhigh", source: .netease, fileExtension: "audio", maximumSizeMB: 100)
        try Data(0..<32).write(to: session.partialFileURL)
        try await cache.clear()
        let result = try await cache.commitAndRetain(session, byteCount: 32,
            contentType: "audio/mp4", fileExtension: "m4a")
        guard case .deferredDiscard = result else {
            Issue.record("Cleared streams must not reappear as completed entries")
            return
        }
        try await cache.discard(session)
        #expect(try await cache.entry(for: 123, requestedQuality: "exhigh") == nil)
        #expect(!FileManager.default.fileExists(atPath: session.partialFileURL.path))
    }
}
