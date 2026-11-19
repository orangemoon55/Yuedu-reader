import SwiftUI

/// Shared by floating navigation and the Discover category selector.
struct NavigationGlassCapsule: View {
    let tint: Color
    var reduceTransparencyOverride: Bool? = nil
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.accessibilityReduceTransparency) private var systemReduceTransparency

    private var reduceTransparency: Bool { reduceTransparencyOverride ?? systemReduceTransparency }

    static func selectionFill(tint: Color, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color {
        tint.opacity(contrast == .increased ? 0.28 : (scheme == .dark ? 0.22 : 0.12))
    }

    var body: some View {
        Capsule(style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                Capsule(style: .continuous)
                    .fill(reduceTransparency ? Color(uiColor: .secondarySystemBackground)
                          : Color(red: 0.83, green: 0.77, blue: 0.68).opacity(colorScheme == .dark ? 0.04 : 0.12))
            }
            .overlay { Capsule(style: .continuous).fill(tint.opacity(reduceTransparency ? 0.04 : 0.035)) }
            .overlay {
                Capsule(style: .continuous).strokeBorder(
                    Color.white.opacity(contrast == .increased ? 0.65 : (colorScheme == .dark ? 0.16 : 0.55)),
                    lineWidth: contrast == .increased ? 1.5 : 0.75
                )
            }
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.12), radius: 12, y: 5)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
