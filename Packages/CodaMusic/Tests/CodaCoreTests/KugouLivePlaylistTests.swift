#if os(macOS)
import Foundation
import Testing
@testable import CodaCore

/// Opt-in integration check. Uses only a newly created private scratch playlist;
/// confirms the server's song list and deletes that scratch playlist on completion.
@Suite("Kugou live playlist writes", .enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_LIVE_PLAYLIST_AUDIT"] == "1"))
struct KugouLivePlaylistTests {
    @Test func createAddReadBackAndRemoveScratchPlaylist() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "wow.caicai.coda.music-accounts", "-a", "beans.kugou.auth.v2", "-w"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        try process.run()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.userAuthenticationRequired) }
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes = Data()
        if text.hasPrefix("{") { bytes = Data(text.utf8) }
        else {
            var i = text.startIndex
            while i < text.endIndex {
                let end = text.index(i, offsetBy: 2)
                guard let byte = UInt8(text[i..<end], radix: 16) else { throw URLError(.cannotDecodeRawData) }
                bytes.append(byte); i = end
            }
        }
        let credentials = try JSONDecoder().decode([String: String].self, from: bytes)
        let api = KugouMusicAPI(playlistCredentials: credentials)
        let playlist = try await api.createPlaylist(name: "Coda诊断-\(UUID().uuidString.prefix(8))", isPrivate: true)
        do {
            let hash = "F351CC2E22A89E83CC2B7FADBBE0D5A2"
            let song = ProviderSong(id: -1, name: "Coda protocol check", artists: "", album: "", coverURL: nil, duration: 0,
                source: .kugou, kugouHash: hash, kugouAlbumAudioId: "502869095", kugouAlbumId: "71455238")
            try await api.addSongs(listID: playlist.id, songs: [song])
            // Cloud-list writes become visible to reads after a short propagation delay.
            var found = false
            for attempt in 0..<8 {
                if attempt > 0 { try await Task.sleep(for: .milliseconds(500)) }
                let songs = try await api.playlistSongs(listID: playlist.id, cloud: true)
                if songs.contains(where: { $0.kugouHash?.uppercased() == hash }) { found = true; break }
            }
            #expect(found)
        } catch {
            try await api.unsubscribePlaylist(listID: playlist.id)
            throw error
        }
        try await api.unsubscribePlaylist(listID: playlist.id)
    }
}
#endif
