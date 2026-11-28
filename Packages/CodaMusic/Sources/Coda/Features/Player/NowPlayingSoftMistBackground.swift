import SwiftUI

#if os(iOS)
/// Independent cover-derived portrait surface, shared by preview/full lyrics.
/// No display link, audio-reactive shader, bundled reference assets or network
/// work belongs to this view. A bottom scrim keeps persistent controls readable.
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
                            .blur(radius: 72, opaque: true)
                            .saturation(0.64)
                            .opacity(0.66)
                            .id(artworkKey)
                            .transition(.opacity)
                    }
                    Color.black.opacity(contrast == .increased ? 0.56 : 0.30)
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.08), location: 0),
                        .init(color: .black.opacity(0.20), location: 0.40),
                        .init(color: .black.opacity(0.78), location: 1)
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
