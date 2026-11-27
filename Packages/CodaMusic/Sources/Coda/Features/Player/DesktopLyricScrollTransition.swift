// SPDX-License-Identifier: GPL-3.0-only
// Adapted from MeloX DesktopLyricsScrollView, AppleMusicLyricsLinePositionPlanner,
// AppleMusicLyricsDynamicSpring, and LyricMovementTransition at 09713edb847a.
// See ThirdPartyNotices/MeloX.md.
#if os(macOS)
import SwiftUI

struct DesktopLyricScrollTransition {
    let id = UUID()
    let targetIndex: Int
    let originIndex: Int?
    let originOffset: CGFloat
    let initialY: [Int: CGFloat]
    let visibleAtOrigin: Set<Int>
    let spring: Spring
    let maximumDuration: TimeInterval?
    private(set) var startedAt: Date?
    private(set) var duration: TimeInterval = 0
    private var rows: [Int: Row] = [:]

    struct Row {
        let initialOffset: CGFloat
        let delay: TimeInterval
        let spring: Spring
        let settlingDuration: TimeInterval
        let timeScale: Double
        let startedAt: Date

        func offset(at date: Date) -> CGFloat {
            let elapsed = date.timeIntervalSince(startedAt) - delay
            guard elapsed > 0 else { return initialOffset }
            guard elapsed < settlingDuration else { return 0 }
            let progress = spring.value(target: 1, initialVelocity: 0, time: elapsed * timeScale)
            return initialOffset * (1 - progress)
        }
    }

    init(
        targetIndex: Int, originIndex: Int?, originOffset: CGFloat, frames: [Int: CGRect],
        viewportHeight: CGFloat, timedWordGap: TimeInterval?, maximumDuration: TimeInterval?,
        carrying previous: Self?
    ) {
        self.targetIndex = targetIndex
        self.originIndex = originIndex
        self.originOffset = originOffset
        self.maximumDuration = maximumDuration
        spring = Self.lineChangeSpring(timedWordGap: timedWordGap)
        let now = Date.now
        let positions = frames.map { index, frame in
            let y = frame.minY + originOffset
            let presentationY = previous?.presentationY(for: index, frame: frame, scrollOffset: originOffset, at: now)
            return (index, presentationY ?? y)
        }
        let initialY = Dictionary(uniqueKeysWithValues: positions)
        self.initialY = initialY
        visibleAtOrigin = Set(frames.keys.filter { index in
            guard let frame = frames[index], let y = initialY[index] else { return false }
            return y < viewportHeight && y + frame.height > 0
        })
    }

    mutating func start(at date: Date, frames: [Int: CGRect], scrollOffset: CGFloat, viewportHeight: CGFloat) {
        let visible = visibleAtOrigin.union(frames.compactMap { index, frame in
            let y = frame.minY + scrollOffset
            return y < viewportHeight && y + frame.height > 0 ? index : nil
        })
        startedAt = date
        guard let first = visible.min(), let last = visible.max() else { return }
        let mounted = frames.keys.sorted()
        let participating = mounted.filter { (first...last).contains($0) }
        let reverse = originOffset < scrollOffset
        let delayStep = reverse ? 0.025 : 0.05
        let originOrder = originIndex.flatMap { participating.firstIndex(of: $0) }
        let settling = spring.settlingDuration(target: 1, initialVelocity: 0, epsilon: 0.001)
        let plan = participating.enumerated().compactMap { order, index -> (Int, CGFloat, TimeInterval)? in
            guard let frame = frames[index] else { return nil }
            let startY = initialY[index] ?? frame.minY + originOffset
            let offset = startY - (frame.minY + scrollOffset)
            guard offset != 0 else { return nil }
            // MeloX counts stagger slots from the previously positioned line
            // when it is still mounted in either viewport.
            let lineOrder = originOrder.map { reverse ? $0 - order : order - $0 }
                ?? (reverse ? participating.count - 1 - order : order)
            return (index, offset, Double(max(lineOrder - 1, 0)) * delayStep)
        }
        guard let lastDelay = plan.map({ $0.2 }).max() else { return }
        let fullDuration = settling + lastDelay
        duration = min(fullDuration, maximumDuration ?? fullDuration)
        guard duration > 0 else { return }
        let scale = duration / fullDuration
        rows = Dictionary(uniqueKeysWithValues: plan.map { index, offset, delay in
            (index, Row(initialOffset: offset, delay: delay * scale, spring: spring,
                        settlingDuration: settling * scale, timeScale: 1 / scale, startedAt: date))
        })
    }

    func position(for index: Int) -> DesktopLyricScrollPosition.Phase {
        if startedAt == nil {
            return .preparing(initialY: initialY[index], originOffset: originOffset)
        }
        return rows[index].map { .moving($0) } ?? .idle
    }

    private func presentationY(for index: Int, frame: CGRect, scrollOffset: CGFloat, at date: Date) -> CGFloat {
        if startedAt == nil { return initialY[index] ?? frame.minY + originOffset }
        return frame.minY + scrollOffset + (rows[index]?.offset(at: date) ?? 0)
    }

    private static func lineChangeSpring(timedWordGap: TimeInterval?) -> Spring {
        guard let timedWordGap else {
            return Spring(mass: 1, stiffness: 100, damping: 18, allowOverDamping: true)
        }
        let progress = min(max((timedWordGap - 0.20) / 0.55, 0), 1)
        let frequency = 2 * Double.pi / (0.48 + progress * 0.27)
        let dampingRatio = 0.90 - progress * 0.12
        return Spring(mass: 1, stiffness: frequency * frequency,
                      damping: 2 * frequency * dampingRatio, allowOverDamping: true)
    }
}

struct DesktopLyricScrollPosition: ViewModifier {
    enum Phase {
        case idle
        case preparing(initialY: CGFloat?, originOffset: CGFloat)
        case moving(DesktopLyricScrollTransition.Row)
    }

    let phase: Phase

    func body(content: Content) -> some View {
        let row: DesktopLyricScrollTransition.Row? = if case let .moving(row) = phase { row } else { nil }
        let prepared: (CGFloat?, CGFloat)? = if case let .preparing(y, origin) = phase { (y, origin) } else { nil }
        TimelineView(.animation(paused: row == nil)) { context in
            content
                .offset(y: row?.offset(at: context.date) ?? 0)
                .visualEffect { effect, geometry in
                    guard let (initialY, originOffset) = prepared else { return effect.offset(y: 0) }
                    // Read the actual row position from the same render pass
                    // that applies compensation for the native scroll jump.
                    let viewportY = geometry.frame(in: .named("appleMusicLyricViewport")).minY
                    let startY = initialY ?? geometry.frame(in: .named("appleMusicLyricContent")).minY + originOffset
                    return effect.offset(y: startY - viewportY)
                }
        }
    }
}
#endif
