import SwiftUI

/// Keep the position with the SwiftUI page, rather than with a UIKit scroll
/// view that navigation can replace when the scene returns to the foreground.
struct ScenePreservingScrollView<Content: View>: View {
    var axes: Axis.Set = .vertical
    var showsIndicators = true
    var isPrimaryContent = true
    @ViewBuilder var content: () -> Content
    @Environment(\.compactWindowLayout) private var compactWindowLayout
    #if os(macOS)
    @Environment(\.mainColumnGeometry) private var mainColumnGeometry
    #endif
    #if os(iOS)
    @StateObject private var position: SceneScrollPosition
    @Environment(\.sceneScrollStore) private var scrollStore
    @Environment(\.sceneScrollPage) private var scrollPage
    @Environment(\.iPadChrome) private var iPadChrome
    @Environment(\.mainColumnGeometry) private var mainColumnGeometry

    private var allowsChromeOverflow: Bool {
        UIDevice.current.userInterfaceIdiom == .pad && !compactWindowLayout && iPadChrome == .legacy && mainColumnGeometry != nil
    }

    /// iOS 16 drops a finger tap inside a nested horizontal scroll view when
    /// the touch's contact radius (about 30pt on iPad) reaches past the scroll
    /// view's top or bottom edge; a Pencil tap has no radius and still works.
    /// Transparent room inside the scroll view, cancelled by the same negative
    /// padding outside, keeps the layout while every finger contact on the
    /// content fits within the scroll view.
    private var fingerTouchClearance: CGFloat {
        guard axes == .horizontal else { return 0 }
        if #available(iOS 17.0, *) { return 0 }
        return 44
    }
    #endif

    init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, isPrimaryContent: Bool = true,
         file: StaticString = #fileID, line: UInt = #line,
         @ViewBuilder content: @escaping () -> Content) {
        self.axes = axes
        self.showsIndicators = showsIndicators
        self.isPrimaryContent = isPrimaryContent
        self.content = content
        #if os(iOS)
        _position = StateObject(wrappedValue: SceneScrollPosition(label: "\(file):\(line)"))
        #endif
    }

    var body: some View {
        ScrollView(axes, showsIndicators: showsIndicators) {
            content()
                #if os(iOS)
                .background(SceneScrollProbe(position: position,
                    store: axes.contains(.vertical) ? scrollStore : nil, page: scrollPage,
                    isPrimaryContent: isPrimaryContent && axes == .vertical,
                    allowsChromeOverflow: allowsChromeOverflow))
                .padding(.vertical, fingerTouchClearance)
                #endif
        }
        #if os(iOS)
        .padding(.vertical, -fingerTouchClearance)
        .modifier(IPadScrollOverflow(enabled: allowsChromeOverflow))
        #elseif os(macOS)
        .modifier(DesktopScrollOverflow(enabled: mainColumnGeometry != nil && !compactWindowLayout))
        #endif
    }
}

#if os(macOS)
/// Both shelves and their enclosing vertical viewport must allow overflow;
/// MainWindow clips the resulting canvas at the actual window edges.
private struct DesktopScrollOverflow: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}
#endif

#if os(iOS)
private struct IPadScrollOverflow: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *), enabled {
            content.scrollClipDisabled()
        } else {
            content
        }
    }
}
#endif

/// Register Form/List pages with the same native bottom-bar behavior as scroll pages.
extension View {
    @ViewBuilder
    func nativeTabBarScrolling() -> some View {
        #if os(iOS)
        background(SceneScrollProbe(position: nil, store: nil, page: nil,
                                    isPrimaryContent: true, searchesDescendants: true))
        #else
        self
        #endif
    }
}

#if os(iOS)
/// Owned above NavigationSplitView. iPadOS 16 can replace the entire detail
/// subtree during app-switcher adaptation, including its SwiftUI StateObjects.
final class SceneScrollPositionStore: ObservableObject {
    struct Page: Hashable {
        var section: SidebarItem
        var path: [Destination]
    }

    struct Key: Hashable {
        var page: Page
        var location: String
    }

    var offsets: [Key: CGPoint] = [:]
}

private struct SceneScrollStoreKey: EnvironmentKey {
    static let defaultValue: SceneScrollPositionStore? = nil
}

private struct SceneScrollPageKey: EnvironmentKey {
    static let defaultValue: SceneScrollPositionStore.Page? = nil
}

extension EnvironmentValues {
    var sceneScrollStore: SceneScrollPositionStore? {
        get { self[SceneScrollStoreKey.self] }
        set { self[SceneScrollStoreKey.self] = newValue }
    }

    var sceneScrollPage: SceneScrollPositionStore.Page? {
        get { self[SceneScrollPageKey.self] }
        set { self[SceneScrollPageKey.self] = newValue }
    }
}

private struct SceneScrollProbe: UIViewRepresentable {
    let position: SceneScrollPosition?
    let store: SceneScrollPositionStore?
    let page: SceneScrollPositionStore.Page?
    let isPrimaryContent: Bool
    var searchesDescendants = false
    var allowsChromeOverflow = false

    func makeUIView(context: Context) -> Probe {
        position?.configure(store: store, page: page)
        let probe = Probe()
        probe.isUserInteractionEnabled = false
        probe.position = position
        probe.isPrimaryContent = isPrimaryContent
        probe.searchesDescendants = searchesDescendants
        probe.allowsChromeOverflow = allowsChromeOverflow
        return probe
    }

    func updateUIView(_ view: Probe, context: Context) {
        position?.configure(store: store, page: page)
        view.isPrimaryContent = isPrimaryContent
        view.searchesDescendants = searchesDescendants
        view.allowsChromeOverflow = allowsChromeOverflow
        view.connect()
        view.scheduleRegistration()
    }

    static func dismantleUIView(_ view: Probe, coordinator: Void) {
        view.unregisterPrimaryScrollView()
        view.restoreClipping()
    }

    final class Probe: UIView {
        var position: SceneScrollPosition?
        var isPrimaryContent = false
        var searchesDescendants = false
        var allowsChromeOverflow = false
        private weak var overflowScrollView: UIScrollView?
        private var originalClipping = true

        func restoreClipping() {
            overflowScrollView?.clipsToBounds = originalClipping
            overflowScrollView = nil
        }

        private func updateClipping() {
            guard allowsChromeOverflow else {
                restoreClipping()
                return
            }
            // Every shelf and enclosing vertical viewport has its own probe.
            // Change only our scroll view so nested probes never fight over
            // restoring an ancestor's clipping, or retain their own hierarchy.
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    if overflowScrollView !== scroll {
                        restoreClipping()
                        originalClipping = scroll.clipsToBounds
                        overflowScrollView = scroll
                    }
                    scroll.clipsToBounds = false
                    return
                }
                ancestor = view.superview
            }
        }

        private struct Registration {
            weak var controller: UIViewController?
            weak var previousScrollView: UIScrollView?
        }
        private var registrations: [Registration] = []
        private weak var registeredScrollView: UIScrollView?
        private var registrationScheduled = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil {
                unregisterPrimaryScrollView()
                restoreClipping()
            }
            connect()
            scheduleRegistration()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            connect()
        }

        func connect() {
            guard window != nil else { return }
            updateClipping()
            if !isPrimaryContent { unregisterPrimaryScrollView() }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    position?.attach(scroll)
                    registerPrimaryScrollView(scroll)
                    return
                }
                if searchesDescendants {
                    if let scroll = verticalScrollView(in: view) {
                        registerPrimaryScrollView(scroll)
                        return
                    }
                    // Stay inside this page's hosting controller; never attach
                    // a Form probe to another tab or a presented sheet.
                    if view.next is UIViewController { return }
                }
                ancestor = view.superview
            }
        }

        private func verticalScrollView(in view: UIView) -> UIScrollView? {
            guard !view.isHidden, view.alpha > 0 else { return nil }
            if let scroll = view as? UIScrollView,
               !(scroll is UITextView), scroll.isScrollEnabled,
               scroll.alwaysBounceVertical || scroll.contentSize.height > scroll.bounds.height {
                return scroll
            }
            for child in view.subviews {
                if let scroll = verticalScrollView(in: child) { return scroll }
            }
            return nil
        }

        func scheduleRegistration() {
            guard isPrimaryContent, window != nil, !registrationScheduled else { return }
            registrationScheduled = true
            // SwiftUI attaches its navigation/tab containers after the probe.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.registrationScheduled = false
                self.connect()
            }
        }

        @objc private func scrollGestureChanged(_ gesture: UIPanGestureRecognizer) {
            // Reconnect before UIKit processes a new scrolling interaction.
            if gesture.state == .began { connect() }
        }

        private func registerPrimaryScrollView(_ scroll: UIScrollView) {
            guard #available(iOS 26.0, *), isPrimaryContent,
                  UIDevice.current.userInterfaceIdiom == .phone else { return }
            var responder: UIResponder? = self
            var contentController: UIViewController?
            while let current = responder {
                if let controller = current as? UIViewController {
                    contentController = controller
                    break
                }
                responder = current.next
            }
            guard let contentController else { return }

            // The tab bar observes its direct child. Registering only the
            // navigation stack's top screen leaves SwiftUI's intervening
            // hosting controllers free to select a horizontal shelf instead.
            var owners: [UIViewController] = []
            var ancestor: UIViewController? = contentController
            while let controller = ancestor, !(controller is UITabBarController) {
                guard let view = controller.viewIfLoaded, scroll.isDescendant(of: view) else { break }
                if let navigation = controller as? UINavigationController,
                   let visible = navigation.topViewController,
                   let visibleView = visible.viewIfLoaded,
                   !scroll.isDescendant(of: visibleView) { return }
                owners.append(controller)
                ancestor = controller.parent
            }
            guard let tabController = ancestor as? UITabBarController,
                  let selected = tabController.selectedViewController,
                  owners.contains(where: { $0 === selected }) else { return }

            let sameOwners = registrations.count == owners.count
                && zip(registrations, owners).allSatisfy { $0.controller === $1 }
            if registeredScrollView !== scroll || !sameOwners {
                unregisterPrimaryScrollView()
                registeredScrollView = scroll
                registrations = owners.map { owner in
                    let previous = owner.contentScrollView(for: .bottom)
                    return Registration(controller: owner, previousScrollView: previous === scroll ? nil : previous)
                }
                scroll.panGestureRecognizer.addTarget(self, action: #selector(scrollGestureChanged(_:)))
                for owner in owners { owner.setContentScrollView(scroll, for: .bottom) }
            } else {
                for owner in owners where owner.contentScrollView(for: .bottom) !== scroll {
                    owner.setContentScrollView(scroll, for: .bottom)
                }
            }
        }

        func unregisterPrimaryScrollView() {
            guard let scroll = registeredScrollView else {
                registrations.removeAll()
                return
            }
            scroll.panGestureRecognizer.removeTarget(self, action: #selector(scrollGestureChanged(_:)))
            for registration in registrations.reversed() {
                if let controller = registration.controller,
                   controller.contentScrollView(for: .bottom) === scroll {
                    controller.setContentScrollView(registration.previousScrollView, for: .bottom)
                }
            }
            registrations.removeAll()
            registeredScrollView = nil
        }
    }
}

private final class SceneScrollPosition: NSObject, ObservableObject {
    private let label: String
    private weak var scrollView: UIScrollView?
    private var observations: [NSKeyValueObservation] = []
    private var store: SceneScrollPositionStore?
    private var storageKey: SceneScrollPositionStore.Key?
    private var offset: CGPoint? {
        didSet {
            if let storageKey, let offset { store?.offsets[storageKey] = offset }
        }
    }
    private var startsAtTop = false
    private var suspended = false
    private var restoring = false
    private var applying = false
    private var restoreScheduled = false
    private var settleWork: DispatchWorkItem?

    init(label: String) {
        self.label = label
        super.init()
        suspended = UIApplication.shared.applicationState != .active
        // UIApplication resigns before the scene's snapshot layout starts.
        NotificationCenter.default.addObserver(self, selector: #selector(suspend),
                                               name: UIApplication.willResignActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(resume),
                                               name: UIApplication.didBecomeActiveNotification, object: nil)
    }

    deinit {
        settleWork?.cancel()
    }

    func configure(store: SceneScrollPositionStore?, page: SceneScrollPositionStore.Page?) {
        guard let store, let page else { return }
        let key = SceneScrollPositionStore.Key(page: page, location: label)
        guard self.store !== store || storageKey != key else { return }
        self.store = store
        storageKey = key
        offset = store.offsets[key]
        startsAtTop = offset == nil
        if scrollView != nil, !suspended { beginRestoring() }
    }

    func attach(_ scroll: UIScrollView) {
        guard scrollView !== scroll else { return }
        scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(userDidScroll))
        observations.removeAll()
        scrollView = scroll
        scroll.panGestureRecognizer.addTarget(self, action: #selector(userDidScroll))
        if offset == nil { startsAtTop = true }
        observations = [
            scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                guard let self, !self.applying else { return }
                if self.restoring { self.scheduleRestore() }
                else if !self.suspended && !self.startsAtTop { self.offset = scroll.contentOffset }
            },
            scroll.observe(\.contentSize, options: [.new]) { [weak self] _, _ in
                if self?.restoring == true { self?.scheduleRestore() }
            },
            scroll.observe(\.bounds, options: [.new]) { [weak self] _, _ in
                if self?.restoring == true { self?.scheduleRestore() }
            }
        ]
        // A replacement scroll view must use the old page position as well.
        if !suspended { beginRestoring() }
    }

    @objc private func suspend() {
        settleWork?.cancel()
        // Offset observations keep the last foreground position; do not read
        // it here, when UIKit may already have performed a snapshot layout.
        suspended = true
        restoring = false
    }

    @objc private func resume() {
        guard suspended else { return }
        suspended = false
        beginRestoring()
    }

    @objc private func userDidScroll() {
        guard let scroll = scrollView,
              scroll.panGestureRecognizer.state == .began || scroll.panGestureRecognizer.state == .changed else { return }
        settleWork?.cancel()
        restoring = false
        startsAtTop = false
        offset = scroll.contentOffset
    }

    private func beginRestoring() {
        restoring = true
        scheduleRestore()
    }

    private func scheduleRestore() {
        guard !restoreScheduled, !suspended else { return }
        restoreScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.restoreScheduled = false
            guard self.restoring, !self.suspended, let scroll = self.scrollView,
                  scroll.window != nil else { return }
            self.applying = true
            scroll.layoutIfNeeded()
            let offset = self.startsAtTop
                ? CGPoint(x: -scroll.adjustedContentInset.left, y: -scroll.adjustedContentInset.top)
                : (self.offset ?? scroll.contentOffset)
            if scroll.contentOffset != offset {
                UIView.performWithoutAnimation { scroll.setContentOffset(offset, animated: false) }
            }
            self.applying = false
            // A scene can lay out more than once after activation. Continue
            // protecting the saved position until those changes have settled.
            self.settleWork?.cancel()
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.startsAtTop = false
                self.offset = scroll.contentOffset
                self.restoring = false
            }
            self.settleWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
}

#endif
