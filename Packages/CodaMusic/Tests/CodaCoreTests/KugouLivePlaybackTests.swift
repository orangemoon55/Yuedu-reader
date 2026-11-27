#if os(macOS)
import Foundation
import Testing
@testable import CodaCore

/// Explicitly opt in to read the saved account and check real audio headers.
/// No playback, account changes, or credentials are written or logged.
@Suite("Kugou live member playback", .enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_LIVE_AUDIT"] == "1"))
struct KugouLivePlaybackTests {
    @Test func todayPlaylistPlayback() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "wow.caicai.coda.music-accounts", "-a", "beans.kugou.auth.v2", "-w"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        try process.run()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes = Data()
        if text.hasPrefix("{") { bytes = Data(text.utf8) }
        else {
            var i = text.startIndex
            while i < text.endIndex {
                let end = text.index(i, offsetBy: 2)
                bytes.append(try #require(UInt8(text[i..<end], radix: 16))); i = end
            }
        }
        let credentials = try JSONDecoder().decode([String: String].self, from: bytes)
        let api = KugouMusicAPI(playbackCredentials: credentials)
        let song = ProviderSong(id: 1, name: "Today", artists: "G-DRAGON / 김종완 of NELL", album: "1st Mini Album : One Of A Kind", coverURL: nil, duration: 221.013, source: .kugou, kugouHash: "DAD519D7A02C4DB89E2CB763620F551D", kugouAlbumAudioId: "742833", kugouAlbumId: "518881", kugouQualityHashes: ["standard": "DAD519D7A02C4DB89E2CB763620F551D", "exhigh": "0F15E2E736A973886EC5A1193EEA4168"])
        let metadata = await api.playbackMetadata(for: song)
        #expect(metadata.kugouAlbumAudioId == "61722485")
        let result = try await api.songURLResult(song: song, quality: .hires)

        #expect(result?.quality == .lossless)
        let address = try #require(result?.url)
        let url = try #require(URL(string: address))
        var request = URLRequest(url: url)
        request.setValue("bytes=0-41", forHTTPHeaderField: "Range")
        request.timeoutInterval = 15
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let (stream, response) = try await session.bytes(for: request)
        #expect((response as? HTTPURLResponse)?.statusCode == 206)
        var header = Data()
        for try await byte in stream { header.append(byte); if header.count == 42 { break } }
        #expect(KugouMusicAPI.flacQuality(header: header) == .lossless)
    }

    @Test func stalePlayerTrackRecovers320KAndMenuUsesResponseEncoding() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "wow.caicai.coda.music-accounts", "-a", "beans.kugou.auth.v2", "-w"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        try process.run()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes = Data()
        if text.hasPrefix("{") { bytes = Data(text.utf8) }
        else {
            var i = text.startIndex
            while i < text.endIndex {
                let end = text.index(i, offsetBy: 2)
                bytes.append(try #require(UInt8(text[i..<end], radix: 16))); i = end
            }
        }
        let credentials = try JSONDecoder().decode([String: String].self, from: bytes)
        let api = KugouMusicAPI(playbackCredentials: credentials)
        let hash = "AF9D806FC0283153D1764B761FC0195C"
        let song = ProviderSong(id: 1, name: "小rapper", artists: "Rapeter", album: "DirtyGOOD 装乖", coverURL: nil,
            duration: 277.752, source: .kugou, kugouHash: hash, kugouAlbumAudioId: "278146795", kugouAlbumId: "78128901",
            kugouQualityHashes: Dictionary(uniqueKeysWithValues: ["standard", "exhigh", "lossless", "hires"].map { ($0, hash) }))
        let metadata = await api.playbackMetadata(for: song)
        #expect(KugouMusicAPI.metadataQualities(metadata) == [.standard, .exhigh])
        let options = try await api.qualityOptions(song: metadata)
        #expect(options.map(\.quality) == [.standard, .exhigh])
        #expect(options.map(\.title) == ["标准 · 128 kbps", "高品质 · 320 kbps"])
        let result = try await api.songURLResult(song: song, quality: .hires)
        #expect(result?.quality == .exhigh)
        // The queue snapshot for 跃 uses the old mix-song ID and lacks lossless hashes.
        let yue = ProviderSong(id: 2, name: "跃", artists: "薛之谦", album: "跃", coverURL: nil, duration: 351.373,
            source: .kugou, kugouHash: "8AB096BE4C20974627EC4AACEF148588", kugouAlbumAudioId: "475737829", kugouAlbumId: "154407186",
            kugouQualityHashes: ["standard": "8AB096BE4C20974627EC4AACEF148588", "exhigh": "ACD387181A1F4C0AF0CACEE717E74CC9"])
        let firstLossless = try await api.songURLResult(song: yue, quality: .lossless)
        #expect(firstLossless?.quality == .lossless)
        let firstHighest = try await api.songURLResult(song: yue, quality: .hires)
        #expect(firstHighest?.quality == .hires)
    }

    @Test func memberCanResolveBothReportedRecordingsAtEveryQuality() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "wow.caicai.coda.music-accounts", "-a", "beans.kugou.auth.v2", "-w"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let raw = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes: Data
        if text.hasPrefix("{") { bytes = Data(text.utf8) }
        else {
            var decoded = Data()
            var index = text.startIndex
            while index < text.endIndex {
                let next = text.index(index, offsetBy: 2)
                decoded.append(try #require(UInt8(text[index..<next], radix: 16)))
                index = next
            }
            bytes = decoded
        }
        let credentials = try JSONDecoder().decode([String: String].self, from: bytes)
        let api = KugouMusicAPI(playbackCredentials: credentials)
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let recordings = [
            ("F351CC2E22A89E83CC2B7FADBBE0D5A2", "502869095", "71455238"),
            ("0E609D845E0C07897F76AC4138FBBC94", "324003078", "46062560"),
        ]
        for (hash, audioID, albumID) in recordings {
            for quality: ProviderAudioQuality in [.standard, .exhigh, .lossless, .hires] {
                let song = ProviderSong(id: 1, name: "Live audit", artists: "", album: "", coverURL: nil, duration: 0,
                    source: .kugou, kugouHash: hash, kugouAlbumAudioId: audioID, kugouAlbumId: albumID)
                let result = try #require(await api.songURLResult(song: song, quality: quality))
                let address = result.url
                #expect(result.quality == quality)
                var audio = URLRequest(url: try #require(URL(string: address)))
                audio.setValue("bytes=0-41", forHTTPHeaderField: "Range")
                audio.timeoutInterval = 15
                let (stream, http) = try await session.bytes(for: audio)
                #expect((http as? HTTPURLResponse)?.statusCode == 206)
                var header = Data()
                for try await byte in stream { header.append(byte); if header.count == 42 { break } }
                if quality == .lossless || quality == .hires {
                    #expect(KugouMusicAPI.flacQuality(header: header) == quality)
                } else {
                    
                    #expect(header.starts(with: Data("ID3".utf8)) || header.first == 0xff)
                }
            }
        }
    }
}
#endif
