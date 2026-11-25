import SwiftUI
import UIKit

/// Readcc's public-API glass renderer. All supported systems use the same layers;
/// no UIGlassEffect, private backdrop filter, runtime selector or frame snapshot.
/// Only a view's background is painted: layout, icons and hit testing stay with it.
struct ReadccGlassPalette: Equatable {
    let lightRim: Double
    let darkRim: Double
    let wash: Double
    let selectedWash: Double
    let sheen: Double
    let shadow: Double
    let edgeWidth: CGFloat

    static func resolve(dark: Bool, increasedContrast: Bool) -> Self {
        Self(lightRim: 0, darkRim: 0,
             wash: dark ? 0.08 : 0.28,
             selectedWash: increasedContrast ? 1 : (dark ? 0.24 : 0.18),
             sheen: dark ? 0.035 : 0.10,
             shadow: dark ? 0.08 : 0.035,
             edgeWidth: 0)
    }
}

/// UIKit's live backdrop material is used on every supported system, including iOS26;
/// it samples scrolling content behind the view without blurring foreground labels.
/// Its style is system-controlled rather than an app-defined blur radius.
enum ReadccBackdropBlurMaterial: Equatable {
    case light
    case dark

    static func resolve(dark: Bool) -> Self {
        dark ? .dark : .light
    }

    var uiBlurStyle: UIBlurEffect.Style {
        switch self {
        case .light: .systemMaterialLight
        case .dark: .systemMaterialDark
        }
    }
}

private struct ReadccBackdropBlur: UIViewRepresentable {
    let dark: Bool

    func makeUIView(context: Context) -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: effect)
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: UIVisualEffectView, context: Context) {
        let style: UIUserInterfaceStyle = dark ? .dark : .light
        guard view.overrideUserInterfaceStyle != style else { return }
        view.overrideUserInterfaceStyle = style
        view.effect = effect
    }

    private var effect: UIBlurEffect {
        UIBlurEffect(style: ReadccBackdropBlurMaterial.resolve(dark: dark).uiBlurStyle)
    }
}

/// Directional double rim, shallow body wash, and broad specular reflection.
/// Generic Shape retains each caller's existing outline, including circles/cards.
struct ReadccLegacyGlassSurface<SurfaceShape: Shape>: View {
    let shape: SurfaceShape
    var selectedTint: Color? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    private var palette: ReadccGlassPalette {
        .resolve(dark: scheme == .dark, increasedContrast: contrast == .increased)
    }

    var body: some View {
        ReadccBackdropBlur(dark: scheme == .dark)
            .overlay {
                shape.fill((scheme == .dark ? Color.black : .white).opacity(palette.wash))
            }
            .overlay {
                if let selectedTint {
                    shape.fill(selectedTint.opacity(palette.selectedWash))
                }
            }
            .overlay {
                shape.fill(LinearGradient(
                    stops: [.init(color: .white.opacity(palette.sheen), location: 0),
                            .init(color: .white.opacity(palette.sheen * 0.12), location: 0.43),
                            .init(color: .clear, location: 0.58),
                            .init(color: .white.opacity(palette.sheen * 0.32), location: 1)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .clipShape(shape)
            .shadow(color: .black.opacity(palette.shadow), radius: 8, x: 0, y: 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

/// Selected glass is a lens over the backdrop, not an opaque painted pill.
/// Accessibility requests still use Build32's measured, opaque contrast fallback.
struct ReadccGlassSelection<SurfaceShape: Shape>: View {
    let shape: SurfaceShape
    let tint: Color
    var reduceTransparencyOverride: Bool? = nil
    /// Selected controls already on a glass rail reuse its live backdrop.
    var samplesBackdrop = true
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast
    @Bindable private var settings = GlobalSettings.shared

    var body: some View {
        let color = NavigationGlassCapsule.selectionFill(tint: tint, scheme: scheme, contrast: contrast)
        if contrast == .increased || !InterfaceGlassPolicy.shouldUseGlass(
            isEnabled: settings.interfaceFrostedGlass,
            systemReduceTransparency: reduceTransparency,
            override: reduceTransparencyOverride
        ) {
            shape.fill(color)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        } else if samplesBackdrop {
            ReadccLegacyGlassSurface(shape: shape, selectedTint: color)
        } else {
            shape.fill(color.opacity(scheme == .dark ? 0.24 : 0.18))
                .overlay {
                    shape.fill(LinearGradient(colors: [.white.opacity(0.08), .clear],
                                              startPoint: .topLeading, endPoint: .bottomTrailing))
                }
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }
}

private struct ReadccGlassControlSurface: ViewModifier {
    let cornerRadius: CGFloat
    let selected: Bool
    let onDark: Bool

    private var outline: RoundedRectangle {
        RoundedRectangle(cornerRadius: max(0, cornerRadius), style: .continuous)
    }

    func body(content: Content) -> some View {
        content.background {
            Group {
                if selected {
                    ReadccGlassSelection(shape: outline, tint: DSColor.accent)
                } else {
                    Color.clear.floatingSurfaceBackground(in: outline,
                        fill: onDark ? Color(white: 0.12) : DSColor.surface)
                }
            }
            .environment(\.colorScheme, onDark ? .dark : nilScheme)
            .allowsHitTesting(false)
        }
    }

    @Environment(\.colorScheme) private var nilScheme
}

extension View {
    /// Paints only the background. It never adds padding, a frame or a gesture.
    func readccGlassSurface(cornerRadius: CGFloat = 22, selected: Bool = false,
                            onDark: Bool = false) -> some View {
        modifier(ReadccGlassControlSurface(cornerRadius: cornerRadius,
                                           selected: selected, onDark: onDark))
    }
}

/// An optical press response, intentionally not a layout/scale transformation.
/// The original Button still owns taps, cancellation, VoiceOver and scroll intent.
struct ReadccGlassPressStyle: ButtonStyle {
    var cornerRadius: CGFloat = 24
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Bindable private var settings = GlobalSettings.shared

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                if settings.interfaceFrostedGlass && !reduceTransparency {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(RadialGradient(colors: [.white.opacity(0.32), .white.opacity(0.05), .clear],
                                             center: .topLeading, startRadius: 0, endRadius: 110))
                        .opacity(configuration.isPressed ? 1 : 0)
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
            }
            .brightness(configuration.isPressed ? 0.035 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: configuration.isPressed ? 0.12 : 0.22),
                       value: configuration.isPressed)
    }
}
