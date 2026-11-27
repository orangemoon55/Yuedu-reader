import Combine
import Foundation

enum PreferenceValue: Codable, Equatable {
    case string(String), boolean(Bool), number(Double), strings([String])
}

struct PreferenceEdit: Codable, Equatable {
    let value: PreferenceValue
    let revision: SyncRevision
}

struct SyncedPreferences: Codable, Equatable {
    var fields: [String: PreferenceEdit] = [:]

    mutating func merge(_ other: Self) {
        fields.merge(other.fields) { local, remote in
            local.revision < remote.revision ? remote : local
        }
    }
}

extension SettingsManager {
    /// Keep the portable preference contract beside its projection and validation.
    var syncPreferenceChanges: AnyPublisher<Void, Never> {
        Publishers.MergeMany([
            $alwaysHighestAudioQuality.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $audioQuality.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $appearance.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $showLyricsTranslation.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $lyricsAnnotation.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $verbatimLyrics.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $showMainWindowAmbientBackground.removeDuplicates().map { _ in () }.eraseToAnyPublisher(),
            $mainWindowAmbientBackgroundIntensity.removeDuplicates().map { _ in () }.eraseToAnyPublisher()
        ]).eraseToAnyPublisher()
    }

    /// Explicit portable preferences; cache policy, output routing and platform
    /// layouts stay local. Unknown fields remain in SyncedPreferences for newer apps.
    var syncPreferences: [String: PreferenceValue] {
        [Keys.quality: .string(audioQuality.rawValue),
         Keys.highestQuality: .boolean(alwaysHighestAudioQuality),
         Keys.appearance: .string(appearance.rawValue),
         Keys.showTranslation: .boolean(showLyricsTranslation),
         Keys.annotation: .string(lyricsAnnotation.rawValue),
         Keys.verbatimLyrics: .boolean(verbatimLyrics),
         Keys.mainWindowAmbientBackground: .boolean(showMainWindowAmbientBackground),
         Keys.mainWindowAmbientBackgroundIntensity: .number(mainWindowAmbientBackgroundIntensity)]
    }

    func applySyncPreferences(_ preferences: SyncedPreferences) throws {
        // Validate the entire known projection before any setter runs its side effects.
        for (key, edit) in preferences.fields {
            switch (key, edit.value) {
            case (Keys.quality, .string(let value)):
                guard AudioQuality(rawValue: value) != nil else { throw SyncError.invalidRecord }
            case (Keys.appearance, .string(let value)):
                guard AppAppearance(rawValue: value) != nil else { throw SyncError.invalidRecord }
            case (Keys.annotation, .string(let value)):
                guard LyricsAnnotation(rawValue: value) != nil else { throw SyncError.invalidRecord }
            case (Keys.mainWindowAmbientBackgroundIntensity, .number(let value)):
                guard value.isFinite, Self.mainWindowAmbientBackgroundIntensityRange.contains(value) else {
                    throw SyncError.invalidRecord
                }
            case (Keys.highestQuality, .boolean), (Keys.showTranslation, .boolean), (Keys.verbatimLyrics, .boolean),
                 (Keys.mainWindowAmbientBackground, .boolean): break
            case (Keys.highestQuality, _), (Keys.quality, _), (Keys.appearance, _), (Keys.annotation, _),
                 (Keys.mainWindowAmbientBackgroundIntensity, _), (Keys.showTranslation, _),
                 (Keys.verbatimLyrics, _), (Keys.mainWindowAmbientBackground, _):
                throw SyncError.invalidRecord
            default: break
            }
        }
        let current = syncPreferences
        for (key, edit) in preferences.fields where current[key] != edit.value {
            switch (key, edit.value) {
            case (Keys.quality, .string(let value)):
                if let quality = AudioQuality(rawValue: value) { audioQuality = quality }
            case (Keys.appearance, .string):
                break // Older devices may still sync a manual theme; follow the system here.
            case (Keys.annotation, .string(let value)):
                if let annotation = LyricsAnnotation(rawValue: value) { lyricsAnnotation = annotation }
            case (Keys.highestQuality, .boolean(let value)): alwaysHighestAudioQuality = value
            case (Keys.showTranslation, .boolean(let value)): showLyricsTranslation = value
            case (Keys.verbatimLyrics, .boolean): break // Word-by-word lyrics are always enabled.
            case (Keys.mainWindowAmbientBackground, .boolean): break // Main interface tint has been removed.
            case (Keys.mainWindowAmbientBackgroundIntensity, .number(let value)): mainWindowAmbientBackgroundIntensity = value
            default: break
            }
        }
    }
}
