#if os(macOS)
import AppKit
import AVFoundation
import Foundation
import Testing
@testable import CodaCore

@MainActor private final class KugouAuditAudioCompletion: NSObject, AVAudioPlayerDelegate {
    var finished = false
    var successful = false

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        successful = flag
        finished = true
    }
}

/// Explicit opt-in: genuinely decodes/plays audio with volume zero, then
/// writes one history increment and one start/end pair. No invented duration,
/// repeated submissions, account mutations or device automation.
@Suite("Kugou real listening report", .enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_REPORT_LIVE_AUDIT"] == "1"))
@MainActor struct KugouPlaybackReportLiveTests {
    @Test func realAudioPlaybackIsAcknowledgedAndReconciled() async throws {
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
                let end = text.index(i, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                bytes.append(try #require(UInt8(text[i..<end], radix: 16))); i = end
            }
        }
        let credentials = try JSONDecoder().decode([String: String].self, from: bytes)
        let api = KugouMusicAPI(playbackCredentials: credentials, playlistCredentials: credentials)
        let baseline = try await api.listeningRanking(week: true)
        var selected: (ProviderSong, OfflineAudioResource, Int)?
        for item in baseline.prefix(10) where item.song.duration > 70 {
            let song = item.song
            var object: [String: Any] = ["id": -123, "name": song.name, "dt": Int(song.duration * 1000)]
            object["platformSong"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(song))
            let track = try JSONDecoder().decode(Track.self, from: JSONSerialization.data(withJSONObject: object))
            if let resource = try? await api.downloadResource(song: song, track: track, level: "standard", accountScope: "kugou:report-audit") {
                selected = (song, resource, item.count); break
            }
        }
        let (song, resource, initialCount) = try #require(selected)
        let songID = try #require(song.kugouMixSongID)
        let (audio, _) = try await URLSession.shared.data(from: resource.url)
        let player = try AVAudioPlayer(data: audio)
        let completion = KugouAuditAudioCompletion()
        player.delegate = completion
        player.volume = 0
        player.prepareToPlay()
        defer { player.stop() }
        let system = ProcessInfo.processInfo.operatingSystemVersion
        let screen = try #require(NSScreen.main)
        let client = try KugouPlaybackLogClient(credentials: credentials, device: .init(model: "Mac",
            system: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            width: Int(screen.frame.width * screen.backingScaleFactor), height: Int(screen.frame.height * screen.backingScaleFactor)))
        var startAccepted = false, historyAccepted = false, endAccepted = false
        var reportedMilliseconds = 0
        let transport = KugouPlaybackReporter.Transport(baseline: { _ in initialCount }, start: { id in
            try await client.report(event: .start, songID: id); startAccepted = true
        }, history: { id, time in
            try await api.uploadPlayHistory(songID: id, playedAt: time); historyAccepted = true
        }, end: { id, ms, completed in
            reportedMilliseconds = ms
            try await client.report(event: .end, songID: id, durationMS: ms, completed: completed); endAccepted = true
        }, confirm: { _, _, _ in .init() })
        let reporter = KugouPlaybackReporter(binding: { "read-write-audit" }, transport: { transport }, accepted: {}, reconciliationDelays: [])
        let startedAt = Date()
        #expect(player.play())
        reporter.begin(song: .init(trackID: -123, mixSongID: songID, hash: song.kugouHash ?? ""), position: player.currentTime)
        let fullTrack = ProcessInfo.processInfo.environment["CODA_KUGOU_REPORT_FULL_TRACK"] == "1"
        let target = fullTrack ? player.duration : 65
        let deadline = ProcessInfo.processInfo.systemUptime + target + 15
        var position = player.currentTime
        while (fullTrack ? !completion.finished : player.isPlaying && position < target),
              ProcessInfo.processInfo.systemUptime < deadline {
            try await Task.sleep(nanoseconds: 250_000_000)
            // AVAudioPlayer can reset currentTime when it naturally finishes.
            // Preserve measured progress; do not substitute the track duration.
            let next = player.currentTime
            if next >= position {
                reporter.sample(position: next, advancing: player.isPlaying)
                position = next
            }
        }
        let completed = fullTrack && completion.finished && completion.successful
        reporter.finish(position: position, completed: completed)
        player.stop()
        await reporter.waitForPendingSubmissions()
        #expect(position >= target - 0.5)
        if fullTrack { #expect(completed) }
        #expect(reportedMilliseconds > Int((target - 5) * 1000) && reportedMilliseconds <= Int(position * 1000) + 100)
        var historyConfirmed = false, rankingConfirmed = false
        var finalCount: Int?
        let delays: [UInt64] = fullTrack ? [3, 12, 30, 75, 120] : [3, 12, 30]
        for delay in delays {
            try await Task.sleep(nanoseconds: delay * 1_000_000_000)
            let history = try await api.recentSongPlays(limit: 100)
            let ranking = try await api.listeningRanking(week: true)
            historyConfirmed = history.contains { $0.song.kugouMixSongID == songID && $0.playedAt.timeIntervalSince1970 >= floor(startedAt.timeIntervalSince1970) }
            finalCount = ranking.first { $0.song.kugouMixSongID == songID }?.count
            rankingConfirmed = finalCount.map { $0 > initialCount } ?? false
            if historyConfirmed && rankingConfirmed { break }
        }
        print("KuGou real report: startAccepted=\(startAccepted), historyAccepted=\(historyAccepted), endAccepted=\(endAccepted), historyConfirmed=\(historyConfirmed), rankingConfirmed=\(rankingConfirmed), initialCount=\(initialCount), finalCount=\(finalCount.map(String.init) ?? "absent"), completed=\(completed), actualMilliseconds=\(reportedMilliseconds)")
        #expect(historyAccepted && historyConfirmed)
        #expect(startAccepted && endAccepted)
        #expect(rankingConfirmed)
    }
}
#endif
