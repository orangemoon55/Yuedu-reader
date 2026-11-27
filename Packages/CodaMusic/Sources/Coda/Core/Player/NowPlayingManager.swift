import Combine
import Foundation
import MediaPlayer

/// System Now Playing integration: media keys, Control Center, lock-screen metadata.
@MainActor
final class NowPlayingManager {
    static let shared = NowPlayingManager()

    private weak var player: PlayerService?
    private var artworkTask: Task<Void, Never>?
    private var playbackStateCancellables: Set<AnyCancellable> = []
    private var info: [String: Any] = [:]

    private(set) var isAttached = false
    private var commandTargets: [(MPRemoteCommand, Any)] = []

    private init() {}

    /// Relinquish only our own targets; never remove another owner's registrations.
    func detach() {
        guard isAttached else { return }
        clear()
        isAttached = false
        playbackStateCancellables.removeAll()
        for (command, token) in commandTargets { command.removeTarget(token) }
        commandTargets.removeAll()
        let center = MPRemoteCommandCenter.shared()
        center.likeCommand.isEnabled = false
        center.changeShuffleModeCommand.isEnabled = false
        center.changeRepeatModeCommand.isEnabled = false
        player = nil
    }

    func attach(to player: PlayerService) {
        guard !isAttached else { return }
        isAttached = true
        self.player = player
        playbackStateCancellables.removeAll()
        let center = MPRemoteCommandCenter.shared()
        let commands: [MPRemoteCommand] = [center.playCommand, center.pauseCommand, center.togglePlayPauseCommand,
                        center.nextTrackCommand, center.previousTrackCommand,
                        center.changePlaybackPositionCommand, center.changeShuffleModeCommand,
                        center.changeRepeatModeCommand]
        commands.forEach { $0.isEnabled = true }
        center.stopCommand.isEnabled = false
        center.skipForwardCommand.isEnabled = false
        center.skipBackwardCommand.isEnabled = false

        func add(_ command: MPRemoteCommand,
                 _ handler: @escaping @MainActor (MPRemoteCommandEvent) -> MPRemoteCommandHandlerStatus) {
            let token = command.addTarget { @Sendable [weak self] event in
                let perform: @MainActor () -> MPRemoteCommandHandlerStatus = {
                    guard let self, self.isAttached else { return .noActionableNowPlayingItem }
                    return handler(event)
                }
                if Thread.isMainThread {
                    return MainActor.assumeIsolated { perform() }
                }
                return DispatchQueue.main.sync { MainActor.assumeIsolated { perform() } }
            }
            commandTargets.append((command, token))
        }

        add(center.playCommand) { [weak player] _ in
            guard let player, player.hasCurrentTrack else { return .noActionableNowPlayingItem }
            if !player.isPlaying { player.togglePlayPause() }
            return .success
        }
        add(center.pauseCommand) { [weak player] _ in
            guard let player, player.hasCurrentTrack else { return .noActionableNowPlayingItem }
            if player.isPlaying { player.togglePlayPause() }
            return .success
        }
        add(center.togglePlayPauseCommand) { [weak player] _ in
            guard let player, player.hasCurrentTrack else { return .noActionableNowPlayingItem }
            player.togglePlayPause()
            return .success
        }
        add(center.nextTrackCommand) { [weak player] _ in
            player?.next()
            return .success
        }
        add(center.previousTrackCommand) { [weak player] _ in
            player?.previous()
            return .success
        }
        add(center.changePlaybackPositionCommand) { [weak player] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            player?.seek(to: event.positionTime)
            return .success
        }

        // Like feedback (Control Center long-press / CarPlay; isActive = hearted)
        center.likeCommand.isEnabled = true
        center.likeCommand.localizedTitle = String(localized: "喜欢")
        center.likeCommand.localizedShortTitle = String(localized: "喜欢")
        add(center.likeCommand) { [weak player] _ in
            guard let track = player?.currentTrack else { return .noActionableNowPlayingItem }
            Task { @MainActor in
                await AccountStore.shared.toggleLike(trackID: track.id)
                NowPlayingManager.shared.refreshLikeState()
            }
            return .success
        }

        // NB: we deliberately do NOT register skipForward/skipBackward (±15s).
        // Enabling those commands makes iOS show "back 15s / forward 15s" on the
        // lock screen and Dynamic Island *instead of* previous/next track — a
        // podcast-style layout that's wrong for a music player and hid the
        // skip-track buttons (#83, #87). Previous/next above stay the system
        // media buttons everywhere, including CarPlay.

        // Shuffle / Repeat — backs the shuffle and repeat buttons on the CarPlay Now Playing screen.
        add(center.changeShuffleModeCommand) { [weak player] event in
            guard let player,
                  let event = event as? MPChangeShuffleModeCommandEvent else { return .commandFailed }
            let wantOn = event.shuffleType != .off
            if player.shuffleEnabled != wantOn { player.toggleShuffle() }
            return .success
        }
        add(center.changeRepeatModeCommand) { [weak player] event in
            guard let player,
                  let event = event as? MPChangeRepeatModeCommandEvent else { return .commandFailed }
            // MPRepeatType: .off / .one / .all → RepeatMode: .off / .one / .all
            let target: RepeatMode? = switch event.repeatType {
                case .off:  .off
                case .one:  .one
                case .all:  .all
                default:    nil
            }
            if let target, player.repeatMode != target { player.repeatMode = target }
            return .success
        }

        #if os(macOS)
        // Shuffle is one of the queue orders on macOS (`shuffleEnabled` is
        // derived), so observe the order and map it back to on/off.
        player.$queueOrder
            .map { $0 == .shuffled }
            .removeDuplicates()
            .sink { enabled in
                center.changeShuffleModeCommand.currentShuffleType = enabled ? .items : .off
            }
            .store(in: &playbackStateCancellables)
        #else
        player.$shuffleEnabled
            .removeDuplicates()
            .sink { enabled in
                center.changeShuffleModeCommand.currentShuffleType = enabled ? .items : .off
            }
            .store(in: &playbackStateCancellables)
        #endif

        player.$repeatMode
            .removeDuplicates()
            .sink { mode in
                center.changeRepeatModeCommand.currentRepeatType = switch mode {
                case .off: .off
                case .one: .one
                case .all: .all
                }
            }
            .store(in: &playbackStateCancellables)
    }

    /// Reflects the current track's hearted state on the like command.
    func refreshLikeState() {
        guard isAttached else { return }
        guard let track = player?.currentTrack else {
            MPRemoteCommandCenter.shared().likeCommand.isActive = false
            return
        }
        MPRemoteCommandCenter.shared().likeCommand.isActive =
            AccountStore.shared.isLiked(track.id)
    }

    func updateMetadata(for track: Track, duration: TimeInterval) {
        guard isAttached else { return }
        info = [
            MPMediaItemPropertyTitle: track.name,
            MPMediaItemPropertyArtist: track.artistNames,
            MPMediaItemPropertyAlbumTitle: track.album.name,
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: 0.0,
            MPNowPlayingInfoPropertyPlaybackRate: 1.0,
            // Declare the session as audio so system surfaces treat it as a
            // complete now-playing app (best-effort hardening for #36/#40).
            MPNowPlayingInfoPropertyMediaType: MPNowPlayingInfoMediaType.audio.rawValue,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = .playing
        refreshLikeState()

        artworkTask?.cancel()
        // 1024px: the lock screen's tap-to-fullscreen artwork presentation
        // needs high-resolution art to engage.
        guard let url = track.album.picUrl?.resizedImageURL(1024) else { return }
        artworkTask = Task { [weak self] in
            let apply: ImageCache.CachedImageHandler = { [weak self] image in
                guard let self, self.isAttached, !Task.isCancelled else { return }
                let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
                self.info[MPMediaItemPropertyArtwork] = artwork
                MPNowPlayingInfoCenter.default().nowPlayingInfo = self.info
            }
            if let image = await ImageCache.shared.image(for: url, onCachedImage: apply) {
                apply(image)
            }
        }
    }

    func updateElapsed(_ elapsed: TimeInterval, rate: Double) {
        guard isAttached else { return }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = elapsed
        info[MPNowPlayingInfoPropertyPlaybackRate] = rate
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = rate > 0 ? .playing : .paused
    }

    func clear() {
        guard isAttached else { return }
        artworkTask?.cancel()
        artworkTask = nil
        info = [:]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
        MPRemoteCommandCenter.shared().likeCommand.isActive = false
    }
}
