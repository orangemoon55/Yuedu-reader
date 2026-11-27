// SPDX-License-Identifier: GPL-3.0-only
// Adapted from youshen2/MeloX, commit a41ea0e1e1fa69fb543d827b853fe3aff5420951.
// Source: MeloX/Core/Lyrics/LyricModels.swift
// Adapted for integration with Coda. See ThirdPartyNotices/MeloX.md.
import Foundation

struct LyricSyllable: Identifiable, Hashable, Sendable {
    let text: String
    let startTime: TimeInterval
    let endTime: TimeInterval

    var id: String {
        "\(startTime)-\(endTime)-\(text)"
    }
}

enum LyricLineTimingKind: Hashable, Sendable {
    /// The line carries an authored content duration, usually from YRC.
    case precise

    /// LRC only tells us when this line is replaced by the next one. Its
    /// inferred display duration must not be treated as sung-content timing.
    case lineSynchronized
}

enum LyricAgentAlignment: Hashable, Sendable {
    case normal
    case flipped
}

enum LyricAgentKind: Hashable, Sendable {
    case person
    case group
}

struct LyricAgent: Hashable, Sendable {
    let identifier: String
    let displayName: String
    let kind: LyricAgentKind
    let alignment: LyricAgentAlignment
}

enum LyricVocalistsType: Hashable, Sendable {
    case single
    case duet
    case group

    static func resolve(in lines: [TimedLyricLine]) -> LyricVocalistsType {
        let agents = lines.compactMap(\.agent)
        let personIdentifiers = Set(
            agents
                .filter { $0.kind == .person }
                .map(\.identifier)
        )
        if agents.contains(where: { $0.kind == .group })
            || personIdentifiers.count > 2 {
            return .group
        }
        return personIdentifiers.count == 2 ? .duet : .single
    }
}

enum LyricBackgroundVocalsPosition: Hashable, Sendable {
    case beforePrimary
    case afterPrimary
}

struct LyricBackgroundVocal: Hashable, Sendable {
    let time: TimeInterval
    let duration: TimeInterval?
    let text: String
    let syllables: [LyricSyllable]
    let translation: String?
    let position: LyricBackgroundVocalsPosition

    func lyricLine(
        parentID: TimedLyricLine.ID,
        agent: LyricAgent?
    ) -> TimedLyricLine {
        TimedLyricLine(
            id: "\(parentID):background-vocal",
            time: time,
            duration: duration,
            text: text,
            syllables: syllables,
            translation: translation,
            agent: agent
        )
    }
}

struct TimedLyricLine: Identifiable, Hashable, Sendable {
    let id: String
    let time: TimeInterval
    let duration: TimeInterval?
    let timingKind: LyricLineTimingKind
    let text: String
    let syllables: [LyricSyllable]
    let romanization: String?
    let romanizationSyllables: [LyricSyllable]
    let translation: String?
    let agent: LyricAgent?
    let backgroundVocal: LyricBackgroundVocal?

    init(
        id: String? = nil,
        time: TimeInterval,
        duration: TimeInterval? = nil,
        timingKind: LyricLineTimingKind = .precise,
        text: String,
        syllables: [LyricSyllable] = [],
        romanization: String? = nil,
        romanizationSyllables: [LyricSyllable] = [],
        translation: String? = nil,
        agent: LyricAgent? = nil,
        backgroundVocal: LyricBackgroundVocal? = nil
    ) {
        self.id = id ?? Self.fallbackID(
            time: time,
            text: text
        )
        self.time = time
        self.duration = duration
        self.timingKind = timingKind
        self.text = text
        self.syllables = syllables
        self.romanization = romanization
        self.romanizationSyllables = romanizationSyllables
        self.translation = translation
        self.agent = agent
        self.backgroundVocal = backgroundVocal
    }

    init(
        id: String,
        copying line: TimedLyricLine
    ) {
        self.init(
            id: id,
            time: line.time,
            duration: line.duration,
            timingKind: line.timingKind,
            text: line.text,
            syllables: line.syllables,
            romanization: line.romanization,
            romanizationSyllables: line.romanizationSyllables,
            translation: line.translation,
            agent: line.agent,
            backgroundVocal: line.backgroundVocal
        )
    }

    var isSyllableSynced: Bool {
        !syllables.isEmpty
    }

    static func fallbackID(
        time: TimeInterval,
        text: String
    ) -> String {
        "line:\(time.bitPattern):\(Self.stableTextHash(text))"
    }

    static func stableTextHash(_ text: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in text.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    var hasTranslation: Bool {
        guard let translation else { return false }
        return !translation
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    var hasRomanization: Bool {
        guard let romanization else { return false }
        return !romanization
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    func makePseudoSyllables() -> [LyricSyllable] {
        guard syllables.isEmpty,
              let duration,
              duration > 0 else { return [] }

        let characters = Array(text)
        guard !characters.isEmpty else { return [] }

        let characterDuration = duration / Double(characters.count)
        return characters.enumerated().map { index, character in
            let startTime = time + Double(index) * characterDuration
            return LyricSyllable(
                text: String(character),
                startTime: startTime,
                endTime: startTime + characterDuration
            )
        }
    }

    func attachingTranslation(_ translation: String?) -> TimedLyricLine {
        TimedLyricLine(
            id: id,
            time: time,
            duration: duration,
            timingKind: timingKind,
            text: text,
            syllables: syllables,
            romanization: romanization,
            romanizationSyllables: romanizationSyllables,
            translation: translation,
            agent: agent,
            backgroundVocal: backgroundVocal
        )
    }

    func attachingRomanization(
        _ romanization: String?,
        romanizationSyllables: [LyricSyllable] = []
    ) -> TimedLyricLine {
        TimedLyricLine(
            id: id,
            time: time,
            duration: duration,
            timingKind: timingKind,
            text: text,
            syllables: syllables,
            romanization: romanization,
            romanizationSyllables: romanizationSyllables,
            translation: translation,
            agent: agent,
            backgroundVocal: backgroundVocal
        )
    }

    func attachingAgent(
        _ agent: LyricAgent?,
        text: String? = nil,
        syllables: [LyricSyllable]? = nil
    ) -> TimedLyricLine {
        TimedLyricLine(
            id: id,
            time: time,
            duration: duration,
            timingKind: timingKind,
            text: text ?? self.text,
            syllables: syllables ?? self.syllables,
            romanization: romanization,
            romanizationSyllables: romanizationSyllables,
            translation: translation,
            agent: agent,
            backgroundVocal: backgroundVocal
        )
    }

}
