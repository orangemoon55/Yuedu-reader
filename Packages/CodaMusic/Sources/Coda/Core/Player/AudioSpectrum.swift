import Accelerate
import AVFoundation
import Foundation
import os

/// Real-time band levels pulled out of the playing audio.
///
#if os(macOS)
/// `PlaybackEngine` hands us every buffer of its final mixed output (see
/// `setOutputSampleSink`) and we run a small FFT over it. That callback is a
/// real-time audio thread: everything it touches below is preallocated,
/// allocation-free; onset publication uses a nonblocking try-lock.
///
/// The mixer's tap hears whatever the listener hears — both decks and a
/// pre-rendered segment during a hand-over — so there is nothing to re-wire per
/// track. See `tapState`, which callers use to decide between real levels,
/// holding still, and the decorative fallback.
#else
/// The streaming player delivers decoded PCM through its frame filter. Each track
/// receives its own analyzer so late output from the outgoing deck cannot
/// overwrite the new track's levels.
#endif
@MainActor
final class AudioSpectrum {
    static let shared = AudioSpectrum()

    /// Number of frequency bands published to the UI. Read from the audio thread
    /// too, so it stays outside the actor's isolation.
    nonisolated static let bandCount = 4

    #if os(macOS)
    /// One store for the life of the process: the engine's tap is installed
    /// once on a mixer that never goes away, so — unlike a per-item player tap —
    /// there is no outgoing analyzer to leave writing over the new track. It is
    /// cleared at the points where silence is correct instead of replaced.
    ///
    /// `nonisolated` because the audio thread writes into it directly; every
    /// field it exposes is a plain slot, so a torn read costs one stale bar.
    private nonisolated let store = SpectrumStore()
    #else
    /// Replaced for each new item rather than cleared.
    ///
    /// The outgoing track's tap keeps running until its player item is actually
    /// swapped out, so clearing the store in place doesn't work: the old tap
    /// simply writes the old track's levels straight back, and the bars show the
    /// previous song for a moment as the new one starts. Handing the new item a
    /// fresh store leaves the old tap writing to one nobody reads, which it
    /// keeps alive on its own until it is finalized.
    private var store = SpectrumStore()
    #endif
    private init() {}

    /// True while the tap is actually delivering samples for the current track.
    var isLive: Bool { store.isLive }

    /// What is known about the current track's tap.
    ///
    /// Three states rather than a flag, because there is a stretch after the
    /// user hits play where the answer isn't known yet: the track's URL is still
    /// being resolved. Treating that as "untappable" flashes the decorative
    /// animation for a moment right as a song starts, and treating it as
    /// "tapped" would freeze the previous track's last frame under it.
    enum TapState {
        /// Nothing playing.
        case idle
        /// Resolving the source; it isn't known yet whether it can be tapped.
        case preparing
        /// A tap is attached. `isLive` says whether samples have arrived yet.
        case tapped
        /// This source can't be tapped — the decorative fallback belongs here.
        case untappable
    }

    private(set) var tapState: TapState = .idle

    /// Latest level for one band, already smoothed and normalized to `0...1`.
    /// A single pointer read — cheap enough to call per bar, per frame.
    func level(at index: Int) -> Float {
        store.level(at: index)
    }


    func takeOnsets() -> SpectrumOnsetMailbox.Peaks {
        store.onsets.take(now: ProcessInfo.processInfo.systemUptime)
    }

    #if os(macOS)
    /// One buffer of the engine's final output. Called on a real-time audio
    /// thread — allocates nothing, locks nothing, hops no actor.
    nonisolated func ingest(_ buffer: AVAudioPCMBuffer) {
        store.ingest(buffer)
    }

    /// Call once a deck is actually carrying the track: the mixer's tap is
    /// permanent, so every source the engine can play is a tapped one.
    func markTapped() {
        tapState = .tapped
    }
    #else
    /// The streaming player delivers decoded PCM directly, including cached files.
    func makeStreamingSink() -> (AVAudioPCMBuffer) -> Void {
        let sink = SpectrumStore()
        store = sink
        tapState = .tapped
        return { buffer in sink.ingest(buffer) }
    }

    #endif

    /// Call as soon as a track is chosen — before its URL is resolved — so the
    /// bars hold still instead of falling back while the answer is unknown.
    func beginPreparing() {
        tapState = .preparing
        #if os(macOS)
        store.reset()
        #else
        store = SpectrumStore()
        #endif
    }

    /// Silences the bands without forgetting that the current item is tapped —
    /// pausing shouldn't make a tapped track look untappable when it resumes.
    func reset() {
        store.reset()
    }
}

/// Positive spectral change with a moving noise floor and a short refractory period.
/// Independently implemented from standard spectral-flux/onset concepts used by aubio.
struct SpectrumOnsetDetector {
    private var average: Float = 0
    private var deviation: Float = 0
    private var cooldown: Float = 0
    private var primed = false

    mutating func advance(flux: Float, audible: Bool, delta: Float) -> Float {
        cooldown = max(0, cooldown - delta)
        guard primed else {
            primed = true
            average = flux
            return 0
        }
        let threshold = max(0.012, average + deviation * 1.5)
        let onset = audible && cooldown == 0 && flux > threshold
            ? min(1, (flux - threshold) / max(0.05, threshold * 2)) : 0
        let coefficient = 1 - expf(-delta / 0.45)
        deviation += (abs(flux - average) - deviation) * coefficient
        average += (flux - average) * coefficient
        if onset > 0 { cooldown = 0.08 }
        return onset
    }
}

/// A peak mailbox: audio never waits for the UI; undelivered peaks are retried.
final class SpectrumOnsetMailbox: @unchecked Sendable {
    struct Peaks: Sendable {
        var bass: Float = 0
        var melody: Float = 0
        var timestamp: TimeInterval = 0
    }
    private let storage = OSAllocatedUnfairLock(initialState: Peaks())

    func publish(bass: Float, melody: Float, now: TimeInterval) -> Bool {
        storage.withLockIfAvailable { peaks in
            if now - peaks.timestamp > 0.15 { peaks = Peaks() }
            peaks.bass = max(peaks.bass, bass)
            peaks.melody = max(peaks.melody, melody)
            if bass > 0 || melody > 0 { peaks.timestamp = now }
            return true
        } == true
    }

    func take(now: TimeInterval) -> Peaks {
        storage.withLock { peaks in
            let result = now - peaks.timestamp <= 0.15 ? peaks : Peaks()
            peaks = Peaks()
            return result
        }
    }
}

// MARK: - Spectrum store shared with the audio thread

#if os(macOS)
/// Backing storage for the tap. Read by `AudioSpectrum` on the main actor and
/// written from the engine's audio thread; every field it exposes is a plain
/// `Float` slot, so a torn read costs at most one slightly stale bar.
#else
/// Backing storage held by `AudioSpectrum` and the deck’s PCM callback; every field it exposes is a plain
/// `Float` slot, so a torn read costs at most one slightly stale bar.
#endif
private final class SpectrumStore: @unchecked Sendable {
    /// 1024-sample Hann window with a 512-sample hop: better bass resolution
    /// while preserving approximately 12ms onset updates at 44.1kHz.
    private static let fftSize = 1024
    private static let log2n = vDSP_Length(10)  // 2^10 == 1024
    private static let binCount = fftSize / 2

    /// Published band levels, written by the audio thread, read by the UI.
    private let levels: UnsafeMutablePointer<Float>
    /// Whether the tap has produced audio recently.
    private let liveFlag: UnsafeMutablePointer<Int32>

    /// Scratch buffers — preallocated because the audio thread must not malloc.
    private let window: UnsafeMutablePointer<Float>
    private let mono: UnsafeMutablePointer<Float>
    private let ring: UnsafeMutablePointer<Float>
    private var ringFill = 0
    private let realp: UnsafeMutablePointer<Float>
    private let imagp: UnsafeMutablePointer<Float>
    private let magnitudes: UnsafeMutablePointer<Float>
    private let fftSetup: FFTSetup?
    private let previousMagnitudes: UnsafeMutablePointer<Float>
    private let detectors: UnsafeMutablePointer<SpectrumOnsetDetector>
    let onsets = SpectrumOnsetMailbox()
    private var pendingBass: Float = 0
    private var pendingMelody: Float = 0

    #if os(macOS)
    /// Source format, learned from the buffers themselves.
    #else
    /// Source format, learned in the tap's prepare callback.
    #endif
    private var sampleRate: Double = 44_100
    private var channelCount = 2
    private var isInterleaved = true

    /// Band definitions resolved to bin indices for the current sample rate.
    private let binLo: UnsafeMutablePointer<Int32>
    private let binHi: UnsafeMutablePointer<Int32>
    /// Current window edges in dB, tracking the level this band is producing.
    private let windowHiDB: UnsafeMutablePointer<Float>
    private let windowLoDB: UnsafeMutablePointer<Float>

    init() {
        let n = Self.fftSize
        levels = .allocate(capacity: AudioSpectrum.bandCount)
        levels.initialize(repeating: 0, count: AudioSpectrum.bandCount)
        liveFlag = .allocate(capacity: 1)
        liveFlag.initialize(to: 0)
        window = .allocate(capacity: n)
        mono = .allocate(capacity: n)
        ring = .allocate(capacity: n)
        ring.initialize(repeating: 0, count: n)
        realp = .allocate(capacity: Self.binCount)
        imagp = .allocate(capacity: Self.binCount)
        magnitudes = .allocate(capacity: Self.binCount)
        previousMagnitudes = .allocate(capacity: Self.binCount)
        previousMagnitudes.initialize(repeating: 0, count: Self.binCount)
        detectors = .allocate(capacity: AudioSpectrum.bandCount)
        detectors.initialize(repeating: SpectrumOnsetDetector(), count: AudioSpectrum.bandCount)
        binLo = .allocate(capacity: AudioSpectrum.bandCount)
        binHi = .allocate(capacity: AudioSpectrum.bandCount)
        windowHiDB = .allocate(capacity: AudioSpectrum.bandCount)
        windowLoDB = .allocate(capacity: AudioSpectrum.bandCount)
        fftSetup = vDSP_create_fftsetup(Self.log2n, FFTRadix(kFFTRadix2))
        vDSP_hann_window(window, vDSP_Length(n), Int32(vDSP_HANN_NORM))
        // Seeded for the common rate; `adopt(format:)` corrects it if the source
        // turns out to be 48kHz or Hi-Res.
        for i in 0..<AudioSpectrum.bandCount {
            let band = Self.bandEdges[i]
            let binWidth = Float(44_100) / Float(n)
            binLo[i] = Int32(max(1, Int(band.low / binWidth)))
            binHi[i] = Int32(min(Self.binCount - 1, Int(band.high / binWidth)))
            windowHiDB[i] = band.ceilingDB
            windowLoDB[i] = band.floorDB
        }
    }

    deinit {
        previousMagnitudes.deallocate()
        detectors.deinitialize(count: AudioSpectrum.bandCount)
        detectors.deallocate()
        levels.deallocate()
        liveFlag.deallocate()
        window.deallocate()
        mono.deallocate()
        ring.deallocate()
        realp.deallocate()
        imagp.deallocate()
        magnitudes.deallocate()
        binLo.deallocate()
        binHi.deallocate()
        windowHiDB.deallocate()
        windowLoDB.deallocate()
        if let fftSetup { vDSP_destroy_fftsetup(fftSetup) }
    }

    var isLive: Bool { liveFlag.pointee != 0 }

    func level(at index: Int) -> Float {
        guard index >= 0, index < AudioSpectrum.bandCount else { return 0 }
        return levels[index]
    }

    func reset() {
        for i in 0..<AudioSpectrum.bandCount {
            levels[i] = 0
            // Start each track from the calibrated window rather than inheriting
            // the last one's loudness.
            let band = Self.bandEdges[i]
            windowHiDB[i] = band.ceilingDB
            windowLoDB[i] = band.floorDB
        }
        ringFill = 0
        previousMagnitudes.update(repeating: 0, count: Self.binCount)
        for i in 0..<AudioSpectrum.bandCount { detectors[i] = SpectrumOnsetDetector() }
        pendingBass = 0
        pendingMelody = 0
        _ = onsets.take(now: ProcessInfo.processInfo.systemUptime)
        liveFlag.pointee = 0
    }

    // MARK: PCM input

    /// Analyze one buffer from the engine's mixer tap.
    ///
    /// The mixer hands us non-interleaved float in practice; `process` reads the
    /// first buffer of the list either way, which is the left channel there and
    /// the interleaved frames if the format ever changes under us.
    func ingest(_ buffer: AVAudioPCMBuffer) {
        adoptIfNeeded(buffer.format.streamDescription.pointee)
        process(buffer.mutableAudioBufferList, frames: Int(buffer.frameLength))
    }

    /// Re-resolve the band bins when the source format actually changes.
    /// Called per buffer, so the common case must be the early return: `adopt`
    /// also re-seeds the tracking windows, and doing that every buffer would
    /// freeze them at their calibrated defaults.
    private func adoptIfNeeded(_ format: AudioStreamBasicDescription) {
        let interleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0
        guard format.mSampleRate != sampleRate
            || Int(format.mChannelsPerFrame) != channelCount
            || interleaved != isInterleaved else { return }
        adopt(format: format)
    }
    private func adopt(format: AudioStreamBasicDescription) {
        reset()
        sampleRate = format.mSampleRate > 0 ? format.mSampleRate : 44_100
        channelCount = max(1, Int(format.mChannelsPerFrame))
        isInterleaved = (format.mFormatFlags & kAudioFormatFlagIsNonInterleaved) == 0

        // Resolve each band to bin indices once, here, so the process callback
        // touches nothing but plain buffers — iterating a Swift array of tuples
        // on a real-time thread risks retain traffic and lazy-init locks.
        let binWidth = Float(sampleRate) / Float(Self.fftSize)
        for i in 0..<AudioSpectrum.bandCount {
            let band = Self.bandEdges[i]
            binLo[i] = Int32(max(1, Int(band.low / binWidth)))
            binHi[i] = Int32(min(Self.binCount - 1, Int(band.high / binWidth)))
            windowHiDB[i] = band.ceilingDB
            windowLoDB[i] = band.floorDB
        }
    }

    // MARK: Audio-thread analysis

    /// Frequency bands, each with its own dB window.
    ///
    /// Music falls off steeply with frequency — measured across tracks, presence
    /// sits some 30dB under bass — so one shared window would peg the low bars and
    /// leave the high ones flat on the floor. The windows below were calibrated
    /// from real material so every bar spends its time in the visible middle.
    private static let bandEdges: [(low: Float, high: Float, floorDB: Float, ceilingDB: Float)] = [
        (60, 250, -44, -20),
        (250, 800, -46, -26),
        (800, 2_500, -62, -36),
        (2_500, 8_000, -72, -50),
    ]

    /// Envelope time constants in seconds: rise fast so transients register,
    /// fall slowly so the bars read as motion rather than flicker. A slow release
    /// smears beats together and the bars stop reading as movement at all.
    private static let attackSeconds: Float = 0.03
    private static let releaseSeconds: Float = 0.16

    /// Each band's window tracks both edges of the level it actually sees.
    ///
    /// A fixed window can't serve both a sparse acoustic mix and a dense,
    /// heavily-limited one. The loud mix doesn't merely sit higher — it barely
    /// moves, riding a few dB under its limiter, so any window wide enough for
    /// the acoustic track renders it as four motionless bars. Tracking both
    /// edges lets the window slide *and* close in, so a small dynamic range is
    /// spread across the full height instead of vanishing.
    ///
    /// How fast the window closes back in once the extremes stop arriving. Slow
    /// enough that the window describes the passage, not the current beat.
    private static let windowRelaxDBPerSecond: Float = 1.0

    /// How fast each edge reaches out to a new extreme. Snapping to the exact
    /// min/max instead lets one freak-quiet frame set the floor tens of dB below
    /// anything the music does, and the window then describes that outlier for
    /// the rest of the song. The lower edge is the more exposed of the two, so
    /// it moves more cautiously.
    private static let windowRiseSeconds: Float = 0.15
    private static let windowFallSeconds: Float = 0.5

    /// Never let the window close below this, or a quiet passage gets stretched
    /// until its noise floor looks like music.
    private static let minWindowDB: Float = 6

    /// Nor let it open wider than this. Without a cap, one outlier sets an edge
    /// that takes minutes to relax back, and everything in between reads flat.
    private static let maxWindowDB: Float = 42

    /// Frames below this carry no signal at all — digital silence lands near
    /// -180dB. They must not touch the window, or leading silence drags its
    /// floor to the numeric bottom and the whole track plays out against it.
    private static let noSignalDB: Float = -95

    /// A band whose upper edge sits below this reads as silence.
    private static let silenceDB: Float = -70


    fileprivate func process(_ bufferList: UnsafeMutablePointer<AudioBufferList>, frames: Int) {
        guard frames > 0 else { return }
        let abl = UnsafeMutableAudioBufferListPointer(bufferList)
        guard let first = abl.first, let raw = first.mData else { return }

        let n = Self.fftSize
        let src = raw.bindMemory(to: Float.self,
                                 capacity: Int(first.mDataByteSize) / MemoryLayout<Float>.size)
        let floatCount = Int(first.mDataByteSize) / MemoryLayout<Float>.size
        let available = isInterleaved && channelCount > 1
            ? min(frames, floatCount / channelCount)
            : min(frames, floatCount)
        guard available > 0 else { return }

        // Keep incomplete windows across callbacks and overlap by half a window.
        // Both planar and interleaved stereo contribute, including right-only audio.
        let right = !isInterleaved && abl.count > 1 ? abl[1] : nil
        let rightSamples = right?.mData?.assumingMemoryBound(to: Float.self)
        let rightCount = right.map { Int($0.mDataByteSize) / MemoryLayout<Float>.size } ?? 0
        for frame in 0..<available {
            let left = src[isInterleaved ? frame * channelCount : frame]
            let other: Float
            if isInterleaved && channelCount > 1 {
                other = src[frame * channelCount + 1]
            } else if let rightSamples, frame < rightCount {
                other = rightSamples[frame]
            } else {
                other = left
            }
            let value = (left + other) * 0.5
            ring[ringFill] = value.isFinite ? value : 0
            ringFill += 1
            if ringFill == n {
                analyze(blockFrames: n / 2)
                memmove(ring, ring.advanced(by: n / 2), n / 2 * MemoryLayout<Float>.size)
                ringFill = n / 2
            }
        }
    }

    /// One FFT over `ring`, folded into the published levels.
    private func analyze(blockFrames: Int) {
        guard let fftSetup else { return }
        let n = Self.fftSize
        let take = blockFrames

        vDSP_vmul(ring, 1, window, 1, mono, 1, vDSP_Length(n))

        var split = DSPSplitComplex(realp: realp, imagp: imagp)
        mono.withMemoryRebound(to: DSPComplex.self, capacity: n / 2) { ptr in
            vDSP_ctoz(ptr, 2, &split, 1, vDSP_Length(n / 2))
        }
        vDSP_fft_zrip(fftSetup, &split, 1, Self.log2n, FFTDirection(FFT_FORWARD))
        vDSP_zvabs(&split, 1, magnitudes, 1, vDSP_Length(Self.binCount))

        // vDSP's real FFT returns doubled magnitudes; scale back before dB.
        var scale: Float = 1.0 / Float(2 * n)
        vDSP_vsmul(magnitudes, 1, &scale, magnitudes, 1, vDSP_Length(Self.binCount))

        var sawSignal = false

        // Smoothing coefficients derived from elapsed time, so the envelope
        // behaves the same whatever buffer size the tap hands us.
        let dt = Float(take) / Float(sampleRate)
        let attackCoefficient = 1 - expf(-dt / Self.attackSeconds)
        let releaseCoefficient = 1 - expf(-dt / Self.releaseSeconds)
        let relax = Self.windowRelaxDBPerSecond * dt
        let riseCoefficient = 1 - expf(-dt / Self.windowRiseSeconds)
        let fallCoefficient = 1 - expf(-dt / Self.windowFallSeconds)

        pendingBass *= expf(-dt / 0.15)
        pendingMelody *= expf(-dt / 0.15)
        for i in 0..<AudioSpectrum.bandCount {
            let lo = Int(binLo[i])
            let hi = Int(binHi[i])
            guard hi >= lo else { continue }

            var sum: Float = 0
            vDSP_sve(magnitudes.advanced(by: lo), 1, &sum, vDSP_Length(hi - lo + 1))
            let mean = sum / Float(hi - lo + 1)
            if mean > 1e-7 { sawSignal = true }

            let db = 20 * log10f(max(mean, 1e-9))
            // Log compression makes changes in softer partials useful without
            // letting a loud sustained fundamental dominate the onset measure.
            var flux: Float = 0
            for bin in lo...hi {
                let compressed = log1pf(magnitudes[bin] * 1000)
                flux += max(0, compressed - previousMagnitudes[bin])
            }
            flux /= Float(hi - lo + 1)
            let onset = detectors[i].advance(flux: flux, audible: db > Self.silenceDB, delta: dt)
            if i == 0 { pendingBass = max(pendingBass, onset) }
            if i == 1 || i == 2 { pendingMelody = max(pendingMelody, onset) }

            // Move the window's edges toward what this band is actually doing:
            // snap out to a new extreme, creep back in otherwise.
            var hiDB = windowHiDB[i]
            var loDB = windowLoDB[i]
            // Reach out toward a new extreme, relax back when none arrives.
            // Silent frames are skipped entirely.
            if db > Self.noSignalDB {
                if db > hiDB { hiDB += (db - hiDB) * riseCoefficient } else { hiDB -= relax }
                if db < loDB { loDB += (db - loDB) * fallCoefficient } else { loDB += relax }
                if hiDB - loDB > Self.maxWindowDB {
                    loDB = hiDB - Self.maxWindowDB
                }
                if hiDB - loDB < Self.minWindowDB {
                    let mid = (hiDB + loDB) * 0.5
                    hiDB = mid + Self.minWindowDB * 0.5
                    loDB = mid - Self.minWindowDB * 0.5
                }
            }
            windowHiDB[i] = hiDB
            windowLoDB[i] = loDB

            var target: Float = 0
            if hiDB > Self.silenceDB {
                target = (db - loDB) / (hiDB - loDB)
                target = min(max(target, 0), 1)
            }

            let previous = levels[i]
            let coefficient = target > previous ? attackCoefficient : releaseCoefficient
            levels[i] = previous + (target - previous) * coefficient
        }

        for bin in 0..<Self.binCount {
            previousMagnitudes[bin] = log1pf(magnitudes[bin] * 1000)
        }
        if onsets.publish(bass: pendingBass, melody: pendingMelody,
                          now: ProcessInfo.processInfo.systemUptime) {
            pendingBass = 0
            pendingMelody = 0
        }
        if sawSignal { liveFlag.pointee = 1 }
    }
}
