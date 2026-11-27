// SPDX-License-Identifier: GPL-3.0-only
// Synchronization loop adapted from MeloX NowPlayingLyricSynchronizer.
// See ThirdPartyNotices/MeloX.md for source revision and integration changes.
import Combine
import Foundation

/// One lyric clock drives line focus, overlapping vocals and per-glyph progress.
/// Engine samples replace its anchor; neither SwiftUI nor the scrubber owns time.
@MainActor
final class LyricsCursor: ObservableObject {
    @Published var activeIndex: Int?
    @Published private(set) var activeIndices: Set<Int> = []
    @Published var seekRevision: UInt = 0 {
        didSet { restartTransitions() }
    }

    private var clock = LyricPlaybackClock()
    private var lyrics: ParsedLyrics?
    private var lines: [TimedLyricLine] = []
    private var indicesByID: [String: Int] = [:]
    private var rate: Double = 0
    private var duration: TimeInterval = 0
    private var advanceTime: TimeInterval = 0
    private var timeOffset: TimeInterval = 0
    private var transition: Task<Void, Never>?

    var playbackTime: TimeInterval { clock.position(duration: duration) + timeOffset }

    func timeUntilFocus(at lyricTime: TimeInterval) -> TimeInterval? {
        guard rate > 0 else { return nil }
        return (lyricTime - (playbackTime + advanceTime)) / rate
    }

    func synchronize(lyrics: ParsedLyrics?, at time: TimeInterval, playing: Bool,
                     rate: Double = 1, duration: TimeInterval = 0,
                     advanceTime: TimeInterval = 0, timeOffset: TimeInterval = 0, sampledAt date: Date = Date()) {
        guard time.isFinite, timeOffset.isFinite else { return }
        let changed = self.lyrics != lyrics
        let nextRate = playing && rate.isFinite ? max(rate, 0) : 0
        let stateChanged = nextRate != self.rate || advanceTime != self.advanceTime || timeOffset != self.timeOffset
        let previous = LyricPlaybackTimeline.position(
            at: clock.position(at: date, duration: self.duration) + self.timeOffset + self.advanceTime, in: lines)
        if changed {
            self.lyrics = lyrics
            lines = lyrics?.synchronizedLines ?? []
            indicesByID = Dictionary(uniqueKeysWithValues: lines.enumerated().map { ($0.element.id, $0.offset) })
        }
        self.duration = duration
        self.advanceTime = advanceTime
        self.timeOffset = timeOffset
        self.rate = nextRate
        // Reanchor the lyric clock to the engine sample before projecting the position.
        clock.reanchor(to: time, rate: nextRate, at: date)
        let current = publishPosition(at: date)
        if changed || stateChanged || transition == nil
            || previous.nextTransitionTime != current.nextTransitionTime {
            restartTransitions()
        }
    }

    @discardableResult
    private func publishPosition(at date: Date = Date()) -> LyricPlaybackPosition {
        let position = LyricPlaybackTimeline.position(
            at: clock.position(at: date, duration: duration) + timeOffset + advanceTime, in: lines)
        let index = position.highlightedLyricID.flatMap { indicesByID[$0] }
        let active = Set(position.activeLyricIDs.compactMap { indicesByID[$0] })
        if activeIndex != index { activeIndex = index }
        if activeIndices != active { activeIndices = active }
        return position
    }

    private func nextTransitionDelay() -> TimeInterval? {
        let position = publishPosition()
        guard let next = position.nextTransitionTime else { return nil }
        return timeUntilFocus(at: next)
    }

    private func restartTransitions() {
        transition?.cancel()
        transition = nil
        guard rate > 0, !lines.isEmpty else { return }
        // Schedule the next authored transition, then consult the
        // projected engine clock again. A seek/pause/source change cancels it.
        transition = Task { [weak self] in
            while !Task.isCancelled {
                guard let remaining = self?.nextTransitionDelay() else { return }
                guard remaining > 0 else {
                    await Task.yield()
                    continue
                }
                do { try await Task.sleep(for: .seconds(remaining)) }
                catch { return }
            }
        }
    }

    deinit { transition?.cancel() }
}
