import Foundation

/// Search metadata may span providers, but native player/write/detail actions
/// belong to the single active provider account. Fixtures are never playable.
enum CodaSearchInteractionPolicy {
    static func activationReceiptIsCurrent(ticket: UUID, authenticationKey: String?,
                                           currentTicket: UUID, currentAuthenticationKey: String?) -> Bool {
        ticket == currentTicket && authenticationKey == currentAuthenticationKey
    }

    static func canUseNativePanel(source: MusicProvider, active: MusicProvider,
                                  context: MusicProvider, fixture: Bool,
                                  switching: Bool) -> Bool {
        !fixture && !switching && source == active && source == context
    }

    static func canPlaySearchTrack(_ track: Track, source: MusicProvider,
                                   registeredTracks: [Track], fixture: Bool,
                                   switching: Bool) -> Bool {
        guard !fixture, !switching, sourceProvider(of: track) == source else { return false }
        if source == .netease {
            guard track.id > 0, track.platformSong == nil else { return false }
        } else {
            guard track.id < 0, track.platformSong?.source.rawValue == source.rawValue else { return false }
        }
        return registeredTracks.contains {
            $0.id == track.id && $0.name == track.name && $0.platformSong == track.platformSong
        }
    }

    static func sourceProvider(of track: Track) -> MusicProvider? {
        if let song = track.platformSong { return MusicProvider(rawValue: song.source.rawValue) }
        return track.id > 0 ? .netease : nil
    }
}

/// A search-result tap is the sole entry point for cross-provider activation.
/// It preserves the registered Track value and delegates activation to the
/// account manager; it never changes account context for search itself.
@MainActor
enum CodaSearchPlaybackCoordinator {
    enum Result: Equatable { case played, stale, rejected }

    static func play(
        track: Track,
        source: MusicProvider,
        registeredTracks: [Track],
        fixture: Bool,
        switching: Bool,
        isCurrent: @MainActor () -> Bool,
        initialContextIsCurrent: @MainActor () -> Bool,
        activeProvider: @MainActor () -> MusicProvider?,
        contextTicket: @MainActor () -> UUID,
        selectProvider: @MainActor (MusicProvider) async throws -> UUID,
        startPlayback: @MainActor (Track) -> Void
    ) async throws -> Result {
        guard CodaSearchInteractionPolicy.canPlaySearchTrack(
            track, source: source, registeredTracks: registeredTracks,
            fixture: fixture, switching: switching
        ) else { return .rejected }
        try Task.checkCancellation()
        guard isCurrent(), initialContextIsCurrent() else { return .stale }

        // The lifecycle returns the ticket captured at activation commit BEFORE
        // bootstrap suspends. A later same-provider activation must not revive this tap.
        let activatedTicket: UUID
        if activeProvider() != source {
            activatedTicket = try await selectProvider(source)
        } else {
            activatedTicket = contextTicket()
        }
        try Task.checkCancellation()
        guard isCurrent(), activeProvider() == source,
              CodaSearchInteractionPolicy.sourceProvider(of: track) == source,
              contextTicket() == activatedTicket else { return .stale }
        startPlayback(track)
        return .played
    }
}
