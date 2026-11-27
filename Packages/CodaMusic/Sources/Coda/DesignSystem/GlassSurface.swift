import SwiftUI

/// One material recipe for navigation and playback chrome on every platform.
/// Native Liquid Glass owns its lighting on OS 26+. Older systems use a live
/// backdrop material with a translucent face and directional edge highlights.
enum GlassSurfaceStyle {
    static let lightFaceOpacity = 0.10
    static let darkFaceOpacity = 0.14
    static let lightHighlightOpacity = 0.58
    static let darkHighlightOpacity = 0.28

    static func faceOpacity(dark: Bool) -> Double {
        dark ? darkFaceOpacity : lightFaceOpacity
    }

    static func highlightOpacity(dark: Bool) -> Double {
        dark ? darkHighlightOpacity : lightHighlightOpacity
    }
}

struct LegacyGlassBackground<S: Shape>: View {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        surface
            .overlay {
                shape.fill((dark ? Color.black : .white)
                    .opacity(GlassSurfaceStyle.faceOpacity(dark: dark)))
            }
            .overlay {
                shape.fill(LinearGradient(
                    colors: [.white.opacity(dark ? 0.07 : 0.18), .white.opacity(0.01),
                             .black.opacity(dark ? 0.06 : 0.02)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            }
            .overlay {
                // Keep the edge inside the surface even for a capsule or circle.
                shape.stroke(LinearGradient(
                    colors: [.white.opacity(GlassSurfaceStyle.highlightOpacity(dark: dark)),
                             .white.opacity(dark ? 0.04 : 0.10),
                             .white.opacity(dark ? 0.14 : 0.30)],
                    startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1)
                    .clipShape(shape)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var surface: some View {
        #if os(macOS)
        // The fallback is used on macOS 15. A live backdrop across the
        // full-height floating sidebar makes native window transforms sample
        // and blur the desktop repeatedly. Keep this surface self-contained.
        shape.fill(Color(nsColor: .windowBackgroundColor))
        #else
        shape.fill(.ultraThinMaterial)
        #endif
    }
}

/// Shape and spacing belong to the caller; lighting, contrast and accessibility
/// belong here so the sidebar, dock, back control and phone capsules stay in sync.
struct FloatingGlassSurface<S: Shape>: ViewModifier {
    let shape: S
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        if #unavailable(macOS 26.0) {
            content
                .compatGlass(in: shape)
                .clipShape(shape)
                .background {
                    // Shadow only the outline behind the opaque fallback.
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                        .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.09),
                                radius: 12, y: 4)
                }
        } else {
            nativeSurface(content)
        }
        #else
        nativeSurface(content)
        #endif
    }

    private func nativeSurface(_ content: Content) -> some View {
        content.compatGlass(in: shape)
            .clipShape(shape)
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.22 : 0.09), radius: 12, y: 4)
    }
}

extension View {
    /// Floating chrome over scrolling content must own every touch inside its
    /// outline. The legacy glass material ignores hits, and on iOS 16/17 a bare
    /// hit shape still lets UIKit lists underneath receive the tap, so an empty
    /// gesture claims the gaps between controls. Apply it to a control
    /// container, never inside a Button's label, where it would win over the
    /// Button's own action.
    func blocksTouchPassThrough(in shape: some Shape) -> some View {
        background {
            shape.fill(Color.clear)
                .contentShape(shape)
                .onTapGesture {}
                #if os(iOS)
                // Before iOS 18 the root hosting view can return the page's
                // nested hosting view from UIKit hit testing even where
                // SwiftUI chrome sits on top, so a tap on a chrome Button also
                // reaches the row underneath. A real UIView behind the chrome
                // ends UIKit hit testing here; the chrome's SwiftUI controls
                // still receive the touch through their own hosting view.
                .background(UIKitTouchBarrier())
                #endif
                .accessibilityHidden(true)
        }
    }
}

#if os(iOS)
private struct UIKitTouchBarrier: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.isAccessibilityElement = false
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}
#endif
