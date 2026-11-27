// SPDX-License-Identifier: GPL-3.0-only
// Adapted from MeloX a41ea0e1 (GPL-3.0-only). See ThirdPartyNotices/MeloX.md.
#if os(iOS) || CODA_STREAMING_TESTS
@preconcurrency import AVFoundation

enum AudioPlaybackState: Equatable { case idle, loading, paused, playing }

@MainActor
final class AudioPlaybackDeck: NSObject, @preconcurrency AudioPlayerDelegate {
    var onStateChanged: (() -> Void)?
    var onSeekCompleted: (() -> Void)?
    var onEnded: (() -> Void)?
    var onFailure: ((Error) -> Void)?

    private(set) var state: AudioPlaybackState = .idle
    private(set) var itemIdentifier: Int?
    private(set) var itemID: UUID?
    private(set) var error: Error?
    private(set) var channelCount: AVAudioChannelCount = 2
    private var player: AudioPlayer?
    private var loadContinuation: CheckedContinuation<Bool, Never>?
    private var source: URL?
    private var finishedPosition: TimeInterval?
    private var currentEntryID: AudioEntryId?
    private var initialSeek: TimeInterval?
    private var isSeeking = false
    private var wantsPlayback = false
    private var playbackRate: Float = 1
    private var outputVolume: Float = 1
    var httpDataSink: ((HTTPAudioDataChunk) -> Void)?
    var sampleSink: ((AVAudioPCMBuffer) -> Void)?

    var hasCurrentItem: Bool { itemID != nil }
    var sourceURL: URL? { source }
    var isReady: Bool { state == .playing || state == .paused }
    var currentPlaybackTime: TimeInterval? {
        guard let player, !isSeeking, initialSeek == nil else { return nil }
        return finishedPosition ?? max(player.progress, 0)
    }
    func playbackDuration(referenceDuration: TimeInterval) -> TimeInterval? {
        Self.validatedDuration(player?.exactDuration, referenceDuration: referenceDuration)
    }

    /// Some external streams contain bogus packet/frame counts. Even a parser's
    /// "exact" duration must agree with the catalog before replacing its clock.
    /// Shorter media remains valid (for example a 30-second preview).
    static func validatedDuration(_ duration: TimeInterval?, referenceDuration: TimeInterval) -> TimeInterval? {
        guard let duration, duration.isFinite, duration > 0 else { return nil }
        if referenceDuration.isFinite, referenceDuration > 0,
           duration > referenceDuration + max(30, referenceDuration * 0.2) {
            return nil
        }
        return duration
    }
    var rate: Float {
        get { state == .playing ? playbackRate : 0 }
        set {
            if newValue == 0 { pause() }
            else {
                playbackRate = newValue
                player?.rate = newValue
                play()
            }
        }
    }
    var volume: Float {
        get { outputVolume }
        set {
            outputVolume = newValue
            if isReady { player?.volume = newValue }
        }
    }

    func load(_ source: URL, identifier: Int? = nil,
              startAt: TimeInterval = 0, autoplay: Bool = false, bufferDuration: TimeInterval = 8) async -> Bool {
        clear()
        let id = UUID()
        itemID = id
        itemIdentifier = identifier
        self.source = source
        wantsPlayback = autoplay
        initialSeek = max(startAt, 0)
        isSeeking = true
        transition(to: .loading)
        let format = await AudioPlaybackFormat.load(from: source)
        guard itemID == id, !Task.isCancelled else { return false }
        let player = AudioPlayer(
            configuration: AudioPlayerConfiguration(
                bufferSizeInSeconds: max(bufferDuration, 8),
                secondsRequiredToStartPlaying: 0.3, gracePeriodAfterSeekInSeconds: 0.1),
            outputFormat: format, httpDataSink: httpDataSink)
        self.player = player
        channelCount = format?.channelCount ?? 2
        player.volume = 0
        player.delegate = self
        if let sampleSink {
            player.frameFiltering.add(entry: "coda.spectrum") { buffer, _ in sampleSink(buffer) }
        }
        return await withCheckedContinuation { continuation in
            loadContinuation = continuation
            player.play(url: source)
        }
    }

    func play() {
        wantsPlayback = true
        #if os(iOS)
        zzTrace("deck.play playerState=\(String(describing: player?.state)) progress=\(String(describing: player?.progress))")
        #endif
        if player?.state == .stopped { seek(to: 0) }
        player?.resume()
        // resume() can fail while the system audio session is unavailable.
        // Only report playing once the underlying player accepted the resume.
        if isReady, let player, player.state != .paused { transition(to: .playing) }
    }

    func play(atRate rate: Float) { self.rate = rate }

    func pause() {
        wantsPlayback = false
        // A muted seek keeps decoding until it can settle at the requested sample.
        if !isSeeking {
            player?.pause()
            if hasCurrentItem { transition(to: .paused) }
        }
    }

    func seek(to seconds: TimeInterval) {
        guard let player else { initialSeek = max(seconds, 0); return }
        isSeeking = true
        finishedPosition = nil
        player.volume = 0
        transition(to: .loading)
        if player.state == .stopped, let source {
            initialSeek = max(seconds, 0)
            currentEntryID = nil
            player.play(url: source)
            return
        }
        player.seek(to: max(seconds, 0))
        player.resume()
    }

    func clear() {
        itemID = nil
        itemIdentifier = nil
        source = nil
        finishedPosition = nil
        currentEntryID = nil
        player?.delegate = nil
        player?.stop()
        player = nil
        initialSeek = nil
        isSeeking = false
        wantsPlayback = false
        playbackRate = 1
        error = nil
        loadContinuation?.resume(returning: false)
        loadContinuation = nil
        transition(to: .idle)
    }

    private func transition(to newState: AudioPlaybackState) {
        guard state != newState else { return }
        state = newState
        onStateChanged?()
    }

    func audioPlayerDidStartPlaying(player: AudioPlayer, with entryId: AudioEntryId) {
        guard player === self.player else { return }
        currentEntryID = entryId
        guard let target = initialSeek else { return }
        initialSeek = nil
        player.seek(to: target)
    }

    func audioPlayerStateChanged(player: AudioPlayer,
                                 with newState: AudioPlayerState, previous: AudioPlayerState) {
        guard player === self.player else { return }
        switch newState {
        case .playing:
            guard initialSeek == nil, !player.isSeeking, player.state == .playing else { return }
            let completedSeek = isSeeking
            isSeeking = false
            if !wantsPlayback { player.pause() }
            player.volume = outputVolume
            transition(to: wantsPlayback ? .playing : .paused)
            loadContinuation?.resume(returning: true)
            loadContinuation = nil
            if completedSeek { onSeekCompleted?() }
        case .bufferring, .running:
            transition(to: .loading)
        case .paused:
            if !isSeeking { transition(to: .paused) }
        case .ready, .stopped, .error, .disposed:
            break
        }
    }

    func audioPlayerDidFinishPlaying(player: AudioPlayer, entryId: AudioEntryId,
                                     stopReason: AudioPlayerStopReason, progress: Double, duration: Double) {
        #if os(iOS)
        zzTrace("deck.didFinish reason=\(stopReason) progress=\(progress) duration=\(duration) same=\(player === self.player) entryMatch=\(currentEntryID == entryId)")
        #endif
        guard player === self.player, currentEntryID == entryId, stopReason == .eof else { return }
        finishedPosition = progress
        isSeeking = false
        wantsPlayback = false
        loadContinuation?.resume(returning: false)
        loadContinuation = nil
        transition(to: .paused)
        onEnded?()
    }
    func audioPlayerUnexpectedError(player: AudioPlayer, error: AudioPlayerError) {
        guard player === self.player else { return }
        self.error = error
        isSeeking = false
        wantsPlayback = false
        transition(to: .paused)
        loadContinuation?.resume(returning: false)
        loadContinuation = nil
        onFailure?(error)
    }
    func audioPlayerDidFinishBuffering(player: AudioPlayer, with entryId: AudioEntryId) {}
    func audioPlayerDidCancel(player: AudioPlayer, queuedItems: [AudioEntryId]) {}
    func audioPlayerDidReadMetadata(player: AudioPlayer, metadata: [String: String]) {}
}

#endif
