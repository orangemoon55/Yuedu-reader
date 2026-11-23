import Foundation
import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@Suite("Qingyun Night Copper", .serialized)
struct QingyunNightCopperThemeTests {
    private typealias Migration = QingyunNightCopperRetirementMigration

    @Test("removed built-in is not selectable; classic keeps System light and dark")
    @MainActor
    func palette() {
        #expect(AppearanceThemePreset.preset(id: Migration.retiredThemeID) == nil)
        #expect(AppearanceThemePreset.freeSolidPresets.count == 6)
        #expect(!AppearanceThemePreset.allDefaultPresets.contains { $0.id == Migration.retiredThemeID })
        let settings = GlobalSettings.shared
        let savedApplying = settings.isApplyingAppearanceExtras
        let savedPreview = settings.appearanceSlotPreview
        settings.appearanceSlotPreview = nil
        let saved = (settings.appearanceThemeID, settings.appearanceDarkThemeID,
                     settings.appearanceUsesSeparateDarkTheme, settings.appearanceFollowsSystem,
                     settings.appearancePinnedColorScheme)
        settings.isApplyingAppearanceExtras = true
        defer {
            settings.appearanceThemeID = saved.0
            settings.appearanceDarkThemeID = saved.1
            settings.appearanceUsesSeparateDarkTheme = saved.2
            settings.appearanceFollowsSystem = saved.3
            settings.appearancePinnedColorScheme = saved.4
            settings.appearanceSlotPreview = savedPreview
            settings.isApplyingAppearanceExtras = savedApplying
        }
        // A stale ID also resolves safely before the next launch migration.
        settings.appearanceThemeID = Migration.retiredThemeID
        settings.appearanceDarkThemeID = "unavailable-pack"
        settings.appearanceUsesSeparateDarkTheme = true
        settings.appearanceFollowsSystem = true
        settings.appearancePinnedColorScheme = .dark
        #expect(settings.appearanceWindowColorScheme == nil)
        for scheme in [ColorScheme.light, .dark] {
            #expect(settings.effectiveAppearanceColorScheme(systemColorScheme: scheme) == scheme)
            #expect(settings.appearanceBaseTheme(for: scheme, isProActive: false).isClassic)
            #expect(settings.appThemeOnScreen(for: scheme, isProActive: false,
                                             hasResolvedEntitlements: true) == nil)
        }
    }

    @Test("installed build 11 restores saved raw selection and only artwork; second run is inert")
    func migratesOnce() throws {
        try withDefaults { defaults in
            seedBuild11(defaults)
            let custom = AppearanceCustomTheme(id: "old-theme", name: "My imported pack",
                backgroundHex: 0xF0F0F0, textHex: 0x333333, barHex: 0xFFFFFF,
                accentHex: 0x3377FF, dialogueHex: 0xEEEEEE)
            var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(custom)) as? [String: Any])
            json["futureField"] = ["retain": true]
            let untouched: [String: Any] = [
                "yd_global_font_postscript": "ExistingGlobalFont",
                "yd_reader_font_postscript": "ExistingReaderFont",
                "yd_reader_font_size": 23.5,
                "yd_page_margin_h": 31.0,
                "yd_root_tab_visible_ids": ["bookshelf", "settings"],
                "yd_root_tab_order_ids": ["settings", "bookshelf"],
                "yd_root_tab_icon_assets": Data("icons".utf8),
                "yd_custom_appearance_themes": try JSONSerialization.data(withJSONObject: [json]),
                "yd_appearance_extras_baseline": Data("baseline unchanged".utf8),
                "yd_reading_settings_global": Data("shared setup unchanged".utf8),
                "yd_reading_settings_builtin_themes": Data("{\"night_copper\":{\"future\":1},\"classic\":{}}".utf8),
                "yd_reader_custom_backgrounds": Data("reader backgrounds".utf8),
                "yd_appearance_bind_reader_theme": false,
                "yd_reader_theme": "護眼綠",
                "yd_reader_progress": 0.75,
                "yd_book_sources": Data("sources".utf8),
                "yd_chapter_cache": Data("cached chapters".utf8),
                "qy_night_copper_build11_completed": true,
            ]
            for (key, value) in untouched { defaults.set(value, forKey: key) }
            let previous: [String: Any] = [
                Migration.selectionKeys[0]: "old-theme", Migration.selectionKeys[1]: "ocean_blue",
                Migration.selectionKeys[2]: true, Migration.selectionKeys[3]: true,
                Migration.selectionKeys[4]: "light", Migration.selectionKeys[5]: "light",
            ]
            defaults.set(previous, forKey: Migration.previousAppearanceKey)
            var artwork = AppearanceThemeExtras()
            artwork.pageBackgrounds = ["global": .init(lightImageFileName: "kept-page.jpg")]
            artwork.cardBackground = .init(light: .init(imageFileName: "kept-card.png"))
            // A poisoned unrelated field must never be replayed.
            artwork.globalFontPostScript = "DoNotRestore"
            artwork.visibleTabIDs = ["rss"]
            let backup = try JSONEncoder().encode(artwork)
            defaults.set(backup, forKey: Migration.artworkBaselineKey)
            #expect(Migration.runIfNeeded(defaults: defaults))
            for key in Migration.selectionKeys {
                #expect(NSDictionary(dictionary: [key: defaults.object(forKey: key)!]).isEqual(to: [key: previous[key]!]))
            }
            for (key, value) in untouched {
                let actual = try #require(defaults.object(forKey: key))
                #expect(NSDictionary(dictionary: [key: actual]).isEqual(to: [key: value]))
            }
            let pages = try #require(defaults.data(forKey: "yd_appearance_page_backgrounds"))
            #expect(try JSONDecoder().decode([String: AppearancePageBackgroundConfig].self, from: pages) == artwork.pageBackgrounds)
            let card = try #require(defaults.data(forKey: "yd_appearance_card_background"))
            #expect(try JSONDecoder().decode(AppearanceCardBackground.self, from: card) == artwork.cardBackground)
            #expect(defaults.data(forKey: Migration.artworkBaselineKey) == backup)
            #expect(NSDictionary(dictionary: defaults.dictionary(forKey: Migration.previousAppearanceKey)!).isEqual(to: previous))
            let after = defaults.dictionaryRepresentation()
            #expect(!Migration.runIfNeeded(defaults: defaults))
            #expect(NSDictionary(dictionary: defaults.dictionaryRepresentation()).isEqual(to: after))
        }
    }

    @Test("missing or damaged backup returns to classic/System without touching a damaged theme store")
    func missingOrDamagedBackup() throws {
        let backups: [Any?] = [nil, Data("broken".utf8),
                              [Migration.selectionKeys[0]: 42],
                              [Migration.selectionKeys[4]: "invalid-scheme"]]
        for backup in backups {
            try withDefaults { defaults in
                seedBuild11(defaults)
                if let backup { defaults.set(backup, forKey: Migration.previousAppearanceKey) }
                let damagedThemes = Data("unreadable custom themes".utf8)
                defaults.set(damagedThemes, forKey: GlobalSettings.customAppearanceThemesKey)
                #expect(Migration.runIfNeeded(defaults: defaults))
                for key in Migration.selectionKeys.prefix(2) {
                    #expect(defaults.string(forKey: key) == GlobalSettings.defaultAppearanceThemeID)
                }
                for key in Migration.selectionKeys.dropFirst(2) { #expect(defaults.object(forKey: key) == nil) }
                #expect(defaults.data(forKey: GlobalSettings.customAppearanceThemesKey) == damagedThemes)
            }
        }
    }

    @Test("absent original keys remain absent; deleted original theme falls back to classic")
    func sparseOrDeletedSelection() throws {
        let backups: [[String: Any]] = [[:], [Migration.selectionKeys[0]: "deleted-pack"]]
        for previous in backups {
            try withDefaults { defaults in
                seedBuild11(defaults)
                defaults.set(previous, forKey: Migration.previousAppearanceKey)
                #expect(Migration.runIfNeeded(defaults: defaults))
                if previous.isEmpty {
                    #expect(defaults.object(forKey: Migration.selectionKeys[0]) == nil)
                } else {
                    #expect(defaults.string(forKey: Migration.selectionKeys[0]) == GlobalSettings.defaultAppearanceThemeID)
                }
                for key in Migration.selectionKeys.dropFirst() { #expect(defaults.object(forKey: key) == nil) }
            }
        }
    }

    @Test("a later custom choice and its flags/artwork win over the build 11 backup")
    func respectsNewerCustomSelection() throws {
        for customIsOnScreen in [true, false] {
            try withDefaults { defaults in
                seedBuild11(defaults)
                let custom = AppearanceCustomTheme(id: "new-pack", name: "New pack",
                    backgroundHex: 1, textHex: 2, barHex: 3, accentHex: 4, dialogueHex: 5)
                let themes = try JSONEncoder().encode([custom])
                defaults.set(themes, forKey: GlobalSettings.customAppearanceThemesKey)
                defaults.set("new-pack", forKey: Migration.selectionKeys[0])
                defaults.set(!customIsOnScreen, forKey: Migration.selectionKeys[2])
                defaults.set([Migration.selectionKeys[0]: "forest_green"], forKey: Migration.previousAppearanceKey)
                defaults.set(Data("{\"pageBackgrounds\":{}}".utf8), forKey: Migration.artworkBaselineKey)
                let livePages = Data("new artwork".utf8)
                defaults.set(livePages, forKey: "yd_appearance_page_backgrounds")
                let before = defaults.dictionaryRepresentation()
                #expect(!Migration.runIfNeeded(defaults: defaults))
                #expect(defaults.string(forKey: Migration.selectionKeys[0]) == "new-pack")
                #expect(defaults.string(forKey: Migration.selectionKeys[1]) == GlobalSettings.defaultAppearanceThemeID)
                for key in Migration.selectionKeys.dropFirst(2) {
                    #expect(NSDictionary(dictionary: [key: defaults.object(forKey: key)!]).isEqual(to: [key: before[key]!]))
                }
                #expect(defaults.data(forKey: "yd_appearance_page_backgrounds") == livePages)
                #expect(defaults.data(forKey: GlobalSettings.customAppearanceThemesKey) == themes)
            }
        }
    }

    @Test("an imported theme with the retired identifier remains user-owned")
    func customIdentifierCollision() throws {
        try withDefaults { defaults in
            seedBuild11(defaults)
            let custom = AppearanceCustomTheme(id: Migration.retiredThemeID, name: "Imported",
                backgroundHex: 1, textHex: 2, barHex: 3, accentHex: 4, dialogueHex: 5)
            let themes = try JSONEncoder().encode([custom])
            defaults.set(themes, forKey: GlobalSettings.customAppearanceThemesKey)
            #expect(!Migration.runIfNeeded(defaults: defaults))
            #expect(defaults.string(forKey: Migration.selectionKeys[0]) == custom.id)
            #expect(defaults.data(forKey: GlobalSettings.customAppearanceThemesKey) == themes)
            #expect(AppearanceThemePreset.preset(id: custom.id, customThemes: [custom])?.isCustom == true)
        }
    }

    @Test("missing/damaged artwork stays untouched; valid layers restore independently")
    func damagedArtwork() throws {
        let backups: [String?] = [nil, "broken", "[]", "{}", "{\"pageBackgrounds\":42,\"cardBackground\":false}"]
        for backup in backups {
            try withDefaults { defaults in
                seedBuild11(defaults)
                let pages = Data("live pages".utf8), card = Data("live card".utf8)
                defaults.set(pages, forKey: "yd_appearance_page_backgrounds")
                defaults.set(card, forKey: "yd_appearance_card_background")
                if let backup { defaults.set(Data(backup.utf8), forKey: Migration.artworkBaselineKey) }
                #expect(Migration.runIfNeeded(defaults: defaults))
                #expect(defaults.data(forKey: "yd_appearance_page_backgrounds") == pages)
                #expect(defaults.data(forKey: "yd_appearance_card_background") == card)
            }
        }
        try withDefaults { defaults in
            seedBuild11(defaults)
            let card = Data("live card".utf8)
            defaults.set(card, forKey: "yd_appearance_card_background")
            defaults.set(Data("{\"pageBackgrounds\":{},\"cardBackground\":42}".utf8), forKey: Migration.artworkBaselineKey)
            #expect(Migration.runIfNeeded(defaults: defaults))
            let pages = try #require(defaults.data(forKey: "yd_appearance_page_backgrounds"))
            #expect(try JSONDecoder().decode([String: AppearancePageBackgroundConfig].self, from: pages).isEmpty)
            #expect(defaults.data(forKey: "yd_appearance_card_background") == card)
        }
        try withDefaults { defaults in
            seedBuild11(defaults)
            defaults.set(Data("live card".utf8), forKey: "yd_appearance_card_background")
            defaults.set(Data("{\"pageBackgrounds\":{}}".utf8), forKey: Migration.artworkBaselineKey)
            #expect(Migration.runIfNeeded(defaults: defaults))
            #expect(defaults.object(forKey: "yd_appearance_card_background") == nil)
        }
    }

    @Test("fresh installation never opts into Night Copper")
    func newInstall() throws {
        try withDefaults { defaults in
            #expect(!Migration.runIfNeeded(defaults: defaults))
            for key in Migration.selectionKeys { #expect(defaults.object(forKey: key) == nil) }
        }
    }

    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suite = "NightCopperRetirement-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(defaults)
    }

    private func seedBuild11(_ defaults: UserDefaults) {
        defaults.set(Migration.retiredThemeID, forKey: Migration.selectionKeys[0])
        defaults.set(Migration.retiredThemeID, forKey: Migration.selectionKeys[1])
        defaults.set(false, forKey: Migration.selectionKeys[2])
        defaults.set(false, forKey: Migration.selectionKeys[3])
        defaults.set("dark", forKey: Migration.selectionKeys[4])
        defaults.set("dark", forKey: Migration.selectionKeys[5])
        defaults.set(true, forKey: "qy_night_copper_build11_completed")
    }
}
