import Foundation
import XCTest
@testable import DeckHarness

final class HTTPCacheObservationTests: XCTestCase {
    private func response(_ status: Int = 200, _ headers: [String: String]) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://fixture.invalid/audio")!, statusCode: status,
                        httpVersion: "HTTP/1.1", headerFields: headers)!
    }

    func testRangesMapOriginalBytesAndRejectMalformedBodies() throws {
        var range = try XCTUnwrap(HTTPAudioDataRange(response: response(206,
            ["Content-Range": "bytes 50-59/100", "Content-Length": "10", "Content-Type": "audio/mp4"])))
        XCTAssertEqual(range.consume(Data(repeating: 1, count: 4))?.offset, 50)
        let next = try XCTUnwrap(range.consume(Data(repeating: 2, count: 6)))
        XCTAssertEqual(next.offset, 54)
        XCTAssertEqual(next.totalLength, 100)
        XCTAssertNil(range.consume(Data([0])))
        for header in ["bytes -1-4/10", "bytes 5-4/10", "bytes 0-10/10", "bytes 0-4/*"] {
            XCTAssertNil(HTTPAudioDataRange(response: response(206, ["Content-Range": header])))
        }
        XCTAssertNil(HTTPAudioDataRange(response: response(200, ["Content-Length": "10", "Content-Encoding": "gzip"])))
        XCTAssertNil(HTTPAudioDataRange(response: response(403, ["Content-Length": "10"])))
        var oversized = try XCTUnwrap(HTTPAudioDataRange(response: response(200, ["Content-Length": "5"])))
        XCTAssertNil(oversized.consume(Data(repeating: 0, count: 6)))
        XCTAssertNil(oversized.consume(Data([0])), "A malformed body cannot resume at a false offset")
    }

    func testStreamObserverUsesTheSameSingleRequest() async throws {
        let state = ObservationState()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CacheFixtureProtocol.self]
        let client = NetworkingClient(configuration: config, httpDataSink: { state.add($0) })
        let finished = expectation(description: "stream complete")
        let stream = client.stream(request: URLRequest(url: URL(string: "https://fixture.invalid/full")!))
            .responseStream { event in
                if case .complete = event { finished.fulfill() }
            }.resume()
        await fulfillment(of: [finished], timeout: 3)
        withExtendedLifetime(stream) {}
        let chunks = state.chunks
        XCTAssertEqual(chunks.reduce(Data()) { $0 + $1.data }, Data(0..<32))
        XCTAssertEqual(chunks.first?.offset, 0)
        XCTAssertTrue(chunks.allSatisfy { $0.totalLength == 32 })
        XCTAssertEqual(CacheFixtureProtocol.count(for: "/full"), 1)
    }

    func testMP4AtomFetchAlsoObservesOriginalOffsetsWithoutAnotherRequest() async throws {
        let state = ObservationState()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [CacheFixtureProtocol.self]
        let client = NetworkingClient(configuration: config, httpDataSink: { state.add($0) })
        let finished = expectation(description: "atom fetch complete")
        let task = client.task(request: URLRequest(url: URL(string: "https://fixture.invalid/atom")!)) { result in
            XCTAssertEqual(try? result.get(), Data(0..<32))
            finished.fulfill()
        }
        await fulfillment(of: [finished], timeout: 3)
        withExtendedLifetime(task) {}
        XCTAssertEqual(state.chunks.first?.offset, 100)
        XCTAssertEqual(state.chunks.first?.totalLength, 132)
        XCTAssertEqual(state.chunks.first?.data, Data(0..<32))
        XCTAssertEqual(CacheFixtureProtocol.count(for: "/atom"), 1)
    }
}

private final class ObservationState: @unchecked Sendable {
    private let lock = NSLock()
    private var values: [HTTPAudioDataChunk] = []
    var chunks: [HTTPAudioDataChunk] { lock.lock(); defer { lock.unlock() }; return values }
    func add(_ chunk: HTTPAudioDataChunk) { lock.lock(); defer { lock.unlock() }; values.append(chunk) }
}

private final class CacheFixtureProtocol: URLProtocol, @unchecked Sendable {
    private static let lock = NSLock()
    private static var counts: [String: Int] = [:]
    static func count(for path: String) -> Int { lock.lock(); defer { lock.unlock() }; return counts[path, default: 0] }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "fixture.invalid" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let path = request.url!.path
        Self.lock.lock()
        Self.counts[path, default: 0] += 1
        Self.lock.unlock()
        var headers = ["Content-Length": "32", "Content-Type": "audio/mp4"]
        if path == "/atom" { headers["Content-Range"] = "bytes 100-131/132" }
        let response = HTTPURLResponse(url: request.url!, statusCode: path == "/atom" ? 206 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(0..<16))
        client?.urlProtocol(self, didLoad: Data(16..<32))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
