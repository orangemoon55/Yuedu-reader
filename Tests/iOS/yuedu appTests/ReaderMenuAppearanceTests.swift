import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class ReaderMenuAppearanceTests: XCTestCase {
    func testTransparentMenuFillIsFlattenedAndTextHasReadableContrast() {
        for style in [UIUserInterfaceStyle.light, .dark] {
            let traits = UITraitCollection(userInterfaceStyle: style)
            let ground = UIColor.systemBackground.resolvedColor(with: traits)
            let transparent = UIColor(red: 0.2, green: 0.6, blue: 0.4, alpha: 0.08)
            let fill = ReaderMenuColors.opaque(transparent, over: ground, traits: traits)
            var alpha: CGFloat = 0
            fill.getRed(nil, green: nil, blue: nil, alpha: &alpha)
            XCTAssertEqual(alpha, 1)
            let ink = ReaderMenuColors.legible(fill, on: fill, traits: traits)
            XCTAssertGreaterThanOrEqual(ReaderMenuColors.contrast(ink, fill), 4.5)
        }
    }

    func testHighContrastAndTransparentInkStayReadable() {
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: .dark),
            UITraitCollection(accessibilityContrast: .high)
        ])
        for fill in [UIColor.black, .white, UIColor(red: 0.1, green: 0.16, blue: 0.2, alpha: 1)] {
            let ink = ReaderMenuColors.legible(.clear, on: fill, traits: traits)
            XCTAssertGreaterThanOrEqual(ReaderMenuColors.contrast(ink, fill), 7)
        }
    }

    func testLegacyNightCopperImportKeepsOtherReadingPreferences() throws {
        let data = Data("""
        {"readerTheme":"夜銅","boundLightReaderTheme":"白天","boundDarkReaderTheme":"nightCopper","fontSize":23}
        """.utf8)
        let settings = try JSONDecoder().decode(AppearanceThemeReadingSettings.self, from: data)
        XCTAssertEqual(settings.readerTheme, ReaderTheme.night.rawValue)
        XCTAssertEqual(settings.boundDarkReaderTheme, ReaderTheme.night.rawValue)
        XCTAssertEqual(settings.boundLightReaderTheme, ReaderTheme.white.rawValue)
        XCTAssertEqual(settings.fontSize, 23)
    }

    func testOldNightCopperDefaultsAreMigratedIdempotently() throws {
        let suite = "ReaderMenuAppearanceTests.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("夜銅", forKey: "yd_reader_theme")
        defaults.set("夜铜", forKey: "lastDarkTheme")
        defaults.set("nightCopper", forKey: "lastLightTheme")
        defaults.set(24, forKey: "unrelatedSize")
        for _ in 0..<2 { ReaderThemeStorageMigration.migrateDefaults(defaults) }
        XCTAssertEqual(defaults.string(forKey: "yd_reader_theme"), ReaderTheme.night.rawValue)
        XCTAssertEqual(defaults.string(forKey: "lastDarkTheme"), ReaderTheme.night.rawValue)
        XCTAssertEqual(defaults.string(forKey: "lastLightTheme"), ReaderTheme.white.rawValue)
        XCTAssertEqual(defaults.integer(forKey: "unrelatedSize"), 24)
    }
}
