import Foundation

/// Where the current queue came from — used for scrobbling and UI affordances.
enum PlaySource: Codable, Equatable {
    case playlist(Int)
    case album(Int)
    case artist(Int)
    case daily
    case cloud
    case none
    case qishuiFeed(QishuiFeedState, playlistID: Int?)

    var sourceID: Int {
        switch self {
        case .playlist(let id), .album(let id), .artist(let id): return id
        case .qishuiFeed(_, let playlistID): return playlistID ?? 0
        default: return 0
        }
    }

    var qishuiFeed: QishuiFeedState? {
        if case .qishuiFeed(let feed, _) = self { return feed }
        return nil
    }

    func withQishuiFeed(_ feed: QishuiFeedState) -> Self {
        guard case .qishuiFeed(_, let playlistID) = self else { return self }
        return .qishuiFeed(feed, playlistID: playlistID)
    }
}

extension PlayContext {
    var source: PlaySource {
        switch kind {
        case .playlist: return .playlist(id)
        case .album: return .album(id)
        case .artist: return .artist(id)
        case .daily: return .daily
        case .cloud: return .cloud
        default: return .none
        }
    }

    /// The saved download collection this place maps to, if it can be one.
    var downloadCollectionID: String? {
        switch kind {
        case .playlist: return "playlist:\(id)"
        case .album: return "album:\(id)"
        default: return nil
        }
    }
}

struct PlaybackQueueCandidate: Equatable {
    enum Origin: Equatable { case inserted(Int), queue(Int), fm(Int) }
    let track: Track
    let origin: Origin
}

enum PlaybackQueuePlan {
    /// Commits the edited future order into one queue. Priority entries become
    /// ordinary queue entries so dragging across that boundary changes playback
    /// order too. The current song, history, and undisplayed tail stay intact.
    static func reorderingUpcoming(queue: [Track], currentIndex: Int, inserted: [Track],
                                   from offsets: IndexSet, to destination: Int) -> [Track]? {
        guard queue.indices.contains(currentIndex), !offsets.isEmpty else { return nil }
        let future = inserted + Array(queue.dropFirst(currentIndex + 1))
        guard offsets.allSatisfy({ future.indices.contains($0) }),
              (0...future.count).contains(destination) else { return nil }
        let moving = offsets.map { future[$0] }
        var reordered = future.enumerated().filter { !offsets.contains($0.offset) }.map(\.element)
        let insertion = destination - offsets.filter { $0 < destination }.count
        reordered.insert(contentsOf: moving, at: insertion)
        return Array(queue.prefix(currentIndex + 1)) + reordered
    }

    /// One bounded pass through the actual order. The original queue is never
    /// sorted or filtered to produce an offline view of it.
    static func next(queue: [Track], currentIndex: Int, inserted: [Track], fm: [Track],
                     isFM: Bool, repeatAll: Bool, limit: Int = .max) -> [PlaybackQueueCandidate] {
        guard limit > 0 else { return [] }
        if isFM { return fm.prefix(limit).enumerated().map { .init(track: $0.element, origin: .fm($0.offset)) } }
        var result = inserted.prefix(limit).enumerated().map { PlaybackQueueCandidate(track: $0.element, origin: .inserted($0.offset)) }
        let start = min(queue.count, max(0, currentIndex + 1))
        for index in queue.indices.dropFirst(start).prefix(limit - result.count) {
            result.append(.init(track: queue[index], origin: .queue(index)))
        }
        if repeatAll, queue.indices.contains(currentIndex) {
            for index in (0...currentIndex).prefix(limit - result.count) {
                result.append(.init(track: queue[index], origin: .queue(index)))
            }
        }
        return result
    }
}

/// How far ahead the song cache fills while the network is free: a few songs,
/// a short stretch of listening, and a bounded number of bytes.
struct PrefetchLimits: Equatable {
    var tracks = 5
    var seconds: TimeInterval = 20 * 60
    var bytes: Int64 = 100_000_000

    func window(_ candidates: [Track]) -> [Track] {
        var result: [Track] = []
        var duration: TimeInterval = 0
        for track in candidates {
            guard result.count < tracks, track.duration.isFinite, track.duration > 0,
                  duration + track.duration <= seconds else { break }
            result.append(track)
            duration += track.duration
        }
        return result
    }
}

struct OfflineQueueSelection {
    let candidate: PlaybackQueueCandidate
    /// Nil when the song sits in the platform's song cache rather than a download.
    let lease: OfflinePlaybackLease?
    let skipped: Int
}

enum OfflineQueueSelector {
    /// The first upcoming song that is on this device: downloaded, or else
    /// held by the song cache.
    static func firstAvailable(_ candidates: [PlaybackQueueCandidate], scope: String?, quality: String,
                               store: OfflineStore, isCached: (Int) async -> Bool) async throws -> OfflineQueueSelection? {
        for (skipped, candidate) in candidates.enumerated() {
            try Task.checkCancellation()
            if let scope, let lease = try await store.acquire(accountScope: scope, trackID: candidate.track.id, preferredQuality: quality) {
                if Task.isCancelled { try? await store.release(lease); throw CancellationError() }
                return .init(candidate: candidate, lease: lease, skipped: skipped)
            }
            if await isCached(candidate.track.id) { return .init(candidate: candidate, lease: nil, skipped: skipped) }
        }
        return nil
    }
}

struct OfflinePlaybackIssue: Identifiable {
    enum Kind { case missingTrack, emptyQueue }
    let id = UUID()
    let kind: Kind
    let trackName: String?
}

/// Resolves a place from what is on this device before asking the network: a
/// playlist snapshot saved for offline browsing, or the songs downloaded from
/// that place. Both players share it.
@MainActor
enum OfflineContextResolver {
    typealias Resolution = (tracks: [Track], source: PlaySource)

    static func resolve(_ context: PlayContext, offline: Bool,
                        online: () async throws -> Resolution?) async throws -> Resolution? {
        let downloads = DownloadManager.shared
        let scope = AccountStore.shared.offlineScope
        await downloads.start()
        guard scope == AccountStore.shared.offlineScope else { throw CancellationError() }
        if context.kind == .playlist, let scope,
           let saved = await PlaylistSnapshotStore.shared.load(id: context.id, scope: scope) {
            guard scope == AccountStore.shared.offlineScope else { throw CancellationError() }
            let summary = AccountStore.shared.userPlaylists.first { $0.id == context.id }
            if offline || !saved.needsBackgroundRefresh(summary: summary),
               !saved.detail.tracks.isEmpty || saved.isComplete {
                return (saved.detail.tracks, .playlist(context.id))
            }
        }
        let liked = context.kind == .playlist && AccountStore.shared.likedSongsPlaylist?.id == context.id
            ? AccountStore.shared.likedTrackIDs : []
        // The manager may still be switching accounts; then it has nothing to offer.
        let local = downloads.accountScope == scope ? downloads.localTracks(for: context, likedTrackIDs: liked) : []
        if offline {
            if !local.isEmpty { return (local, context.source) }
            throw URLError(.notConnectedToInternet)
        }
        do {
            if context.kind == .playlist, scope != nil {
                // Loading through the model saves the snapshot for offline browsing;
                // without an account scope it has nowhere to save and loads nothing.
                let model = PlaylistContent(playlistID: context.id)
                await model.load()
                guard model.detail != nil, !model.tracks.isEmpty || model.detail?.trackCount == 0 else {
                    throw URLError(.cannotLoadFromNetwork)
                }
                return (model.tracks, .playlist(context.id))
            }
            return try await online()
        } catch {
            guard !Task.isCancelled else { throw CancellationError() }
            // Nothing online but something stored: the downloads beat an error.
            if !local.isEmpty { return (local, context.source) }
            throw error
        }
    }
}

/// What "next" and "previous" do, decided once for both players. The players
/// only carry the step out: their engines differ, the queue rules do not.
enum PlaybackAdvancePlan {
    enum Next: Equatable {
        /// Offline: pick the first upcoming song stored on this device.
        case offline
        case personalFM
        /// Play the head of the "play next" list.
        case playNext
        case queue(index: Int)
        /// The Qishui stream ran out of loaded songs but has more to give.
        case loadMoreQishui(QishuiFeedState)
        /// A Qishui batch is already loading and advances when it lands.
        case waitForQishui
        /// Past the last song with nothing to wrap to.
        case endOfQueue
        case idle
    }

    /// - Parameter offlineHasCandidates: offline, and some upcoming song exists
    ///   to scan for a stored copy.
    static func next(queueCount: Int, currentIndex: Int, hasPlayNext: Bool, isFM: Bool,
                     offlineHasCandidates: Bool, repeatMode: RepeatMode,
                     qishuiFeed: QishuiFeedState?, isLoadingQishuiFeed: Bool) -> Next {
        if offlineHasCandidates { return .offline }
        if isFM { return .personalFM }
        if hasPlayNext { return .playNext }
        guard queueCount > 0 else { return .idle }
        let index = currentIndex + 1
        if index < queueCount { return .queue(index: index) }
        if let qishuiFeed, qishuiFeed.hasMore {
            return isLoadingQishuiFeed ? .waitForQishui : .loadMoreQishui(qishuiFeed)
        }
        // A Qishui stream never wraps back to songs it already recommended.
        guard repeatMode == .all, qishuiFeed == nil else { return .endOfQueue }
        return .queue(index: 0)
    }

    /// Previous always changes tracks, regardless of elapsed playback time.
    /// At the queue start it wraps only when there is another track to play.
    static func previousIndex(queueCount: Int, currentIndex: Int, isFM: Bool,
                              repeatMode: RepeatMode) -> Int? {
        guard !isFM, queueCount > 0 else { return nil }
        let index = currentIndex - 1
        if index >= 0 { return index }
        guard repeatMode == .all, queueCount > 1 else { return nil }
        return queueCount - 1
    }

    /// Keeps recent songs out of the next Qishui batch while allowing the
    /// stream to recommend an older song again after a long session.
    static func qishuiExclusions(queue: [Track], playNext: [Track], current: Track?) -> [Track] {
        Array(queue.suffix(200)) + playNext + [current].compactMap { $0 }
    }
}

/// Refills an empty personal FM list: up to three tries, a second apart.
@MainActor
enum PersonalFMRefill {
    enum Result: Equatable {
        case loaded([Track])
        case failed
        /// Another request or a mode change replaced this one.
        case superseded
    }

    static func load(fetch: () async throws -> [Track] = { try await NeteaseAPI.personalFM() },
                     retryDelay: Duration = .seconds(1),
                     isCurrent: () -> Bool) async -> Result {
        for attempt in 0..<3 {
            let tracks = try? await fetch()
            guard isCurrent() else { return .superseded }
            if let tracks, !tracks.isEmpty { return .loaded(tracks) }
            if attempt < 2 {
                try? await Task.sleep(for: retryDelay)
                guard isCurrent() else { return .superseded }
            }
        }
        ToastCenter.shared.show(String(localized: "获取私人漫游数据失败"))
        return .failed
    }
}
