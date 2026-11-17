import SwiftUI
import UIKit

/// Reads keyboard geometry in this root's window; no global key-window lookup,
/// timers or keyboard requests in RootTabBarVisibility. Hardware keyboards leave
/// the bar available, floating/docked software keyboards put it away.
struct RootTabKeyboardObserver: UIViewRepresentable {
    @Binding var isVisible: Bool

    static func isOccluding(keyboardFrame: CGRect, windowBounds: CGRect, bottomSafeArea: CGFloat) -> Bool {
        let intersection = windowBounds.intersection(keyboardFrame)
        return !intersection.isNull && intersection.width > 0
            && intersection.height > max(0, bottomSafeArea) + 1
    }

    /// Presented sheets have a separate controller ancestry even in the same
    /// UIWindow. Their keyboard must not relayout the covered tab's bottom slot.
    @MainActor
    static func belongsToRoot(_ responder: UIView, observer: UIView) -> Bool {
        func owner(of view: UIView) -> UIViewController? {
            var current: UIResponder? = view
            while let value = current {
                if let controller = value as? UIViewController { return controller }
                current = value.next
            }
            return nil
        }
        guard let root = owner(of: observer) else { return false }
        var current = owner(of: responder)
        while let controller = current {
            if controller === root { return true }
            current = controller.parent
        }
        return false
    }

    func makeUIView(context: Context) -> KeyboardView {
        let view = KeyboardView()
        view.isUserInteractionEnabled = false
        view.report = { isVisible = $0 }
        return view
    }

    func updateUIView(_ view: KeyboardView, context: Context) {
        view.report = { isVisible = $0 }
    }

    static func dismantleUIView(_ view: KeyboardView, coordinator: ()) {
        view.stopObserving()
    }

    @MainActor
    final class KeyboardView: UIView {
        var report: ((Bool) -> Void)?
        private var observing = false
        private var lastVisible = false

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { stopObserving(); return }
            guard !observing else { return }
            observing = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardChanged(_:)),
                name: UIResponder.keyboardWillChangeFrameNotification, object: nil
            )
            NotificationCenter.default.addObserver(
                self, selector: #selector(keyboardHidden(_:)),
                name: UIResponder.keyboardWillHideNotification, object: nil
            )
        }

        func stopObserving() {
            NotificationCenter.default.removeObserver(self)
            observing = false
            publish(false)
        }

        @objc private func keyboardChanged(_ notification: Notification) {
            guard let window, window.isKeyWindow,
                  window.windowScene?.activationState == .foregroundActive else {
                publish(false)
                return
            }
            // Keyboard notifications are process-wide. A different scene's field
            // must never put this root's tabs away (isLocal means app, not scene).
            guard let responder = firstResponder(in: window) else { return }
            guard RootTabKeyboardObserver.belongsToRoot(responder, observer: self) else { return }
            guard notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool != false,
                  let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            let localFrame = window.convert(frame, from: window.screen.coordinateSpace)
            publish(RootTabKeyboardObserver.isOccluding(
                keyboardFrame: localFrame, windowBounds: window.bounds,
                bottomSafeArea: window.safeAreaInsets.bottom
            ))
        }

        private func firstResponder(in view: UIView) -> UIView? {
            if view.isFirstResponder { return view }
            for child in view.subviews {
                if let responder = firstResponder(in: child) { return responder }
            }
            return nil
        }

        @objc private func keyboardHidden(_ notification: Notification) {
            guard let window, window.isKeyWindow else { return }
            publish(false)
        }

        private func publish(_ visible: Bool) {
            guard lastVisible != visible else { return }
            lastVisible = visible
            // UIKit may deliver during layout; never publish SwiftUI state from
            // updateUIView/dismantleUIView's render transaction.
            Task { @MainActor [weak self] in
                guard let self, self.lastVisible == visible else { return }
                self.report?(visible)
            }
        }
    }
}
