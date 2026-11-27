import SwiftUI

/// Player bars currently on screen, in SwiftUI global coordinates (top-left
/// origin of the window's root hosting view). Where the system has no zoom
/// transition (macOS, and iOS before 18) the player grows out of the most
/// recently placed bar and shrinks back into it, so it reads the frame here.
@MainActor
enum NowPlayingZoomSource {
    struct Source {
        var frame: CGRect
        var cornerRadius: CGFloat
    }

    private static var sources: [UUID: (source: Source, order: Int)] = [:]
    private static var counter = 0

    static func update(_ id: UUID, frame: CGRect, cornerRadius: CGFloat) {
        guard frame.width > 1, frame.height > 1, frame.minX.isFinite, frame.minY.isFinite else {
            sources[id] = nil
            return
        }
        counter += 1
        sources[id] = (Source(frame: frame, cornerRadius: min(cornerRadius, frame.height / 2)), counter)
    }

    static func remove(_ id: UUID) { sources[id] = nil }

    /// The most recently placed bar that is still inside `bounds`.
    static func source(within bounds: CGRect) -> Source? {
        sources.values
            .filter { bounds.intersects($0.source.frame) }
            .max { $0.order < $1.order }?
            .source
    }
}

struct NowPlayingZoomSourceReporter: ViewModifier {
    var cornerRadius: CGFloat = 26
    @State private var id = UUID()

    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                let frame = proxy.frame(in: .global)
                Color.clear
                    .onAppear { NowPlayingZoomSource.update(id, frame: frame, cornerRadius: cornerRadius) }
                    .onChange(of: frame) {
                        NowPlayingZoomSource.update(id, frame: $0, cornerRadius: cornerRadius)
                    }
                    .onDisappear { NowPlayingZoomSource.remove(id) }
            }
        )
    }
}
