#if os(macOS)
import SwiftUI
import QuartzCore

/// Animate the navigation canvas without replacing the NavigationStack or
/// rebuilding its retained pages. The sidebar and player dock stay stationary.
struct DesktopNavigationTransition<Content: View>: NSViewRepresentable {
    let selection: SidebarItem
    let path: [Destination]
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeCoordinator() -> Coordinator {
        Coordinator(selection: selection, path: path)
    }

    func makeNSView(context: Context) -> NavigationHost {
        let view = NavigationHost(rootView: hostedContent(context))
        // Let the window propose the canvas size; page intrinsic sizes must
        // not resize the enclosing window when navigating.
        view.sizingOptions = []
        // This host is a full-window canvas, like the sibling sidebar. AppKit
        // otherwise adds titlebar clearance again across the hosting boundary.
        // DesktopContentClearance reserves the shared top edge for every page.
        view.safeAreaRegions = []
        view.wantsLayer = true
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ view: NavigationHost, context: Context) {
        let previous = context.coordinator
        let sectionChanged = previous.selection != selection
        let pathChanged = previous.path != path
        // A sidebar change also clears the old section's detail history. That
        // follow-up update belongs to the fade, rather than a second back push.
        let clearingSectionHistory = previous.isResettingSection && path.isEmpty
        if (sectionChanged || (pathChanged && !clearingSectionHistory)), view.window != nil {
            let transition = CATransition()
            transition.type = sectionChanged || reduceMotion ? .fade : .push
            transition.subtype = path.count < previous.path.count ? .fromLeft : .fromRight
            transition.duration = sectionChanged || reduceMotion ? 0.2 : 0.3
            transition.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            view.layer?.add(transition, forKey: "navigation")
        }
        if sectionChanged {
            previous.isResettingSection = !path.isEmpty
        } else if pathChanged {
            previous.isResettingSection = false
        }
        previous.selection = selection
        previous.path = path
        view.updateContent(hostedContent(context))
    }

    final class NavigationHost: NSHostingView<AnyView> {
        private var pendingContent: AnyView?

        func updateContent(_ content: AnyView) {
            // AppKit already proposes the changing frame to the existing tree.
            // Replacing its root as well performs a second reconciliation for
            // every drag event. Retain the latest environment/actions for release.
            if inLiveResize { pendingContent = content }
            else {
                pendingContent = nil
                rootView = content
            }
        }

        override func viewWillStartLiveResize() {
            super.viewWillStartLiveResize()
            layer?.removeAnimation(forKey: "navigation")
        }

        override func viewDidEndLiveResize() {
            super.viewDidEndLiveResize()
            if let pendingContent {
                self.pendingContent = nil
                rootView = pendingContent
            }
        }
    }

    private func hostedContent(_ context: Context) -> AnyView {
        // A hosting boundary needs the full environment, including account,
        // player, navigation actions and the current appearance.
        AnyView(content().environment(\.self, context.environment))
    }

    final class Coordinator {
        var selection: SidebarItem
        var path: [Destination]
        var isResettingSection = false

        init(selection: SidebarItem, path: [Destination]) {
            self.selection = selection
            self.path = path
        }
    }
}
#endif
