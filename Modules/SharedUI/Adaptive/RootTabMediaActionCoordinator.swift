import Combine
import Foundation

/// Lives at ContentView, above every replaceable navigation stack and menu host.
/// Menu actions must return before changing AppStorage-backed destination identity:
/// synchronously destroying the currently dismissing context-menu/navigation host is
/// unsafe on iOS. Coalesce rapid selections and cancel a pending action on a tab tap.
@MainActor
final class RootTabMediaActionCoordinator: ObservableObject {
    typealias DismissalWait = @MainActor () async throws -> Void
    private let waitForDismissal: DismissalWait
    private var pending: Task<Void, Never>?
    private var generation = UUID()

    init(waitForDismissal: @escaping DismissalWait = {
        // SwiftUI does not expose UIContextMenuInteraction's dismissal animator.
        // Let the standard dismissal finish; never mutate the host in its action.
        await Task.yield()
        try await Task.sleep(for: .milliseconds(450))
    }) {
        self.waitForDismissal = waitForDismissal
    }

    func schedule(_ action: @escaping @MainActor () -> Void) {
        cancel()
        let token = generation
        let wait = waitForDismissal
        pending = Task { @MainActor [weak self] in
            do { try await wait() } catch { return }
            guard !Task.isCancelled, let self, self.generation == token else { return }
            self.pending = nil
            action()
        }
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        generation = UUID()
    }
}
