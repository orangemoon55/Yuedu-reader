import Foundation
import os.log

/// Adds a single cloud history entry once the engine has played audible audio.
@MainActor
final class QishuiHistoryReporter {
    private struct Session {
        let trackID: String
        let ticket: UUID
        let credentials: [String: String]
        var listening = PlaybackListeningAccumulator()
        var submitted = false
    }

    private static let log = Logger(subsystem: "wow.caicai.coda", category: "qishui-history")
    private var active: Session?
    private var submission: Task<Void, Never>?

    func begin(_ track: Track) {
        let context = MusicProviderContext.shared
        guard context.current == .qishui, active == nil,
              let trackID = track.platformSong?.qishui?.trackID else { return }
        let api = QishuiMusicAPI.shared
        guard api.isLoggedIn else { return }
        active = Session(trackID: trackID, ticket: context.ticket, credentials: api.credentials)
    }

    func sample(position: TimeInterval, advancing: Bool) {
        guard var current = active, !current.submitted else { return }
        current.listening.sample(position: position, advancing: advancing, uptime: ProcessInfo.processInfo.systemUptime)
        if current.listening.seconds >= 0.25 {
            current.submitted = true
            submit(current)
        }
        active = current
    }

    func discontinuity() { active?.listening.discontinuity() }
    func finish() { active = nil }

    private func submit(_ current: Session) {
        let previous = submission
        submission = Task {
            await previous?.value
            let api = QishuiMusicAPI.shared
            do {
                try MusicProviderContext.shared.check(current.ticket)
                guard api.credentials == current.credentials else { return }
                try await api.appendRecentPlay(trackID: current.trackID)
                try MusicProviderContext.shared.check(current.ticket)
                SidebarResources.playbackChanged()
            } catch is CancellationError {
                return
            } catch {
                Self.log.error("Qishui recent play was not acknowledged")
            }
        }
    }
}
