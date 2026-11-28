import SwiftUI

#if os(iOS)
/// Independent cover-derived poster surface. No display link, audio-reactive
/// shader, bundled reference assets or network work belongs to this view.
struct NowPlayingSoftMistBackground: View {
    let artwork: PlatformImage?
    let artworkKey: String?
    let colors: ArtworkColors
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                // Opaque underlay also covers absent/loading/failed artwork.
                Color(red: 0.08, green: 0.08, blue: 0.10)
                if !reduceTransparency {
                    LinearGradient(colors: [colors.primary, colors.secondary],
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                    if let artwork {
                        Image(platformImage: artwork)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.18)
                            .blur(radius: 62, opaque: true)
                            .saturation(0.72)
                            .opacity(0.72)
                            .id(artworkKey)
                            .transition(.opacity)
                    }
                    Color.black.opacity(contrast == .increased ? 0.50 : 0.26)
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.02), location: 0),
                        .init(color: .black.opacity(0.12), location: 0.40),
                        .init(color: .black.opacity(0.62), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.45), value: artworkKey)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
#endif
