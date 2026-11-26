import Foundation
import SwiftUI
import XCTest
@testable import yuedu_app

@MainActor
final class MediaVideoLayoutSettingsTests: XCTestCase {
    func testVideoDefaultsRetainThreeColumnPortraitTemplate() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(MediaPreferences.videoKernel(in: defaults), .automatic)
        XCTAssertEqual(MediaPreferences.videoPosterColumns(in: defaults), 3)
        XCTAssertTrue(MediaPreferences.videoShowsFacts(in: defaults))
        XCTAssertEqual(MediaPreferences.videoCardDensity(in: defaults), .comfortable)
        XCTAssertEqual(MediaHubVideoLayout.posterColumnCount, 3)
        XCTAssertEqual(MediaHubVideoLayout.columns.count, 3)
        XCTAssertEqual(MediaHubVideoLayout.posterAspectRatio, 2.0 / 3.0)
        XCTAssertEqual(MediaHubVideoLayout.skeletonCount, 9)
    }

    func testKernelRoundTripsAndRejectsUnknownOrWrongTypedValues() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        XCTAssertEqual(MediaPreferences.videoKernelKey, "media.video.kernel")
        for kernel in VideoKernelPreference.allCases {
            MediaPreferences.setVideoKernel(kernel, in: defaults)
            XCTAssertEqual(defaults.string(forKey: MediaPreferences.videoKernelKey), kernel.rawValue)
            XCTAssertEqual(MediaPreferences.videoKernel(in: defaults), kernel)
        }
        for invalid in ["unknown", "KSPlayer", "", 1, true] as [Any] {
            defaults.set(invalid, forKey: MediaPreferences.videoKernelKey)
            XCTAssertEqual(MediaPreferences.videoKernel(in: defaults), .automatic)
        }
    }

    func testVideoSettingsPersistInOnlyTheirOwnSuite() throws {
        let (first, firstSuite) = try makeDefaults()
        let (second, secondSuite) = try makeDefaults()
        defer {
            first.removePersistentDomain(forName: firstSuite)
            second.removePersistentDomain(forName: secondSuite)
        }

        MediaPreferences.setVideoKernel(.ksPlayer, in: first)
        MediaPreferences.setVideoPosterColumns(5, in: first)
        MediaPreferences.setVideoShowsFacts(false, in: first)
        MediaPreferences.setVideoCardDensity(.compact, in: first)
        XCTAssertEqual(MediaPreferences.videoKernel(in: first), .ksPlayer)
        XCTAssertEqual(MediaPreferences.videoPosterColumns(in: first), 5)
        XCTAssertFalse(MediaPreferences.videoShowsFacts(in: first))
        XCTAssertEqual(MediaPreferences.videoCardDensity(in: first), .compact)
        XCTAssertEqual(first.string(forKey: MediaPreferences.videoCardDensityKey), "compact")
        XCTAssertEqual(MediaPreferences.videoKernel(in: second), .automatic)
        XCTAssertEqual(MediaPreferences.videoPosterColumns(in: second), 3)
        XCTAssertTrue(MediaPreferences.videoShowsFacts(in: second))
        XCTAssertEqual(MediaPreferences.videoCardDensity(in: second), .comfortable)
    }

    func testVideoColumnCountClampsReadAndWriteBoundaries() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        for (input, expected) in [(Int.min, 2), (-1, 2), (1, 2), (2, 2), (3, 3),
                                  (4, 4), (5, 5), (9, 5), (Int.max, 5)] {
            MediaPreferences.setVideoPosterColumns(input, in: defaults)
            XCTAssertEqual(MediaPreferences.videoPosterColumns(in: defaults), expected)
            XCTAssertEqual(defaults.integer(forKey: MediaPreferences.videoPosterColumnsKey), expected)
            defaults.set(input, forKey: MediaPreferences.videoPosterColumnsKey)
            XCTAssertEqual(MediaPreferences.videoPosterColumns(in: defaults), expected)
        }
    }

    func testInvalidVideoColumnsFallBackToThree() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        for invalid in ["4", "three", true, false, 2.5, Double.nan, Double.infinity] as [Any] {
            defaults.set(invalid, forKey: MediaPreferences.videoPosterColumnsKey)
            XCTAssertEqual(MediaPreferences.videoPosterColumns(in: defaults), 3)
        }
    }

    func testFactsAndDensityRejectInvalidStoredTypesAndValues() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        for invalid in ["false", 0, 1, ""] as [Any] {
            defaults.set(invalid, forKey: MediaPreferences.videoShowsFactsKey)
            XCTAssertTrue(MediaPreferences.videoShowsFacts(in: defaults))
        }
        for invalid in ["dense", "Compact", "", 1, true] as [Any] {
            defaults.set(invalid, forKey: MediaPreferences.videoCardDensityKey)
            XCTAssertEqual(MediaPreferences.videoCardDensity(in: defaults), .comfortable)
        }
        for density in MediaVideoCardDensity.allCases {
            MediaPreferences.setVideoCardDensity(density, in: defaults)
            XCTAssertEqual(MediaPreferences.videoCardDensity(in: defaults), density)
        }
    }

    func testVideoLibraryMusicAndPlaybackSettingsRemainIndependent() throws {
        let (defaults, suite) = try makeDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }

        MediaPreferences.setPosterColumns(5, in: defaults)
        MediaPreferences.setHomeShowsHero(false, in: defaults)
        MediaPreferences.setHomeShowsContinue(false, in: defaults)
        MediaPreferences.setMusicArtworkSquare(false, in: defaults)
        MediaPreferences.setMusicDefaultRate(0.75, in: defaults)
        MediaPreferences.setMusicResumeEnabled(false, in: defaults)
        MediaPreferences.setMusicLoopCurrent(true, in: defaults)
        MediaPreferences.setVideoDefaultRate(1.5, in: defaults)
        MediaPreferences.setVideoResumeEnabled(false, in: defaults)
        XCTAssertEqual(MediaPreferences.videoPosterColumns(in: defaults), 3)
        XCTAssertTrue(MediaPreferences.videoShowsFacts(in: defaults))
        XCTAssertEqual(MediaPreferences.videoCardDensity(in: defaults), .comfortable)

        MediaPreferences.setVideoPosterColumns(2, in: defaults)
        MediaPreferences.setVideoShowsFacts(false, in: defaults)
        MediaPreferences.setVideoCardDensity(.compact, in: defaults)
        MediaPreferences.setVideoKernel(.avFoundation, in: defaults)
        XCTAssertEqual(MediaPreferences.posterColumns(in: defaults), 5)
        XCTAssertFalse(MediaPreferences.homeShowsHero(in: defaults))
        XCTAssertFalse(MediaPreferences.homeShowsContinue(in: defaults))
        XCTAssertFalse(MediaPreferences.musicArtworkSquare(in: defaults))
        XCTAssertEqual(MediaPreferences.musicDefaultRate(in: defaults), 0.75)
        XCTAssertFalse(MediaPreferences.musicResumeEnabled(in: defaults))
        XCTAssertTrue(MediaPreferences.musicLoopCurrent(in: defaults))
        XCTAssertEqual(MediaPreferences.videoDefaultRate(in: defaults), 1.5)
        XCTAssertFalse(MediaPreferences.videoResumeEnabled(in: defaults))

        MediaPreferences.setPosterColumns(4, in: defaults)
        XCTAssertEqual(MediaPreferences.videoPosterColumns(in: defaults), 2)
        XCTAssertFalse(MediaPreferences.videoShowsFacts(in: defaults))
        XCTAssertEqual(MediaPreferences.videoCardDensity(in: defaults), .compact)
        XCTAssertEqual(MediaPreferences.videoKernel(in: defaults), .avFoundation)
    }

    func testEverySelectedColumnTemplateIsExplicitAndWidthIndependent() {
        for count in 2...5 {
            for density in MediaVideoCardDensity.allCases {
                let columns = MediaHubVideoLayout.columns(count: count, density: density)
                XCTAssertEqual(columns.count, count)
                for column in columns {
                    switch column.size {
                    case .flexible(let minimum, let maximum):
                        XCTAssertEqual(minimum, 0)
                        XCTAssertEqual(maximum, .infinity)
                    default:
                        XCTFail("Video templates must use explicit equal flexible columns, never adaptive columns")
                    }
                    XCTAssertEqual(column.spacing, MediaHubVideoLayout.spacing(for: density))
                }
                XCTAssertEqual(MediaHubVideoLayout.posterAspectRatio, 2.0 / 3.0)
            }
        }
        XCTAssertEqual(MediaHubVideoLayout.columns(count: Int.min).count, 2)
        XCTAssertEqual(MediaHubVideoLayout.columns(count: Int.max).count, 5)
    }

    func testCompactDensityChangesSpacingNotDefaultColumnCountOrAspectRatio() {
        XCTAssertEqual(MediaHubVideoLayout.spacing(for: .comfortable), 12)
        XCTAssertEqual(MediaHubVideoLayout.rowSpacing(for: .comfortable), 20)
        XCTAssertEqual(MediaHubVideoLayout.cardSpacing(for: .comfortable), 5)
        XCTAssertEqual(MediaHubVideoLayout.spacing(for: .compact), 8)
        XCTAssertEqual(MediaHubVideoLayout.rowSpacing(for: .compact), 12)
        XCTAssertEqual(MediaHubVideoLayout.cardSpacing(for: .compact), 3)
        XCTAssertEqual(MediaHubVideoLayout.columns.count, 3)
        XCTAssertEqual(MediaHubVideoLayout.posterAspectRatio, 2.0 / 3.0)
    }

    func testSkeletonUsesThreeRowsForEachSelectedFixedTemplate() {
        for count in 2...5 {
            XCTAssertEqual(MediaHubVideoLayout.skeletonCount(forColumnCount: count), count * 3)
            XCTAssertEqual(MediaHubVideoLayout.skeletonCount(forColumnCount: count) % count, 0)
        }
        XCTAssertEqual(MediaHubVideoLayout.skeletonCount(forColumnCount: 3), MediaHubVideoLayout.skeletonCount)
        XCTAssertEqual(MediaHubVideoLayout.skeletonCount(forColumnCount: Int.min), 6)
        XCTAssertEqual(MediaHubVideoLayout.skeletonCount(forColumnCount: Int.max), 15)
    }

    private func makeDefaults() throws -> (UserDefaults, String) {
        let suite = "MediaVideoLayoutSettingsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defaults.removePersistentDomain(forName: suite)
        return (defaults, suite)
    }
}
