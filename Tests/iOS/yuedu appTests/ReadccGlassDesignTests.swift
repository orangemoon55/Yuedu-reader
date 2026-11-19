import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("Readcc glass design")
struct ReadccGlassDesignTests {
    private func defaults() throws -> (String, UserDefaults) {
        let name = "glass-tests-\(UUID())"
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    @Test("New glass defaults leave reader content and theme choices unchanged")
    func firstMigration() throws {
        let (name, prefs) = try defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(28, forKey: "reader.font.size")
        prefs.set("custom-paper", forKey: "reader.theme")
        prefs.set(false, forKey: "yd_interface_frosted_glass")
        prefs.set(0.0, forKey: "yd_interface_glass_transparency")
        #expect(InterfaceGlassDefaultsMigration.runIfNeeded(defaults: prefs))
        #expect(prefs.bool(forKey: InterfaceGlassDefaultsMigration.cardsKey))
        #expect(prefs.integer(forKey: "reader.font.size") == 28)
        #expect(prefs.string(forKey: "reader.theme") == "custom-paper")
        #expect(!prefs.bool(forKey: "yd_interface_frosted_glass"))
        #expect(prefs.double(forKey: "yd_interface_glass_transparency") == 0)
        prefs.set(false, forKey: InterfaceGlassDefaultsMigration.cardsKey)
        #expect(!InterfaceGlassDefaultsMigration.runIfNeeded(defaults: prefs))
        #expect(!prefs.bool(forKey: InterfaceGlassDefaultsMigration.cardsKey))
    }

    @Test("A persisted card-material choice is preserved", arguments: [false, true])
    func explicitChoice(_ enabled: Bool) throws {
        let (name, prefs) = try defaults()
        defer { prefs.removePersistentDomain(forName: name) }
        prefs.set(enabled, forKey: InterfaceGlassDefaultsMigration.cardsKey)
        #expect(InterfaceGlassDefaultsMigration.runIfNeeded(defaults: prefs))
        #expect(prefs.bool(forKey: InterfaceGlassDefaultsMigration.cardsKey) == enabled)
    }

    @Test("Reduce Transparency and the glass switch use opaque surfaces")
    func accessibility() {
        #expect(GlobalSettings.defaultInterfaceGlassCards)
        #expect(InterfaceGlassPolicy.shouldUseGlass(isEnabled: true, systemReduceTransparency: false))
        #expect(!InterfaceGlassPolicy.shouldUseGlass(isEnabled: true, systemReduceTransparency: true))
        #expect(!InterfaceGlassPolicy.shouldUseGlass(isEnabled: false, systemReduceTransparency: false))
        #expect(!InterfaceGlassPolicy.shouldUseGlass(isEnabled: false, systemReduceTransparency: true))
        #expect(!InterfaceGlassPolicy.shouldUseGlass(isEnabled: true, systemReduceTransparency: false, override: true))
    }
}
