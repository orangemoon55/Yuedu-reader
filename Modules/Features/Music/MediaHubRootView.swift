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
        Group {
            if embedsNavigationStack {
                NavigationStack { navigationContent }
            } else {
                navigationContent
            }
        }
    }

    private var navigationContent: some View {
        MusicJSSourceView(isLibrary: isLibrary)
            .navigationTitle(localized(isLibrary ? kind.libraryTitleKey : kind.titleKey))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Label(localized("关闭"), systemImage: "xmark") }
                        .accessibilityIdentifier("mediaHub.close")
                }
                if let mediaMenuContext {
                    RootTabMediaToolbar(tab: mediaMenuContext.tab, onSelect: mediaMenuContext.onSelect,
                                        onDefault: mediaMenuContext.onDefault)
                }
            }
            .themedAppSurface(for: .explore)
    }
}
