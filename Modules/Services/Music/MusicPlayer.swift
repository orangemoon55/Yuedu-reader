import AVFoundation
import Combine
import MediaPlayer

/// The one native music engine used by the Media Hub. It is a real AVQueuePlayer: no preview
/// timers, synthetic progress, provider mocks, or service-specific resolver are involved.
@MainActor
final class MusicPlayer: ObservableObject {
    static let shared = MusicPlayer(queuePlayer: AVQueuePlayer())

    @Published private(set) var currentTrack: MediaHubLibraryItem?
    @Published private(set) var queue: [MediaHubLibraryItem] = []
    @Published private(set) var isPlaying = false
    @Published private(set) var currentTime: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    @Published private(set) var errorMessage: String?

    private let queuePlayer: AVQueuePlayer
    private var queueItems: [AVPlayerItem] = []
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

    init(queuePlayer: AVQueuePlayer = AVQueuePlayer()) {
        self.queuePlayer = queuePlayer
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
                    if self.isPlaying { self.stopForTakeover() }
                }
            }
        }
    }

    private convenience init() {
        self.init(queuePlayer: AVQueuePlayer())
    }

    /// Start one item and optionally append the remaining imported items as a real AV queue.
    func play(_ item: MediaHubLibraryItem, queue items: [MediaHubLibraryItem] = []) {
        errorMessage = nil
        // Existing app audio owns the same session. This is a deliberate takeover, not a
        // second session: it stops TTS/audiobook before activating playback for this queue.
        TTSCoordinator.yieldSystemMediaToMusic()
        NowPlayingHub.shared.stop()
        stopQueue(clearMetadata: false)

        let requested = ([item] + items.filter { $0.id != item.id })
            .filter { $0.kind == .music }
        var built: [(MediaHubLibraryItem, AVPlayerItem)] = []
        for candidate in requested {
            guard let descriptor = MusicTrackDescriptor.from(candidate),
                  let url = descriptor.resolvedURL() else {
                if candidate.id == item.id { fail(MusicPlayerError.invalidTrack) }
                continue
            }
            if url.isFileURL && !FileManager.default.fileExists(atPath: url.path) {
                if candidate.id == item.id { fail(MusicPlayerError.localFileMissing) }
                continue
            }
            let asset = HeaderedMediaAsset.make(url: url, headers: descriptor.headers)
            built.append((candidate, AVPlayerItem(asset: asset)))
        }
        guard let first = built.first, first.0.id == item.id else {
            if errorMessage == nil { fail(MusicPlayerError.invalidTrack) }
            return
        }

        queue = built.map(\.0)
        queueItems = built.map(\.1)
        currentTrack = first.0
        NowPlayingHub.shared.attachMusic(self)
        for playerItem in queueItems { queuePlayer.insert(playerItem, after: nil) }
        activateAudioSession()
        installItemObservers(first.1)
        configureNowPlaying(for: first.0, elapsed: 0, duration: 0, playing: true)
        queuePlayer.play()
        isPlaying = true
    }

    func pause() {
        queuePlayer.pause()
        isPlaying = false
        updateNowPlaying()
    }

    func resume() {
        guard currentTrack != nil else { return }
        errorMessage = nil
        activateAudioSession()
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
        let target = max(0, min(time, duration > 0 ? duration : time))
        queuePlayer.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        currentTime = target
        updateNowPlaying()
    }

    func next() {
        guard queuePlayer.currentItem != nil else { return }
        queuePlayer.advanceToNextItem()
        guard queuePlayer.currentItem != nil else {
            isPlaying = false
            currentTime = 0
            duration = 0
            updateNowPlaying()
            setRemoteCommands(enabled: true)
            return
        }
        syncCurrentTrack()
        queuePlayer.play()
        isPlaying = true
        updateNowPlaying()
        setRemoteCommands(enabled: true)
    }

    func previous() {
        guard let index = currentTrack.flatMap({ current in queue.firstIndex { $0.id == current.id } }), index > 0 else {
            seek(to: 0)
            return
        }
        let target = queue[index - 1]
        play(target, queue: Array(queue.dropFirst(index)))
    }

    private func installObservers() {
        let center = NotificationCenter.default
        endObserver = center.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: nil,
            queue: .main) { [weak self] note in
                Task { @MainActor in self?.itemEnded(note.object as? AVPlayerItem) }
            }
        failedObserver = center.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: nil,
            queue: .main) { [weak self] note in
                Task { @MainActor in self?.itemFailed(note.object as? AVPlayerItem) }
            }
        let session = AVAudioSession.sharedInstance()
        interruptionObserver = center.addObserver(forName: AVAudioSession.interruptionNotification,
            object: session, queue: .main) { [weak self] note in
                Task { @MainActor in self?.handleInterruption(note) }
            }
        routeObserver = center.addObserver(forName: AVAudioSession.routeChangeNotification,
            object: session, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.updateNowPlaying() }
            }
        timeObserver = queuePlayer.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.5, preferredTimescale: 600),
            queue: .main) { [weak self] time in
                Task { @MainActor in
                    guard let self else { return }
                    let seconds = time.seconds
                    if seconds.isFinite && seconds >= 0 { self.currentTime = seconds }
                    if let item = self.queuePlayer.currentItem {
                        let value = item.duration.seconds
                        if value.isFinite && value > 0 { self.duration = value }
                    }
                }
            }
    }

    private func installItemObservers(_ item: AVPlayerItem) {
        // Status becomes failed asynchronously; polling is bounded and runs only for the item
        // that was just selected, while the notification above catches failures during playback.
        Task { @MainActor [weak self, weak item] in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard let self, let item, self.queuePlayer.currentItem === item else { return }
                if item.status == .readyToPlay { return }
                if item.status == .failed { self.itemFailed(item); return }
            }
        }
    }

    private func itemEnded(_ item: AVPlayerItem?) {
        guard let item else { return }
        let action = MusicQueuePlaybackPolicy.endAction(
            isCurrentItem: queuePlayer.currentItem === item,
            repeatsCurrent: MediaPreferences.musicLoopCurrent,
            hasNext: hasNextTrack
        )
        switch action {
        case .ignore:
            return
        case .repeatCurrent:
            // AVQueuePlayer is configured to pause at item boundaries, so the current item is
            // still selected here. Seek only that item; never let the queue silently move first.
            queuePlayer.seek(to: .zero) { [weak self, weak item] finished in
                Task { @MainActor in
                    guard let self, let item, finished, self.queuePlayer.currentItem === item else { return }
                    self.queuePlayer.play()
                    self.isPlaying = true
                    self.currentTime = 0
                    self.updateNowPlaying()
                }
            }
        case .advance:
            queuePlayer.advanceToNextItem()
            guard queuePlayer.currentItem != nil else { return }
            syncCurrentTrack()
            queuePlayer.play()
            isPlaying = true
            updateNowPlaying()
            setRemoteCommands(enabled: true)
        case .finish:
            isPlaying = false
            if duration > 0 { currentTime = duration }
            updateNowPlaying()
            setRemoteCommands(enabled: true)
        }
    }

    private var currentQueueIndex: Int? {
        guard let current = queuePlayer.currentItem else { return nil }
        return queueItems.firstIndex(where: { $0 === current })
    }

    private var hasNextTrack: Bool {
        guard let index = currentQueueIndex else { return false }
        return MusicQueuePlaybackPolicy.nextIndex(after: index, itemCount: queue.count) != nil
    }

    private func itemFailed(_ item: AVPlayerItem?) {
        guard item == nil || item === queuePlayer.currentItem else { return }
        let code = (item?.error as NSError?)?.code ?? -1
        fail(MusicPlayerError.avPlayer(code: code))
    }

    private func syncCurrentTrack() {
        guard let current = queuePlayer.currentItem,
              let index = queueItems.firstIndex(where: { $0 === current }), queue.indices.contains(index) else { return }
        currentTrack = queue[index]
        currentTime = 0
        duration = 0
        installItemObservers(current)
    }

    private func fail(_ error: MusicPlayerError) {
        isPlaying = false
        errorMessage = error.localizedDescription
        updateNowPlaying()
    }

    private func stopQueue(clearMetadata: Bool, deactivateSession: Bool = true) {
        queuePlayer.pause()
        queuePlayer.removeAllItems()
        isPlaying = false
        currentTime = 0
        duration = 0
        queue = []
        queueItems = []
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

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began { isPlaying = false; updateNowPlaying() }
        else if type == .ended,
                let rawOptions = note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt,
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
                Task { @MainActor in self?.seek(to: event.positionTime) }; return .success
            })
        ]
    }

    private func removeRemoteCommandTargets() {
        for target in commandTargets { target.command.removeTarget(target.token) }
        commandTargets.removeAll()
    }

    private func setRemoteCommands(enabled: Bool) {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = enabled
        center.pauseCommand.isEnabled = enabled
        center.togglePlayPauseCommand.isEnabled = enabled
        center.nextTrackCommand.isEnabled = enabled && hasNextTrack
        center.previousTrackCommand.isEnabled = enabled && (currentQueueIndex ?? 0) > 0
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

    deinit {
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
