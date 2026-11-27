#if os(macOS)
import AVFoundation
import Foundation
import Testing
@testable import CodaCore

/// Writes to the real Kugou cloud: uploads CODA_KUGOU_CLOUD_FILE, resolves and decodes
/// its playback URL, then deletes it again. Opt-in only; no app launch or device runner.
@Suite("Kugou live cloud changes", .enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_CLOUD_LIVE_AUDIT"] == "1"))
struct KugouCloudChangesLiveTests {
    @Test func uploadsPlaysAndDeletesOneFile() async throws {
        let path = try #require(ProcessInfo.processInfo.environment["CODA_KUGOU_CLOUD_FILE"])
        let credentials = try Self.credentials()
        let api = KugouMusicAPI(playbackCredentials: credentials, playlistCredentials: credentials)
        let file = try await CloudUploadFile.prepare(URL(fileURLWithPath: path))
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        func uploaded(_ library: KugouMusicAPI.CloudLibrary) -> ProviderSong? {
            library.songs.first { $0.kugouCloud?.byteCount == file.size || $0.kugouHash?.lowercased() == file.md5 }
        }

        let before = try await api.cloudLibrary()
        try #require(uploaded(before) == nil, "File already in cloud; refusing to delete a pre-existing copy")
        print("Kugou cloud before: \(before.songs.count) songs, used=\(before.usedBytes ?? -1)")

        try await api.uploadCloudFile(.init(url: file.url, md5: file.md5, size: file.size, ext: file.ext,
                                            title: file.title, artist: file.taggedArtist, durationMS: file.durationMS))
        var song: ProviderSong?
        for _ in 0..<6 where song == nil {
            song = uploaded(try await api.cloudLibrary())
            if song == nil { try await Task.sleep(for: .seconds(2)) }
        }
        let item = try #require(song, "Uploaded file did not appear in the cloud list")
        print("Uploaded: name=\(item.name), artists=\(item.artists), duration=\(item.duration), albumAudioId=\(item.kugouAlbumAudioId ?? "-")")

        var deleted = false
        defer { if !deleted { print("WARNING: uploaded file was not deleted") } }
        do {
            let address = try await api.userCloudURL(song: item)
            let (audio, response) = try await URLSession.shared.data(from: try #require(URL(string: address)))
            #expect((response as? HTTPURLResponse)?.statusCode == 200)
            let local = FileManager.default.temporaryDirectory.appendingPathComponent("coda-kugou-cloud-\(UUID()).\(file.ext)")
            defer { try? FileManager.default.removeItem(at: local) }
            try audio.write(to: local)
            let decoded = try AVAudioFile(forReading: local)
            let seconds = Double(decoded.length) / decoded.fileFormat.sampleRate
            print("Playback URL: \(audio.count) bytes, decoded \(Int(seconds))s (local \(file.durationMS / 1000)s)")
            #expect(abs(seconds - Double(file.durationMS) / 1000) < 3)
        } catch {
            try await api.deleteCloudSongs([item]); deleted = true
            throw error
        }

        try await api.deleteCloudSongs([item]); deleted = true
        var gone = false
        for _ in 0..<6 where !gone {
            gone = uploaded(try await api.cloudLibrary()) == nil
            if !gone { try await Task.sleep(for: .seconds(2)) }
        }
        #expect(gone, "Deleted file is still listed")
        print("Deleted and confirmed absent")
    }

    /// Prefers the dev app's login, then the release app's; only a logged-in record is used.
    static func credentials() throws -> [String: String] {
        for service in ["wow.caicai.coda.dev.music-accounts", "wow.caicai.coda.music-accounts"] {
            if let values = try? credentials(service: service), values["token"]?.isEmpty == false { return values }
        }
        throw URLError(.userAuthenticationRequired)
    }

    static func credentials(service: String) throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", service, "-a", "beans.kugou.auth.v2", "-w"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        try process.run()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.userAuthenticationRequired) }
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes = Data(text.utf8)
        if !text.hasPrefix("{") {
            bytes = Data(); var index = text.startIndex
            while index < text.endIndex {
                let end = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                bytes.append(try #require(UInt8(text[index..<end], radix: 16))); index = end
            }
        }
        return try JSONDecoder().decode([String: String].self, from: bytes)
    }
}
#endif
