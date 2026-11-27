// SPDX-License-Identifier: GPL-3.0-only
// Adapted from youshen2/MeloX, commit a41ea0e1e1fa69fb543d827b853fe3aff5420951.
// Source: MeloX/Features/Player/Lyrics/Shared/TimedLyricTextBuilder.swift
// Adapted for integration with Coda. See ThirdPartyNotices/MeloX.md.
import Foundation

@MainActor
enum TimedLyricTextBuilder {
    private static var cache: [[LyricSyllable]: [LyricTimingTextAttribute]] = [:]
    static func attributes(from syllables: [LyricSyllable]) -> [LyricTimingTextAttribute] {
        if let cached = cache[syllables] { return cached }
        let characters = timedCharacters(from: syllables)
        let words = wordTimings(for: characters, source: characters.map(\.text).joined())
        let result = characters.enumerated().map { index, character in
            let word = words[index]
            return LyricTimingTextAttribute(
                startTime: character.startTime, endTime: character.endTime,
                syllableStartTime: character.syllableStartTime, syllableEndTime: character.syllableEndTime,
                characterIndex: character.characterIndex, characterCount: character.characterCount,
                wordStartTime: word.startTime, wordEndTime: word.endTime,
                wordCharacterIndex: word.characterIndex, wordCharacterCount: word.characterCount,
                usesWordTimingForLongTone: word.usesWordTimingForLongTone, isWhitespace: character.isWhitespace)
        }
        if cache.count >= 256, let first = cache.keys.first { cache.removeValue(forKey: first) }
        cache[syllables] = result
        return result
    }
    private static func wordTimings(
        for characters: [TimedCharacter],
        source: String
    ) -> [WordTiming] {
        var result = characters.map { character in
            WordTiming(
                startTime: character.startTime,
                endTime: character.endTime,
                characterIndex: 0,
                characterCount: 1,
                usesWordTimingForLongTone: false
            )
        }

        for range in LyricWordSegmenter.blockRanges(in: source) {
            guard range.lowerBound >= characters.startIndex,
                  range.upperBound <= characters.endIndex,
                  range.lowerBound < range.upperBound else {
                continue
            }

            let timedIndices = range.filter {
                !characters[$0].isWhitespace
            }
            guard let startTime = timedIndices
                .map({ characters[$0].startTime })
                .min(),
                let endTime = timedIndices
                    .map({ characters[$0].endTime })
                    .max() else {
                continue
            }
            let characterPositions = Dictionary(
                uniqueKeysWithValues: timedIndices.enumerated().map {
                    ($0.element, $0.offset)
                }
            )
            let usesWordTimingForLongTone =
                timedIndices.count > 1
                    && timedIndices.allSatisfy {
                        characters[$0].isLatinLetter
                    }
            for index in range {
                result[index] = WordTiming(
                    startTime: startTime,
                    endTime: endTime,
                    characterIndex:
                        characterPositions[index]
                            ?? max(timedIndices.count - 1, 0),
                    characterCount: max(timedIndices.count, 1),
                    usesWordTimingForLongTone:
                        usesWordTimingForLongTone
                )
            }
        }
        return result
    }

    private static func timedCharacters(
        from syllables: [LyricSyllable]
    ) -> [TimedCharacter] {
        syllables.flatMap { syllable -> [TimedCharacter] in
            let characters = Array(syllable.text)
            guard !characters.isEmpty else { return [] }

            let duration = max(
                syllable.endTime - syllable.startTime,
                0
            )
            let characterDuration = duration / Double(characters.count)

            return characters.enumerated().map { entry in
                let startTime = syllable.startTime
                    + Double(entry.offset) * characterDuration
                let endTime = entry.offset == characters.count - 1
                    ? max(syllable.endTime, startTime)
                    : startTime + characterDuration
                return TimedCharacter(
                    text: String(entry.element),
                    startTime: startTime,
                    endTime: endTime,
                    syllableStartTime: syllable.startTime,
                    syllableEndTime: syllable.endTime,
                    characterIndex: entry.offset,
                    characterCount: characters.count
                )
            }
        }
    }


    struct WordTiming {
        let startTime: TimeInterval
        let endTime: TimeInterval
        let characterIndex: Int
        let characterCount: Int
        let usesWordTimingForLongTone: Bool
    }

    struct TimedCharacter {
        let text: String
        let startTime: TimeInterval
        let endTime: TimeInterval
        let syllableStartTime: TimeInterval
        let syllableEndTime: TimeInterval
        let characterIndex: Int
        let characterCount: Int

        var isLineBreak: Bool {
            text == "\n" || text == "\r" || text == "\r\n"
        }

        var isWhitespace: Bool {
            text.allSatisfy(\.isWhitespace)
        }

        var isLatinLetter: Bool {
            !text.isEmpty
                && text.unicodeScalars.allSatisfy { scalar in
                    (65...90).contains(scalar.value)
                        || (97...122).contains(scalar.value)
                }
        }
    }
}
