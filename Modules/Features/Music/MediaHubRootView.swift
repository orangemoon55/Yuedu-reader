import SwiftUI

/// Music destination; the root tab keeps ownership of its original reading stack.
struct MediaHubRootView: View {
    let kind: MediaHubKind
    let isLibrary: Bool
    let onClose: () -> Void
    let onReturnToBookshelf: (() -> Void)?
    let tabBarIconSize: CGFloat
    let tabBarHidesLabels: Bool
    private let embedsNavigationStack: Bool
    @Environment(\.rootTabMediaMenuContext) private var mediaMenuContext

    init(kind: MediaHubKind, isLibrary: Bool, onClose: @escaping () -> Void,
         onReturnToBookshelf: (() -> Void)? = nil,
         tabBarIconSize: CGFloat = 24, tabBarHidesLabels: Bool = false,
         embedsNavigationStack: Bool = true) {
        self.kind = kind
        self.isLibrary = isLibrary
        self.onClose = onClose
        self.onReturnToBookshelf = onReturnToBookshelf
        self.tabBarIconSize = tabBarIconSize
        self.tabBarHidesLabels = tabBarHidesLabels
        self.embedsNavigationStack = embedsNavigationStack
    }

    var body: some View {
        // Coda owns its navigation stacks and theme. Do not wrap it in the legacy JS layout.
        CodaMusicDestination(isLibrary: isLibrary, onClose: onClose,
                             onReturnToBookshelf: onReturnToBookshelf,
                             tabBarIconSize: tabBarIconSize, tabBarHidesLabels: tabBarHidesLabels)
    }
}
