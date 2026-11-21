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
        // A clean tint wash, not gray mixed into blue. Keep the caller's hue;
        // neutral/transparent accents fall back to the app's system-blue direction.
        // Opaque output keeps adaptive primary labels readable over any artwork.
        let dark = scheme == .dark
        let increased = contrast == .increased
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: increased ? .high : .normal)
        ])
        let blue = UIColor.systemBlue.resolvedColor(with: traits)
        let accent = UIColor(tint).resolvedColor(with: traits)
        var br: CGFloat = 0, bg: CGFloat = 0.48, bb: CGFloat = 1, ba: CGFloat = 1
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        _ = blue.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        if !accent.getRed(&ar, green: &ag, blue: &ab, alpha: &aa) {
            ar = br; ag = bg; ab = bb; aa = 1
        }
        // Resolve alpha against blue before measuring hue, including Color.clear.
        aa = min(1, max(0, aa))
        ar = br * (1 - aa) + min(1, max(0, ar)) * aa
        ag = bg * (1 - aa) + min(1, max(0, ag)) * aa
        ab = bb * (1 - aa) + min(1, max(0, ab)) * aa
        let peak = max(ar, max(ag, ab))
        if peak - min(ar, min(ag, ab)) <= peak * 0.12 {
            ar = br; ag = bg; ab = bb
        }
        // Normalize dark imported accents before making the wash; do not turn
        // deep theme colors into muddy gray. Bound chroma to avoid a solid neon pill.
        let high = max(ar, max(ag, ab)), low = min(ar, min(ag, ab))
        let saturation = min(0.80, max(0.55, (high - low) / high))
        let amount: CGFloat = dark ? 1 : (increased ? 0.38 : 0.28)
        func channel(_ value: CGFloat) -> CGFloat {
            1 - saturation * (1 - (value - low) / (high - low)) * amount
        }
        let r = channel(ar), g = channel(ag), b = channel(ab)

        func luminance(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGFloat {
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : CGFloat(pow(Double((value + 0.055) / 1.055), 2.4))
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        // White primary text stays above 4.5:1 (7:1 with Increase Contrast).
        // Light mode stays pastel and visibly separate from unselected surfaces.
        let lower: CGFloat = dark ? (increased ? 0.075 : 0.14) : (increased ? 0.48 : 0.58)
        let upper: CGFloat = dark ? (increased ? 0.095 : 0.17) : (increased ? 0.70 : 0.80)
        let current = luminance(r, g, b)
        let target = min(upper, max(lower, current))
        var adjustment: CGFloat = 0
        let endpoint: CGFloat = current < lower ? 1 : 0
        if current != target {
            var low: CGFloat = 0, high: CGFloat = 1
            for _ in 0..<20 {
                let middle = (low + high) / 2
                let value = luminance(r + (endpoint - r) * middle,
                                      g + (endpoint - g) * middle,
                                      b + (endpoint - b) * middle)
                if (value < target) == (endpoint == 1) { low = middle } else { high = middle }
            }
            adjustment = high
        }
        return Color(uiColor: UIColor(
            red: r + (endpoint - r) * adjustment,
            green: g + (endpoint - g) * adjustment,
            blue: b + (endpoint - b) * adjustment,
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
