import UIKit
import XCTest
@preconcurrency import CodaCore
@testable import yuedu_app

@MainActor
final class CodaMusicHostIntegrationTests: XCTestCase {
    func testProviderCollectionIsExactlyTheFourUpstreamProviders() {
        XCTAssertEqual(ReadccHostBridge.providerIDs, Set(["netease", "qq", "kugou", "qishui"]))
    }

    func testInstallingHooksDoesNotClaimAudioOrStopEitherEngine() {
        let audio = ReadccHostBridge.AudioOwnership()
        var hostStops = 0
        var codaStops = 0
        audio.installReadccStop { hostStops += 1 }
        audio.installCodaStop { codaStops += 1 }
        XCTAssertEqual(audio.owner, .none)
        XCTAssertEqual(hostStops, 0)
        XCTAssertEqual(codaStops, 0)
    }

    func testSameOwnerDoesNotDoubleInvokeCallbacks() {
        let audio = ReadccHostBridge.AudioOwnership()
        var hostStops = 0
        var codaStops = 0
        audio.installReadccStop { hostStops += 1 }
        audio.installCodaStop { codaStops += 1 }
        XCTAssertTrue(audio.claim(.readcc))
        XCTAssertFalse(audio.claim(.readcc))
        XCTAssertEqual(hostStops, 0)
        XCTAssertEqual(codaStops, 0)
        XCTAssertTrue(audio.claim(.coda))
        XCTAssertFalse(audio.claim(.coda))
        XCTAssertEqual(audio.owner, .coda)
        XCTAssertEqual(hostStops, 1)
        XCTAssertEqual(codaStops, 0)
        XCTAssertTrue(audio.claim(.readcc))
        XCTAssertFalse(audio.claim(.readcc))
        XCTAssertEqual(audio.owner, .readcc)
        XCTAssertEqual(hostStops, 1)
        XCTAssertEqual(codaStops, 1)
    }

    func testRepeatedTransfersStopOnlyOutgoingEngineOnce() {
        let audio = ReadccHostBridge.AudioOwnership()
        var events: [String] = []
        audio.installReadccStop { events.append("stop-readcc") }
        audio.installCodaStop { events.append("stop-coda") }
        audio.claim(.coda)
        audio.claim(.readcc)
        audio.claim(.coda)
        audio.claim(.readcc)
        XCTAssertEqual(events, ["stop-readcc", "stop-coda", "stop-readcc", "stop-coda"])
        XCTAssertEqual(audio.owner, .readcc)
    }

    func testReentrantClaimCannotReplaceRequestedOwner() {
        let audio = ReadccHostBridge.AudioOwnership()
        var accepted = true
        var events: [String] = []
        audio.installReadccStop {
            events.append("stop-readcc")
            accepted = audio.claim(.readcc)
        }
        audio.installCodaStop { events.append("stop-coda") }
        XCTAssertTrue(audio.claim(.coda))
        XCTAssertFalse(accepted)
        XCTAssertEqual(audio.owner, .coda)
        XCTAssertEqual(events, ["stop-readcc"])
        XCTAssertTrue(audio.claim(.readcc))
        XCTAssertEqual(events, ["stop-readcc", "stop-coda"])
    }

    func testReplacingHooksDoesNotPauseExistingCodaOwner() {
        let audio = ReadccHostBridge.AudioOwnership()
        var codaStops = 0
        audio.installCodaStop { codaStops += 1 }
        audio.claim(.coda)
        audio.installReadccStop {}
        audio.installReadccStop {}
        XCTAssertEqual(audio.owner, .coda)
        XCTAssertEqual(codaStops, 0)
        XCTAssertFalse(audio.claim(.coda))
        XCTAssertEqual(codaStops, 0)
    }

    func testForeignSessionDoesNotConsumeCompletion() {
        var completions = 0
        XCTAssertFalse(ReadccHostBridge.acceptsBackgroundSession(identifier: "readcc.tests.foreign"))
        XCTAssertFalse(ReadccHostBridge.handleBackgroundSession(identifier: "readcc.tests.foreign") { completions += 1 })
        XCTAssertEqual(completions, 0)
    }

    func testExistingDelegateCompletesForeignSessionExactlyOnce() {
        var completions = 0
        RSSAppNotificationDelegate().application(UIApplication.shared,
            handleEventsForBackgroundURLSession: "readcc.tests.foreign",
            completionHandler: { completions += 1 })
        XCTAssertEqual(completions, 1)
    }

    func testEmbeddedPolicyDisablesStandaloneUpdater() {
        ReadccHostBridge.configureEmbeddedHost()
        XCTAssertTrue(ReadccHostBridge.isEmbedded)
        XCTAssertFalse(ReadccHostBridge.allowsStandaloneUpdates)
    }
}
