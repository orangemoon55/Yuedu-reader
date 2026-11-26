// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 jo32 and Yingxia contributors.
// Adapted from Yingxia (jo32/tvbox-silicon), Sources/TVCore/MusicQueue.swift,
// commit a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c (read-only upstream):
// https://github.com/jo32/tvbox-silicon/blob/a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c/Sources/TVCore/MusicQueue.swift
// Readcc adaptation: MusicTrack -> generic Track; retain the upstream index/clamp,
// navigation, bounded-failure and previous-restart algorithms. Omit collection,
// provider/rate-limit helpers, Codable and MusicLibrary/resume/history persistence.
// This queue is runtime-only: it never saves resolved URLs, headers or credentials.

/// The full ordered selection and its cursor, independent of AVQueuePlayer's consumed items.
struct YingxiaMusicQueue<Track> {
    private(set) var tracks: [Track]
    private(set) var index: Int

    init(tracks: [Track], start: Int = 0) {
        self.tracks = tracks
        index = tracks.isEmpty ? 0 : min(max(0, start), tracks.count - 1)
    }

    var current: Track? { tracks.indices.contains(index) ? tracks[index] : nil }
    var hasNext: Bool { index + 1 < tracks.count }
    var hasPrevious: Bool { index > 0 }

    @discardableResult mutating func advance() -> Track? {
        guard hasNext else { return nil }
        index += 1
        return current
    }

    @discardableResult mutating func back() -> Track? {
        guard hasPrevious else { return nil }
        index -= 1
        return current
    }

    @discardableResult mutating func jump(to position: Int) -> Track? {
        guard tracks.indices.contains(position) else { return nil }
        index = position
        return current
    }

    // Computed rather than stored because Swift generic types cannot have static stored properties.
    static var failuresBeforeStopping: Int { 3 }

    /// Upstream's request bound: skip two failed tracks, then stop on the third consecutive failure.
    func skipsAfterFailure(consecutive failures: Int, wraps: Bool = false) -> Bool {
        (hasNext || wraps && tracks.count > 1) && failures < Self.failuresBeforeStopping
    }

    /// Upstream restarts only AFTER three seconds; exactly three seconds still goes back.
    static var restartThreshold: Double { 3 }
}
