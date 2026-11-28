import SwiftUI
@preconcurrency import CodaCore

/// Coda owns all music UI and settings. No legacy Readcc music toolbar or JS sheet.
struct CodaMusicDestination: View {
    let isLibrary: Bool
    let onClose: () -> Void
    let onReturnToBookshelf: (() -> Void)?
    let tabBarIconSize: CGFloat
    let tabBarHidesLabels: Bool
    @ScaledMetric(relativeTo: .caption) private var labelLineHeight: CGFloat = 15
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        IOSMainWindow(initialDestination: isLibrary ? .library : .home,
                      onDeclineDisclaimer: onClose,
                      onReturnToReading: onClose,
                      onReturnToBookshelf: onReturnToBookshelf,
                      embeddedTabBarMetrics: ReadccTabBarMetrics(iconSize: tabBarIconSize,
                          labelLineHeight: labelLineHeight, showsLabels: !tabBarHidesLabels,
                          accessibilityText: dynamicTypeSize.isAccessibilitySize))
    }
}

/// Installed once by the existing app delegate, not by a view appearance.
@MainActor
enum ReadccCodaAudioHost {
    static func install() {
        ReadccHostBridge.configureEmbeddedHost()
        ReadccHostBridge.audio.installReadccStop {
            TTSCoordinator.yieldSystemMediaToMusic() // Includes settings voice previews.
            NowPlayingHub.shared.yieldToCoda()
            AudioSessionActivator.finishPendingOperationsForTakeover()
        }
    }

    static func claimReadcc() { ReadccHostBridge.audio.claim(.readcc) }
    static var codaOwnsAudio: Bool { ReadccHostBridge.audio.owner == .coda }
}
