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
        // A real theme-colored selection, not a nearly invisible 5% surface wash.
        // All consumers retain their adaptive primary label/icon color. Bound the
        // opaque fill's luminance so even white, black and imported theme accents
        // remain distinct without sacrificing small-text contrast in either scheme.
        let dark = scheme == .dark
        let increased = contrast == .increased
        let traits = UITraitCollection(traitsFrom: [
            UITraitCollection(userInterfaceStyle: dark ? .dark : .light),
            UITraitCollection(accessibilityContrast: increased ? .high : .normal)
        ])
        let neutral = (dark ? UIColor.systemGray2 : UIColor.systemGray3).resolvedColor(with: traits)
        let accent = UIColor(tint).resolvedColor(with: traits)
        var nr: CGFloat = 0, ng: CGFloat = 0, nb: CGFloat = 0, na: CGFloat = 0
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        _ = neutral.getRed(&nr, green: &ng, blue: &nb, alpha: &na)
        if !accent.getRed(&ar, green: &ag, blue: &ab, alpha: &aa) {
            ar = nr; ag = ng; ab = nb
        }
        // Composite transparent accents first; Color.clear must not become black.
        // Clamp extended-gamut input into the sRGB range measured below.
        aa = min(1, max(0, aa))
        ar = nr * (1 - aa) + min(1, max(0, ar)) * aa
        ag = ng * (1 - aa) + min(1, max(0, ag)) * aa
        ab = nb * (1 - aa) + min(1, max(0, ab)) * aa
        let amount: CGFloat = increased ? 0.52 : 0.40
        let r = nr * (1 - amount) + ar * amount
        let g = ng * (1 - amount) + ag * amount
        let b = nb * (1 - amount) + ab * amount

        func luminance(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) -> CGFloat {
            func linear(_ value: CGFloat) -> CGFloat {
                value <= 0.04045 ? value / 12.92 : CGFloat(pow(Double((value + 0.055) / 1.055), 2.4))
            }
            return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
        }
        let lower: CGFloat = dark ? (increased ? 0.06 : 0.08) : 0.32
        let upper: CGFloat = dark ? (increased ? 0.095 : 0.14) : (increased ? 0.46 : 0.58)
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
