import SwiftUI

/// Shared bounds for the iPad and Mac player, measured inside system safe areas.
struct NowPlayingSplitGeometry {
    let size: CGSize
    let reservedLeftHeight: CGFloat
    /// The iPhone's landscape height is scarce, so it keeps the shared split
    /// rules but sits closer to its wider handle.
    var handleWidth: CGFloat = Self.handleWidth
    var handleToContentSpacing: CGFloat = Self.handleToContentSpacing
    /// Side margin used while the cover is limited by width. The iPhone uses
    /// a smaller one so its cover fills the short landscape height.
    var preferredHorizontalInset: CGFloat? = nil

    static let handleWidth: CGFloat = 44
    static let handleHeight: CGFloat = 5
    static let handleToContentSpacing: CGFloat = 32
    static func verticalInset(height: CGFloat) -> CGFloat {
        8
    }
    var verticalInset: CGFloat { Self.verticalInset(height: size.height) }
    var top: CGFloat { verticalInset + Self.handleHeight + handleToContentSpacing }
    var contentHeight: CGFloat { max(0, size.height - top - verticalInset) }
    // The shared visual handle is centered; its leading edge is the divider.
    var halfWidth: CGFloat { max(0, (size.width - handleWidth) * 0.5) }
    var horizontalInset: CGFloat {
        let preferred = preferredHorizontalInset ?? min(72, max(24, size.width * 0.05))
        // Increase the equal side margins when a short viewport limits the square cover.
        let availableCoverHeight = max(0, contentHeight - reservedLeftHeight)
        return min(halfWidth * 0.5, max(preferred, (halfWidth - availableCoverHeight) * 0.5))
    }
    var playerWidth: CGFloat { max(0, halfWidth - horizontalInset * 2) }
    var panelWidth: CGFloat { max(0, size.width - halfWidth - horizontalInset) }
}

private struct NowPlayingFlushPanelEdgesKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var nowPlayingFlushPanelEdges: Bool {
        get { self[NowPlayingFlushPanelEdgesKey.self] }
        set { self[NowPlayingFlushPanelEdgesKey.self] = newValue }
    }
}
