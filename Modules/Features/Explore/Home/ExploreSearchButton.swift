import SwiftUI

/// Exactly the search icon the root navigation used, including imported day/night artwork.
struct ExploreSearchButton: View {
    let open: () -> Void
    var iconSize: CGFloat = 26
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Button(action: open) {
            icon
                .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(RootTabItem.search.titleKey))
        .accessibilityIdentifier("explore.search")
    }

    @ViewBuilder private var icon: some View {
        if let custom = RootTabIconRenderer.customIcon(for: .search, colorScheme: colorScheme,
                                                       pointSize: iconSize,
                                                       displayScale: displayScale, settings: GlobalSettings.shared) {
            Image(uiImage: custom.image)
                .renderingMode(custom.isTemplate ? .template : .original)
                .resizable().scaledToFit()
                .frame(width: iconSize, height: iconSize)
        } else {
            Image(systemName: RootTabItem.search.defaultSystemImage)
                .font(.system(size: FloatingRootTabBarLayout.defaultIconSize))
        }
    }
}
