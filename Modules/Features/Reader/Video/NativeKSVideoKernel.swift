import AVFoundation
import KSPlayer
import UIKit

/// Readcc's adapter for the upstream KSPlayer FFmpeg/VideoToolbox renderer.
/// It owns no source resolver: the same resolved URL and headers reach either kernel.
/// A missing KSPlayer dependency is a build error, never a silent placeholder player.
@MainActor
final class NativeKSVideoKernel: NSObject, MediaPlayerDelegate {
    private(set) var engine: KSMEPlayer?
    private var timer: Timer?
    private var timeoutTask: Task<Void, Never>?
    var onReady: (() -> Void)?
    var onTick: ((Double, Double, Bool, CGSize) -> Void)?
    var onFinish: ((Error?) -> Void)?

    var view: UIView? { engine?.view }
    var isReady: Bool { engine?.isReadyToPlay == true }

    static func options(headers: [String: String]) -> KSOptions {
        let options = KSOptions()
        // Reject line breaks before KSOptions turns dictionary entries into HTTP lines.
        let safe = headers.filter { key, value in
            !key.isEmpty && !key.contains(":") && !key.contains(where: { $0.isWhitespace || $0.isNewline })
                && !value.contains("\r") && !value.contains("\n")
        }
        options.appendHeader(safe)
        options.isLoopPlay = false
        options.hardwareDecode = true
        // Bound a failed source instead of leaving the page spinning indefinitely.
        options.formatContextOptions["rw_timeout"] = 20_000_000
        return options
    }

    func open(_ stream: VideoStream) {
        stop()
        let next = KSMEPlayer(url: stream.url, options: Self.options(headers: stream.headers))
        engine = next
        next.delegate = self
        next.prepareToPlay()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.publishTimeline() }
        }
        timeoutTask = Task { [weak self, weak next] in
            try? await Task.sleep(for: .seconds(30))
            guard !Task.isCancelled, let self, let next,
                  self.engine === next, !next.isReadyToPlay else { return }
            self.onFinish?(NSError(domain: "Readcc.KSPlayer", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: "KSPlayer: media preparation timed out"]))
        }
    }

    func play(rate: Float) {
        engine?.playbackRate = rate
        engine?.play()
    }
    func pause() { engine?.pause() }
    func setRate(_ rate: Float) { engine?.playbackRate = rate }
    func seek(to seconds: Double, completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in }) {
        guard seconds.isFinite, let engine, engine.isReadyToPlay, engine.seekable else {
            completion(false)
            return
        }
        let identity = ObjectIdentifier(engine)
        engine.seek(time: max(0, seconds)) { [weak self] finished in
            Task { @MainActor [weak self] in
                guard let self, self.engine.map(ObjectIdentifier.init) == identity else { return }
                completion(finished)
            }
        }
    }
    func stop() {
        timeoutTask?.cancel()
        timeoutTask = nil
        timer?.invalidate()
        timer = nil
        engine?.delegate = nil
        engine?.shutdown()
        engine = nil
    }

    private func isCurrent(_ player: some MediaPlayerProtocol) -> Bool {
        guard let engine else { return false }
        return ObjectIdentifier(player) == ObjectIdentifier(engine)
    }
    private func publishTimeline() {
        guard let engine, engine.isReadyToPlay else { return }
        let time = engine.currentPlaybackTime
        let duration = engine.duration
        onTick?(time.isFinite ? max(0, time) : 0,
                duration.isFinite ? max(0, duration) : 0,
                engine.seekable, engine.naturalSize)
    }
    func readyToPlay(player: some MediaPlayerProtocol) {
        guard isCurrent(player) else { return }
        timeoutTask?.cancel()
        publishTimeline()
        onReady?()
    }
    func changeLoadState(player: some MediaPlayerProtocol) {
        guard isCurrent(player) else { return }
        publishTimeline()
    }
    func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {}
    func playBack(player: some MediaPlayerProtocol, loopCount: Int) {}
    func finish(player: some MediaPlayerProtocol, error: Error?) {
        guard isCurrent(player) else { return }
        timeoutTask?.cancel()
        onFinish?(error)
    }
}
