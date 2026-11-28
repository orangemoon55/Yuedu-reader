import Combine
import Foundation

/// Exact account identity, not merely a provider match. Never log this value.
struct CodaSearchSessionIdentity: Equatable {
    let revision: UUID
    let provider: MusicProvider
    let ticket: UUID
    let authenticationKey: String?
}

/// Preserves only the one session revision synchronously published by this tap's
/// activation commit. Bootstrap may then suspend without destroying its owner.
@MainActor
final class CodaSearchSessionLifecycle: ObservableObject {
    private struct Commit {
        let request: UUID
        let session: CodaSearchSessionIdentity
        let presentationID: UUID
        var active = true
    }
    @Published private var commit: Commit?

    func presentationID(for session: CodaSearchSessionIdentity) -> UUID {
        commit?.session == session ? commit!.presentationID : session.revision
    }

    func preservesRoute(for session: CodaSearchSessionIdentity) -> Bool {
        commit?.session == session && commit?.active == true
    }

    func owns(_ request: UUID, session: CodaSearchSessionIdentity) -> Bool {
        commit?.request == request && preservesRoute(for: session)
    }

    /// Called inside activationCommitted, immediately before changeProvider.
    /// @Published delivers willSet synchronously; use its incoming revision, not
    /// the store's still-old revision. prefix(1) cannot authorize later changes.
    func observeNextCommit(request: UUID, origin: CodaSearchSessionIdentity,
                           provider: MusicProvider, ticket: UUID, authenticationKey: String?,
                           revisions: Published<UUID>.Publisher,
                           snapshot: @escaping (UUID) -> CodaSearchSessionIdentity) -> AnyCancellable {
        let originalID = presentationID(for: origin)
        return revisions.dropFirst().prefix(1).sink { [weak self] revision in
            let destination = snapshot(revision)
            guard destination.revision == revision, revision != origin.revision,
                  provider != origin.provider, destination.provider == provider,
                  destination.ticket == ticket, ticket != origin.ticket,
                  destination.authenticationKey == authenticationKey else { return }
            self?.commit = Commit(request: request, session: destination, presentationID: originalID)
        }
    }

    func cancel(_ request: UUID) {
        guard commit?.request == request else { return }
        // Retain the identity alias so cancelling a query does not itself erase
        // the search field. Authorization and route preservation end immediately.
        commit?.active = false
    }

    func invalidate() { commit = nil }
}
