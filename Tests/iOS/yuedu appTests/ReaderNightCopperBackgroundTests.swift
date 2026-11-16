import Foundation
import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class ReaderNightCopperBackgroundTests: XCTestCase {
    private func isolated(_ body: () throws -> Void) rethrows {
        let defaults = UserDefaults.standard
        let keys = ["yd_reader_theme", "lastLightTheme", "lastDarkTheme"]
        let oldValues = keys.map { defaults.object(forKey: $0) }
        let settings = GlobalSettings.shared
        let applying = settings.isApplyingReadingSettingsSync
        let old = (settings.appearanceBindReaderTheme, settings.readerDarkMode,
                   settings.readerFollowSystemTheme, settings.readerCustomBackgroundID)
        let palette = AppearanceThemePreset.activeReaderTheme
        settings.isApplyingReadingSettingsSync = true
        AppearanceThemePreset.activeReaderTheme = nil
        defer {
            settings.appearanceBindReaderTheme = old.0
            settings.readerDarkMode = old.1
            settings.readerFollowSystemTheme = old.2
            settings.readerCustomBackgroundID = old.3
            settings.isApplyingReadingSettingsSync = applying
            AppearanceThemePreset.activeReaderTheme = palette
            for (key, value) in zip(keys, oldValues) {
                if let value { defaults.set(value, forKey: key) }
                else { defaults.removeObject(forKey: key) }
            }
        }
        try body()
    }

    func testFirstChoiceAndDarkClassification() {
        XCTAssertEqual(ReaderTheme.allCases, [.nightCopper, .night, .white, .green, .sepia])
        XCTAssertTrue(ReaderTheme.nightCopper.isDark)
        XCTAssertFalse(ReaderTheme.green.isDark)
        XCTAssertEqual(ReaderTheme.nightCopper.epubJSName, "nightCopper")
        XCTAssertEqual(ReaderBoundTheme(storageValue: ReaderBoundTheme.reading(.nightCopper).storageValue),
                       .reading(.nightCopper))
    }

    func testReadingChoicePersistsWithoutWritingApplicationAppearanceOrTypography() {
        isolated {
            let settings = GlobalSettings.shared
            let appearance = (settings.appearanceThemeID, settings.appearanceDarkThemeID,
                              settings.appearanceFollowsSystem, settings.appearancePinnedColorScheme)
            let typography = (settings.readerFontSize, settings.selectedReaderFontPostScript,
                              settings.selectedGlobalFontPostScript)
            ReaderTheme.green.persist()
            ReaderTheme.nightCopper.persist()
            XCTAssertEqual(ReaderTheme.loadPersisted(), .nightCopper)
            XCTAssertEqual(ReaderTheme.lastDarkTheme, .nightCopper)
            XCTAssertEqual(ReaderTheme.lastLightTheme, .green)
            ReaderTheme.sepia.persist()
            XCTAssertEqual(ReaderTheme.lastDarkTheme, .nightCopper)
            ReaderTheme.night.persist()
            XCTAssertEqual(ReaderTheme.lastDarkTheme, .night)
            XCTAssertEqual(settings.appearanceThemeID, appearance.0)
            XCTAssertEqual(settings.appearanceDarkThemeID, appearance.1)
            XCTAssertEqual(settings.appearanceFollowsSystem, appearance.2)
            XCTAssertEqual(settings.appearancePinnedColorScheme, appearance.3)
            XCTAssertEqual(settings.readerFontSize, typography.0)
            XCTAssertEqual(settings.selectedReaderFontPostScript, typography.1)
            XCTAssertEqual(settings.selectedGlobalFontPostScript, typography.2)
        }
    }

    func testResolutionKeepsCopperOnReopenAndRestoresLastDayBackground() {
        isolated {
            let settings = GlobalSettings.shared
            settings.appearanceBindReaderTheme = false
            settings.readerCustomBackgroundID = nil
            ReaderTheme.green.persist()
            ReaderTheme.nightCopper.persist()
            settings.setReaderDarkMode(true, deviceIsDark: false)
            let result = settings.readerBackgroundResolution(mode: settings.readerMode, wornTheme: .nightCopper)
            XCTAssertEqual(result.theme, .nightCopper)
            XCTAssertFalse(result.paintsWithAppearanceTheme)
            XCTAssertNil(result.customBackground)
            XCTAssertEqual(settings.readerBackgroundResolution(mode: .light, wornTheme: .nightCopper).theme, .green)
            XCTAssertEqual(settings.readerBackgroundResolution(mode: .dark, wornTheme: .green).theme, .nightCopper)
            XCTAssertTrue(GlobalSettings.startingReaderDarkMode(stored: nil, theme: .nightCopper,
                                                               wornBackgroundIsDark: false, binds: false))
            settings.adoptReaderDarkMode(from: .nightCopper)
            XCTAssertTrue(settings.readerDarkMode)
        }
    }

    func testCopperHasReadableIntrinsicColorsAndDoesNotBecomeTheAppTheme() {
        isolated {
            func components(_ color: UIColor) -> [CGFloat] {
                var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                XCTAssertTrue(color.getRed(&r, green: &g, blue: &b, alpha: &a))
                return [r, g, b, a]
            }
            let background = components(ReaderTheme.nightCopper.uiBackgroundColor)
            let text = components(ReaderTheme.nightCopper.uiTextColor)
            XCTAssertEqual(background[0], 21.0 / 255, accuracy: 0.001)
            XCTAssertEqual(background[1], 35.0 / 255, accuracy: 0.001)
            XCTAssertEqual(text[0], 237.0 / 255, accuracy: 0.001)
            XCTAssertGreaterThan(text[0] - background[0], 0.8)
            XCTAssertNil(AppearanceThemePreset.preset(id: QingyunNightCopperRetirementMigration.retiredThemeID))
        }
    }
}
