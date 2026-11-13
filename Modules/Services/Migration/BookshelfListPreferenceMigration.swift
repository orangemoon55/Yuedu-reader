import Foundation

/// Restores the list-style bookshelf once for readers upgrading from a grid preference.
enum BookshelfListPreferenceMigration {
    static let completedKey = "yd_bookshelf_list_preference_migration_v1_completed"
    static let gridPreferenceKey = "bookLayoutIsGrid"

    static func runIfNeeded(defaults: UserDefaults = .standard) {
        guard !defaults.bool(forKey: completedKey) else { return }
        defaults.set(false, forKey: gridPreferenceKey)
        defaults.set(true, forKey: completedKey)
    }
}
