import SwiftUI

/// Music destination; the root tab keeps ownership of its original reading stack.
struct MediaHubRootView: View {
    let kind: MediaHubKind
    let isLibrary: Bool
    let onClose: () -> Void
    private let embedsNavigationStack: Bool
    @Environment(\.rootTabMediaMenuContext) private var mediaMenuContext

    init(kind: MediaHubKind, isLibrary: Bool, onClose: @escaping () -> Void,
         embedsNavigationStack: Bool = true) {
        self.kind = kind
        self.isLibrary = isLibrary
        self.onClose = onClose
        self.embedsNavigationStack = embedsNavigationStack
    }

    var body: some View {
        // Coda owns its navigation stacks and theme. Do not wrap it in the legacy JS layout.
        CodaMusicDestination(isLibrary: isLibrary, onClose: onClose)
    }
}
