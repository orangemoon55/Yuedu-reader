// SPDX-License-Identifier: GPL-3.0-only
// Playback submission sequencing adapted from MeloX a41ea0e1 (GPL-3.0-only).
// See ThirdPartyNotices/MeloX.md.
import Foundation
import os.log
#if os(iOS)
import UIKit
#endif

/// Preserve event order and the account/source that actually started a song.
@MainActor
final class PlaybackHistoryReporter {
    struct Session {
        let id = UUID()
        let trackID: Int
        let sourceID: Int
        let account: String
        let song: NeteasePlaybackLog.Song
        let startedAt: Date
    }

    private static let log = Logger(subsystem: "wow.caicai.coda", category: "playback-history")
    private let client: NeteaseClient
    private let upload: (NeteasePlaybackLog.Song, NeteasePlaybackLog.Event, Int, Bool) async throws -> Void
    private var submission: Task<Void, Never>?
    private var reconciliation: Task<Void, Never>?
    private var activeSessions = Set<UUID>()
    private var activeAccount: String?

    init(client: NeteaseClient = .shared,
         upload: ((NeteasePlaybackLog.Song, NeteasePlaybackLog.Event, Int, Bool) async throws -> Void)? = nil) {
        self.client = client
        self.upload = upload ?? { song, event, seconds, completed in
            try await client.uploadPlaybackLog(song: song, event: event, seconds: seconds, completed: completed)
        }
    }

    func start(trackID: Int, sourceID: Int, duration: TimeInterval = 0,
               quality: String? = nil, fee: Int = 0, bitrate: Int? = nil) -> Session? {
        guard trackID > 0, MusicProviderContext.shared.current == .netease,
              let account = client.authenticationFingerprint else { return nil }
        if activeAccount != account { activeSessions.removeAll(); activeAccount = account }
        let length = duration.isFinite ? Int(min(max(duration, 0), Double(Int.max / 2))) : 0
        let song = NeteasePlaybackLog.Song(id: trackID, sourceID: sourceID, duration: length, quality: quality, fee: fee, bitrate: bitrate)
        let session = Session(trackID: trackID, sourceID: sourceID, account: account, song: song, startedAt: .now)
        activeSessions.insert(session.id)
        enqueue(session, event: .start, seconds: 0) { [upload] _ in
            try await upload(song, .start, 0, false)
        }
        return session
    }

    func finish(_ session: Session, playbackTime: TimeInterval, duration: TimeInterval, completed: Bool) {
        guard activeSessions.remove(session.id) != nil else { return }
        let length = duration.isFinite ? max(0, duration) : 0
        let elapsed = playbackTime.isFinite ? max(0, playbackTime) : 0
        let time = completed ? length : (length > 0 ? min(elapsed, length) : elapsed)
        // Clamp before converting to Int, including malformed remote durations.
        let seconds = Int(min(time, Double(Int.max / 2)))
        // No duration event for a selection that never actually played.
        guard seconds > 0 else { return }
        enqueue(session, event: .finish, seconds: seconds) { [upload] _ in
            try await upload(session.song, .finish, seconds, completed)
        }
    }

    private func enqueue(_ session: Session, event: NeteasePlaybackLog.Event, seconds: Int, send: @escaping (NeteaseClient) async throws -> Void) {
        let previous = submission
        let client = client
        submission = Task { @MainActor in
            await previous?.value
            guard client.authenticationFingerprint == session.account else { return }
            #if os(iOS)
            // A natural end can stop background audio before the duration log
            // reaches the server. Keep this bounded network operation alive.
            let backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "Playback report")
            defer {
                if backgroundTask != .invalid { UIApplication.shared.endBackgroundTask(backgroundTask) }
            }
            #endif
            do {
                try await send(client)
                Self.log.notice("Playback log accepted: event=\(event.rawValue, privacy: .public), song=\(session.trackID), seconds=\(seconds); history not yet confirmed")
                if client === NeteaseClient.shared, client.authenticationFingerprint == session.account {
                    SidebarResources.playbackChanged()
                    scheduleReconciliation(session: session)
                }
            } catch is CancellationError {
                return
            } catch {
                Self.log.error("Playback report failed for song \(session.trackID): \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // A file acknowledgement is separate from history/statistics ingestion.
    // Confirm remote timestamps instead of presenting an upload as synchronized.
    private func scheduleReconciliation(session: Session) {
        reconciliation?.cancel()
        let client = client
        reconciliation = Task { @MainActor in
            var historyConfirmed = false
            // History usually appears first. Keep refreshing statistics for
            // three minutes even after that confirmation, without re-uploading.
            for delay: UInt64 in [3, 12, 30, 75, 60] {
                do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) }
                catch { return }
                guard client.authenticationFingerprint == session.account else { return }
                SidebarResources.playbackChanged()
                guard !historyConfirmed else { continue }
                do {
                    let records = try await NeteaseAPI.recentSongs(using: client)
                    guard client.authenticationFingerprint == session.account else { return }
                    let earliest = Date(timeIntervalSince1970: floor(session.startedAt.timeIntervalSince1970))
                    if records.contains(where: { $0.song.id == session.trackID && $0.playedAt >= earliest }) {
                        Self.log.notice("Remote playback history confirmed for song \(session.trackID)")
                        historyConfirmed = true
                    }
                } catch is CancellationError { return }
                catch {
                    let failure = error as NSError
                    Self.log.notice("Playback history verification unavailable for song \(session.trackID): \(failure.domain, privacy: .public) code=\(failure.code)")
                }
            }
            if !historyConfirmed {
                Self.log.notice("Playback log accepted but remote history remains unconfirmed for song \(session.trackID)")
            }
        }
    }

    func waitForPendingSubmissions() async {
        await submission?.value
    }
}
