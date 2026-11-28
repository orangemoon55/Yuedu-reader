import Foundation

/// Geometry only: reserve the live controls, then let the poster scroll rather
/// than shrinking artwork/text to zero on SE, Split View or accessibility sizes.
struct NowPlayingPosterLayout {
    let viewportHeight: CGFloat
    let coverSide: CGFloat
    let contentWidth: CGFloat

    init(width: CGFloat, height: CGFloat, controlsHeight: CGFloat, accessibilityText: Bool = false) {
        let width = width.isFinite ? max(0, width) : 0
        let height = height.isFinite ? max(0, height) : 0
        let controls = controlsHeight.isFinite ? max(0, controlsHeight) : 0
        contentWidth = min(width, 440)
        viewportHeight = max(0, height - controls)
        let textReserve: CGFloat = accessibilityText ? 288 : 212
        let preferred = min(contentWidth * 0.76, accessibilityText ? 192 : 300)
        coverSide = min(contentWidth, max(min(contentWidth, 136),
                                       min(preferred, viewportHeight - textReserve)))
    }
}
