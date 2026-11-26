import Foundation
import XCTest
@testable import yuedu_app

/// Deterministic policy/lifecycle tests, not evidence of decoded video or device playback.
@MainActor
final class VideoKernelPreferenceTests: XCTestCase {
    func testStablePersistedCasesAndLabels() {
        XCTAssertEqual(VideoKernelPreference.allCases.map(\.rawValue), ["automatic", "ksPlayer", "avFoundation"])
        for preference in VideoKernelPreference.allCases {
            XCTAssertEqual(preference.id, preference.rawValue)
            XCTAssertFalse(preference.title.isEmpty)
            XCTAssertEqual(preference.label, preference.title)
        }
    }

    func testOnlyAutomaticAllowsExactlyOneKSIntoAVFallback() {
        var state = VideoPlaybackLoadState(policy: VideoKernelPolicy(preference: .automatic))
        let token = state.begin()
        XCTAssertEqual(state.kernel, .ksPlayer)
        XCTAssertTrue(state.takeAVFallback(for: token))
        XCTAssertEqual(state.kernel, .avFoundation)
        XCTAssertTrue(state.usedAVFallback)
        XCTAssertFalse(state.takeAVFallback(for: token))
        XCTAssertFalse(state.accepts(token, kernel: .ksPlayer))
        XCTAssertTrue(state.accepts(token, kernel: .avFoundation))
    }

    func testForcedKSNeverSilentlyFallsBackAndAVStartsDirectly() {
        for preference in [VideoKernelPreference.ksPlayer, .avFoundation] {
            var state = VideoPlaybackLoadState(policy: VideoKernelPolicy(preference: preference))
            let token = state.begin()
            XCTAssertEqual(state.kernel, preference == .ksPlayer ? .ksPlayer : .avFoundation)
            XCTAssertFalse(state.takeAVFallback(for: token))
            XCTAssertFalse(state.usedAVFallback)
        }
    }

    func testExplicitLegacyOverrideWinsAndNilUsesTypedPreference() {
        for preference in VideoKernelPreference.allCases {
            XCTAssertEqual(VideoKernelPolicy(preference: preference).preference, preference)
            XCTAssertEqual(VideoKernelPolicy(preference: preference, legacyOverride: nil).preference, preference)
            XCTAssertEqual(VideoKernelPolicy(preference: preference, legacyOverride: false).preference, .avFoundation)
            XCTAssertEqual(VideoKernelPolicy(preference: preference, legacyOverride: true).preference, .automatic)
        }
    }

    func testInvalidPersistedEnumResolvesToAutomaticPolicy() throws {
        let suite = "VideoKernelPreferenceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        for invalid: Any in ["unknown", "KSPlayer", "", 123, true] {
            defaults.set(invalid, forKey: MediaPreferences.videoKernelKey)
            let policy = VideoKernelPolicy(preference: MediaPreferences.videoKernel(in: defaults))
            XCTAssertEqual(policy.preference, .automatic)
            XCTAssertEqual(policy.initialKernel, .ksPlayer)
        }
    }

    func testOldResolverSuccessErrorReadyAndSeekTokensAreRejected() throws {
        var state = VideoPlaybackLoadState(policy: VideoKernelPolicy(preference: .automatic))
        let old = state.begin()
        let seek = try XCTUnwrap(state.beginSeek())
        let current = state.begin()
        // Both resolver success and all error branches use the same accepts(load) gate.
        XCTAssertFalse(state.accepts(old))
        XCTAssertFalse(state.receiveReady(for: old, kernel: .ksPlayer))
        XCTAssertFalse(state.takeAVFallback(for: old))
        XCTAssertFalse(state.finishPreparing(for: old))
        XCTAssertFalse(state.accepts(seek))
        XCTAssertTrue(state.accepts(current))
        XCTAssertTrue(state.receiveReady(for: current, kernel: .ksPlayer))
        XCTAssertFalse(state.receiveReady(for: current, kernel: .ksPlayer))
    }

    func testOnlyLatestSeekCanCompleteWithinSameGeneration() throws {
        var state = VideoPlaybackLoadState(policy: VideoKernelPolicy(preference: .automatic))
        let token = state.begin()
        let first = try XCTUnwrap(state.beginSeek())
        let second = try XCTUnwrap(state.beginSeek())
        XCTAssertFalse(state.accepts(first))
        XCTAssertTrue(state.accepts(second))
        XCTAssertTrue(state.takeAVFallback(for: token))
        XCTAssertFalse(state.accepts(second), "The KS seek must not resume the AV fallback")
    }

    func testPauseWhileLoadingSurvivesReadyAndFallback() {
        var state = VideoPlaybackLoadState(policy: VideoKernelPolicy(preference: .automatic))
        let token = state.begin()
        state.setWantsPlayback(false)
        XCTAssertTrue(state.receiveReady(for: token, kernel: .ksPlayer))
        XCTAssertTrue(state.takeAVFallback(for: token))
        XCTAssertFalse(state.wantsPlayback)
        XCTAssertTrue(state.isPreparing)
        XCTAssertTrue(state.receiveReady(for: token, kernel: .avFoundation))
        XCTAssertTrue(state.finishPreparing(for: token))
        XCTAssertFalse(state.wantsPlayback)
        XCTAssertFalse(state.isPreparing)
        XCTAssertFalse(state.finishPreparing(for: token))
        state.setWantsPlayback(true)
        XCTAssertTrue(state.wantsPlayback)
    }

    func testInternalLinkRefreshKeepsFallbackBudgetAndPauseIntent() {
        var state = VideoPlaybackLoadState(policy: VideoKernelPolicy(preference: .automatic))
        let first = state.begin()
        state.setWantsPlayback(false)
        XCTAssertTrue(state.takeAVFallback(for: first))
        let refreshed = state.begin(preservingContinuation: true)
        XCTAssertFalse(state.accepts(first))
        XCTAssertEqual(state.kernel, .avFoundation)
        XCTAssertTrue(state.usedAVFallback)
        XCTAssertFalse(state.wantsPlayback)
        XCTAssertFalse(state.takeAVFallback(for: refreshed))
        let explicitRetry = state.begin()
        XCTAssertEqual(state.kernel, .ksPlayer)
        XCTAssertTrue(state.wantsPlayback)
        XCTAssertFalse(state.usedAVFallback)
        XCTAssertTrue(state.takeAVFallback(for: explicitRetry))
    }

    func testCloseInvalidatesAllQueuedWorkAndReopenUsesNewGeneration() throws {
        var state = VideoPlaybackLoadState(policy: VideoKernelPolicy(preference: .automatic))
        let token = state.begin()
        let seek = try XCTUnwrap(state.beginSeek())
        state.close()
        state.close()
        state.setWantsPlayback(true)
        XCTAssertNil(state.token)
        XCTAssertFalse(state.wantsPlayback)
        XCTAssertFalse(state.accepts(token))
        XCTAssertFalse(state.accepts(seek))
        XCTAssertFalse(state.receiveReady(for: token, kernel: .ksPlayer))
        XCTAssertFalse(state.takeAVFallback(for: token))
        XCTAssertFalse(state.finishPreparing(for: token))
        XCTAssertNil(state.beginSeek())
        let reopened = state.begin()
        XCTAssertNotEqual(reopened, token)
        XCTAssertFalse(state.accepts(token))
        XCTAssertTrue(state.accepts(reopened))
    }
}
