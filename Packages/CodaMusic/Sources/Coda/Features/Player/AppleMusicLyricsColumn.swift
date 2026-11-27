import SwiftUI

private struct NowPlayingLyricsPresentedKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    var nowPlayingLyricsPresented: Bool {
        get { self[NowPlayingLyricsPresentedKey.self] }
        set { self[NowPlayingLyricsPresentedKey.self] = newValue }
    }
}

#if os(iOS)
import UIKit

struct NowPlayingLyricsInterface {
    let isVisible: Bool
    let bottomOverlayHeight: CGFloat
    let onVisibilityChange: (Bool) -> Void
    let onInteraction: () -> Void
}

private struct NowPlayingLyricsInitialFocusPreparedKey: EnvironmentKey {
    static let defaultValue: (() -> Void)? = nil
}

private struct NowPlayingLyricsInterfaceKey: EnvironmentKey {
    static let defaultValue: NowPlayingLyricsInterface? = nil
}

extension EnvironmentValues {
    var nowPlayingLyricsInitialFocusPrepared: (() -> Void)? {
        get { self[NowPlayingLyricsInitialFocusPreparedKey.self] }
        set { self[NowPlayingLyricsInitialFocusPreparedKey.self] = newValue }
    }

    var nowPlayingLyricsInterface: NowPlayingLyricsInterface? {
        get { self[NowPlayingLyricsInterfaceKey.self] }
        set { self[NowPlayingLyricsInterfaceKey.self] = newValue }
    }
}
#endif

/// Playback following uses the MeloX line-position cascade. The native scroll
/// view still owns browsing, hit testing and accessibility.
struct AppleMusicLyricsColumn: View {
    let lyrics: ParsedLyrics

    /// Only tap-to-seek needs the player. Observing it would re-run this body
    /// (and diff every row) on unrelated updates such as volume or buffering.
    private var player: PlayerService { .shared }
    @ObservedObject private var cursor = PlayerService.shared.lyricsCursor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nowPlayingLyricsPresented) private var isPresented
    #if os(iOS)
    @Environment(\.nowPlayingLyricsInterface) private var lyricsInterface
    @Environment(\.nowPlayingLyricsInitialFocusPrepared) private var onInitialFocusPrepared
    #endif
    @Environment(\.nowPlayingFlushPanelEdges) private var flushPanelEdges
    @State private var activeIndex: Int?
    @State private var isUserScrolling = false
    @State private var scrollGeometry = LyricScrollGeometry()
    #if os(macOS)
    @State private var movement: DesktopLyricScrollTransition?
    #else
    @State private var movement: LyricScrollMovement?
    #endif
    @State private var seekFeedback: LyricSeekFeedback?

    private let anchor = UnitPoint(x: 0.5, y: 0.36)

    private func primaryFontSize(width: CGFloat) -> CGFloat {
        min(48, max(36, 36 + (width - 600) * 0.035))
    }

    var body: some View {
        GeometryReader { viewport in
            let fontSize = primaryFontSize(width: viewport.size.width)
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 25 * fontSize / 36) {
                        Color.clear.frame(height: viewport.size.height * anchor.y)
                        ForEach(Array(lyrics.lines.enumerated()), id: \.element.id) { index, line in
                            AppleMusicLyricRow(
                                line: line,
                                isActive: cursor.activeIndices.contains(index),
                                distance: index - (activeIndex ?? 0),
                                isBrowsing: isUserScrolling,
                                isSeekTarget: seekFeedback?.index == index,
                                fontSize: fontSize,
                                viewportHeight: viewport.size.height
                            ) {
                                seekFeedback = LyricSeekFeedback(
                                    index: index, revision: cursor.seekRevision &+ 1
                                )
                                player.seek(to: line.time - player.lyricsTimeOffset)
                                isUserScrolling = false
                                follow(index, proxy: proxy, height: viewport.size.height, animated: true, isManualSeek: true)
                            }
                            // Rows only re-render when their own visual inputs
                            // change; a line change touches a handful of rows.
                            .equatable()
                            #if os(macOS)
                            .modifier(DesktopLyricScrollPosition(phase: movement?.position(for: index) ?? .idle))
                            .onGeometryChange(for: CGRect.self) { row in
                                row.frame(in: .named("appleMusicLyricContent"))
                            } action: { frame in
                                scrollGeometry.frames[index] = frame
                            }
                            .onDisappear { scrollGeometry.frames.removeValue(forKey: index) }
                            #else
                            // Measure the laid-out row before the follow offset is
                            // applied. Writing frames directly avoids merging a
                            // preference dictionary across every visible row.
                            .onGeometryChange(for: CGRect.self) { row in
                                row.frame(in: .named("appleMusicLyricContent"))
                            } action: { frame in
                                scrollGeometry.frames[index] = frame
                            }
                            .onDisappear { scrollGeometry.frames.removeValue(forKey: index) }
                            .modifier(LyricScrollPosition(index: index, movement: movement, geometry: scrollGeometry))
                            #endif
                            .id(line.id)
                            .accessibilityIdentifier("syncedLyricLine-\(index)")
                        }
                        Color.clear.frame(height: viewport.size.height * (1 - anchor.y))
                    }
                    .padding(.horizontal, flushPanelEdges ? 0 : 28)
                    .coordinateSpace(name: "appleMusicLyricContent")
                    .background {
                        GeometryReader { content in
                            Color.clear.preference(
                                key: LyricsScrollOffset.self,
                                value: content.frame(in: .named("appleMusicLyricViewport")).minY
                            )
                        }
                    }
                    #if os(iOS)
                    .background {
                        // A background receives only unclaimed taps, which
                        // toggle the controls. Lyric buttons only seek.
                        Color.clear
                            .contentShape(Rectangle())
                            .onTapGesture { lyricsInterface?.onInteraction() }
                            .accessibilityHidden(true)
                    }
                    .background {
                        if let lyricsInterface, isPresented {
                            LyricsInterfaceScrollObserver(interface: lyricsInterface)
                        }
                    }
                    #endif
                }
                #if os(macOS)
                .scrollClipDisabled()
                #endif
                .coordinateSpace(name: "appleMusicLyricViewport")
                // Scroll masks only affect drawing. Keep offscreen lyric-row
                // buttons from receiving taps outside the visible column.
                .contentShape(Rectangle())
                .clipped()
                .accessibilityIdentifier("syncedLyricsScroll")
                .mask {
                    lyricsViewportMask(height: viewport.size.height)
                }
                #if os(macOS)
                .task(id: movement?.id) {
                    await runDesktopMovement(proxy: proxy, height: viewport.size.height)
                }
                #endif
                .onPreferenceChange(LyricsScrollOffset.self) { offset in
                    scrollGeometry.offset = offset
                    #if os(iOS)
                    if let movement {
                        scrollGeometry.movingOffset = offset
                        if let offset, movement.hasArrived(at: offset) {
                            self.movement = nil
                        }
                    }
                    #endif
                }
                .task(id: seekFeedback?.id) {
                    guard let feedback = seekFeedback else { return }
                    // Keep confirmation through the scroll spring, including
                    // tapping the current line. A new tap cancels this task.
                    do {
                        try await Task.sleep(for: .milliseconds(reduceMotion ? 150 : 380))
                        for _ in 0..<40 {
                            try Task.checkCancellation()
                            guard seekFeedback?.id == feedback.id else { return }
                            if !isDesktopAnimating,
                               let frame = scrollGeometry.frames[feedback.index], let offset = scrollGeometry.offset,
                               cursor.activeIndex == feedback.index,
                               abs(frame.minY + frame.height * anchor.y + offset
                                   - viewport.size.height * anchor.y) <= 2 {
                                break
                            }
                            try await Task.sleep(for: .milliseconds(50))
                        }
                    } catch { return }
                    guard seekFeedback?.id == feedback.id else { return }
                    seekFeedback = nil
                }
                .onChange(of: isUserScrolling) { browsing in
                    if browsing {
                        seekFeedback = nil
                        movement = nil
                    }
                }
                .onDisappear {
                    seekFeedback = nil
                    movement = nil
                }
                .onChange(of: isPresented) { visible in
                    seekFeedback = nil
                    if visible {
                        follow(cursor.activeIndex, proxy: proxy, animated: false)
                    } else {
                        movement = nil
                    }
                }
                .onChange(of: reduceMotion) { reduced in
                    if reduced { movement = nil }
                }
                .onAppear {
                    activeIndex = cursor.activeIndex
                    // Wait for the scroll view to lay out before restoring position.
                    DispatchQueue.main.async {
                        follow(cursor.activeIndex, proxy: proxy, animated: false)
                        #if os(iOS)
                        DispatchQueue.main.async { onInitialFocusPrepared?() }
                        #endif
                    }
                }
                .onChange(of: cursor.activeIndex) { index in
                    guard isPresented else { return }
                    // The tap already requested its scroll. Do not restart
                    // that animation when the playback cursor catches up.
                    if let feedback = seekFeedback {
                        if index == feedback.index { return }
                        seekFeedback = nil
                    }
                    if isUserScrolling {
                        activeIndex = index
                    } else {
                        follow(index, proxy: proxy, height: viewport.size.height, animated: true)
                    }
                }
                .onChange(of: cursor.seekRevision) { _ in
                    if seekFeedback?.revision == cursor.seekRevision { return }
                    seekFeedback = nil
                    follow(cursor.activeIndex, proxy: proxy, animated: false)
                }
                .onChange(of: lyrics) { _ in
                    seekFeedback = nil
                    follow(cursor.activeIndex, proxy: proxy, animated: false)
                }
                #if os(macOS)
                .task(id: viewport.size) {
                    // Live resize can deliver a new size each frame. Only the
                    // final layout needs to restore the current lyric's anchor.
                    do {
                        try await Task.sleep(nanoseconds: 120_000_000)
                    } catch {
                        return
                    }
                    guard !Task.isCancelled, !isUserScrolling else { return }
                    follow(activeIndex, proxy: proxy, animated: false)
                }
                #else
                .onChange(of: viewport.size) { _ in
                    DispatchQueue.main.async {
                        if !isUserScrolling {
                            follow(activeIndex, proxy: proxy, animated: false)
                        }
                    }
                }
                #endif
                .lyricsScrollTracking(isUserScrolling: $isUserScrolling) {
                    follow(cursor.activeIndex, proxy: proxy, height: viewport.size.height, animated: true, isBrowsingReturn: true)
                }
            }
        }
    }

    private func lyricsViewportMask(height: CGFloat) -> some View {
        #if os(iOS)
        let overlay = lyricsInterface.map { $0.isVisible ? $0.bottomOverlayHeight : 0 } ?? 0
        #else
        let overlay: CGFloat = 0
        #endif
        let bottom = min(1, max(0.12, (height - overlay) / max(height, 1)))
        return LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .black, location: min(0.10, bottom * 0.2)),
            .init(color: .black, location: max(0.10, bottom - 0.10)),
            .init(color: .clear, location: bottom),
            .init(color: .clear, location: 1)
        ], startPoint: .top, endPoint: .bottom)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.34), value: bottom)
    }

    private func follow(
        _ index: Int?, proxy: ScrollViewProxy, height: CGFloat = 0, animated: Bool,
        isManualSeek: Bool = false, isBrowsingReturn: Bool = false
    ) {
        guard let index, lyrics.lines.indices.contains(index) else {
            activeIndex = nil
            movement = nil
            if let first = lyrics.lines.first {
                proxy.scrollTo(first.id, anchor: anchor)
            }
            return
        }
        let previous = activeIndex
        let allowsMotion = animated && !reduceMotion
        let next = index + 1
        let remaining = !isManualSeek && lyrics.lines.indices.contains(next)
            ? cursor.timeUntilFocus(at: lyrics.lines[next].time) : nil
        let hasTime = remaining.map { $0 >= 0.12 } ?? true
        #if os(macOS)
        let nextMovement = allowsMotion && hasTime
            ? makeDesktopMovement(to: index, from: previous, height: height, remaining: remaining,
                                  forced: isManualSeek || isBrowsingReturn)
            : nil
        activeIndex = index
        movement = nextMovement
        if nextMovement != nil { return }
        var transaction = Transaction(animation: nil)
        if allowsMotion {
            transaction.animation = .easeInOut(duration: min(0.35, max(0.10, remaining ?? 0.35)))
        } else {
            transaction.disablesAnimations = true
        }
        #else
        let nextMovement = allowsMotion && hasTime
            ? makeMovement(to: index, from: previous, height: height, remaining: remaining,
                           forced: isManualSeek || isBrowsingReturn)
            : nil
        var transaction = Transaction(animation: nil)
        if let nextMovement {
            transaction.animation = nextMovement.animation
        } else if allowsMotion {
            // Even without mounted geometry, let the native scroll view
            // move continuously during playback and lyric taps.
            transaction.animation = .easeInOut(duration: min(0.35, max(0.10, remaining ?? 0.35)))
        } else {
            transaction.disablesAnimations = true
        }
        activeIndex = index
        if nextMovement != nil { scrollGeometry.movingOffset = scrollGeometry.offset }
        movement = nextMovement
        #endif
        withTransaction(transaction) {
            proxy.scrollTo(lyrics.lines[index].id, anchor: anchor)
        }
    }

    private var isDesktopAnimating: Bool {
        #if os(macOS)
        return movement != nil
        #else
        return false
        #endif
    }

    #if os(macOS)
    private func makeDesktopMovement(
        to index: Int, from previous: Int?, height: CGFloat, remaining: TimeInterval?, forced: Bool
    ) -> DesktopLyricScrollTransition? {
        guard height > 0, let offset = scrollGeometry.offset, let target = scrollGeometry.frames[index] else {
            return nil
        }
        let distance = target.minY + offset - (height - target.height) * anchor.y
        guard abs(distance) >= 1, abs(distance) < height * 0.75 else { return nil }
        return DesktopLyricScrollTransition(
            targetIndex: index, originIndex: previous, originOffset: offset, frames: scrollGeometry.frames,
            viewportHeight: height, timedWordGap: timedWordGap(from: previous, to: index, forced: forced),
            maximumDuration: remaining.map { $0 * 0.8 }, carrying: movement
        )
    }

    private func runDesktopMovement(proxy: ScrollViewProxy, height: CGFloat) async {
        guard var current = movement, current.startedAt == nil else { return }
        let index = current.targetIndex
        guard lyrics.lines.indices.contains(index) else { return }
        // Install the preparation phase before issuing the one-way scroll
        // request. The visual effect keeps each row at its current screen Y.
        await Task.yield()
        guard !Task.isCancelled, movement?.id == current.id else { return }
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) {
            proxy.scrollTo(lyrics.lines[index].id, anchor: anchor)
        }
        do {
            for _ in 0..<12 {
                try await Task.sleep(for: .milliseconds(8))
                guard movement?.id == current.id else { return }
                if let offset = scrollGeometry.offset, let frame = scrollGeometry.frames[index],
                   abs(frame.minY + offset - (height - frame.height) * anchor.y) <= 1 {
                    break
                }
            }
            guard let offset = scrollGeometry.offset else {
                withTransaction(transaction) { movement = nil }
                return
            }
            // If the lazy stack revised its estimated heights, settle at
            // the measured positions instead of dropping the prepared offset.
            current.start(at: .now, frames: scrollGeometry.frames, scrollOffset: offset, viewportHeight: height)
            withTransaction(transaction) { movement = current }
            try await Task.sleep(for: .seconds(current.duration + 0.05))
        } catch { return }
        guard !Task.isCancelled, movement?.id == current.id else { return }
        withTransaction(transaction) { movement = nil }
    }
    #else
    private func makeMovement(
        to index: Int, from previous: Int?, height: CGFloat, remaining: TimeInterval?, forced: Bool
    ) -> LyricScrollMovement? {
        guard height > 0, let offset = scrollGeometry.offset, let target = scrollGeometry.frames[index] else {
            return nil
        }
        let destination = (height - target.height) * anchor.y - target.minY
        let distance = offset - destination
        // Distant targets use the native animation without per-row lag.
        guard abs(distance) >= 1, abs(distance) < height * 0.75 else { return nil }

        let frames = scrollGeometry.frames
        let visible = frames.keys.filter { row in
            guard let frame = frames[row] else { return false }
            let carried = movement?.offset(for: row, scrollOffset: offset) ?? 0
            let currentY = frame.minY + offset + carried
            let targetY = frame.minY + destination
            return (currentY < height && currentY + frame.height > 0)
                || (targetY < height && targetY + frame.height > 0)
        }
        guard let first = visible.min(), let last = visible.max() else { return nil }
        let rows = frames.keys.filter { (first...last).contains($0) }.sorted()
        let orderedRows = distance < 0 ? Array(rows.reversed()) : rows
        let spring = timedWordGap(from: previous, to: index, forced: forced).map(LyricScrollSpring.timedWord)
            ?? .lineChange
        return LyricScrollMovement(
            origin: offset,
            destination: destination,
            rows: orderedRows,
            delayStep: distance < 0 ? 0.025 : 0.05,
            spring: spring,
            maximumDuration: remaining.map { $0 * 0.8 }
        ) { row in
            movement?.offset(for: row, scrollOffset: offset) ?? 0
        }
    }
    #endif

    private func timedWordGap(from previous: Int?, to index: Int, forced: Bool) -> TimeInterval? {
        guard !forced, let previous, let timeline = lyrics.timeline,
              timeline.indices.contains(previous), timeline.indices.contains(index),
              timeline[previous].timingKind == .precise, timeline[index].timingKind == .precise,
              lyrics.lines[previous].words?.isEmpty == false, lyrics.lines[index].words?.isEmpty == false,
              let duration = timeline[previous].duration, duration.isFinite, duration >= 0 else {
            return nil
        }
        let gap = timeline[index].time - (timeline[previous].time + duration)
        return gap.isFinite ? gap : nil
    }
}

private final class LyricScrollGeometry: ObservableObject {
    var frames: [Int: CGRect] = [:]
    var offset: CGFloat?
    #if os(iOS)
    @Published var movingOffset: CGFloat?
    #endif
}

#if os(iOS)
private struct LyricScrollMovement {
    private struct Row {
        let initialOffset: CGFloat
        let lag: CGFloat
    }

    func hasArrived(at offset: CGFloat) -> Bool {
        (origin > destination ? offset - destination : destination - offset) <= 0.5
    }

    private let origin: CGFloat
    private let destination: CGFloat
    private let rows: [Int: Row]
    let animation: Animation

    init(
        origin: CGFloat, destination: CGFloat, rows: [Int], delayStep: TimeInterval, spring: LyricScrollSpring,
        maximumDuration: TimeInterval?, initialOffset: (Int) -> CGFloat
    ) {
        self.origin = origin
        self.destination = destination
        self.rows = Dictionary(uniqueKeysWithValues: rows.enumerated().map { order, index in
            let delay = Double(max(order - 1, 0)) * delayStep
            return (index, Row(initialOffset: initialOffset(index), lag: min(delay / spring.duration, 0.8)))
        })
        let fullDuration = spring.duration + Double(max(rows.count - 2, 0)) * delayStep
        let duration = min(fullDuration, maximumDuration ?? fullDuration)
        animation = spring.animation(duration: duration)
    }

    func offset(for index: Int, scrollOffset: CGFloat?) -> CGFloat {
        guard let row = rows[index], let scrollOffset else { return 0 }
        let distance = origin - destination
        let progress = min(max((origin - scrollOffset) / distance, 0), 1)
        guard progress > 0 else { return row.initialOffset }
        guard progress < 1 else { return 0 }
        // Remap native progress so trailing rows start slower and catch up.
        // The correction is zero at the destination, even when the platform
        // applies its own scroll curve or finishes early.
        let rowProgress = progress * progress / (progress + row.lag * (1 - progress))
        return distance * (progress - rowProgress) + row.initialOffset * (1 - rowProgress)
    }
}

/// MeloX's line-change and timed-word spring parameters, used by the native
/// scroll animation on both platforms.
private struct LyricScrollSpring {
    static let lineChange = Self(frequency: 10, dampingRatio: 0.9)

    private let attenuation: Double
    private let frequency: Double
    let duration: TimeInterval

    private init(frequency: Double, dampingRatio: Double) {
        self.frequency = frequency
        attenuation = frequency * dampingRatio
        let oscillation = frequency * sqrt(1 - dampingRatio * dampingRatio)
        let envelope = hypot(1, attenuation / oscillation)
        duration = log(envelope / 0.005) / attenuation
    }

    static func timedWord(gap: TimeInterval) -> Self {
        guard gap.isFinite else { return .lineChange }
        let progress = min(max((gap - 0.20) / 0.55, 0), 1)
        let period = 0.48 + progress * 0.27
        return Self(frequency: 2 * .pi / period, dampingRatio: 0.90 - progress * 0.12)
    }

    func animation(duration: TimeInterval) -> Animation {
        let speed = self.duration / duration
        let scaledFrequency = frequency * speed
        return .interpolatingSpring(
            mass: 1, stiffness: scaledFrequency * scaledFrequency, damping: 2 * attenuation * speed
        )
    }
}

private struct LyricScrollPosition: ViewModifier {
    let index: Int
    let movement: LyricScrollMovement?
    @ObservedObject var geometry: LyricScrollGeometry

    func body(content: Content) -> some View {
        let offset = movement?.offset(for: index, scrollOffset: geometry.movingOffset) ?? 0
        content
            .offset(y: offset)
            .animation(nil, value: offset)
    }
}
#endif

private struct LyricSeekFeedback {
    let id = UUID()
    let index: Int
    let revision: UInt
}

#if os(iOS)
/// Bridges normalized scroll-offset tracking to iOS 16. Observing the
/// existing scroll view avoids an extra recognizer competing with lyric taps.
private struct LyricsInterfaceScrollObserver: UIViewRepresentable {
    let interface: NowPlayingLyricsInterface

    func makeUIView(context: Context) -> Probe {
        let view = Probe()
        view.isUserInteractionEnabled = false
        view.interface = interface
        return view
    }

    func updateUIView(_ view: Probe, context: Context) {
        if view.interface?.isVisible != interface.isVisible {
            view.tracker.begin(isInterfaceVisible: interface.isVisible)
        }
        view.interface = interface
        view.connect()
    }

    static func dismantleUIView(_ view: Probe, coordinator: ()) {
        view.disconnect()
    }

    final class Probe: UIView {
        var interface: NowPlayingLyricsInterface?
        private var lastViewportSize = CGSize.zero
        var tracker = LyricsScrollInterfaceVisibilityTracker()
        private weak var scrollView: UIScrollView?
        private var observation: NSKeyValueObservation?
        private var lastOffset: CGFloat = 0

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if window == nil { disconnect() } else { connect() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            connect()
        }

        func connect() {
            guard window != nil else { return }
            var ancestor = superview
            while let view = ancestor {
                if let scroll = view as? UIScrollView {
                    guard scrollView !== scroll else { return }
                    disconnect()
                    scrollView = scroll
                    lastOffset = normalizedOffset(scroll)
                    lastViewportSize = scroll.bounds.size
                    scroll.panGestureRecognizer.addTarget(self, action: #selector(didPan(_:)))
                    observation = scroll.observe(\.contentOffset, options: [.new]) { [weak self] scroll, _ in
                        self?.didScroll(scroll)
                    }
                    return
                }
                ancestor = view.superview
            }
        }

        func disconnect() {
            scrollView?.panGestureRecognizer.removeTarget(self, action: #selector(didPan(_:)))
            observation = nil
            scrollView = nil
            tracker.end()
        }

        private func normalizedOffset(_ scroll: UIScrollView) -> CGFloat {
            let insets = scroll.adjustedContentInset
            let maximum = max(scroll.contentSize.height + insets.top + insets.bottom - scroll.bounds.height, 0)
            return min(max(scroll.contentOffset.y + insets.top, 0), maximum)
        }

        @objc private func didPan(_ gesture: UIPanGestureRecognizer) {
            if gesture.state == .began, let scrollView {
                lastOffset = normalizedOffset(scrollView)
                tracker.begin(isInterfaceVisible: interface?.isVisible ?? true)
            } else if gesture.state == .cancelled || gesture.state == .failed {
                tracker.end()
            }
        }

        private func didScroll(_ scroll: UIScrollView) {
            let offset = normalizedOffset(scroll)
            guard lastViewportSize == scroll.bounds.size else {
                lastViewportSize = scroll.bounds.size
                lastOffset = offset
                return
            }
            let delta = offset - lastOffset
            lastOffset = offset
            // Retain manual browsing through inertia. Automatic
            // following and edge rubber-banding cannot hide or reveal controls.
            guard scroll.isDragging || scroll.isDecelerating else {
                tracker.end()
                return
            }
            if let visible = tracker.update(offsetDelta: delta, hideThreshold: 200) {
                interface?.onVisibilityChange(visible)
            }
        }
    }
}
#endif

private struct AppleMusicLyricRow: View, Equatable {
    let line: LyricLine
    let isActive: Bool
    let distance: Int
    let isBrowsing: Bool
    let isSeekTarget: Bool
    let fontSize: CGFloat
    let viewportHeight: CGFloat
    let seek: () -> Void

    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var contrast

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.line == rhs.line && lhs.isActive == rhs.isActive
            && lhs.visualDistance == rhs.visualDistance && lhs.isBrowsing == rhs.isBrowsing
            && lhs.isSeekTarget == rhs.isSeekTarget && lhs.fontSize == rhs.fontSize
            && lhs.viewportHeight == rhs.viewportHeight
    }

    // Both blur and opacity have reached their limits by six rows away.
    private nonisolated var visualDistance: Int { min(max(distance, -6), 6) }

    private var opacity: Double {
        if isActive || isSeekTarget { return 1 }
        if isBrowsing || contrast == .increased { return 0.72 }
        return distance < 0 ? 0.30 : max(0.30, 0.58 - Double(abs(distance)) * 0.055)
    }

    private var blur: CGFloat {
        guard !isActive, !isSeekTarget, !isBrowsing, contrast != .increased else { return 0 }
        return min(3.5, CGFloat(abs(distance)) * 0.65)
    }

    private var annotationFont: Font {
        let showsRomanization = settings.lyricsAnnotation == .romaji && line.romaji != nil
        #if os(iOS)
        let size = UIFont.preferredFont(forTextStyle: showsRomanization ? .callout : .title3).pointSize
        #else
        // Match iOS Callout and Title 3 at the default text size.
        let size: CGFloat = showsRomanization ? 16 : 20
        #endif
        return .system(size: size, weight: .bold)
    }

    private var annotationColor: Color {
        .white.opacity(isActive ? 0.76 : 0.25)
    }

    @ViewBuilder
    private var romanization: some View {
        if settings.lyricsAnnotation == .romaji, let romaji = line.romaji {
            Text(romaji)
                .font(annotationFont)
                .foregroundStyle(annotationColor)
                .padding(.bottom, 5)
        }
    }

    var body: some View {
        Button(action: seek) {
            VStack(alignment: .leading, spacing: 0) {
                romanization
                // Keep the typesetting constant and animate a transform instead
                // of changing the font size: wrapping stays stable on line changes.
                LyricMainText(
                    line: line, isActive: isActive, size: fontSize, weight: .bold,
                    verbatim: settings.verbatimLyrics, inactiveOpacity: 1
                )
                if settings.showLyricsTranslation, let translation = line.translation {
                    Text(translation)
                        .font(annotationFont)
                        .padding(.top, 7)
                        .padding(.bottom, 4)
                        .foregroundStyle(annotationColor)
                }
            }
            .foregroundStyle(.white)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(opacity)
            .scaleEffect(isActive || isBrowsing || isSeekTarget ? 1 : 0.98, anchor: .leading)
            .shadow(color: .white.opacity(isActive ? 0.14 : 0), radius: 12)
            .animation(reduceMotion ? nil : .interpolatingSpring(mass: 1, stiffness: 100, damping: 18),
                       value: opacity)
            .blur(radius: blur)
            .animation(reduceMotion ? nil : .timingCurve(0.33, 0, 0.2, 0.1, duration: 0.12), value: blur)
            .contentShape(Rectangle())
        }
        .buttonStyle(LyricPressButtonStyle(isSeekTarget: isSeekTarget))
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
        .accessibilityHint("跳转到这句歌词")
        .animation(reduceMotion ? nil : .easeOut(duration: 0.35), value: isBrowsing)
    }
}

/// Button's native pressed state yields to scroll gestures and supports
/// keyboard/VoiceOver activation without a competing drag recognizer.
private struct LyricPressButtonStyle: ButtonStyle {
    let isSeekTarget: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.nowPlayingFlushPanelEdges) private var flushPanelEdges

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(configuration.isPressed || isSeekTarget ? 0.12 : 0))
                    // Flush columns have no horizontal gutter: expanding the
                    // background there cuts its rounded corners off at the viewport.
                    .padding(.horizontal, flushPanelEdges ? 0 : -8)
                    .padding(.vertical, -8)
                    .allowsHitTesting(false)
            }
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: configuration.isPressed ? 0.10 : 0.38),
                       value: configuration.isPressed)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.28), value: isSeekTarget)
    }
}


