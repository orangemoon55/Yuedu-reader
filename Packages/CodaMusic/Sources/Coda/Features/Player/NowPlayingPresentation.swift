import SwiftUI

#if os(iOS)
/// Shared geometry and interaction constants for the iPhone Now Playing
/// presentation. Keeping these values together makes the relationship between
/// the drag indicator and the track header explicit and regression-testable.
enum NowPlayingPresentationMetrics {
    static let indicatorTopSpacing: CGFloat = 8
    static let indicatorWidth: CGFloat = 60
    static let indicatorHeight: CGFloat = 5
    static let indicatorHitWidth: CGFloat = 180
    static let indicatorHitHeight: CGFloat = 82

    static let dismissDistance: CGFloat = 110
    static let dismissPrediction: CGFloat = 190
    static let miniPlayerExpandDistance: CGFloat = 28
    static let miniPlayerExpandPrediction: CGFloat = 72
    // A full-height spring overshoots above its final position and briefly
    // exposes the browsing page below the player's bottom edge. Keep the
    // entrance monotonic so the backdrop always covers that edge as it settles.
    static let presentationAnimation = Animation.timingCurve(
        0.16, 1, 0.3, 1,
        duration: 0.52
    )

    static func shouldDismiss(
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) -> Bool {
        translation > dismissDistance || predictedTranslation > dismissPrediction
    }

    static func shouldExpandFromMiniPlayer(
        translation: CGFloat,
        predictedTranslation: CGFloat
    ) -> Bool {
        translation < -miniPlayerExpandDistance
            || predictedTranslation < -miniPlayerExpandPrediction
    }

    /// The system can briefly report no accessory placement while it reparents
    /// the view between the expanded and inline tab-bar containers. Prefer the
    /// compact layout during that undefined interval so a full-width player
    /// cannot be laid out inside the inline container for a transient frame.
    static func shouldUseInlineMiniPlayerLayout(
        placementIsInline: Bool?
    ) -> Bool {
        placementIsInline ?? true
    }
}

private struct NowPlayingExternalBackgroundKey: EnvironmentKey {
    static let defaultValue = false
}

private struct DismissNowPlayingActionKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

struct NowPlayingDismissThenAction {
    let perform: (@escaping () -> Void) -> Void
}

private struct NowPlayingDismissThenActionKey: EnvironmentKey {
    static let defaultValue: NowPlayingDismissThenAction? = nil
}

extension EnvironmentValues {
    var nowPlayingBackgroundIsExternal: Bool {
        get { self[NowPlayingExternalBackgroundKey.self] }
        set { self[NowPlayingExternalBackgroundKey.self] = newValue }
    }

    var dismissNowPlayingAction: (() -> Void)? {
        get { self[DismissNowPlayingActionKey.self] }
        set { self[DismissNowPlayingActionKey.self] = newValue }
    }

    var dismissNowPlayingThenAction: NowPlayingDismissThenAction? {
        get { self[NowPlayingDismissThenActionKey.self] }
        set { self[NowPlayingDismissThenActionKey.self] = newValue }
    }
}

/// The system presentation owns sizing, safe areas and interactive dismissal.
/// Sheets use the native grabber; zoom presentations retain the player handle.
struct IOSNowPlayingPresentation<Content: View>: View {
    @Binding var isPresented: Bool
    var showsDismissIndicator = true
    var deferDismissCompletion: (@escaping () -> Void) -> Void
    @ViewBuilder var content: () -> Content
    @State private var isDismissing = false
    @Environment(\.nowPlayingBackgroundIsExternal) private var backgroundIsExternal

    var body: some View {
        GeometryReader { proxy in
            let isPad = UIDevice.current.userInterfaceIdiom == .pad
            ZStack(alignment: .top) {
                content()
                    .environment(\.dismissNowPlayingAction) { dismiss() }
                    .environment(\.dismissNowPlayingThenAction, NowPlayingDismissThenAction { completion in
                        dismiss(onDismissed: completion)
                    })

                if showsDismissIndicator {
                    indicator
                        .frame(width: isPad ? proxy.size.width : NowPlayingPresentationMetrics.indicatorHitWidth,
                               height: isPad || proxy.size.height > proxy.size.width ? 44 : NowPlayingPresentationMetrics.indicatorHitHeight,
                               alignment: .top)
                        .contentShape(Rectangle())
                        .padding(.top, isPad ? (proxy.size.height > proxy.size.width ? min(32, max(24, proxy.size.height * 0.04)) : NowPlayingSplitGeometry.verticalInset(height: proxy.size.height)) - 1 : 0)
                        .simultaneousGesture(
                            TapGesture().onEnded { dismiss() },
                            including: handleTapDismisses ? .all : .none
                        )
                        .accessibilityLabel("下拉关闭播放页")
                        .accessibilityAction(named: Text("关闭播放页")) { dismiss() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .ignoresSafeArea(.keyboard, edges: UIDevice.current.userInterfaceIdiom == .pad ? .bottom : [])
    }

    /// The zoom presentation (iOS 18+) closes by its own drag; before it the
    /// cover has no system gesture, so a tap on the handle closes it too.
    private var handleTapDismisses: Bool {
        if #available(iOS 18.0, *) { return backgroundIsExternal }
        return true
    }

    private var indicator: some View {
        Capsule()
            .fill(.white.opacity(UIDevice.current.userInterfaceIdiom == .pad ? 0.38 : 0.52))
            .frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 44 : NowPlayingPresentationMetrics.indicatorWidth,
                   height: NowPlayingPresentationMetrics.indicatorHeight)
            .padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 1 : NowPlayingPresentationMetrics.indicatorTopSpacing)
            .accessibilityIdentifier("nowPlayingDismissIndicator")
    }

    private func dismiss(onDismissed completion: (() -> Void)? = nil) {
        guard !isDismissing else { return }
        isDismissing = true
        if let completion { deferDismissCompletion(completion) }
        isPresented = false
    }
}
#endif
