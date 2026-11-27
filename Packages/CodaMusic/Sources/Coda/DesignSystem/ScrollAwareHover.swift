import SwiftUI
#if os(macOS)
import AppKit

/// Tracks wheel and trackpad scrolling without publishing anything, so
/// hover handlers can consult it without re-rendering the views that read it.
@MainActor
enum ScrollActivity {
    /// Hover entries are ignored for this long after the last scroll event,
    /// which also covers the gaps between momentum events.
    private static let settleInterval: TimeInterval = 0.2
    private static var lastScrollTime: TimeInterval = -.infinity
    private static var monitor: Any?

    static var isScrolling: Bool {
        installIfNeeded()
        return ProcessInfo.processInfo.systemUptime - lastScrollTime < settleInterval
    }

    static func installIfNeeded() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { event in
            // Event timestamps share the system uptime clock.
            ScrollActivity.lastScrollTime = event.timestamp
            return event
        }
    }
}
#endif

extension View {
    /// `onHover` that ignores pointer entries while content scrolls beneath a
    /// stationary pointer. Otherwise every card and row crossed during a
    /// scroll starts its own hover animation and shadow pass. Exits still
    /// arrive, so nothing stays highlighted.
    func scrollAwareHover(perform action: @escaping (Bool) -> Void) -> some View {
        #if os(macOS)
        onHover { hovering in
            if hovering, ScrollActivity.isScrolling { return }
            action(hovering)
        }
        #else
        onHover(perform: action)
        #endif
    }
}
