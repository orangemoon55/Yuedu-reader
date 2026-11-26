import SwiftUI

/// The root chooses the actions; each existing navigation stack installs its own toolbar.
/// Nil outside an active, regular-width media-capable root (including previews).
struct RootTabMediaMenuContext {
    let tab: RootTabItem
    let onSelect: (MediaHubKind, Bool) -> Void
    let onDefault: (Bool) -> Void
}

private struct RootTabMediaMenuContextKey: EnvironmentKey {
    static var defaultValue: RootTabMediaMenuContext? { nil }
}

extension EnvironmentValues {
    var rootTabMediaMenuContext: RootTabMediaMenuContext? {
        get { self[RootTabMediaMenuContextKey.self] }
        set { self[RootTabMediaMenuContextKey.self] = newValue }
    }
}

/// Shared by floating tab buttons, native iPad sidebar tabs and the wide-layout toolbar.
/// Empty content disables a native TabContent context menu on unrelated tabs.
struct RootTabMediaMenuItems: View {
    let tab: RootTabItem
    let onSelect: (MediaHubKind, Bool) -> Void
    var onDefault: ((Bool) -> Void)? = nil

    var body: some View {
        ForEach(MediaHubKind.quickActionKinds(for: tab)) { kind in
            Button {
                onSelect(kind, tab == .bookshelf)
            } label: {
                Label(
                    localized(tab == .bookshelf ? kind.libraryTitleKey : kind.titleKey),
                    systemImage: kind.systemImage
                )
            }
            .accessibilityIdentifier("rootTabMedia.\(tab.rawValue).\(kind.rawValue)")
        }
        if !MediaHubKind.quickActionKinds(for: tab).isEmpty, let onDefault {
            Divider()
            Button { onDefault(tab == .bookshelf) } label: {
                Label(localized(tab == .bookshelf ? "阅读书架" : "阅读首页"), systemImage: "book")
            }
            .accessibilityIdentifier("rootTabMedia.\(tab.rawValue).reading")
        }
    }
}

/// TabContent.contextMenu is sidebar-only on iOS 18+. This ordinary toolbar Menu is
/// also reachable on iPadOS 17 and when newer iPads show their native top tab bar.
/// It does not replace a tab, install a long-press overlay or change the tab style.
struct RootTabMediaToolbar: ToolbarContent {
    let tab: RootTabItem
    let onSelect: (MediaHubKind, Bool) -> Void
    var onDefault: ((Bool) -> Void)? = nil

    var body: some ToolbarContent {
        if !MediaHubKind.quickActionKinds(for: tab).isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    RootTabMediaMenuItems(tab: tab, onSelect: onSelect, onDefault: onDefault)
                } label: {
                    Label(localized(tab.titleKey), systemImage: "play.rectangle.on.rectangle")
                }
                .accessibilityIdentifier("rootTabMediaMenu.\(tab.rawValue)")
            }
        }
    }
}
