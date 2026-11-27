import Foundation
import Testing
@testable import CodaCore

/// Qishui member audio is downloaded in full before it can play, so the
/// loader reads quality from the header instead of downloading every
/// candidate, and fetches large files in parallel parts.
@Suite("Qishui fast load")
struct QishuiFastLoadTests {
    private static func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        let size = UInt32(8 + payload.count)
        return withUnsafeBytes(of: size.bigEndian, Array.init) + Array(type.utf8) + payload
    }

    /// ftyp + moov with one protected sample entry (`enca` → `frma` original)
    /// carrying the given codec configuration, then the start of `mdat`.
    private static func header(original: String, config: [UInt8]) -> Data {
        let sinf = box("sinf", box("frma", Array(original.utf8)))
        let entryFields = [UInt8](repeating: 0, count: 28)
        let enca = box("enca", entryFields + sinf + config)
        let stsd = box("stsd", [0, 0, 0, 0, 0, 0, 0, 1] + enca)
        let stbl = box("stbl", stsd)
        let moov = box("moov", box("trak", box("mdia", box("minf", stbl))))
        let ftyp = box("ftyp", Array("M4A ".utf8) + [0, 0, 0, 0])
        return Data(ftyp + moov + [0, 0, 0x10, 0] + Array("mdat".utf8) + [1, 2, 3])
    }

    private static func dfLa(rate: UInt64, depth: UInt64) -> [UInt8] {
        let packed: UInt64 = (rate << 44) | (1 << 41) | ((depth - 1) << 36)
        var streamInfo = [UInt8](repeating: 0, count: 34)
        for index in 0..<8 {
            let shift = UInt64(56 - 8 * index)
            streamInfo[10 + index] = UInt8((packed >> shift) & 0xff)
        }
        let blockHeader: [UInt8] = [0x80, 0, 0, 34]
        let fullBox: [UInt8] = [0, 0, 0, 0]
        return box("dfLa", fullBox + blockHeader + streamInfo)
    }

    private static func alac(rate: UInt32, depth: UInt8) -> [UInt8] {
        var config = [UInt8](repeating: 0, count: 24)
        config[5] = depth
        config[20...23] = ArraySlice(withUnsafeBytes(of: rate.bigEndian, Array.init))
        return box("alac", [0, 0, 0, 0] + config)
    }

    @Test func headerTierReadsFLACAndALACConfigurations() {
        #expect(QishuiAudio.headerTier(Self.header(original: "fLaC", config: Self.dfLa(rate: 44_100, depth: 16))) == .lossless)
        #expect(QishuiAudio.headerTier(Self.header(original: "fLaC", config: Self.dfLa(rate: 96_000, depth: 24))) == .hires)
        #expect(QishuiAudio.headerTier(Self.header(original: "alac", config: Self.alac(rate: 44_100, depth: 16))) == .lossless)
        #expect(QishuiAudio.headerTier(Self.header(original: "alac", config: Self.alac(rate: 48_000, depth: 24))) == .hires)
        // Lossy or truncated headers do not claim a tier.
        #expect(QishuiAudio.headerTier(Self.header(original: "mp4a", config: [])) == nil)
        #expect(QishuiAudio.headerTier(Self.header(original: "fLaC", config: Self.dfLa(rate: 44_100, depth: 16)).prefix(40)) == nil)
    }

    @Test func aVerifiedLevelReplacesTheNamesPromise() {
        var stream = QishuiMusicAPI.PlaybackResource(url: "https://example.com/a", durationMS: 1, bitrate: nil, size: 1,
                                                     format: "flac", quality: "hi_res", playAuth: "x")
        #expect(stream.potentialRank == AudioQuality.allCases.firstIndex(of: .hires))
        stream.verifiedLevel = .lossless
        #expect(stream.potentialRank == AudioQuality.allCases.firstIndex(of: .lossless))
    }

    @Test func parallelDownloadReassemblesTheExactFile() async throws {
        var bytes = [UInt8](repeating: 0, count: QishuiMusicAPI.parallelDownloadThreshold + 123_457)
        var state: UInt32 = 7
        for index in bytes.indices { state = state &* 1_103_515_245 &+ 12_345; bytes[index] = UInt8(state >> 24) }
        let payload = Data(bytes)
        let server = try TestHTTPServer(serving: payload)
        defer { server.stop() }
        let file = try await QishuiMusicAPI.downloadMedia(server.url, expectedSize: payload.count,
                                                          session: URLSession(configuration: .ephemeral), agent: "test")
        defer { try? FileManager.default.removeItem(at: file) }
        #expect(try Data(contentsOf: file) == payload)
    }
}
