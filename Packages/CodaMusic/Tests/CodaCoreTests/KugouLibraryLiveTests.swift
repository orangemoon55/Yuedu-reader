#if os(macOS)
import Foundation
import Testing
@testable import CodaCore

/// Read-only network integration. No app launch, player, test runner on a
/// device, account writes or cloud uploads. Only counts/validation are logged.
@Suite("Kugou live cloud library", .enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_LIBRARY_LIVE_AUDIT"] == "1"))
struct KugouLibraryLiveTests {
    @Test func readsCloudHistoryRankingCapacityAndValidatesOneCompleteDownload() async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "wow.caicai.coda.music-accounts", "-a", "beans.kugou.auth.v2", "-w"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        try process.run()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.userAuthenticationRequired) }
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let bytes: Data
        if text.hasPrefix("{") { bytes = Data(text.utf8) }
        else {
            var data = Data(), index = text.startIndex
            while index < text.endIndex {
                let end = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                data.append(try #require(UInt8(text[index..<end], radix: 16))); index = end
            }
            bytes = data
        }
        let credentials = try JSONDecoder().decode([String: String].self, from: bytes)
        let api = KugouMusicAPI(playbackCredentials: credentials, playlistCredentials: credentials)
        let history = try await api.recentSongPlays()
        #expect(!history.isEmpty && history.count <= 500)
        let week = try await api.listeningRanking(week: true)
        let all = try await api.listeningRanking(week: false)
        let cloud = try await api.cloudLibrary()
        #expect(cloud.maxBytes != nil)
        print("Kugou read audit: history=\(history.count), week=\(week.count), all=\(all.count), cloud=\(cloud.songs.count)")
        var found: (Track, OfflineAudioResource)?
        for entry in history.prefix(8) {
        let song = entry.song
        var object: [String: Any] = ["id": -123, "name": song.name, "dt": Int(song.duration * 1000)]
        object["platformSong"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(song))
        let track = try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: object))
        do {
            let resource = try await api.downloadResource(song: song, track: track, level: "standard", accountScope: "kugou:live-audit")
            found = (track, resource); break
        } catch OfflineAudioError.unavailable { continue }
        }
        let (_, resource) = try #require(found)
        let (audio, response) = try await URLSession.shared.data(from: resource.url)
        #expect((response as? HTTPURLResponse)?.statusCode == 200)
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("coda-kugou-audit-\(UUID()).\(resource.descriptor.identity.format.rawValue)")
        defer { try? FileManager.default.removeItem(at: file) }
        try audio.write(to: file)
        try OfflineAudioValidator.validate(url: file, descriptor: resource.descriptor)
        print("Kugou complete download: size, MD5 and decoded duration verified")
    }
}
#endif
