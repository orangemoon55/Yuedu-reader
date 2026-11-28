import Foundation
import Combine
#if canImport(UIKit)
import SwiftUI
import UIKit
#endif
import Testing
@testable import CodaCore

@MainActor
@Suite("Coda search tap playback coordinator")
struct CodaSearchPlaybackCoordinatorTests {
    @Test func explicitForeignRowTapSwitchesThroughInjectedLifecycleThenPlays() async throws {
        let track = try Self.vendorTrack(.qq, id: 510)
        var active: MusicProvider? = .netease
        var ticket = UUID()
        var selections: [MusicProvider] = []
        var played: Track?
        let result = try await CodaSearchPlaybackCoordinator.play(
            track: track, source: .qq, registeredTracks: [track], fixture: false,
            switching: false, isCurrent: { true }, initialContextIsCurrent: { true }, activeProvider: { active },
            contextTicket: { ticket },
            selectProvider: { provider in
                selections.append(provider)
                active = provider
                ticket = UUID()
                return ticket
            },
            startPlayback: { played = $0 }
        )
        #expect(result == .played)
        #expect(selections == [.qq])
        #expect(active == .qq)
        #expect(played?.id == track.id)
        #expect(played?.platformSong == track.platformSong)
    }

    @Test func neteaseRowPassesOriginalNativeTrackWithoutProviderReconstruction() async throws {
        let original = try PlatformMusicAPI.decode(Track.self, [
            "id": 520, "name": "native title", "dt": 195_000,
            "alia": ["original alias"], "fee": 1,
            "privilege": ["id": 520, "fee": 1, "pl": 320_000]
        ])
        var active: MusicProvider? = .qq
        var ticket = UUID()
        var played: Track?
        let result = try await CodaSearchPlaybackCoordinator.play(
            track: original, source: .netease, registeredTracks: [original],
            fixture: false, switching: false, isCurrent: { true }, initialContextIsCurrent: { true },
            activeProvider: { active }, contextTicket: { ticket },
            selectProvider: { provider in active = provider; ticket = UUID(); return ticket },
            startPlayback: { played = $0 }
        )
        #expect(result == .played)
        #expect(played?.id == original.id)
        #expect(played?.platformSong == nil)
        #expect(played?.alias == ["original alias"])
        #expect(played?.embeddedPrivilege?.pl == 320_000)
    }

    @Test func fixtureAndUnregisteredRowsNeverSwitchOrPlay() async throws {
        let fixture = try Self.vendorTrack(.qq, id: 530)
        var active: MusicProvider? = .netease
        var selections = 0
        var plays = 0
        let fixtureResult = try await CodaSearchPlaybackCoordinator.play(
            track: fixture, source: .qq, registeredTracks: [fixture], fixture: true,
            switching: false, isCurrent: { true }, initialContextIsCurrent: { true }, activeProvider: { active },
            contextTicket: { UUID() },
            selectProvider: { _ in selections += 1; return UUID() }, startPlayback: { _ in plays += 1 }
        )
        let unregisteredResult = try await CodaSearchPlaybackCoordinator.play(
            track: fixture, source: .qq, registeredTracks: [], fixture: false,
            switching: false, isCurrent: { true }, initialContextIsCurrent: { true }, activeProvider: { active },
            contextTicket: { UUID() },
            selectProvider: { _ in selections += 1; return UUID() }, startPlayback: { _ in plays += 1 }
        )
        #expect(fixtureResult == .rejected)
        #expect(unregisteredResult == .rejected)
        #expect(selections == 0 && plays == 0 && active == .netease)
    }

    @Test func supersededTapCannotPlayAfterProviderActivation() async throws {
        let track = try Self.vendorTrack(.kugou, id: 540)
        var active: MusicProvider? = .netease
        var current = true
        var ticket = UUID()
        var plays = 0
        let result = try await CodaSearchPlaybackCoordinator.play(
            track: track, source: .kugou, registeredTracks: [track], fixture: false,
            switching: false, isCurrent: { current }, initialContextIsCurrent: { true }, activeProvider: { active },
            contextTicket: { ticket },
            selectProvider: { provider in
                active = provider
                ticket = UUID()
                current = false
                return ticket
            },
            startPlayback: { _ in plays += 1 }
        )
        #expect(result == .stale)
        #expect(plays == 0)
    }

    @Test func mismatchedSourceAndSwitchInProgressAreRejected() throws {
        let qq = try Self.vendorTrack(.qq, id: 550)
        #expect(!CodaSearchInteractionPolicy.canPlaySearchTrack(
            qq, source: .kugou, registeredTracks: [qq], fixture: false, switching: false))
        #expect(!CodaSearchInteractionPolicy.canPlaySearchTrack(
            qq, source: .qq, registeredTracks: [qq], fixture: false, switching: true))
        #expect(CodaSearchInteractionPolicy.sourceProvider(of: qq) == .qq)
    }

    @Test func sameProviderDoesNotActivateAndPreservesTappedTrack() async throws {
        for provider in [MusicProvider.qq, .kugou, .qishui] {
            let track = try Self.vendorTrack(provider, id: 560)
            let state = PlaybackState(active: provider)
            let result = try await state.play(track, source: provider)
            #expect(result == .played)
            #expect(state.selections == 0)
            #expect(state.played.count == 1)
            #expect(state.played.first?.platformSong == track.platformSong)
        }
    }

    @Test func staleInitialGenerationOrSessionNeverActivatesOrPlays() async throws {
        let track = try Self.vendorTrack(.qq, id: 570)
        for staleSession in [false, true] {
            let state = PlaybackState(active: .netease)
            state.current = staleSession
            state.initialContextCurrent = !staleSession
            let result = try await state.play(track, source: .qq)
            #expect(result == .stale)
            #expect(state.selections == 0 && state.played.isEmpty)
        }
    }

    @Test func wrongProviderAndSwitchInProgressNeverActivateOrPlay() async throws {
        let track = try Self.vendorTrack(.qq, id: 580)
        for switching in [false, true] {
            let state = PlaybackState(active: .netease)
            let result = try await state.play(track, source: switching ? .qq : .kugou,
                                              switching: switching)
            #expect(result == .rejected)
            #expect(state.selections == 0 && state.played.isEmpty)
        }
    }

    @Test func switchErrorPropagatesWithoutPlaying() async throws {
        let track = try Self.vendorTrack(.qq, id: 590)
        let state = PlaybackState(active: .netease)
        do {
            _ = try await state.play(track, source: .qq, select: { _ in
                throw SwitchFailure.failed
            })
            Issue.record("Expected account activation error")
        } catch SwitchFailure.failed { }
        #expect(state.selections == 1 && state.played.isEmpty)
    }

    @Test func incompleteActivationNeverPlays() async throws {
        let track = try Self.vendorTrack(.qq, id: 600)
        let state = PlaybackState(active: .netease)
        let result = try await state.play(track, source: .qq, select: { _ in state.ticket })
        #expect(result == .stale)
        #expect(state.selections == 1 && state.played.isEmpty)
    }

    @Test func cancellationDuringSuspendedActivationNeverPlays() async throws {
        let track = try Self.vendorTrack(.qq, id: 610)
        let state = PlaybackState(active: .netease)
        let gate = ActivationGate()
        let task = Task { @MainActor in
            try await state.play(track, source: .qq, select: { provider in
                let receipt = state.commit(provider)
                await gate.suspend()
                return receipt
            })
        }
        await gate.waitUntilSuspended()
        task.cancel()
        gate.resume()
        do {
            _ = try await task.value
            Issue.record("Expected cancelled tap to throw")
        } catch is CancellationError { }
        #expect(state.selections == 1 && state.played.isEmpty)
    }

    @Test(arguments: ["logout", "account replacement", "same-provider activation", "generation"])
    func activationReceiptCannotBeReplacedDuringBootstrap(_ interruption: String) async throws {
        let track = try Self.vendorTrack(.qq, id: 620)
        let state = PlaybackState(active: .netease)
        let gate = ActivationGate()
        let task = Task { @MainActor in
            try await state.play(track, source: .qq, select: { provider in
                let committedReceipt = state.commit(provider)
                await gate.suspend()
                return committedReceipt
            })
        }
        await gate.waitUntilSuspended()
        // Keep the provider equal: a provider-only check would incorrectly play.
        if interruption == "generation" { state.current = false }
        else { state.ticket = UUID() }
        gate.resume()
        let result = try await task.value
        #expect(result == .stale)
        #expect(state.selections == 1 && state.played.isEmpty)
    }

    @Test func neteaseLogoutDuringBootstrapInvalidatesAuthenticationEvenWithSameTicket() async throws {
        let original = try PlatformMusicAPI.decode(Track.self, ["id": 630, "name": "native"])
        let state = PlaybackState(active: .qq)
        let gate = ActivationGate()
        var authenticationKey: String? = "synthetic-signed-in-fingerprint"
        let task = Task { @MainActor in
            try await state.play(original, source: .netease, select: { provider in
                let receipt = state.commit(provider)
                let committedAuthenticationKey = authenticationKey
                await gate.suspend()
                guard CodaSearchInteractionPolicy.activationReceiptIsCurrent(
                    ticket: receipt, authenticationKey: committedAuthenticationKey,
                    currentTicket: state.ticket, currentAuthenticationKey: authenticationKey
                ) else { throw CancellationError() }
                return receipt
            })
        }
        await gate.waitUntilSuspended()
        let unchangedTicket = state.ticket
        authenticationKey = nil // NetEase logout clears auth without changing its ticket.
        gate.resume()
        do {
            _ = try await task.value
            Issue.record("Expected logged-out activation receipt to be rejected")
        } catch is CancellationError { }
        #expect(state.ticket == unchangedTicket && state.active == .netease)
        #expect(state.selections == 1 && state.played.isEmpty)
    }

    @Test func expectedPublishedCommitSurvivesSuspendedBootstrapAndPlaysOnce() async throws {
        let store = SessionFixture()
        let originID = store.lifecycle.presentationID(for: store.identity)
        let track = try Self.vendorTrack(.qq, id: 640)
        let gate = ActivationGate()
        var plays = 0
        let task = Task { @MainActor in
            try await CodaSearchPlaybackCoordinator.play(
                track: track, source: .qq, registeredTracks: [track], fixture: false,
                switching: false, isCurrent: {
                    store.allowInitial || store.lifecycle.owns(store.request, session: store.identity)
                },
                initialContextIsCurrent: { true }, activeProvider: { store.provider },
                contextTicket: { store.ticket }, selectProvider: { _ in
                    let observation = store.commit()
                    defer { observation.cancel() }
                    await gate.suspend()
                    guard store.lifecycle.owns(store.request, session: store.identity) else { throw CancellationError() }
                    return store.ticket
                }, startPlayback: { selected in
                    #expect(selected.platformSong == track.platformSong)
                    plays += 1
                })
        }
        // Initial pre-activation isCurrent is valid before a commit exists.
        // The fixture permits only that initial identity, then the exact receipt.
        store.allowInitial = true
        await gate.waitUntilSuspended()
        #expect(store.lifecycle.presentationID(for: store.identity) == originID)
        #expect(store.lifecycle.preservesRoute(for: store.identity))
        gate.resume()
        #expect(try await task.value == .played)
        #expect(plays == 1)
    }

    @Test(arguments: ["revision", "authentication", "ticket", "logout", "leave", "query", "scope", "category"])
    func publishedLifecycleRejectsExternalChangesDuringBootstrap(_ change: String) async throws {
        let store = SessionFixture()
        let gate = ActivationGate()
        var played = false
        let task = Task { @MainActor in
            let observation = store.commit()
            defer { observation.cancel() }
            await gate.suspend()
            if store.lifecycle.owns(store.request, session: store.identity) && !Task.isCancelled { played = true }
        }
        await gate.waitUntilSuspended()
        switch change {
        case "revision": store.revision = UUID()
        case "authentication": store.authenticationKey = "synthetic-replacement"
        case "ticket": store.ticket = UUID()
        case "logout": store.lifecycle.invalidate()
        default: store.lifecycle.cancel(store.request); task.cancel()
        }
        #expect(!store.lifecycle.owns(store.request, session: store.identity))
        #expect(!store.lifecycle.preservesRoute(for: store.identity))
        gate.resume()
        await task.value
        #expect(!played)
    }

    #if canImport(UIKit)
    @Test func mountedSearchKeepsItsIdentityAndRouteOnlyForExpectedPublishedCommit() async throws {
        let store = SessionFixture()
        let counts = MountCounts()
        let host = UIHostingController(rootView: LifecycleHost(store: store, lifecycle: store.lifecycle, counts: counts))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true; window.rootViewController = nil }
        try await Task.sleep(for: .milliseconds(80))
        #expect(counts.appeared == 1 && counts.disappeared == 0)
        let observation = store.commit()
        defer { observation.cancel() }
        try await Task.sleep(for: .milliseconds(80))
        #expect(counts.appeared == 1 && counts.disappeared == 0)
        #expect(store.lifecycle.owns(store.request, session: store.identity))
        // Same provider/ticket, but a different revision is external and must
        // exercise the old reset-to-home/removal behavior, not this exemption.
        store.revision = UUID()
        try await Task.sleep(for: .milliseconds(80))
        #expect(counts.disappeared == 1)
        #expect(!store.lifecycle.preservesRoute(for: store.identity))
    }

    @MainActor private final class MountCounts { var appeared = 0; var disappeared = 0 }
    @MainActor private struct LifecycleHost: View {
        @ObservedObject var store: SessionFixture
        @ObservedObject var lifecycle: CodaSearchSessionLifecycle
        let counts: MountCounts
        @State private var searchVisible = true
        var body: some View {
            Group {
                if searchVisible {
                    Color.clear
                        .onAppear { counts.appeared += 1 }
                        .onDisappear { counts.disappeared += 1; lifecycle.cancel(store.request) }
                        .id(lifecycle.presentationID(for: store.identity))
                }
            }
            .onChange(of: store.revision) { _ in
                if !lifecycle.preservesRoute(for: store.identity) { searchVisible = false }
            }
        }
    }
    #endif

    @MainActor private final class SessionFixture: ObservableObject {
        @Published var revision = UUID()
        var provider = MusicProvider.netease
        var ticket = UUID()
        var authenticationKey: String? = "synthetic-initial"
        var allowInitial = true
        let request = UUID()
        let lifecycle = CodaSearchSessionLifecycle()
        var identity: CodaSearchSessionIdentity {
            .init(revision: revision, provider: provider, ticket: ticket, authenticationKey: authenticationKey)
        }
        func commit() -> AnyCancellable {
            let origin = identity
            provider = .qq; ticket = UUID(); authenticationKey = "synthetic-target"
            let observation = lifecycle.observeNextCommit(request: request, origin: origin,
                provider: provider, ticket: ticket, authenticationKey: authenticationKey,
                revisions: $revision, snapshot: { revision in
                    .init(revision: revision, provider: self.provider, ticket: self.ticket,
                          authenticationKey: self.authenticationKey)
                })
            revision = UUID()
            allowInitial = false
            return observation
        }
    }

    private enum SwitchFailure: Error { case failed }

    @MainActor
    private final class ActivationGate {
        private var suspended: CheckedContinuation<Void, Never>?
        private var arrival: CheckedContinuation<Void, Never>?
        func suspend() async {
            await withCheckedContinuation { continuation in
                suspended = continuation
                arrival?.resume()
                arrival = nil
            }
        }
        func waitUntilSuspended() async {
            if suspended != nil { return }
            await withCheckedContinuation { arrival = $0 }
        }
        func resume() {
            suspended?.resume()
            suspended = nil
        }
    }

    @MainActor
    private final class PlaybackState {
        var active: MusicProvider?
        var ticket = UUID()
        var current = true
        var initialContextCurrent = true
        var selections = 0
        var played: [Track] = []
        init(active: MusicProvider) { self.active = active }
        func commit(_ provider: MusicProvider) -> UUID {
            active = provider
            ticket = UUID()
            return ticket
        }
        func play(_ track: Track, source: MusicProvider, switching: Bool = false,
                  select: (@MainActor (MusicProvider) async throws -> UUID)? = nil) async throws
            -> CodaSearchPlaybackCoordinator.Result {
            try await CodaSearchPlaybackCoordinator.play(
                track: track, source: source, registeredTracks: [track], fixture: false,
                switching: switching, isCurrent: { self.current },
                initialContextIsCurrent: { self.initialContextCurrent },
                activeProvider: { self.active }, contextTicket: { self.ticket },
                selectProvider: { provider in
                    self.selections += 1
                    if let select { return try await select(provider) }
                    return self.commit(provider)
                }, startPlayback: { self.played.append($0) }
            )
        }
    }

    private static func vendorTrack(_ provider: MusicProvider, id: Int) throws -> Track {
        let source = ProviderSongSource(rawValue: provider.rawValue)!
        let song = ProviderSong(
            id: id, name: "fixture \(provider.rawValue)", artists: "artist", album: "album",
            coverURL: nil, duration: 180, source: source,
            qqMid: provider == .qq ? "mid-\(id)" : nil,
            kugouHash: provider == .kugou ? "hash-\(id)" : nil,
            kugouAlbumAudioId: provider == .kugou ? "audio-\(id)" : nil,
            qishui: provider == .qishui ? QishuiTrackReference(trackID: "\(id)") : nil
        )
        return Track(id: -id, song: song, artists: [ArtistRef(id: 0, name: "artist")],
                     album: AlbumRef(id: 0, name: "album", picUrl: nil))
    }
}
