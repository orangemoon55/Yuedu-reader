import AVFoundation
import CoreVideo
import Foundation
import Testing
@testable import yuedu_app

/// Real native network/decoder acceptance, offline and localhost only. Never uses user cookies.
@Suite("CatVod authenticated HTTP media", .serialized)
@MainActor
struct CatVodHTTPPlaybackTests {
    private func mediaData() throws -> Data {
        let file = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/VideoStill/video-still-landscape.mp4")
        return try Data(contentsOf: file)
    }

    private func server(_ bytes: Data) throws -> LoopbackPageServer {
        try LoopbackPageServer(request: { _, head in
            let lower = head.lowercased()
            let lines = lower.components(separatedBy: "\r\n")
            guard lines.contains("cookie: fixture_session=authorized"),
                  lines.contains("authorization: bearer synthetic-fixture-only") else {
                return .answer(status: 403, headers: [:], body: Data())
            }
            if let range = lower.components(separatedBy: "\r\n").first(where: { $0.hasPrefix("range: bytes=") }) {
                let parts = range.dropFirst("range: bytes=".count).split(separator: "-", omittingEmptySubsequences: false)
                if let start = parts.first.flatMap({ Int($0) }), start >= 0, start < bytes.count {
                    let requestedEnd = parts.count > 1 ? Int(parts[1]) : nil
                    let end = min(bytes.count - 1, max(start, requestedEnd ?? bytes.count - 1))
                    return .answer(status: 206, headers: ["Content-Type": "video/mp4", "Accept-Ranges": "bytes",
                        "Content-Range": "bytes \(start)-\(end)/\(bytes.count)"], body: bytes.subdata(in: start..<(end + 1)))
                }
                return .answer(status: 416, headers: ["Content-Range": "bytes */\(bytes.count)"], body: Data())
            }
            return .answer(status: 200, headers: ["Content-Type": "video/mp4", "Accept-Ranges": "bytes"], body: bytes)
        })
    }

    private func stream(_ url: URL) throws -> VideoStream {
        let payload: [String: Any] = ["parse": 0, "url": url.absoluteString,
            "header": ["User-Agent": "Readcc Offline Fixture", "Cookie": "fixture_session=authorized",
                       "Authorization": "Bearer synthetic-fixture-only", "Host": "discard.invalid",
                       "Referer": "https://fixture.invalid/", "X-Injected": "bad\r\nInjected: value"]]
        return try CatVodPlaybackFactory.stream(data: JSONSerialization.data(withJSONObject: payload),
            sourceID: "offline", siteKey: "protected", videoID: "fixture", flag: "http",
            episode: CatVodEpisode(id: "one", title: "Fixture", playID: "one")) { address in
                try #require(URL(string: address))
            }
    }

    @Test("factory retains source auth; HTTP 403 without it and 206 with it")
    func authenticatedHTTPTransport() async throws {
        let bytes = try mediaData(), fixture = try server(bytes)
        let base = try await fixture.start()
        defer { fixture.stop() }
        let url = base.appendingPathComponent("fixture.mp4"), resolved = try stream(url)
        #expect(resolved.headers["Cookie"] != nil && resolved.headers["Authorization"] != nil)
        #expect(resolved.headers["Host"] == nil && resolved.headers["X-Injected"] == nil)
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let (_, denied) = try await session.data(from: url)
        #expect((denied as? HTTPURLResponse)?.statusCode == 403)
        var request = URLRequest(url: url)
        for (key, value) in resolved.headers { request.setValue(value, forHTTPHeaderField: key) }
        request.setValue("bytes=0-15", forHTTPHeaderField: "Range")
        let (body, response) = try await session.data(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        #expect(body == bytes.prefix(16))
    }

    @Test("AVFoundation decodes and advances protected CatVod HTTP MP4")
    func protectedAVFoundationPlayback() async throws {
        let fixture = try server(mediaData())
        let base = try await fixture.start()
        defer { fixture.stop() }
        let controller = VideoPlaybackController(link: try stream(base.appendingPathComponent("fixture.mp4")),
            title: "Authorized offline fixture", prefersKSPlayer: false)
        defer { controller.close() }
        controller.start()
        let item = try #require(controller.player.currentItem)
        let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ])
        item.add(output)
        var decoded = false
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(100))
            if let pixel = output.copyPixelBuffer(forItemTime: controller.player.currentTime(), itemTimeForDisplay: nil) {
                decoded = CVPixelBufferGetWidth(pixel) > 0
            }
            if decoded && controller.currentTime > 0.2 { break }
        }
        #expect(item.status == .readyToPlay)
        #expect(controller.kernelName == "AVFoundation")
        #expect(controller.currentTime > 0.2)
        #expect(decoded, "A ready item alone is not proof of decoded video")
    }

    @Test("KS-first protected HTTP either advances or AV fallback decodes a real frame")
    func protectedKSPlayback() async throws {
        let bytes = try mediaData(), fixture = try server(bytes)
        let base = try await fixture.start()
        defer { fixture.stop() }
        let controller = VideoPlaybackController(link: try stream(base.appendingPathComponent("fixture.mp4")),
            title: "KS-first authorized HTTP fixture", prefersKSPlayer: true)
        defer { controller.close() }
        controller.start()
        var advanced = false
        for _ in 0..<200 {
            try await Task.sleep(for: .milliseconds(100))
            if controller.phase == .playing && controller.currentTime > 0.2 { advanced = true; break }
        }
        #expect(advanced, "Neither KSPlayer nor the authorized AV fallback advanced")
        if controller.kernelName == "AVFoundation" {
            // The production controller deliberately falls back when KS cannot open a
            // source-specific HTTP stream. Require a decoded frame, not only a ready item.
            let item = try #require(controller.player.currentItem)
            #expect(item.status == .readyToPlay)
            let output = AVPlayerItemVideoOutput(pixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ])
            item.add(output)
            var decoded = false
            for _ in 0..<50 {
                if let pixel = output.copyPixelBuffer(forItemTime: controller.player.currentTime(), itemTimeForDisplay: nil) {
                    decoded = CVPixelBufferGetWidth(pixel) > 0 && CVPixelBufferGetHeight(pixel) > 0
                }
                if decoded { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            #expect(decoded, "AV fallback did not decode the authenticated HTTP media frame")
        } else {
            #expect(controller.kernelName == "KSPlayer · FFmpeg")
            #expect(controller.phase == .playing && controller.currentTime > 0.2)
        }
    }
}
