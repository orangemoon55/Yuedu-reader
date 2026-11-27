import SwiftUI
#if os(macOS)
import AppKit
#endif

/// A quiet, consistent affordance for rows and section titles that navigate
/// forward or reveal more content.
struct DisclosureChevron: View {
    var body: some View {
        Image(systemName: "chevron.right")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Theme.accent)
            .accessibilityHidden(true)
    }
}

// MARK: - Skeletons

struct SkeletonView: View {
    var cornerRadius: CGFloat = Theme.Radius.standard

    var body: some View {
        #if os(macOS)
        // A single page can show dozens of placeholders while waiting on the
        // network. Static shapes keep the whole window from compositing at 30 Hz.
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary.opacity(0.5))
        #else
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.quaternary.opacity(0.5))
            .overlay { SkeletonShimmer() }
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        #endif
    }
}

#if os(iOS)
/// One repeating animation per placeholder instead of a 30 Hz TimelineView:
/// pages show dozens of skeletons while loading, and re-running each body
/// every frame competed with scrolling.
private struct SkeletonShimmer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweeping = false

    var body: some View {
        if !reduceMotion {
            GeometryReader { geo in
                LinearGradient(colors: [.clear, .primary.opacity(0.08), .clear],
                               startPoint: .leading, endPoint: .trailing)
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: sweeping ? geo.size.width : -geo.size.width * 0.6)
                    // Scope the repeat to the sweep. A `withAnimation` in onAppear
                    // shares its transaction with the update that inserted the
                    // placeholder, and iPadOS 16 then loops the surrounding page's
                    // layout change forever (the whole home page drifting).
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: sweeping)
            }
            .onAppear {
                // Start on the next run loop, outside the inserting transaction.
                DispatchQueue.main.async { sweeping = true }
            }
            .allowsHitTesting(false)
        }
    }
}
#endif

// MARK: - Staggered entrance

private enum AnimationCache {
    nonisolated(unsafe) static var animated = Set<String>()

    static func hasAnimated(_ key: String) -> Bool { animated.contains(key) }

    static func markAnimated(_ key: String) {
        if animated.count > 600 { animated.removeAll() }
        animated.insert(key)
    }
}

struct StaggeredAppearanceModifier: ViewModifier {
    let index: Int
    var itemID: String

    @State private var isVisible = false

    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1 : 0)
            .offset(y: isVisible ? 0 : 16)
            .onAppear {
                if Platform.isReduceMotionEnabled
                    || AnimationCache.hasAnimated(itemID) {
                    isVisible = true
                    return
                }
                withAnimation(AppAnimation.snappy.delay(AppAnimation.stagger(for: index))) {
                    isVisible = true
                }
                AnimationCache.markAnimated(itemID)
            }
    }
}

extension View {
    func staggeredAppearance(index: Int, id: String) -> some View {
        modifier(StaggeredAppearanceModifier(index: index, itemID: id))
    }
}

// MARK: - Section header

struct SectionHeader: View {
    let title: LocalizedStringKey
    var subtitle: String?
    var action: (() -> Void)?

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small) {
            if let action {
                Button(action: action) {
                    HStack(spacing: Theme.Spacing.tight) {
                        Text(title)
                            .font(Theme.Typography.sectionTitle.weight(.semibold))
                            .foregroundStyle(.primary)
                        DisclosureChevron()
                            .offset(x: isHovering ? 2 : 0)
                    }
                }
                .buttonStyle(.plain)
                .scrollAwareHover { hovering in
                    withAnimation(AppAnimation.quick) { isHovering = hovering }
                }
            } else {
                Text(title)
                    .font(Theme.Typography.sectionTitle.weight(.semibold))
            }
            if let subtitle {
                Text(subtitle)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }
}

// MARK: - Badges

struct PlayCountBadge: View {
    let count: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.tight) {
            Image(systemName: "play.fill")
                .font(.system(size: 8, weight: .bold))
            Text(Formatters.playCount(count))
                .font(Theme.Typography.badge.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, Theme.Spacing.small)
        .padding(.vertical, Theme.Spacing.tight)
        .background(.black.opacity(0.35), in: Capsule())
        .background(.ultraThinMaterial.opacity(0.6), in: Capsule())
    }
}

struct VIPBadge: View {
    var body: some View {
        Text("VIP")
            .font(Theme.Typography.badge.weight(.bold))
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, Theme.Spacing.tight)
            .padding(.vertical, Theme.Spacing.micro)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(Theme.accent.opacity(0.8), lineWidth: 1)
            )
    }
}

// MARK: - Hover play overlay

struct PlayOverlayButton: View {
    var visible: Bool
    var size: CGFloat = 40
    let action: () -> Void

    var body: some View {
        #if os(macOS)
        Button(action: action) {
            Image(systemName: "play.fill")
                .font(.system(size: size * 0.38, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Theme.accent.opacity(0.92), in: Circle())
                .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
        }
        .buttonStyle(.pressable)
        .opacity(visible ? 1 : 0)
        .scaleEffect(visible ? 1 : 0.7)
        .animation(AppAnimation.spring, value: visible)
        // Opacity alone leaves it clickable while invisible.
        .allowsHitTesting(visible)
        #else
        EmptyView()
        #endif
    }
}

// MARK: - Playback and volume rails

/// Visual values shared by the playback scrubber and the system volume rail.
enum NowPlayingSliderStyle {
    static let trackHeight: CGFloat = 5
    static let trackOpacity: Double = 0.25
    static let draggingThumbDiameter: CGFloat = 13
    static let hoveringThumbDiameter: CGFloat = 11
    static let thumbShadowOpacity: Double = 0.3
    static let thumbShadowRadius: CGFloat = 2
    static let thumbShadowOffset: CGFloat = 1
}

/// Shared drawing only; each control keeps its own playback/system-volume interaction.
struct PlayerSliderRail: View {
    var fraction: Double
    var axis: Axis = .horizontal
    var fillColor: Color = .white
    var trackColor: Color = .white.opacity(NowPlayingSliderStyle.trackOpacity)
    var trackHeight: CGFloat = NowPlayingSliderStyle.trackHeight
    var thumbDiameter: CGFloat = NowPlayingSliderStyle.draggingThumbDiameter
    var showsThumb = false

    var body: some View {
        GeometryReader { geometry in
            let horizontal = axis == .horizontal
            let length = max(0, horizontal ? geometry.size.width : geometry.size.height)
            let value = fraction.isFinite ? min(max(fraction, 0), 1) : 0
            let filledLength = length * value
            let thickness = trackHeight
            ZStack(alignment: horizontal ? .leading : .bottom) {
                Capsule()
                    .fill(trackColor)
                    .frame(width: horizontal ? length : thickness,
                           height: horizontal ? thickness : length)
                Capsule()
                    .fill(fillColor)
                    .frame(width: horizontal ? filledLength : thickness,
                           height: horizontal ? thickness : filledLength)
                    .opacity(value > 0 ? 1 : 0)
                Circle()
                    .fill(.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    // Animate the thumb size without springing its final position.
                    .animation(.spring(response: 0.24, dampingFraction: 0.72), value: thumbDiameter)
                    .shadow(color: .black.opacity(NowPlayingSliderStyle.thumbShadowOpacity),
                            radius: NowPlayingSliderStyle.thumbShadowRadius,
                            y: NowPlayingSliderStyle.thumbShadowOffset)
                    .offset(x: horizontal ? filledLength - thumbDiameter / 2 : 0,
                            y: horizontal ? 0 : -filledLength + thumbDiameter / 2)
                    .opacity(showsThumb ? 1 : 0)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .accessibilityHidden(true)
    }
}


/// Shared rail, hit testing, drag mapping and pointer feedback for every player slider.
struct PlayerSlider: View {
    var fraction: Double
    var axis: Axis = .horizontal
    var fillColor: Color = .white
    var trackColor: Color = .white.opacity(NowPlayingSliderStyle.trackOpacity)
    var trackHeight: CGFloat = NowPlayingSliderStyle.trackHeight
    var onChanged: (Double) -> Void
    var onEnded: (Double) -> Void = { _ in }
    var onCancelled: () -> Void = { }

    @State private var isHovering = false
    @State private var isDragging = false
    @State private var acceptedGesture = false
    @GestureState private var gestureIsActive = false

    var body: some View {
        GeometryReader { geometry in
            PlayerSliderRail(
                fraction: fraction, axis: axis, fillColor: fillColor, trackColor: trackColor,
                trackHeight: trackHeight,
                thumbDiameter: isDragging ? NowPlayingSliderStyle.draggingThumbDiameter
                    : NowPlayingSliderStyle.hoveringThumbDiameter,
                showsThumb: isDragging || isHovering
            )
            .contentShape(Rectangle())
            #if os(macOS)
            .overlay {
                PlayerSliderMouseInput(
                    onChanged: { point in
                        guard let fraction = fraction(at: point, size: geometry.size) else { return }
                        acceptedGesture = true
                        isDragging = true
                        onChanged(fraction)
                    },
                    onEnded: { point in
                        if acceptedGesture, let fraction = fraction(at: point, size: geometry.size) {
                            onEnded(fraction)
                        }
                        acceptedGesture = false
                        isDragging = false
                    },
                    onCancelled: {
                        if acceptedGesture { onCancelled() }
                        acceptedGesture = false
                        isDragging = false
                    }
                )
            }
            #else
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($gestureIsActive) { _, active, _ in active = true }
                    .onChanged { value in
                        guard acceptedGesture || CGRect(origin: .zero, size: geometry.size)
                            .contains(value.startLocation),
                              let fraction = fraction(at: value.location, size: geometry.size) else { return }
                        acceptedGesture = true
                        isDragging = true
                        onChanged(fraction)
                    }
                    .onEnded { value in
                        if acceptedGesture, let fraction = fraction(at: value.location, size: geometry.size) {
                            onEnded(fraction)
                        }
                        isDragging = false
                        acceptedGesture = false
                    }
            )
            #endif
        }
        .onHover { isHovering = $0 }
        .onChange(of: gestureIsActive) { active in
            guard !active else { return }
            DispatchQueue.main.async {
                guard !gestureIsActive else { return }
                if acceptedGesture { onCancelled() }
                acceptedGesture = false
                isDragging = false
            }
        }
        .onDisappear {
            if acceptedGesture { onCancelled() }
            acceptedGesture = false
            isDragging = false
        }
    }

    private func fraction(at point: CGPoint, size: CGSize) -> Double? {
        let length = axis == .horizontal ? size.width : size.height
        let position = axis == .horizontal ? point.x : size.height - point.y
        guard length.isFinite, length > 0, position.isFinite else { return nil }
        return Double(min(max(position / length, 0), 1))
    }
}

#if os(macOS)
/// Own the mouse sequence so AppKit cannot turn a slider drag into a window drag.
private struct PlayerSliderMouseInput: NSViewRepresentable {
    var onChanged: (CGPoint) -> Void
    var onEnded: (CGPoint) -> Void
    var onCancelled: () -> Void

    func makeNSView(context: Context) -> InputView { InputView() }

    func updateNSView(_ view: InputView, context: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.onCancelled = onCancelled
    }

    static func dismantleNSView(_ view: InputView, coordinator: ()) {
        view.cancelDrag()
    }

    final class InputView: NSView {
        var onChanged: (CGPoint) -> Void = { _ in }
        var onEnded: (CGPoint) -> Void = { _ in }
        var onCancelled: () -> Void = { }
        private var isDragging = false

        override var isFlipped: Bool { true }
        override var mouseDownCanMoveWindow: Bool { false }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            isDragging = true
            onChanged(convert(event.locationInWindow, from: nil))
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragging else { return }
            onChanged(convert(event.locationInWindow, from: nil))
        }

        override func mouseUp(with event: NSEvent) {
            guard isDragging else { return }
            isDragging = false
            onEnded(convert(event.locationInWindow, from: nil))
        }

        func cancelDrag() {
            guard isDragging else { return }
            isDragging = false
            onCancelled()
        }
    }
}
#endif

/// Shared cover geometry for the full player and its bottom controls.
struct PlayerArtworkFrame: ViewModifier {
    enum Style {
        case detail, dock
    }

    let size: CGFloat
    let style: Style
    var cornerRadius: CGFloat? = nil

    private var shape: RoundedRectangle {
        // Keep small portrait covers visibly rounded while scaling larger covers.
        let radius = style == .detail
            ? min(18, max(6, size * 18 / 340))
            : max(4, size * 5 / 40)
        return RoundedRectangle(cornerRadius: cornerRadius ?? radius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .frame(width: size, height: size)
            .clipShape(shape)
            .contentShape(shape)
    }
}

/// Lucide star for available subscriptions; native checkmark when selected.
struct CollectionStarIcon: View {
    let isSelected: Bool

    var body: some View {
        if isSelected {
            Image(systemName: "checkmark")
        } else {
            Image("CollectionStar")
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)

        }
    }
}

// MARK: - Content cross-fade

/// Animates the branch swaps that `value` drives; SwiftUI's default
/// insertion/removal transition is a fade.
struct ContentCrossfade<Value: Equatable>: ViewModifier {
    let value: Value
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.animation(reduceMotion ? nil : AppAnimation.standard, value: value)
    }
}

extension View {
    /// Cross-fades a page's loading skeleton into its content. Pass the exact
    /// condition that shows the skeleton, so a refresh of a filled page stays still.
    func loadingCrossfade<Value: Equatable>(_ showsSkeleton: Value) -> some View {
        modifier(ContentCrossfade(value: showsSkeleton))
    }

    /// Cross-fades content when a segmented control or tab switches it.
    func contentCrossfade<Value: Equatable>(on value: Value) -> some View {
        modifier(ContentCrossfade(value: value))
    }
}
