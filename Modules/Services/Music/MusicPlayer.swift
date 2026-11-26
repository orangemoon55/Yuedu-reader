import AVFoundation
import Combine
import MediaPlayer

/// The one native music engine used by the Media Hub. Yingxia's runtime queue retains the full
/// selection/history; AVQueuePlayer owns only its current native item. There is no second audio
/// engine, synthetic progress, provider mock, resolver or persisted playback URL.
@MainActor
final class MusicPlayer: ObservableObject {
    static let shared = MusicPlayer(queuePlayer: AVQueuePlayer())

    @Published private(set) var currentTrack: MediaHubLibraryItem?
    @Published private(set) var queue: [MediaHubLibraryItem] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    /// Observation lifetime belongs to the current item, not to a readiness timeout. The
    /// injectable installer also lets native tests deliver late/stale events deterministically.
    typealias ItemStatusObserver = @MainActor (
        AVPlayerItem, @escaping @MainActor @Sendable (AVPlayerItem.Status) -> Void
    ) -> AnyCancellable
    typealias RemoteCommandRemoval = @MainActor (MPRemoteCommand, Any) -> Void

    private let queuePlayer: AVQueuePlayer
    private let observeItemStatus: ItemStatusObserver
    private let removeCommandTarget: RemoteCommandRemoval
    private var playbackQueue = YingxiaMusicQueue<MediaHubLibraryItem>(tracks: [])
    private var itemEvents = MusicQueuePlaybackPolicy.ItemEvents()
    private var itemStatusObservation: AnyCancellable?
    private var consecutiveFailures = 0
    private var endObserver: NSObjectProtocol?
    private var failedObserver: NSObjectProtocol?
    private var interruptionObserver: NSObjectProtocol?
    private var routeObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var hubObservation: AnyCancellable?
    private struct RemoteCommandTarget {
        let command: MPRemoteCommand
        let token: Any
    }
    private var commandTargets: [RemoteCommandTarget] = []

    init(queuePlayer: AVQueuePlayer = AVQueuePlayer(),
         statusObserver: ItemStatusObserver? = nil,
         removeCommandTarget: @escaping RemoteCommandRemoval = { command, token in
             command.removeTarget(token)
         }) {
        self.queuePlayer = queuePlayer
        self.observeItemStatus = statusObserver ?? Self.observeStatus
        self.removeCommandTarget = removeCommandTarget
        self.queuePlayer.actionAtItemEnd = .pause
        installObservers()
        // Remote command targets are installed only while this player owns the session. TTS and
        // audiobook playback share MPRemoteCommandCenter and may replace these targets.
        hubObservation = NowPlayingHub.shared.objectWillChange.sink { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                switch NowPlayingHub.shared.source {
                case .none, .music:
                    break
                case .tts, .audiobook:
                    if self.currentTrack != nil { self.stopForTakeover() }
                }
            }
        }
    }

    private convenience init() {
        self.init(queuePlayer: AVQueuePlayer())
    }

    /// Start at the chosen track while retaining the complete supplied playlist, including history.
    func play(_ item: MediaHubLibraryItem, queue items: [MediaHubLibraryItem] = []) {
        // Existing app audio owns the same session. This is a deliberate takeover, not a
        // second session: stop TTS/audiobook before activating playback for this queue.
        TTSCoordinator.yieldSystemMediaToMusic()
        NowPlayingHub.shared.stop()
        stopQueue(clearMetadata: true, deactivateSession: false)

        let requested: [MediaHubLibraryItem]
        if items.contains(where: { $0.id == item.id }) {
            // Keep playlist order; the selected item may have refreshed ephemeral URL/headers.
            requested = items.map { $0.id == item.id ? item : $0 }
        } else {
            requested = [item] + items
        }
        var playable: [MediaHubLibraryItem] = []
        for candidate in requested where candidate.kind == .music {
            do {
                _ = try descriptorAndURL(for: candidate)
                playable.append(candidate)
            } catch {
                if candidate.id == item.id {
                    fail((error as? MusicPlayerError) ?? .invalidTrack)
                    return
                }
            }
        }
        guard item.kind == .music, let start = playable.firstIndex(where: { $0.id == item.id }) else {
            fail(.invalidTrack)
            return
        }
        playbackQueue = YingxiaMusicQueue(tracks: playable, start: start)
        queue = playbackQueue.tracks
        currentTrack = playbackQueue.current
        NowPlayingHub.shared.attachMusic(self)
        activateAudioSession()
        startCurrentTrack(autoplay: true)
    }

    private func descriptorAndURL(for track: MediaHubLibraryItem) throws -> (MusicTrackDescriptor, URL) {
        guard let descriptor = MusicTrackDescriptor.from(track), let url = descriptor.resolvedURL() else {
            throw MusicPlayerError.invalidTrack
        }
        if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
            throw MusicPlayerError.localFileMissing
        }
        return (descriptor, url)
    }

    /// Rebuild only the current AV item: consumed AVQueuePlayer items cannot provide backward
    /// history. The upstream cursor and published full queue do not change during this rebuild.
    private func startCurrentTrack(autoplay: Bool) {
        invalidateItemObservers()
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        guard let track = playbackQueue.current else { return }
        currentTrack = track
        currentTime = 0
        duration = 0
        errorMessage = nil
        isPlaying = autoplay
        do {
            let (descriptor, url) = try descriptorAndURL(for: track)
            let asset = HeaderedMediaAsset.make(url: url, headers: descriptor.headers)
            let item = AVPlayerItem(asset: asset)
            queuePlayer.insert(item, after: nil)
            installItemObservers(item)
            if autoplay { queuePlayer.play() }
            updateNowPlaying()
            setRemoteCommands(enabled: true)
        } catch {
            handleCurrentFailure((error as? MusicPlayerError) ?? .invalidTrack)
        }
    }

    func pause() {
        queuePlayer.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack != nil else { return }
        let needsReplacement = errorMessage != nil || queuePlayer.currentItem == nil
        errorMessage = nil
        consecutiveFailures = 0
        activateAudioSession()
        if needsReplacement {
            startCurrentTrack(autoplay: true)
            return
        }
        if duration > 0 && currentTime >= duration { seek(to: 0) }
        queuePlayer.play()
        isPlaying = true
        updateNowPlaying()
    }

    func togglePlayPause() {
        isPlaying ? pause() : resume()
    }

    func stop() { stopPlayback(clearMetadata: true, deactivateSession: true) }

    /// Used by other app audio owners. Do not queue a session deactivation that could run after
    /// the new owner's activation on the shared AVAudioSession.
    func stopForTakeover() { stopPlayback(clearMetadata: true, deactivateSession: false) }

    private func stopPlayback(clearMetadata: Bool, deactivateSession: Bool) {
        stopQueue(clearMetadata: clearMetadata, deactivateSession: deactivateSession)
        NowPlayingHub.shared.detachMusic(self)
    }

    func seek(to time: TimeInterval) {
        guard time.isFinite, let item = queuePlayer.currentItem else { return }
        let target = max(0, min(time, duration > 0 ? duration : time))
        // Invalidate a pending repeat seek and all already-enqueued callbacks, even if this is
        // still the same AVPlayerItem. User pause/seek must not be undone by an old completion.
        installItemObservers(item)
        queuePlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        updateNowPlaying()
    }

    func next() {
        guard playbackQueue.advance() != nil else { return }
        consecutiveFailures = 0
        startCurrentTrack(autoplay: true)
    }

    func previous() {
        guard currentTrack != nil else { return }
        switch MusicQueuePlaybackPolicy.previousAction(elapsed: currentTime, hasPrevious: playbackQueue.hasPrevious) {
        case .restart:
            seek(to: 0)
        case .back:
            guard playbackQueue.back() != nil else { return }
            consecutiveFailures = 0
            startCurrentTrack(autoplay: true)
        }
    }

    private func installObservers() {
        let center = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        interruptionObserver = center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main) { [weak self] note in
                let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt
                Task { @MainActor in self?.handleInterruption(type: rawType, options: rawOptions) }
            }
        routeObserver = center.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateNowPlaying() }
            }
    }

    /// Internal so the native smoke test can execute this exact production KVO bridge.
    static func observeStatus(
        of item: AVPlayerItem,
        deliver: @escaping @MainActor @Sendable (AVPlayerItem.Status) -> Void
    ) -> AnyCancellable {
        // KVO stays installed through readyToPlay. A later status-only failure must reach the
        // same terminal-event policy even when AVFoundation posts no failed-to-end notification.
        let observation = item.observe(\.status, options: [.initial, .new]) { _, change in
            let rawStatus = change.newValue?.rawValue
            Task { @MainActor in
                guard let rawStatus, let status = AVPlayerItem.Status(rawValue: rawStatus) else { return }
                deliver(status)
            }
        }
        return AnyCancellable { observation.invalidate() }
    }

    private func invalidateItemObservers() {
        itemEvents.invalidate()
        itemStatusObservation?.cancel()
        itemStatusObservation = nil
        queuePlayer.currentItem?.cancelPendingSeeks()
        let center = NotificationCenter.default
        if let endObserver { center.removeObserver(endObserver); self.endObserver = nil }
        if let failedObserver { center.removeObserver(failedObserver); self.failedObserver = nil }
        if let timeObserver { queuePlayer.removeTimeObserver(timeObserver); self.timeObserver = nil }
    }

    private func installItemObservers(_ item: AVPlayerItem) {
        invalidateItemObservers()
        let generation = itemEvents.generation
        let center = NotificationCenter.default
        endObserver = center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item,
            queue: .main) { [weak self] note in
                let ended = note.object as? AVPlayerItem
                Task { @MainActor in self?.itemEnded(ended, generation: generation) }
            }
        failedObserver = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item,
            queue: .main) { [weak self] note in
                let failed = note.object as? AVPlayerItem
                Task { @MainActor in self?.itemFailed(failed, generation: generation) }
            }
        timeObserver = queuePlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main) { [weak self, weak item] time in
                Task { @MainActor in
                    guard let self, let item,
                          self.itemEvents.accepts(generation, isCurrentItem: self.queuePlayer.currentItem === item) else { return }
                    let seconds = time.seconds
                    if seconds.isFinite && seconds >= 0 { self.currentTime = seconds }
                    let value = item.duration.seconds
                    if value.isFinite && value > 0 { self.duration = value }
                    // Like Yingxia, a real playing state, not merely asset readiness, ends a
                    // consecutive failure run. Paused/loading items never reset this budget.
                    if self.queuePlayer.timeControlStatus == .playing { self.consecutiveFailures = 0 }
                }
            }
        itemStatusObservation = observeItemStatus(item) { [weak self, weak item] status in
            guard let self, let item,
                  self.itemEvents.accepts(generation, isCurrentItem: self.queuePlayer.currentItem === item),
                  status == .failed else { return }
            self.itemFailed(item, generation: generation)
        }
    }

    private func itemEnded(_ item: AVPlayerItem?, generation: UInt64) {
        guard let item, itemEvents.consumeTerminalEvent(generation,
            isCurrentItem: queuePlayer.currentItem === item) else { return }
        let action = MusicQueuePlaybackPolicy.endAction(
            isCurrentItem: true,
            repeatsCurrent: MediaPreferences.musicLoopCurrent,
            hasNext: playbackQueue.hasNext
        )
        switch action {
        case .ignore:
            return
        case .repeatCurrent:
            // The .pause boundary retains this item. A manual seek/replacement/stop invalidates
            // this completion; a pause while it is pending must never be turned back into play.
            queuePlayer.seek(to: .zero) { [weak self, weak item] finished in
                Task { @MainActor in
                    guard let self, let item,
                          self.itemEvents.accepts(generation, isCurrentItem: self.queuePlayer.currentItem === item) else { return }
                    guard finished else { self.handleCurrentFailure(.avPlayer(code: -1)); return }
                    self.installItemObservers(item)
                    self.currentTime = 0
                    if self.isPlaying { self.queuePlayer.play() }
                    self.updateNowPlaying()
                }
            }
        case .advance:
            guard playbackQueue.advance() != nil else { return }
            startCurrentTrack(autoplay: isPlaying)
        case .finish:
            queuePlayer.pause()
            isPlaying = false
            if duration > 0 { currentTime = duration }
            updateNowPlaying()
            setRemoteCommands(enabled: true)
        }
    }

    private var hasNextTrack: Bool { playbackQueue.hasNext }

    private func itemFailed(_ item: AVPlayerItem?, generation: UInt64) {
        guard let item, itemEvents.consumeTerminalEvent(generation,
            isCurrentItem: queuePlayer.currentItem === item) else { return }
        let code = (item.error as NSError?)?.code ?? -1
        handleCurrentFailure(.avPlayer(code: code))
    }

    private func handleCurrentFailure(_ error: MusicPlayerError) {
        consecutiveFailures += 1
        if playbackQueue.skipsAfterFailure(consecutive: consecutiveFailures) {
            let autoplay = isPlaying
            playbackQueue.advance()
            startCurrentTrack(autoplay: autoplay)
        } else {
            fail(error)
        }
    }

    private func fail(_ error: MusicPlayerError) {
        invalidateItemObservers()
        queuePlayer.pause()
        isPlaying = false
        errorMessage = error.localizedDescription
        updateNowPlaying()
        setRemoteCommands(enabled: currentTrack != nil)
    }

    private func stopQueue(clearMetadata: Bool, deactivateSession: Bool = true) {
        invalidateItemObservers()
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        isPlaying = false
        currentTime = 0
        duration = 0
        queue = []
        playbackQueue = YingxiaMusicQueue(tracks: [])
        consecutiveFailures = 0
        currentTrack = nil
        errorMessage = nil
        if clearMetadata {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
            removeRemoteCommandTargets()
            setRemoteCommands(enabled: false)
            if deactivateSession { AudioSessionActivator.setActive(false) }
        }
    }

    private func activateAudioSession() {
        configureRemoteCommandsIfNeeded()
        AudioSessionActivator.activate(category: .playback, mode: .moviePlayback,
            options: [.allowAirPlay, .allowBluetoothA2DP])
        setRemoteCommands(enabled: true)
    }

    private func handleInterruption(type rawType: UInt?, options rawOptions: UInt?) {
        guard let rawType,
              let type = AVAudioSession.InterruptionType(rawValue: rawType) else { return }
        if type == .began { isPlaying = false; updateNowPlaying() }
        else if type == .ended,
                let rawOptions,
                AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume) {
            resume()
        }
    }

    func configureRemoteCommandsIfNeeded() {
        guard commandTargets.isEmpty else { return }
        let center = MPRemoteCommandCenter.shared()
        commandTargets = [
            RemoteCommandTarget(command: center.playCommand, token: center.playCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.resume() }; return .success
            }),
            RemoteCommandTarget(command: center.pauseCommand, token: center.pauseCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.pause() }; return .success
            }),
            RemoteCommandTarget(command: center.togglePlayPauseCommand, token: center.togglePlayPauseCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.togglePlayPause() }; return .success
            }),
            RemoteCommandTarget(command: center.nextTrackCommand, token: center.nextTrackCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.next() }; return .success
            }),
            RemoteCommandTarget(command: center.previousTrackCommand, token: center.previousTrackCommand.addTarget { @Sendable [weak self] _ in
                Task { @MainActor in self?.previous() }; return .success
            }),
            RemoteCommandTarget(command: center.changePlaybackPositionCommand, token: center.changePlaybackPositionCommand.addTarget { @Sendable [weak self] event in
                guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
                let position = event.positionTime
                Task { @MainActor in self?.seek(to: position) }; return .success
            })
        ]
    }

    private func removeRemoteCommandTargets() {
        for target in commandTargets { removeCommandTarget(target.command, target.token) }
        commandTargets.removeAll()
    }

    private func setRemoteCommands(enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.nextTrackCommand.isEnabled = enabled && hasNextTrack
        center.previousTrackCommand.isEnabled = enabled && currentTrack != nil
        center.changePlaybackPositionCommand.isEnabled = enabled
    }

    private func configureNowPlaying(for item: MediaHubLibraryItem, elapsed: TimeInterval,
                                     duration: TimeInterval, playing: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: item.title,
            MPMediaItemPropertyArtist: item.remarks ?? "",
            MPMediaItemPropertyAlbumTitle: item.categoryName ?? "",
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? 1.0 : 0.0,
            MPNowPlayingInfoPropertyDefaultPlaybackRate: 1.0,
        ]
        if duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    private func updateNowPlaying() {
        guard let item = currentTrack else { return }
        configureNowPlaying(for: item, elapsed: currentTime, duration: duration, playing: isPlaying)
    }

    isolated deinit {
        itemStatusObservation?.cancel()
        // Only unregister this instance's exact targets. Do not disable global commands,
        // deactivate AVAudioSession, clear metadata, or detach a newer TTS/audiobook owner.
        removeRemoteCommandTargets()
        let center = NotificationCenter.default
        if let endObserver { center.removeObserver(endObserver) }
        if let failedObserver { center.removeObserver(failedObserver) }
        if let interruptionObserver { center.removeObserver(interruptionObserver) }
        if let routeObserver { center.removeObserver(routeObserver) }
        if let timeObserver { queuePlayer.removeTimeObserver(timeObserver) }
    }
}

enum MusicPlayerError: LocalizedError {
    case invalidTrack
    case localFileMissing
    case avPlayer(code: Int)

    var errorDescription: String? {
        switch self {
        case .invalidTrack: return localized("這筆音樂沒有可播放的授權網址或本機檔案。")
        case .localFileMissing: return localized("找不到已導入的本機音訊檔案。")
        case .avPlayer(let code): return String(format: localized("音訊播放失敗（AVPlayer 錯誤 %d）。"), code)
        }
    }
}
