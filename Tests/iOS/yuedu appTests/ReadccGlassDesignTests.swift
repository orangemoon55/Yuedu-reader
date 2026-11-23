import Foundation
import SwiftUI
import UIKit
import Testing
@testable import yuedu_app

@MainActor
@Suite("Readcc glass design")
struct ReadccGlassDesignTests {
    private func defaults() throws -> (String, UserDefaults) {
        let name = "glass-tests-\(UUID())"
        return (name, try #require(UserDefaults(suiteName: name)))
    }

    private func rgba(_ color: UIColor, traits: UITraitCollection) throws -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #expect(color.resolvedColor(with: traits).getRed(&r, green: &g, blue: &b, alpha: &a))
        return (r, g, b, a)
    }

    private func luminance(_ rgb: (CGFloat, CGFloat, CGFloat, CGFloat)) -> CGFloat {
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : CGFloat(pow(Double((value + 0.055) / 1.055), 2.4))
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    @Test("Every shared glass selection is opaque, visible and readable for extreme theme accents")
    func selectionContrast() throws {
        let accents: [Color] = [.black, .white, .clear, .gray, .red, .green, .blue, .yellow,
                                Color(uiColor: .systemBlue),
                                Color(red: 0.96, green: 0.96, blue: 0.96),
                                Color(red: 0.84, green: 0.60, blue: 0.18),
                                Color(red: 0.16, green: 0.04, blue: 0.22),
                                Color(red: 0.02, green: 0.07, blue: 0.04),
                                .blue.opacity(0.15), .red.opacity(0.35)]
        for scheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let traits = UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light),
                    UITraitCollection(accessibilityContrast: contrast == .increased ? .high : .normal)
                ])
                let label = luminance(try rgba(.label, traits: traits))
                let surface = try rgba(.secondarySystemBackground, traits: traits)
                for accent in accents {
                    let fill = try rgba(UIColor(NavigationGlassCapsule.selectionFill(
                        tint: accent, scheme: scheme, contrast: contrast)), traits: traits)
                    let selected = luminance(fill)
                    let ratio = (max(label, selected) + 0.05) / (min(label, selected) + 0.05)
                    #expect(abs(fill.3 - 1) < 0.0001)
                    #expect(ratio >= (contrast == .increased ? 7 : 4.5))
                    #expect(abs(selected - luminance(surface)) > 0.035)
                    // Light selections must be fresh washes, not the old muddy neutral.
                    if scheme == .light { #expect(selected >= 0.4799) }
                }
            }
        }
    }

    @Test("Default selections are clean UI blue, pastel in light mode and luminous in dark mode")
    func selectedBlueDirection() throws {
        for scheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let traits = UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light),
                    UITraitCollection(accessibilityContrast: contrast == .increased ? .high : .normal)
                ])
                for accent in [Color.blue, Color(uiColor: .systemBlue),
                               Color(red: 0.20, green: 0.47, blue: 0.96)] {
                    let fill = try rgba(UIColor(NavigationGlassCapsule.selectionFill(
                        tint: accent, scheme: scheme, contrast: contrast)), traits: traits)
                    #expect(fill.2 > fill.1 && fill.1 > fill.0)
                    #expect(fill.2 - fill.0 > 0.15)
                    if scheme == .light {
                        #expect(fill.0 > 0.60 && fill.2 > 0.90)
                    } else {
                        #expect(fill.2 > 0.50 && fill.2 - fill.0 > 0.30)
                    }
                }
            }
        }
    }

    @Test("Neutral accents fall back to UI blue while imported colors retain their hue")
    func selectedImportedAccents() throws {
        for scheme in [ColorScheme.light, .dark] {
            for contrast in [ColorSchemeContrast.standard, .increased] {
                let traits = UITraitCollection(traitsFrom: [
                    UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light),
                    UITraitCollection(accessibilityContrast: contrast == .increased ? .high : .normal)
                ])
                func fill(_ accent: Color) throws -> (CGFloat, CGFloat, CGFloat, CGFloat) {
                    try rgba(UIColor(NavigationGlassCapsule.selectionFill(
                        tint: accent, scheme: scheme, contrast: contrast)), traits: traits)
                }
                let blue = try fill(Color(uiColor: .systemBlue))
                for neutral in [Color.black, .white, .gray, .clear] {
                    let result = try fill(neutral)
                    #expect(abs(result.0 - blue.0) < 0.0001)
                    #expect(abs(result.1 - blue.1) < 0.0001)
                    #expect(abs(result.2 - blue.2) < 0.0001)
                }
                let gold = try fill(Color(red: 0.84, green: 0.60, blue: 0.18))
                #expect(gold.0 > gold.1 && gold.1 - gold.2 > 0.10)
                let plum = try fill(Color(red: 0.16, green: 0.04, blue: 0.22))
                #expect(plum.2 > plum.0 && plum.0 - plum.1 > 0.10)
                let forest = try fill(Color(red: 0.02, green: 0.07, blue: 0.04))
                #expect(forest.1 - forest.0 > 0.10 && forest.1 > forest.2)
            }
        }
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
