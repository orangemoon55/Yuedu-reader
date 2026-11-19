import SwiftUI
import UIKit

/// Shared by floating navigation and the Discover category selector. The material is
/// intentionally the same `floatingSurfaceBackground` used by every app control; this
/// keeps theme artwork, custom fills, and Reduce Transparency behavior in one place.
struct NavigationGlassCapsule: View {
    let tint: Color
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast

    static func selectionFill(tint: Color, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        // Blend only a trace of the theme tint into an adaptive system neutral. The
        // selected wash remains low-saturation, with enough separation in dark mode.
        let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
        let neutral = UIColor.secondarySystemBackground.resolvedColor(with: traits)
        let accent = UIColor(tint).resolvedColor(with: traits)
        var nr: CGFloat = 0, ng: CGFloat = 0, nb: CGFloat = 0, na: CGFloat = 0
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        _ = neutral.getRed(&nr, green: &ng, blue: &nb, alpha: &na)
        _ = accent.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        let amount: CGFloat = contrast == .increased ? 0.12 : 0.05
        return Color(uiColor: UIColor(
            red: nr * (1 - amount) + ar * amount,
            green: ng * (1 - amount) + ag * amount,
            blue: nb * (1 - amount) + ab * amount,
            alpha: 1
        ))
    }

    var body: some View {
        Capsule(style: .continuous)
            .fill(Color.clear)
            .floatingSurfaceBackground(
                in: Capsule(style: .continuous),
                reduceTransparencyOverride: reduceTransparencyOverride
            )
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(contrast == .increased ? 0.42 : (colorScheme == .dark ? 0.20 : 0.24)),
                        lineWidth: contrast == .increased ? 1.5 : 0.75
                    )
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
