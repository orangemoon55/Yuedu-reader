#if os(macOS)
import SwiftUI
import QuartzCore

/// Lets the player's handle drag the presented surface down to dismiss it.
/// `ended` returns true when the drag went far or fast enough to close.
struct DesktopNowPlayingDrag {
    var changed: (_ translation: CGFloat) -> Void
    var ended: (_ translation: CGFloat, _ predicted: CGFloat) -> Bool
}

private struct DesktopNowPlayingDragKey: EnvironmentKey {
    static let defaultValue: DesktopNowPlayingDrag? = nil
}

extension EnvironmentValues {
    var desktopNowPlayingDrag: DesktopNowPlayingDrag? {
        get { self[DesktopNowPlayingDragKey.self] }
        set { self[DesktopNowPlayingDragKey.self] = newValue }
    }
}

/// Keep SwiftUI and native surfaces at their final layout throughout presentation.
/// Only an AppKit-owned ancestor layer moves; native frames never need to catch up.
/// macOS has no SwiftUI zoom transition, so the player grows out of the player
/// bar and shrinks back into it here, matching iOS (see CoverZoomMotion).
struct DesktopNowPlayingPresentation<Content: View>: NSViewRepresentable {
    @Binding var isPresented: Bool
    var onDismissed: () -> Void
    @ViewBuilder var content: () -> Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeNSView(context: Context) -> PlayerSurface { PlayerSurface() }

    func updateNSView(_ view: PlayerSurface, context: Context) {
        view.onDismissed = onDismissed
        let drag = DesktopNowPlayingDrag(
            changed: { [weak view] in view?.dragChanged(translation: $0) },
            ended: { [weak view] in view?.dragEnded(translation: $0, predicted: $1) ?? false })
        // The drag value is applied inside the environment snapshot so the
        // snapshot cannot overwrite it.
        view.update(isPresented: isPresented, reduceMotion: reduceMotion,
                    content: AnyView(content()
                        .environment(\.desktopNowPlayingDrag, drag)
                        .environment(\.self, context.environment)))
    }

    static func dismantleNSView(_ view: PlayerSurface, coordinator: ()) {
        view.cancelPresentation()
    }

    final class PlayerSurface: NSView {
        private let surface = NSView()
        private let maskLayer: CALayer = {
            let layer = CALayer()
            layer.backgroundColor = NSColor.black.cgColor
            layer.cornerCurve = .continuous
            return layer
        }()
        private var hosting: NSHostingView<AnyView>?
        private var presented = false
        private var generation = 0
        private var awaitingFirstLayout = false
        private var reduceMotion = false
        var onDismissed: (() -> Void)?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.masksToBounds = true
            surface.wantsLayer = true
            addSubview(surface)
            surface.isHidden = true
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

        override func hitTest(_ point: NSPoint) -> NSView? {
            presented ? super.hitTest(point) : nil
        }

        override func layout() {
            super.layout()
            // Moving the ancestor layer never changes these layout frames.
            if surface.frame != bounds { surface.frame = bounds }
            if let hosting, hosting.frame != surface.bounds { hosting.frame = surface.bounds }
            if awaitingFirstLayout, bounds.height > 0, bounds.width > 0 {
                awaitingFirstLayout = false
                // Start as the player bar, hidden, so the first frame never
                // shows the player at full size.
                var start = collapsedGeometry().geometry
                start.opacity = 0
                setModel(start)
                hosting?.layoutSubtreeIfNeeded()
                let token = generation
                // Commit the fully laid-out starting surface before moving it.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == token, self.presented else { return }
                    self.animate(toPresented: true, token: token)
                }
            }
        }

        func update(isPresented: Bool, reduceMotion: Bool, content: AnyView) {
            self.reduceMotion = reduceMotion
            if let hosting { hosting.rootView = content }
            guard presented != isPresented else { return }
            presented = isPresented
            dragging = false
            generation += 1
            let token = generation

            if isPresented, hosting == nil {
                let host = NSHostingView(rootView: content)
                host.sizingOptions = []
                hosting = host
                surface.addSubview(host)
                surface.isHidden = false
                awaitingFirstLayout = true
                needsLayout = true
                layoutSubtreeIfNeeded()
            } else if hosting != nil {
                awaitingFirstLayout = false
                animate(toPresented: isPresented, token: token)
            }
        }

        // MARK: Zoom geometry

        /// Where the surface is drawn: an ancestor transform plus a rounded
        /// mask in the surface's own (untransformed) bounds. The hosted views
        /// keep their full-window layout in every state.
        private struct Geometry {
            var transform: CATransform3D
            var maskSize: CGSize
            var cornerRadius: CGFloat
            var opacity: Float
        }

        private var expandedGeometry: Geometry {
            Geometry(transform: CATransform3DIdentity, maskSize: bounds.size, cornerRadius: 0, opacity: 1)
        }

        /// The surface scaled to the player bar's width, centered on it and
        /// masked to a strip of the bar's height. Without a visible bar it
        /// sits below the window, as the earlier slide did.
        private func collapsedGeometry() -> (geometry: Geometry, fades: Bool) {
            if reduceMotion {
                return (Geometry(transform: CATransform3DIdentity, maskSize: bounds.size,
                                 cornerRadius: 0, opacity: 0), false)
            }
            guard let source = zoomSourceFrame(), bounds.width > 0, bounds.height > 0 else {
                return (Geometry(transform: CATransform3DMakeTranslation(0, -bounds.height, 0),
                                 maskSize: bounds.size, cornerRadius: 0, opacity: 1), false)
            }
            let scale = max(0.05, source.frame.width / bounds.width)
            let anchor = surfaceAnchor
            let center = CGPoint(x: bounds.midX, y: bounds.midY)
            // Layer transforms apply about the anchor: p' = a + s(p - a) + t.
            let tx = source.frame.midX - anchor.x - scale * (center.x - anchor.x)
            let ty = source.frame.midY - anchor.y - scale * (center.y - anchor.y)
            let transform = CATransform3DScale(CATransform3DMakeTranslation(tx, ty, 0), scale, scale, 1)
            return (Geometry(transform: transform,
                             maskSize: CGSize(width: bounds.width,
                                              height: min(bounds.height, source.frame.height / scale)),
                             cornerRadius: source.cornerRadius / scale,
                             opacity: 1), true)
        }

        private var surfaceAnchor: CGPoint {
            let point = surface.layer?.anchorPoint ?? .zero
            return CGPoint(x: point.x * bounds.width, y: point.y * bounds.height)
        }

        /// The player bar's frame in this view's coordinates. SwiftUI's global
        /// space is the window's root hosting view, top-left origin.
        private func zoomSourceFrame() -> (frame: CGRect, cornerRadius: CGFloat)? {
            guard let root = window?.contentView else { return nil }
            let rootBounds = CGRect(origin: .zero, size: root.bounds.size)
            guard let source = NowPlayingZoomSource.source(within: rootBounds) else { return nil }
            var rect = source.frame
            if !root.isFlipped { rect.origin.y = root.bounds.height - rect.maxY }
            let local = convert(rect, from: root)
            guard bounds.intersects(local) else { return nil }
            return (local, source.cornerRadius)
        }

        private func setModel(_ geometry: Geometry) {
            guard let layer = surface.layer else { return }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.transform = geometry.transform
            layer.opacity = geometry.opacity
            if layer.mask !== maskLayer { layer.mask = maskLayer }
            maskLayer.bounds = CGRect(origin: .zero, size: geometry.maskSize)
            maskLayer.position = CGPoint(x: bounds.midX, y: bounds.midY)
            maskLayer.cornerRadius = geometry.cornerRadius
            CATransaction.commit()
        }

        /// Full-size surface with no mask, so window resizing and the hosted
        /// views are untouched while the player is up.
        private func settleExpanded() {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            surface.layer?.mask = nil
            surface.layer?.transform = CATransform3DIdentity
            surface.layer?.opacity = 1
            CATransaction.commit()
        }

        private static func spring(_ keyPath: String, from: Any?, to: Any?,
                                   dampingRatio: CGFloat, stiffness: CGFloat) -> CASpringAnimation {
            let animation = CASpringAnimation(keyPath: keyPath)
            animation.mass = 1
            animation.stiffness = stiffness
            animation.damping = 2 * dampingRatio * stiffness.squareRoot()
            animation.fromValue = from
            animation.toValue = to
            animation.duration = animation.settlingDuration
            return animation
        }

        private func animate(toPresented: Bool, token: Int) {
            guard let layer = surface.layer else { return }
            // Continue from what is on screen, so an interrupted open or close
            // turns around without a jump.
            let visible = layer.presentation() ?? layer
            if layer.mask !== maskLayer { setModel(Geometry(
                transform: visible.transform, maskSize: bounds.size,
                cornerRadius: 0, opacity: visible.opacity)) }
            let visibleMask = maskLayer.presentation() ?? maskLayer
            let start = Geometry(transform: visible.transform, maskSize: visibleMask.bounds.size,
                                 cornerRadius: visibleMask.cornerRadius, opacity: visible.opacity)
            let collapsed = collapsedGeometry()
            var end = toPresented ? expandedGeometry : collapsed.geometry
            let fadesOut = !toPresented && collapsed.fades && !reduceMotion
            if fadesOut { end.opacity = 0 }
            setModel(end)

            let now = layer.convertTime(CACurrentMediaTime(), from: nil)
            var animations: [(String, CAAnimation, CALayer)] = []
            var duration: CFTimeInterval
            if reduceMotion {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = start.opacity
                fade.toValue = end.opacity
                fade.duration = 0.2
                fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animations.append(("opacity", fade, layer))
                duration = 0.2
            } else {
                let ratio: CGFloat = toPresented ? 0.9 : 0.92
                let stiffness: CGFloat = toPresented ? 220 : 280
                let motion = Self.spring("transform", from: NSValue(caTransform3D: start.transform),
                                         to: NSValue(caTransform3D: end.transform),
                                         dampingRatio: ratio, stiffness: stiffness)
                let maskBounds = Self.spring("bounds",
                                             from: NSValue(rect: CGRect(origin: .zero, size: start.maskSize)),
                                             to: NSValue(rect: CGRect(origin: .zero, size: end.maskSize)),
                                             dampingRatio: 1, stiffness: stiffness)
                let corner = Self.spring("cornerRadius", from: start.cornerRadius, to: end.cornerRadius,
                                         dampingRatio: 1, stiffness: stiffness)
                animations += [("transform", motion, layer),
                               ("bounds", maskBounds, maskLayer),
                               ("cornerRadius", corner, maskLayer)]
                // The spring's tail is invisible; finish once it has settled
                // to within a fraction of a point.
                duration = min(motion.duration, toPresented ? 0.55 : 0.45)
                animations.forEach { $0.1.duration = duration }

                // Cross-fade with the player bar: in quickly on open, out over
                // the last part of the shrink on close.
                let fadesIn = toPresented && start.opacity < 1
                if fadesIn || fadesOut || start.opacity != end.opacity {
                    let fade = CABasicAnimation(keyPath: "opacity")
                    fade.fromValue = fadesIn ? 0 : start.opacity
                    fade.toValue = end.opacity
                    fade.duration = fadesOut ? 0.18 : 0.16
                    if fadesOut {
                        fade.beginTime = now + duration * 0.4
                        fade.fillMode = .backwards
                    }
                    animations.append(("opacity", fade, layer))
                }
            }

            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self] in
                guard let self, self.generation == token else { return }
                if self.presented {
                    self.settleExpanded()
                    return
                }
                self.surface.isHidden = true
                self.settleExpanded()
                self.hosting?.removeFromSuperview()
                self.hosting = nil
                self.onDismissed?()
            }
            for (key, animation, target) in animations {
                target.add(animation, forKey: "playerPresentation.\(key)")
            }
            CATransaction.commit()
        }

        // MARK: Drag to dismiss

        private var dragging = false

        /// Follows the pointer downward; upward drags are rubber-banded.
        func dragChanged(translation: CGFloat) {
            guard presented, hosting != nil, !awaitingFirstLayout, bounds.height > 0,
                  let layer = surface.layer else { return }
            if !dragging {
                dragging = true
                // Drop any running open animation; its completion must not
                // reset the surface under the pointer.
                generation += 1
                layer.removeAllAnimations()
                maskLayer.removeAllAnimations()
            }
            let offset = translation >= 0
                ? translation
                : -Self.rubberBand(-translation, limit: bounds.height * 0.08)
            setModel(Geometry(transform: CATransform3DMakeTranslation(0, -offset, 0),
                              maskSize: bounds.size,
                              cornerRadius: min(18, max(0, offset) / 8),
                              opacity: 1))
        }

        /// Returns true when the caller should dismiss; otherwise springs back.
        func dragEnded(translation: CGFloat, predicted: CGFloat) -> Bool {
            guard dragging else { return false }
            dragging = false
            let threshold = min(160, bounds.height * 0.22)
            if presented, translation > threshold || (translation > 24 && predicted > bounds.height * 0.4) {
                return true
            }
            generation += 1
            animate(toPresented: true, token: generation)
            return false
        }

        private static func rubberBand(_ distance: CGFloat, limit: CGFloat) -> CGFloat {
            guard limit > 0 else { return 0 }
            return limit * (1 - 1 / (distance / limit * 0.55 + 1))
        }

        func cancelPresentation() {
            generation += 1
            surface.layer?.removeAllAnimations()
            maskLayer.removeAllAnimations()
            onDismissed = nil
        }
    }
}
#endif
