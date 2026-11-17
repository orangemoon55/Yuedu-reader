import Foundation

/// Build 13's reading background was retired. Keep this at the string boundary:
/// reading setups are shared by global settings, saved themes, sync and imports.
/// Do not map `night_copper`: that is the separate retired *app appearance* ID,
/// whose artwork/selection migration remains owned by its existing migration.
enum ReaderThemeStorageMigration {
    static let retiredValues: Set<String> = ["夜銅", "夜铜", "nightCopper"]
    static let replacement = "夜間"

    static func normalize(_ value: String) -> String {
        retiredValues.contains(value) ? replacement : value
    }

    /// Idempotent and deliberately not one-shot: an old device or backup may write
    /// a retired scalar again after this installation has already been upgraded.
    static func migrateDefaults(_ defaults: UserDefaults) {
        for key in [
            "yd_reader_theme", "lastDarkTheme",
            "yd_appearance_bound_light_reader_theme", "yd_appearance_bound_dark_reader_theme"
        ] {
            guard let old = defaults.string(forKey: key) else { continue }
            let new = normalize(old)
            if new != old { defaults.set(new, forKey: key) }
        }
        // A dark background is never a valid remembered day background.
        if let old = defaults.string(forKey: "lastLightTheme"), retiredValues.contains(old) {
            defaults.set("白天", forKey: "lastLightTheme")
        }
    }
}
