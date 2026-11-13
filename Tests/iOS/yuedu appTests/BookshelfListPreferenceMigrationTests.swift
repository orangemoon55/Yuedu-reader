import Foundation
import Testing
@testable import yuedu_app

@Suite("Bookshelf list preference migration")
struct BookshelfListPreferenceMigrationTests {
    @Test("an existing grid preference is switched to list once")
    func switchesGridToListOnce() {
        let suite = "BookshelfListPreferenceMigrationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(true, forKey: BookshelfListPreferenceMigration.gridPreferenceKey)

        BookshelfListPreferenceMigration.runIfNeeded(defaults: defaults)
        #expect(defaults.bool(forKey: BookshelfListPreferenceMigration.gridPreferenceKey) == false)
        #expect(defaults.bool(forKey: BookshelfListPreferenceMigration.completedKey))

        defaults.set(true, forKey: BookshelfListPreferenceMigration.gridPreferenceKey)
        BookshelfListPreferenceMigration.runIfNeeded(defaults: defaults)
        #expect(defaults.bool(forKey: BookshelfListPreferenceMigration.gridPreferenceKey))
    }
}
