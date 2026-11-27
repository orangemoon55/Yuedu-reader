import Foundation
import os.log
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// Counts engine progress, bounded by monotonic elapsed time. A seek resets
/// the anchor; paused/buffering time and projected UI progress never count.
struct PlaybackListeningAccumulator {
    private var position: TimeInterval?
    private var uptime: TimeInterval?
    private var advancing = false
    private(set) var seconds: TimeInterval = 0

    mutating func sample(position next: TimeInterval, advancing nextAdvancing: Bool, uptime now: TimeInterval) {
        defer {
            position = next.isFinite && next >= 0 ? next : nil
            uptime = now.isFinite ? now : nil
            advancing = nextAdvancing
        }
        guard advancing, let position, let uptime, next.isFinite, now.isFinite else { return }
        let mediaDelta = next - position, elapsed = now - uptime
        guard elapsed > 0, mediaDelta >= 0, mediaDelta <= elapsed * 1.25 + 0.5 else { return }
        seconds += min(mediaDelta, elapsed)
    }

    mutating func discontinuity() { position = nil; uptime = nil; advancing = false }
}

@MainActor
final class KugouPlaybackReporter {
    struct Song {
        let trackID: Int
        let mixSongID: String
        let hash: String
    }
    struct Confirmation {
        var history = false
        var ranking = false
    }
    struct Transport {
        var baseline: (String) async throws -> Int?
        var start: (String) async throws -> Void
        var history: (String, Date) async throws -> Void
        var end: (String, Int, Bool) async throws -> Void
        var confirm: (Song, Date, Int?) async throws -> Confirmation
    }
    private final class Session {
        let song: Song
        let binding: String
        let startedAt: Date
        let transport: Transport
        var accumulator = PlaybackListeningAccumulator()
        var queuedStart = false
        var baseline: Int?
        init(song: Song, binding: String, startedAt: Date, transport: Transport) {
            self.song = song; self.binding = binding; self.startedAt = startedAt; self.transport = transport
        }
    }
    private static let log = Logger(subsystem: "wow.caicai.coda", category: "kugou-playback")
    private let binding: () -> String?
    private let clock: () -> TimeInterval
    private let now: () -> Date
    private let transport: () -> Transport?
    private let accepted: () -> Void
    private let reconciliationDelays: [UInt64]
    private var active: Session?
    private var submission: Task<Void, Never>?
    private var reconciliation: Task<Void, Never>?
    private var queuedRevision = UUID()
    private var completedRevision: UUID?

    init(binding: (() -> String?)? = nil, clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         now: @escaping () -> Date = { Date() }, transport: (() -> Transport?)? = nil,
         accepted: (() -> Void)? = nil, reconciliationDelays: [UInt64] = [3, 12, 30, 75, 120]) {
        self.binding = binding ?? {
            guard MusicProviderContext.shared.current == .kugou, KugouMusicAuth.shared.isLoggedIn else { return nil }
            return MusicProviderContext.shared.authenticationKey
        }
        self.clock = clock; self.now = now
        self.transport = transport ?? { Self.liveTransport() }
        self.accepted = accepted ?? { SidebarResources.playbackChanged() }
        self.reconciliationDelays = reconciliationDelays
    }

    func begin(track: Track, position: TimeInterval) {
        guard track.platformSong?.source == .kugou, track.platformSong?.kugouCloud == nil else { return }
        let metadata = (try? PlatformMusicAPI.shared.song(track.id)) ?? track.platformSong
        guard let id = metadata?.kugouMixSongID ?? track.platformSong?.kugouMixSongID,
              let hash = metadata?.kugouHash else { return }
        begin(song: .init(trackID: track.id, mixSongID: id, hash: hash), position: position)
    }

    func begin(song: Song, position: TimeInterval) {
        guard let identity = binding(), Int64(song.mixSongID).map({ $0 > 0 }) == true else { return }
        if let active, active.binding == identity, active.song.trackID == song.trackID { return }
        // Track transitions explicitly finish the old engine before beginning
        // a new one. Do not infer elapsed audio from a different track's clock.
        active = nil
        guard let transport = transport() else { return }
        let session = Session(song: song, binding: identity, startedAt: now(), transport: transport)
        session.accumulator.sample(position: position, advancing: true, uptime: clock())
        active = session
    }

    func sample(position: TimeInterval, advancing: Bool) {
        guard let active else { return }
        guard binding() == active.binding else { self.active = nil; return }
        active.accumulator.sample(position: position, advancing: advancing, uptime: clock())
        queueStartIfHeard(active)
    }

    func willSeek(position: TimeInterval) {
        sample(position: position, advancing: false)
        active?.accumulator.discontinuity()
    }

    func finish(position: TimeInterval, completed: Bool) {
        guard let active else { return }
        sample(position: position, advancing: false)
        self.active = nil
        guard active.queuedStart, binding() == active.binding else { return }
        let milliseconds = Int(min(active.accumulator.seconds * 1000, Double(Int.max / 2)))
        guard milliseconds > 0 else { return }
        enqueue(active) { [weak self] in
            do {
                try await active.transport.end(active.song.mixSongID, milliseconds, completed)
                guard let self, self.binding() == active.binding else { return }
                Self.log.notice("KuGou playback end accepted: milliseconds=\(milliseconds); remote ranking pending")
                self.accepted()
                self.scheduleReconciliation(active, includesRanking: true)
            } catch {
                Self.log.error("KuGou playback end not confirmed: \(Self.diagnostic(error), privacy: .public)")
                // History may already have been accepted independently.
                self?.scheduleReconciliation(active, includesRanking: true)
            }
        }
    }

    private func queueStartIfHeard(_ session: Session) {
        guard !session.queuedStart, session.accumulator.seconds >= 0.25 else { return }
        session.queuedStart = true
        enqueue(session) { [weak self] in
            session.baseline = try? await session.transport.baseline(session.song.mixSongID)
            guard let self, self.binding() == session.binding else { return }
            do {
                try await session.transport.start(session.song.mixSongID)
                Self.log.notice("KuGou playback start accepted; history/ranking not yet confirmed")
            } catch {
                Self.log.error("KuGou playback start not confirmed: \(Self.diagnostic(error), privacy: .public)")
            }
            guard self.binding() == session.binding else { return }
            // Exactly one history increment per heard track session, including
            // pauses, seeks and quality changes. Never retry an ambiguous write.
            do {
                try await session.transport.history(session.song.mixSongID, session.startedAt)
                guard self.binding() == session.binding else { return }
                Self.log.notice("KuGou history write accepted; remote timestamp pending")
                self.accepted()
                self.scheduleReconciliation(session, includesRanking: false)
            } catch {
                Self.log.error("KuGou history write not confirmed: \(Self.diagnostic(error), privacy: .public)")
            }
        }
    }

    private func enqueue(_ session: Session, action: @escaping () async -> Void) {
        let previous = submission, revision = UUID()
        queuedRevision = revision
        submission = Task { @MainActor [weak self] in
            await previous?.value
            guard let self else { return }
            defer { self.completedRevision = revision }
            guard self.binding() == session.binding else { return }
            #if os(iOS)
            let token = UIApplication.shared.beginBackgroundTask(withName: "KuGou playback report")
            defer { if token != .invalid { UIApplication.shared.endBackgroundTask(token) } }
            #endif
            await action()
        }
    }

    private func scheduleReconciliation(_ session: Session, includesRanking: Bool) {
        guard binding() == session.binding else { return }
        reconciliation?.cancel()
        reconciliation = Task { @MainActor [weak self] in
            guard let self else { return }
            for delay in self.reconciliationDelays {
                do { try await Task.sleep(nanoseconds: delay * 1_000_000_000) }
                catch { return }
                guard self.binding() == session.binding else { return }
                self.accepted()
                do {
                    let result = try await session.transport.confirm(session.song, session.startedAt, session.baseline)
                    guard self.binding() == session.binding else { return }
                    if result.history { Self.log.notice("KuGou remote history timestamp confirmed") }
                    if includesRanking, result.ranking { Self.log.notice("KuGou remote listening count increase confirmed") }
                    if result.history && (!includesRanking || result.ranking) { return }
                } catch { /* Read failures never replay a write. */ }
            }
            Self.log.notice("KuGou remote reconciliation finished; any unconfirmed history/ranking remains pending")
        }
    }

    func waitForPendingSubmissions() async { await submission?.value }

    func waitForPendingSubmissions(timeout: TimeInterval) async {
        guard submission != nil else { return }
        let deadline = clock() + timeout
        while completedRevision != queuedRevision, clock() < deadline {
            do { try await Task.sleep(nanoseconds: 50_000_000) } catch { return }
        }
    }

    private static func diagnostic(_ error: Error) -> String {
        if let failure = error as? KugouPlaybackLogClient.Failure { return failure.localizedDescription }
        let value = error as NSError
        return "\(value.domain) / \(value.code)"
    }

    private static func liveTransport() -> Transport? {
        guard MusicProviderContext.shared.current == .kugou, KugouMusicAuth.shared.isLoggedIn else { return nil }
        KugouMusicAuth.shared.prepareDevice()
        let credentials = KugouMusicAuth.shared.exportedCredentials
        let api = KugouMusicAPI(playbackCredentials: credentials, playlistCredentials: credentials)
        let system = ProcessInfo.processInfo.operatingSystemVersion
        #if os(iOS)
        let screen = UIScreen.main
        let device = KugouPlaybackLogClient.Device(model: UIDevice.current.model, system: UIDevice.current.systemVersion,
            width: Int(screen.bounds.width * screen.scale), height: Int(screen.bounds.height * screen.scale))
        #else
        let screen = NSScreen.main
        let scale = screen?.backingScaleFactor ?? 1
        let device = KugouPlaybackLogClient.Device(model: "Mac", system: "\(system.majorVersion).\(system.minorVersion).\(system.patchVersion)",
            width: Int((screen?.frame.width ?? 1440) * scale), height: Int((screen?.frame.height ?? 900) * scale))
        #endif
        let client = Result { try KugouPlaybackLogClient(credentials: credentials, device: device) }
        return Transport(baseline: { id in
            let records = try await api.listeningRanking(week: true)
            return records.first { $0.song.kugouMixSongID == id }?.count ?? (records.count < 120 ? 0 : nil)
        }, start: { id in
            try await client.get().report(event: .start, songID: id)
        }, history: { id, time in
            try await api.uploadPlayHistory(songID: id, playedAt: time)
        }, end: { id, duration, completed in
            try await client.get().report(event: .end, songID: id, durationMS: duration, completed: completed)
        }, confirm: { song, time, baseline in
            let history = try await api.recentSongPlays(limit: 100)
            let earliest = floor(time.timeIntervalSince1970)
            let found = history.contains { ($0.song.kugouMixSongID == song.mixSongID || $0.song.kugouHash?.lowercased() == song.hash.lowercased()) && $0.playedAt.timeIntervalSince1970 >= earliest }
            guard let baseline else { return .init(history: found) }
            let records = try await api.listeningRanking(week: true)
            return .init(history: found, ranking: records.contains { $0.song.kugouMixSongID == song.mixSongID && $0.count > baseline })
        })
    }
}
