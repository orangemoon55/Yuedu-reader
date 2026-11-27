import Foundation
import XCTest
@testable import DeckHarness

final class StreamCacheTests: XCTestCase {
    func testOverlappingAndOutOfOrderPlaybackRangesProduceTheOriginalFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let done = expectation(description: "complete cache")
        let file = try StreamingAudioCacheFile(fileURL: url, maximumBytes: 32) { result in
            XCTAssertEqual(try? result.get().byteCount, 16)
            done.fulfill()
        }
        let bytes = Data(0..<16)
        for range in [8..<16, 4..<12, 0..<8] {
            file.receive(HTTPAudioDataChunk(data: bytes.subdata(in: range), offset: Int64(range.lowerBound),
                                           totalLength: 16, contentType: "audio/flac", validator: "same"))
        }
        await fulfillment(of: [done], timeout: 2)
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        file.cancel()
    }

    func testAnIncompleteSeekedFileIsDiscardedOnCancellation() async throws {
        try await rejected(chunks: [.init(data: Data([8, 9]), offset: 8, totalLength: 16)], maximum: 32)
    }

    func testFileExceedingTheLimitIsRejected() async throws {
        try await rejected(chunks: [.init(data: Data([0]), offset: 0, totalLength: 100)], maximum: 32)
    }

    func testChangedRepresentationsAreNotCombined() async throws {
        try await rejected(chunks: [
            .init(data: Data([0, 1]), offset: 0, totalLength: 4, validator: "a"),
            .init(data: Data([2, 3]), offset: 2, totalLength: 4, validator: "b")
        ], maximum: 32)
    }

    func testInvalidOffsetsCannotCreateACompleteCache() async throws {
        try await rejected(chunks: [.init(data: Data([0, 1]), offset: -1, totalLength: 2)], maximum: 32)
    }

    private func rejected(chunks: [HTTPAudioDataChunk], maximum: Int64) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        FileManager.default.createFile(atPath: url.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: url) }
        let done = expectation(description: "rejected cache")
        let file = try StreamingAudioCacheFile(fileURL: url, maximumBytes: maximum) { result in
            if case .success = result { XCTFail("A partial or invalid stream must never be promoted") }
            done.fulfill()
        }
        chunks.forEach { file.receive($0) }
        file.cancel()
        await fulfillment(of: [done], timeout: 2)
    }
}
