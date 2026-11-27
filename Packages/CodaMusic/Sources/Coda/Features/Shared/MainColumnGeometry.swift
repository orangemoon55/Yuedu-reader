import SwiftUI

/// Only horizontal geometry affects the floating player and ambient chrome.
/// MainWindow stores this reference in State without subscribing to it; small
/// chrome views observe it so split-view animation does not rebuild navigation.
@MainActor
final class MainColumnGeometry: ObservableObject {
    struct Layout: Equatable {
        var width: CGFloat = 0
        var leadingInset: CGFloat = 0

        init(frame: CGRect = .zero) {
            width = frame.width
            leadingInset = frame.minX
        }
    }

    @Published private(set) var layout = Layout()

    func update(_ next: Layout, animation: Animation? = nil) {
        guard next != layout else { return }
        withAnimation(animation) { layout = next }
    }
}

/// Preserve the last usable viewport through scene deactivation. UIKit's
/// snapshot/reattachment layouts must not resize scroll views and clamp their
/// native offsets. This stores geometry only; it never scrolls a page.
struct SceneViewportSize {
    private(set) var lastActiveSize: CGSize?

    func resolved(_ proposed: CGSize, active: Bool) -> CGSize {
        if active, Self.isUsable(proposed) { return proposed }
        return lastActiveSize ?? (Self.isUsable(proposed) ? proposed : .zero)
    }

    mutating func record(_ proposed: CGSize, active: Bool) {
        guard active, Self.isUsable(proposed) else { return }
        lastActiveSize = proposed
    }

    private static func isUsable(_ size: CGSize) -> Bool {
        size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0
    }
}

private struct MainColumnGeometryKey: EnvironmentKey {
    static let defaultValue: MainColumnGeometry? = nil
}

extension EnvironmentValues {
    var mainColumnGeometry: MainColumnGeometry? {
        get { self[MainColumnGeometryKey.self] }
        set { self[MainColumnGeometryKey.self] = newValue }
    }
}

#if os(iOS)
/// Measure the split controller itself: its detail root leaves the visible
/// navigation hierarchy after a push and no longer reports size changes.
struct IPadMainColumnGeometryReader: UIViewControllerRepresentable {
    let geometry: MainColumnGeometry
    @Environment(\.scenePhase) private var scenePhase

    func makeUIViewController(context: Context) -> SplitColumnGeometryController {
        let controller = SplitColumnGeometryController()
        controller.probe.geometry = geometry
        return controller
    }

    func updateUIViewController(_ controller: SplitColumnGeometryController, context: Context) {
        controller.probe.geometry = geometry
        if scenePhase == .active { controller.probe.scheduleUpdate() }
    }
}

final class SplitColumnGeometryController: UIViewController {
    let probe = SplitColumnGeometryProbe()
    override func loadView() {
        probe.isUserInteractionEnabled = false
        probe.accessibilityElementsHidden = true
        view = probe
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        probe.scheduleUpdate()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        probe.scheduleUpdate()
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.probe.scheduleUpdate()
        }, completion: { [weak self] _ in
            self?.probe.rotationDidFinish()
        })
    }
}

/// The native split controller expresses sidebar clearance through safe areas.
/// Legacy iPad chrome is laid out directly by MainWindow instead.
struct IPadDetailColumnContent<Content: View>: View {
    @ObservedObject var geometry: MainColumnGeometry
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .environment(\.musicLibraryContentWidth,
                         geometry.layout.width > 0 ? geometry.layout.width : .infinity)
    }
}

final class SplitColumnGeometryProbe: UIView {
    var geometry: MainColumnGeometry?
    private var updatePending = false
    private weak var detailProbe: SplitDetailBoundsProbe?
    private var lastWindowSize: CGSize?
    private var pendingAnimationDuration: TimeInterval = 0
    private var transitionInFlight = false

    override init(frame: CGRect) {
        super.init(frame: frame)
        // The first layout can happen before the scene becomes active. That
        // measurement is deliberately ignored; activation must request another
        // even when UIKit has no further layout to perform.
        NotificationCenter.default.addObserver(self, selector: #selector(sceneDidActivate(_:)),
                                               name: UIScene.didActivateNotification, object: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit { NotificationCenter.default.removeObserver(self) }

    @objc private func sceneDidActivate(_ notification: Notification) {
        guard let scene = notification.object as? UIWindowScene, scene === window?.windowScene else { return }
        scheduleUpdate()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        scheduleUpdate()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        scheduleUpdate()
    }

    func rotationDidFinish() {
        guard let root = window?.rootViewController,
              let split = splitController(in: root) else { return }
        split.view.setNeedsLayout()
        split.view.layoutIfNeeded()
        if let detail = split.viewController(for: .secondary)?.viewIfLoaded {
            detail.invalidateIntrinsicContentSize()
            detail.setNeedsLayout()
            detail.layoutIfNeeded()
        }
        scheduleUpdate()
    }

    func scheduleUpdate() {
        // Publishing on the next run loop loses UIKit's animation context.
        // Retain its timing before leaving the split view's layout pass.
        pendingAnimationDuration = max(pendingAnimationDuration, UIView.inheritedAnimationDuration)
        guard !updatePending else { return }
        updatePending = true
        // UIKit must finish laying out the split columns before reading them;
        // publish outside SwiftUI's current layout/update transaction.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.updatePending = false
            let animationDuration = self.pendingAnimationDuration
            self.pendingAnimationDuration = 0
            guard let window = self.window,
                  window.windowScene?.activationState == .foregroundActive,
                  let root = window.rootViewController,
                  let split = self.splitController(in: root),
                  let detail = split.viewController(for: .secondary)?.viewIfLoaded,
                  detail.window != nil else { return }
            self.updateSplitAppearance(split, detail: detail)
            // UIKit may lay out repeatedly during one sidebar transition.
            // Publish its target once instead of restarting a 300ms SwiftUI
            // animation on every intermediate geometry callback.
            guard !self.transitionInFlight else { return }
            // The root background need not lay out when only a split column
            // changes. Follow the secondary view itself, including after a
            // rotation finishes and after navigation pushes replace its root.
            if self.detailProbe?.superview !== detail {
                self.detailProbe?.removeFromSuperview()
                let probe = SplitDetailBoundsProbe(frame: detail.bounds)
                probe.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                probe.isUserInteractionEnabled = false
                probe.accessibilityElementsHidden = true
                probe.onLayout = { [weak self] in self?.scheduleUpdate() }
                detail.addSubview(probe)
                self.detailProbe = probe
            }
            var contentBounds = detail.bounds
            if #available(iOS 26.0, *) {
                // Keep vertical coordinates unchanged: only horizontal safe
                // areas identify the space beside the floating sidebar.
                contentBounds.origin.x += detail.safeAreaInsets.left
                contentBounds.size.width -= detail.safeAreaInsets.left + detail.safeAreaInsets.right
            }
            let frame = detail.convert(contentBounds, to: self)
            let visible = frame.intersection(window.convert(window.bounds, to: self))
            guard !visible.isNull, visible.width > 0 else { return }
            let windowSize = window.bounds.size
            let scale = window.screen.scale
            let alignedFrame = CGRect(x: (visible.minX * scale).rounded() / scale,
                                      y: visible.minY,
                                      width: (visible.width * scale).rounded() / scale,
                                      height: visible.height)
            let next = MainColumnGeometry.Layout(frame: alignedFrame)
            // A sidebar toggle changes the column while the window stays the
            // same size. Animate the observed SwiftUI width alongside UIKit;
            // rotation corrections still use the final window bounds directly.
            let animatesSidebar = self.lastWindowSize == windowSize
                && (self.geometry?.layout.width ?? 0) > 0
                && !UIAccessibility.isReduceMotionEnabled
            self.lastWindowSize = windowSize
            guard next != self.geometry?.layout else { return }
            let coordinator = split.transitionCoordinator
            let nativeDuration = coordinator.map { $0.isAnimated ? $0.transitionDuration : animationDuration } ?? animationDuration
            let duration = nativeDuration > 0 ? nativeDuration : 0.3
            let changesWidth = next.width != self.geometry?.layout.width
            if animatesSidebar, changesWidth {
                self.transitionInFlight = true
                let finish: () -> Void = { [weak self] in
                    guard let self else { return }
                    self.transitionInFlight = false
                    self.scheduleUpdate()
                }
                let registered = coordinator?.isAnimated == true
                    && coordinator?.animate(alongsideTransition: nil, completion: { _ in finish() }) == true
                if !registered {
                    DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: finish)
                }
            }
            self.geometry?.update(next, animation: animatesSidebar && changesWidth
                ? .easeInOut(duration: duration)
                : nil)
        }
    }

    private func updateSplitAppearance(_ split: UISplitViewController, detail: UIView) {
        // iPad uses a permanently visible, tiled sidebar with no toggle.
        split.presentsWithGesture = false
        split.preferredSplitBehavior = .tile
        split.preferredDisplayMode = .oneBesideSecondary
        split.displayModeButtonItem.isHidden = true
        // Legacy iPad uses app-owned overlays and never reaches this probe.
        // No UIKit background or separator surgery is needed.
    }

    private func splitController(in controller: UIViewController) -> UISplitViewController? {
        if let split = controller as? UISplitViewController { return split }
        for child in controller.children {
            if let split = splitController(in: child) { return split }
        }
        return nil
    }
}

private final class SplitDetailBoundsProbe: UIView {
    var onLayout: (() -> Void)?

    override func layoutSubviews() {
        super.layoutSubviews()
        onLayout?()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onLayout?()
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        onLayout?()
    }
}
#endif
