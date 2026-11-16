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
            guard containsFirstResponder(in: window) else { publish(false); return }
            guard notification.userInfo?[UIResponder.keyboardIsLocalUserInfoKey] as? Bool != false,
                  let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            let localFrame = window.convert(frame, from: window.screen.coordinateSpace)
            publish(RootTabKeyboardObserver.isOccluding(
                keyboardFrame: localFrame, windowBounds: window.bounds,
                bottomSafeArea: window.safeAreaInsets.bottom
            ))
        }

        private func containsFirstResponder(in view: UIView) -> Bool {
            view.isFirstResponder || view.subviews.contains { containsFirstResponder(in: $0) }
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
