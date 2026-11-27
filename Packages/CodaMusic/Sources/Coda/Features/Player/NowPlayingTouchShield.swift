#if os(iOS)
import SwiftUI

/// A real UIKit hit target for inert player space. A transparent SwiftUI
/// background gesture can still leave gaps in the iPadOS 16 split-view overlay,
/// allowing a browsing control underneath to receive a supposedly blank tap.
/// Interactive player controls stay above this view in the ZStack.
struct NowPlayingTouchShield: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true
        view.isAccessibilityElement = false
        view.accessibilityElementsHidden = true
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {}
}
/// Observe control touches without letting a SwiftUI drag cancel UIKit buttons.
struct NowPlayingControlsTouchObserver: UIViewRepresentable {
    /// Collapsed controls keep their frame; ignore touches there so taps on
    /// the lyrics underneath do not count as control activity.
    var isEnabled = true
    let onInteractionChange: (Bool) -> Void

    final class ObserverView: UIView, UIGestureRecognizerDelegate {
        var onInteractionChange: ((Bool) -> Void)?
        var isEnabled = true
        private(set) var isTracking = false
        private weak var observedWindow: UIWindow?
        private lazy var observer: UILongPressGestureRecognizer = {
            let gesture = UILongPressGestureRecognizer(target: self, action: #selector(touchChanged(_:)))
            gesture.minimumPressDuration = 0
            gesture.allowableMovement = .greatestFiniteMagnitude
            gesture.cancelsTouchesInView = false
            gesture.delaysTouchesBegan = false
            gesture.delaysTouchesEnded = false
            gesture.delegate = self
            return gesture
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            detach()
            if let window {
                window.addGestureRecognizer(observer)
                observedWindow = window
            }
        }

        func detach() {
            observedWindow?.removeGestureRecognizer(observer)
            observedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard isEnabled, !isHidden, window != nil else { return false }
            return bounds.contains(touch.location(in: self))
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc private func touchChanged(_ gesture: UILongPressGestureRecognizer) {
            switch gesture.state {
            case .began:
                isTracking = true
                onInteractionChange?(true)
            case .ended, .cancelled, .failed:
                guard isTracking else { break }
                isTracking = false
                onInteractionChange?(false)
            default: break
            }
        }
    }

    func makeUIView(context: Context) -> ObserverView {
        let view = ObserverView()
        view.isUserInteractionEnabled = false
        view.onInteractionChange = onInteractionChange
        view.isEnabled = isEnabled
        return view
    }

    func updateUIView(_ view: ObserverView, context: Context) {
        view.onInteractionChange = onInteractionChange
        view.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: ObserverView, coordinator: ()) {
        // A control can remove this view mid-touch (e.g. switching to the
        // queue panel). Report the release so the interaction never sticks.
        if view.isTracking, let onInteractionChange = view.onInteractionChange {
            DispatchQueue.main.async { onInteractionChange(false) }
        }
        view.onInteractionChange = nil
        view.detach()
    }
}
#endif
