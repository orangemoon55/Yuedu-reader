import Foundation
import Observation

/// iOS 17 must not resize a content-height sheet, reveal its navigation bar and
/// push a settings Form in the same update. Hand the route to the reader first;
/// the reader presents it only from the quick sheet's actual onDismiss callback.
@MainActor @Observable
final class ReaderQuickPanelNavigation {
    var settingsDestination: ReaderQuickPanelRoute?
    private(set) var isHandingOff = false
    @ObservationIgnored let osMajorVersion: Int

    init(osMajorVersion: Int = ProcessInfo.processInfo.operatingSystemVersion.majorVersion) {
        self.osMajorVersion = osMajorVersion
    }

    static func presentsInParent(_ route: ReaderQuickPanelRoute, osMajorVersion: Int) -> Bool {
        switch route {
        case .settings, .display, .spacing, .headerFooter, .decoration, .chapterTitleStyle, .commentBubble:
            return osMajorVersion < 18
        case .tableOfContents, .bookmarks, .readingAloud, .autoRead, .touchZoneEditor, .styleImporter, .paywall:
            return true
        }
    }

    func select(_ route: ReaderQuickPanelRoute, handOff: (ReaderQuickPanelRoute) -> Void) {
        guard !isHandingOff else { return }
        if Self.presentsInParent(route, osMajorVersion: osMajorVersion) {
            isHandingOff = true
            handOff(route)
        } else {
            settingsDestination = route
        }
    }

    /// The same SwiftUI sheet value can be presented again without a fresh init.
    func appeared() {
        if settingsDestination == nil { isHandingOff = false }
    }
}

/// Geometry is a measurement, not an instruction to continuously rewrite a detent.
/// Ignore invalid values, sub-point jitter and measurements while pushing/dismissing.
enum ReaderQuickPanelHeightPolicy {
    static func measurement(_ value: CGFloat, replacing previous: CGFloat,
                            isRoot: Bool, minimum: CGFloat = 0) -> CGFloat? {
        guard isRoot, value.isFinite, value >= minimum else { return nil }
        let rounded = value.rounded(.toNearestOrAwayFromZero)
        guard abs(rounded - previous) >= 1 else { return nil }
        return rounded
    }
}
