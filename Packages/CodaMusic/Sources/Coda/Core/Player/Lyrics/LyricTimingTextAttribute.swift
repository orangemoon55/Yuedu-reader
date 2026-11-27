// SPDX-License-Identifier: GPL-3.0-only
// Adapted from youshen2/MeloX, commit a41ea0e1e1fa69fb543d827b853fe3aff5420951.
// Source: MeloX/Features/Player/Lyrics/Shared/LyricGlowTextRenderer.swift
// Adapted for integration with Coda. See ThirdPartyNotices/MeloX.md.
import Foundation

struct LyricTimingTextAttribute: Hashable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let syllableStartTime: TimeInterval
    let syllableEndTime: TimeInterval
    let characterIndex: Int
    let characterCount: Int
    let wordStartTime: TimeInterval
    let wordEndTime: TimeInterval
    let wordCharacterIndex: Int
    let wordCharacterCount: Int
    let usesWordTimingForLongTone: Bool
    let isWhitespace: Bool
}

enum LyricsLongSyllableDetectionMode { case word, character }
