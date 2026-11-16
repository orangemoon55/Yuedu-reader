import Foundation
import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@Suite("Qingyun Night Copper", .serialized)
struct QingyunNightCopperThemeTests {
    @Test("free built-in is selectable and identical in both appearances")
    func palette() throws {
        let theme = try #require(AppearanceThemePreset.preset(id: AppearanceThemePreset.nightCopperID))
        #expect(theme.localizedName == "夜铜")
        #expect(!theme.requiresPro && !theme.isCustom && !theme.isImagePreset)
        #expect(AppearanceThemePreset.freeSolidPresets.contains { $0.id == theme.id })
        #expect(theme.imagePaths.isEmpty)
        for scheme in [ColorScheme.light, .dark] {
            let palette = theme.palette(for: scheme)
            #expect(palette.background.rgbHex == 0x15231E)
            #expect(palette.appCardBackground.rgbHex == 0x293A30)
            #expect(palette.appSecondaryBackground.rgbHex == 0x1B2923)
            #expect(palette.text.rgbHex == 0xEDE3CB)
            #expect(palette.accent.rgbHex == 0xD5B777)
            let labels = try #require(palette.authoredTextColors)
            #expect(labels.primary.rgbHex == 0xEDE3CB)
            #expect(labels.secondary.rgbHex == 0xC3B597)
            #expect(labels.tertiary.rgbHex == 0xA89C81)
            for surface in [palette.background, palette.appCardBackground, palette.appSecondaryBackground] {
                for foreground in [labels.primary, labels.secondary, palette.accent] {
                    #expect(contrast(foreground, surface) >= 4.5)
                }
                // The requested muted tertiary is 4.44:1 on the panel, 5.99:1
                // on the page; preserve that palette without claiming AA body text.
                #expect(contrast(labels.tertiary, surface) >= 3)
            }
        }
        #expect(theme.palette(for: .dark).isDarkAppearancePalette)
    }

    @Test("upgrade preserves fonts, layout, tabs and theme stores; never overrides later choices")
    func migratesOnce() throws {
        let suite = "NightCopper-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let untouched: [String: Any] = [
            "yd_global_font_postscript": "ExistingGlobalFont",
            "yd_reader_font_postscript": "ExistingReaderFont",
            "yd_reader_font_size": 23.5,
            "yd_page_margin_h": 31.0,
            "yd_root_tab_visible_ids": ["bookshelf", "settings"],
            "yd_root_tab_order_ids": ["settings", "bookshelf"],
            "yd_root_tab_icon_assets": Data("icons".utf8),
            "yd_custom_appearance_themes": Data("custom themes unchanged".utf8),
            "yd_appearance_extras_baseline": Data("baseline unchanged".utf8),
            "yd_appearance_page_backgrounds": Data("backgrounds unchanged by migration".utf8),
            "yd_reading_settings_global": Data("shared setup unchanged".utf8),
            "yd_appearance_bind_reader_theme": false,
        ]
        for (key, value) in untouched { defaults.set(value, forKey: key) }
        defaults.set("old-theme", forKey: "yd_appearance_theme_id")
        defaults.set("old-dark", forKey: "yd_appearance_dark_theme_id")
        let oldReading = ["classic": ["fontSize": 17.0, "futureField": "kept"]] as [String: Any]
        defaults.set(try JSONSerialization.data(withJSONObject: oldReading), forKey: "yd_reading_settings_builtin_themes")
        var reading = AppearanceThemeReadingSettings()
        reading.fontPostScript = "ExistingReaderFont"
        reading.fontSize = 23.5
        reading.lineHeightMultiple = 1.8
        reading.pageMarginH = 31
        reading.bindsAppearanceReaderTheme = false
        #expect(QingyunNightCopperThemeMigration.runIfNeeded(defaults: defaults, isStandalone: true, reading: reading))
        #expect(defaults.string(forKey: "yd_appearance_theme_id") == AppearanceThemePreset.nightCopperID)
        #expect(defaults.string(forKey: "yd_appearance_dark_theme_id") == AppearanceThemePreset.nightCopperID)
        #expect(defaults.string(forKey: "yd_appearance_pinned_color_scheme") == "dark")
        #expect(!defaults.bool(forKey: "yd_appearance_follows_system"))
        #expect(!defaults.bool(forKey: "yd_appearance_separate_dark_theme"))
        for (key, value) in untouched {
            let actual = try #require(defaults.object(forKey: key))
            #expect(NSDictionary(dictionary: [key: actual]).isEqual(to: [key: value]))
        }
        let data = try #require(defaults.data(forKey: "yd_reading_settings_builtin_themes"))
        let saved = try JSONDecoder().decode([String: AppearanceThemeReadingSettings].self, from: data)
        #expect(saved[AppearanceThemePreset.nightCopperID] == reading)
        let raw = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let classic = try #require(raw["classic"] as? [String: Any])
        #expect(classic["futureField"] as? String == "kept")
        let previous = try #require(defaults.dictionary(forKey: QingyunNightCopperThemeMigration.previousAppearanceKey))
        #expect(previous["yd_appearance_theme_id"] as? String == "old-theme")
        defaults.set("user-picked-theme", forKey: "yd_appearance_theme_id")
        defaults.set(true, forKey: "yd_appearance_follows_system")
        #expect(!QingyunNightCopperThemeMigration.runIfNeeded(defaults: defaults, isStandalone: true, reading: .init()))
        #expect(defaults.string(forKey: "yd_appearance_theme_id") == "user-picked-theme")
        #expect(defaults.bool(forKey: "yd_appearance_follows_system"))
        #expect(defaults.data(forKey: "yd_reading_settings_builtin_themes") == data)
    }

    @Test("upstream builds and unreadable reading stores are untouched")
    func doesNotForceUpstreamOrDiscardCorruptStore() throws {
        let suite = "NightCopperGate-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("custom", forKey: "yd_appearance_theme_id")
        #expect(!QingyunNightCopperThemeMigration.runIfNeeded(defaults: defaults, isStandalone: false, reading: .init()))
        #expect(!defaults.bool(forKey: QingyunNightCopperThemeMigration.completedKey))
        let corrupt = Data("unreadable".utf8)
        defaults.set(corrupt, forKey: "yd_reading_settings_builtin_themes")
        #expect(!QingyunNightCopperThemeMigration.runIfNeeded(defaults: defaults, isStandalone: true, reading: .init()))
        #expect(defaults.string(forKey: "yd_appearance_theme_id") == "custom")
        #expect(defaults.data(forKey: "yd_reading_settings_builtin_themes") == corrupt)
        #expect(!defaults.bool(forKey: QingyunNightCopperThemeMigration.completedKey))
    }

    @Test("Night Copper extras own empty artwork, never fonts, icons or reading layout")
    @MainActor
    func artworkOnly() {
        let extras = GlobalSettings.nightCopperArtworkExtras
        #expect(extras.pageBackgrounds == [:])
        #expect(extras.cardBackground == nil)
        #expect(extras.globalFontPostScript == nil)
        #expect(extras.tabIcons == nil)
        #expect(extras.visibleTabIDs == nil)
        #expect(extras.tabOrderIDs == nil)
        #expect(extras.reading == nil)
    }

    private func contrast(_ a: UIColor, _ b: UIColor) -> Double {
        func luminance(_ color: UIColor) -> Double {
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, alpha: CGFloat = 0
            color.getRed(&r, green: &g, blue: &b, alpha: &alpha)
            func linear(_ c: CGFloat) -> Double {
                let v = Double(c)
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            return 0.2126 * linear(r) + 0.7152 * linear(g) + 0.0722 * linear(b)
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
