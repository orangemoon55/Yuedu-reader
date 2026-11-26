import SwiftUI

/// Wraps menu-driven route updates in a non-animated transaction. The hosting
/// NavigationStacks remain mounted; this helper deliberately has no timer or task.
@MainActor
struct RootTabMediaActionCoordinator {
    func perform(_ action: @MainActor () -> Void) {
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            action()
        }
    }
}
