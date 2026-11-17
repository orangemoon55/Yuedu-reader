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
        XCTAssertEqual(ReaderTheme.allCases, [.night, .white, .green, .sepia])
        XCTAssertTrue(ReaderTheme.night.isDark)
        XCTAssertFalse(ReaderTheme.green.isDark)
        XCTAssertEqual(ReaderTheme.night.epubJSName, "night")
        XCTAssertEqual(ReaderBoundTheme(storageValue: ReaderBoundTheme.reading(.night).storageValue),
                       .reading(.night))
    }

    func testReadingChoicePersistsWithoutWritingApplicationAppearanceOrTypography() {
        isolated {
            let settings = GlobalSettings.shared
            let appearance = (settings.appearanceThemeID, settings.appearanceDarkThemeID,
                              settings.appearanceFollowsSystem, settings.appearancePinnedColorScheme)
            let typography = (settings.readerFontSize, settings.selectedReaderFontPostScript,
                              settings.selectedGlobalFontPostScript)
            ReaderTheme.green.persist()
            ReaderTheme.night.persist()
            XCTAssertEqual(ReaderTheme.loadPersisted(), .night)
            XCTAssertEqual(ReaderTheme.lastDarkTheme, .night)
            XCTAssertEqual(ReaderTheme.lastLightTheme, .green)
            ReaderTheme.sepia.persist()
            XCTAssertEqual(ReaderTheme.lastDarkTheme, .night)
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
            ReaderTheme.night.persist()
            settings.setReaderDarkMode(true, deviceIsDark: false)
            let result = settings.readerBackgroundResolution(mode: settings.readerMode, wornTheme: .night)
            XCTAssertEqual(result.theme, .night)
            XCTAssertFalse(result.paintsWithAppearanceTheme)
            XCTAssertNil(result.customBackground)
            XCTAssertEqual(settings.readerBackgroundResolution(mode: .light, wornTheme: .night).theme, .green)
            XCTAssertEqual(settings.readerBackgroundResolution(mode: .dark, wornTheme: .green).theme, .night)
            XCTAssertTrue(GlobalSettings.startingReaderDarkMode(stored: nil, theme: .night,
                                                               wornBackgroundIsDark: false, binds: false))
            settings.adoptReaderDarkMode(from: .night)
            XCTAssertTrue(settings.readerDarkMode)
        }
    }

    func testRetiredStoredChoiceReopensAsBlackAndKeepsLastDayBackground() {
        isolated {
            let defaults = UserDefaults.standard
            defaults.set("夜銅", forKey: "yd_reader_theme")
            defaults.set("夜銅", forKey: "lastDarkTheme")
            defaults.set(ReaderTheme.green.rawValue, forKey: "lastLightTheme")
            XCTAssertEqual(ReaderTheme.loadPersisted(), .night)
            XCTAssertEqual(ReaderTheme.lastDarkTheme, .night)
            XCTAssertEqual(ReaderTheme.lastLightTheme, .green)
            XCTAssertEqual(defaults.string(forKey: "yd_reader_theme"), ReaderTheme.night.rawValue)
            XCTAssertEqual(ReaderBoundTheme(storageValue: "夜銅"), .reading(.night))
            XCTAssertNil(AppearanceThemePreset.preset(id: QingyunNightCopperRetirementMigration.retiredThemeID))
        }
    }
}
