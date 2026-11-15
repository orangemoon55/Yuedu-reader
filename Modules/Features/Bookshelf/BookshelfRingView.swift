import SwiftUI
import UIKit
import Observation

/// Eight physical slots, paged independently of the shelf's total book count.
/// Rotation never changes a slot's book, decode size, or view identity.
struct BookshelfRingView: View {
    let books: [ReadingBook]
    let colorScheme: ColorScheme
    let isFattened: (UUID) -> Bool
    let onOpen: (ReadingBook) -> Void
    let onContextAction: (ReadingBook, BookshelfBookContextAction) -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = BookshelfRingMotion()
    @State private var page = 0
    @State private var selectedID: UUID?
    @State private var isVisible = false

    private var pageCount: Int { max(1, (books.count + 7) / 8) }
    private var pageStart: Int { min(page, pageCount - 1) * 8 }
    private var pageBooks: [ReadingBook] { Array(books.dropFirst(pageStart).prefix(8)) }
    private var selectedBook: ReadingBook? {
        let index = pageStart + motion.selectedSlot
        return books.indices.contains(index) ? books[index] : nil
    }

    var body: some View {
        VStack(spacing: 14) {
            if let book = selectedBook {
                selectedBar(book)
            }
            BookshelfRingRotor(
                books: pageBooks, colorScheme: colorScheme, motion: motion,
                reduceMotion: reduceMotion, isFattened: isFattened,
                onContextAction: performContextAction
            )
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: 440)
            if pageCount > 1 { pageControls }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DSSpacing.md)
        .padding(.vertical, 8)
        .accessibilityIdentifier("bookshelf.ring")
        .onAppear {
            isVisible = true
            reconcileBooks()
            motion.isActive = scenePhase == .active
        }
        .onDisappear {
            isVisible = false
            motion.isActive = false
        }
        .onChange(of: scenePhase) { _, phase in
            motion.isActive = isVisible && phase == .active
        }
        .onChange(of: reduceMotion) { _, _ in motion.cancelAndSnap() }
        .onChange(of: books.map(\.id)) { _, _ in reconcileBooks() }
        .onChange(of: motion.selectedSlot) { _, _ in selectedID = selectedBook?.id }
    }

    private func selectedBar(_ book: ReadingBook) -> some View {
        HStack(spacing: 12) {
            // Use the same decode size as the ring's largest tile. Selection does
            // not introduce another request size into the cover pipeline.
            ShelfCoverSlot(book: book, colorScheme: colorScheme, displaySize: BookshelfRingPalette.coverSize)
                .frame(width: 46, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: BookshelfCoverStyle.cornerRadius))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 5) {
                Text(book.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(BookshelfRingPalette.cream)
                    .lineLimit(2)
                Text(book.author.isEmpty ? localized("未知作者") : book.author)
                    .font(.caption)
                    .foregroundStyle(BookshelfRingPalette.cream.opacity(0.72))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    ProgressView(value: BookshelfRingGeometry.progress(book.currentPosition))
                        .tint(BookshelfRingPalette.gold)
                    Text(BookshelfRingGeometry.progress(book.currentPosition), format: .percent.precision(.fractionLength(0)))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(BookshelfRingPalette.cream.opacity(0.8))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(localized("閱讀進度"))
                .accessibilityValue(Text(BookshelfRingGeometry.progress(book.currentPosition), format: .percent))
            }
            Button {
                motion.confirmReading()
                onOpen(book)
            } label: {
                Text(localized("立即閱讀"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(BookshelfRingPalette.cream)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(BookshelfRingPalette.jade, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("bookshelf.ring.read")
        }
        .padding(12)
        .background(BookshelfRingPalette.ink, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(BookshelfRingPalette.gold.opacity(0.5), lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .contextMenu { bookMenu(book) }
        .accessibilityIdentifier("bookshelf.ring.selected")
    }

    private var pageControls: some View {
        HStack(spacing: 20) {
            Button { changePage(by: -1) } label: {
                Image(systemName: "chevron.left").frame(width: 44, height: 44)
            }
            .accessibilityLabel(localized("上一頁"))
            .disabled(page == 0)
            Text("\(pageStart + 1)–\(min(pageStart + 8, books.count)) / \(books.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .accessibilityLabel("\(page + 1) / \(pageCount)")
            Button { changePage(by: 1) } label: {
                Image(systemName: "chevron.right").frame(width: 44, height: 44)
            }
            .accessibilityLabel(localized("下一頁"))
            .disabled(page + 1 >= pageCount)
        }
        .buttonStyle(.plain)
        .foregroundStyle(BookshelfRingPalette.gold)
        .accessibilityIdentifier("bookshelf.ring.pages")
    }

    private func changePage(by delta: Int) {
        let next = min(max(page + delta, 0), pageCount - 1)
        guard next != page else { return }
        let slot = min(motion.selectedSlot, min(8, books.count - next * 8) - 1)
        page = next
        motion.configure(count: pageBooks.count, slot: slot)
        selectedID = selectedBook?.id
    }

    private func reconcileBooks() {
        let index = selectedID.flatMap { id in books.firstIndex { $0.id == id } }
            ?? min(pageStart + motion.selectedSlot, max(0, books.count - 1))
        page = index / 8
        motion.configure(count: pageBooks.count, slot: index % 8)
        selectedID = selectedBook?.id
    }

    private func performContextAction(_ book: ReadingBook, _ action: BookshelfBookContextAction) {
        if case .open = action { motion.confirmReading() } else { motion.cancelAndSnap() }
        onContextAction(book, action)
    }

    private func bookMenu(_ book: ReadingBook) -> some View {
        BookshelfBookContextMenu(
            book: book, isFattened: isFattened(book.id),
            onOpen: { performContextAction(book, .open) },
            onSearchCover: { performContextAction(book, .searchCover) },
            onToggleFatten: { performContextAction(book, .toggleFatten) },
            onDelete: { performContextAction(book, .delete) }
        )
    }
}

// MARK: - Rotor (only this subtree reads the per-frame angle)

private struct BookshelfRingRotor: View {
    let books: [ReadingBook]
    let colorScheme: ColorScheme
    let motion: BookshelfRingMotion
    let reduceMotion: Bool
    let isFattened: (UUID) -> Bool
    let onContextAction: (ReadingBook, BookshelfBookContextAction) -> Void
    @GestureState private var gestureIsActive = false

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let coverWidth = min(BookshelfRingPalette.coverSize.width, diameter * 0.153)
            let tileSize = CGSize(width: coverWidth, height: coverWidth * 1.4)
            let angle = motion.rotation
            ZStack {
                ZStack {
                    ForEach(0..<8, id: \.self) { slot in
                        BookshelfRingSector(slot: slot)
                            .fill(slot == motion.selectedSlot ? BookshelfRingPalette.jade : BookshelfRingPalette.sectors[slot % 4])
                            .overlay {
                                BookshelfRingSector(slot: slot)
                                    .stroke(BookshelfRingPalette.gold.opacity(slot == motion.selectedSlot ? 0.95 : 0.38), lineWidth: slot == motion.selectedSlot ? 2 : 0.8)
                            }
                    }
                }
                .rotationEffect(.degrees(Double(angle)))
                .allowsHitTesting(false)
                Circle().stroke(BookshelfRingPalette.gold.opacity(0.8), lineWidth: 1.2)
                    .padding(diameter * 0.035)
                    .allowsHitTesting(false)
                Circle().stroke(BookshelfRingPalette.gold.opacity(0.5), lineWidth: 1)
                    .padding(diameter * 0.285)
                    .allowsHitTesting(false)

                ForEach(Array(books.enumerated()), id: \.element.id) { slot, book in
                    let radians = (CGFloat(slot) * 45 + angle - 90) * .pi / 180
                    BookshelfRingCoverTile(
                        book: book, colorScheme: colorScheme, size: tileSize,
                        isSelected: slot == motion.selectedSlot,
                        isFattened: isFattened(book.id),
                        onSelect: { motion.select(slot, reduceMotion: reduceMotion) },
                        onContextAction: { onContextAction(book, $0) }
                    )
                    // Only the position changes. No parent rotation, counter-rotation,
                    // scale, image rendering, or per-frame change of displaySize.
                    .position(x: center.x + cos(radians) * diameter * 0.337,
                              y: center.y + sin(radians) * diameter * 0.337)
                }
                if books.indices.contains(motion.selectedSlot) {
                    VStack(spacing: 3) {
                        Text(BookshelfRingGeometry.progress(books[motion.selectedSlot].currentPosition), format: .percent.precision(.fractionLength(0)))
                            .font(.title3.monospacedDigit())
                        Text(localized("閱讀進度")).font(.caption2)
                    }
                    .foregroundStyle(BookshelfRingPalette.gold)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
                Capsule().fill(BookshelfRingPalette.gold)
                    .frame(width: 4, height: 12)
                    .position(x: center.x, y: diameter * 0.043)
                    .allowsHitTesting(false)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Circle())
            .simultaneousGesture(rotationGesture(center: center, diameter: diameter))
            .transaction { $0.animation = nil }
        }
        .onChange(of: gestureIsActive) { _, active in
            // GestureState resets on recognizer cancellation too; onEnded has
            // already cleared the drag on a normal release.
            if !active { motion.cancelDrag() }
        }
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            guard !books.isEmpty else { return }
            switch direction {
            case .increment: motion.select((motion.selectedSlot + 1) % books.count, reduceMotion: reduceMotion)
            case .decrement: motion.select((motion.selectedSlot + books.count - 1) % books.count, reduceMotion: reduceMotion)
            @unknown default: break
            }
        }
    }

    private func rotationGesture(center: CGPoint, diameter: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 8, coordinateSpace: .local)
            .updating($gestureIsActive) { _, active, _ in active = true }
            .onChanged { value in
                let radius = hypot(value.startLocation.x - center.x, value.startLocation.y - center.y)
                guard radius >= diameter * 0.215, radius <= diameter * 0.51 else { return }
                motion.drag(value, center: center, reduceMotion: reduceMotion)
            }
            .onEnded { value in motion.endDrag(value, center: center, reduceMotion: reduceMotion) }
    }
}

private struct BookshelfRingCoverTile: View {
    let book: ReadingBook
    let colorScheme: ColorScheme
    let size: CGSize
    let isSelected: Bool
    let isFattened: Bool
    let onSelect: () -> Void
    let onContextAction: (BookshelfBookContextAction) -> Void

    var body: some View {
        Button(action: onSelect) {
            ShelfCoverSlot(book: book, colorScheme: colorScheme, displaySize: BookshelfRingPalette.coverSize)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: BookshelfCoverStyle.cornerRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: BookshelfCoverStyle.cornerRadius)
                        .stroke(isSelected ? BookshelfRingPalette.gold : Color.white.opacity(0.45), lineWidth: isSelected ? 2 : 0.75)
                }
                .shadow(color: .black.opacity(0.35), radius: 3, y: 3)
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookshelfBookContextMenu(
                book: book, isFattened: isFattened,
                onOpen: { onContextAction(.open) },
                onSearchCover: { onContextAction(.searchCover) },
                onToggleFatten: { onContextAction(.toggleFatten) },
                onDelete: { onContextAction(.delete) }
            )
        }
        .accessibilityLabel(BookshelfAccessibility.description(for: book))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("bookshelf.ring.book.\(book.id.uuidString)")
    }
}

private enum BookshelfRingPalette {
    static let coverSize = CGSize(width: 60, height: 84)
    static let ink = Color(red: 0.055, green: 0.10, blue: 0.085)
    static let jade = Color(red: 0.15, green: 0.29, blue: 0.23)
    static let gold = Color(red: 0.77, green: 0.62, blue: 0.36)
    static let cream = Color(red: 0.96, green: 0.92, blue: 0.82)
    static let sectors = [ink, Color(red: 0.08, green: 0.16, blue: 0.13),
                          Color(red: 0.10, green: 0.20, blue: 0.16), Color(red: 0.07, green: 0.14, blue: 0.12)]
}

private struct BookshelfRingSector: Shape {
    let slot: Int

    func path(in rect: CGRect) -> Path {
        let radius = min(rect.width, rect.height) * 0.465
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = Angle.degrees(Double(slot) * 45 - 112.5)
        let end = Angle.degrees(Double(slot) * 45 - 67.5)
        let inner = radius * (0.215 / 0.465)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.addLine(to: CGPoint(x: center.x + inner * CGFloat(cos(end.radians)),
                                y: center.y + inner * CGFloat(sin(end.radians))))
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Motion and geometry

private enum BookshelfRingGeometry {
    static func progress(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0), 1) : 0
    }

    static func angle(_ point: CGPoint, around center: CGPoint) -> CGFloat {
        atan2(point.y - center.y, point.x - center.x) * 180 / .pi
    }

    static func shortest(_ angle: CGFloat) -> CGFloat {
        var result = angle.truncatingRemainder(dividingBy: 360)
        if result > 180 { result -= 360 }
        if result < -180 { result += 360 }
        return result
    }

    static func target(slot: Int, near angle: CGFloat) -> CGFloat {
        let base = -CGFloat(slot) * 45
        return base + ((angle - base) / 360).rounded() * 360
    }

    /// Empty sectors on a partial last page never become the selected book.
    static func nearestSlot(to angle: CGFloat, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return (0..<count).min {
            abs(target(slot: $0, near: angle) - angle) < abs(target(slot: $1, near: angle) - angle)
        } ?? 0
    }
}

@MainActor @Observable
private final class BookshelfRingMotion {
    private(set) var rotation: CGFloat = 0
    private(set) var selectedSlot = 0
    var isActive = false {
        didSet {
            if !isActive { cancelAndSnap() }
        }
    }

    @ObservationIgnored private var count = 0
    @ObservationIgnored private var dragState: DragState?
    @ObservationIgnored private var settling: Settlement?
    @ObservationIgnored private let ticker = BookshelfRingTicker()
    @ObservationIgnored private let selectionFeedback = UISelectionFeedbackGenerator()
    @ObservationIgnored private let openFeedback = UIImpactFeedbackGenerator(style: .light)
    @ObservationIgnored private var lastFeedbackTime: TimeInterval = -.infinity

    private struct DragState {
        // Immutable for one gesture: selection updates never rebase the rotor.
        let baseRotation: CGFloat
        var accumulated: CGFloat = 0
        var lastAngle: CGFloat?
        var lastTime: TimeInterval
        var velocity: CGFloat = 0
    }

    private struct Settlement {
        let start: CGFloat
        let target: CGFloat
        let startedAt: TimeInterval
    }

    func configure(count: Int, slot: Int) {
        stop()
        dragState = nil
        self.count = min(max(count, 0), 8)
        selectedSlot = min(max(slot, 0), max(0, self.count - 1))
        rotation = -CGFloat(selectedSlot) * 45
    }

    func drag(_ value: DragGesture.Value, center: CGPoint, reduceMotion: Bool) {
        guard isActive, count > 0 else { return }
        if dragState == nil {
            // rotation is the actual displayed angle, not an animation's future target.
            stop()
            selectionFeedback.prepare()
            dragState = DragState(
                baseRotation: rotation,
                lastAngle: BookshelfRingGeometry.angle(value.startLocation, around: center),
                lastTime: value.time.timeIntervalSinceReferenceDate - 1 / 60
            )
        }
        updateDrag(value, center: center, reduceMotion: reduceMotion)
    }

    private func updateDrag(_ value: DragGesture.Value, center: CGPoint, reduceMotion: Bool) {
        guard var drag = dragState else { return }
        let now = value.time.timeIntervalSinceReferenceDate
        let angle = BookshelfRingGeometry.angle(value.location, around: center)
        // Crossing the center makes atan2 ill-conditioned. Pause there instead
        // of turning a nearly zero-radius movement into a half revolution.
        guard hypot(value.location.x - center.x, value.location.y - center.y) > 18 else {
            drag.lastAngle = nil
            drag.lastTime = now
            drag.velocity = 0
            dragState = drag
            return
        }
        let delta = drag.lastAngle.map { BookshelfRingGeometry.shortest(angle - $0) } ?? 0
        let elapsed = now - drag.lastTime
        if elapsed > 0 {
            let sample = min(max(delta / CGFloat(max(elapsed, 1 / 240)), -720), 720)
            drag.velocity = elapsed > 0.12 ? sample : drag.velocity * 0.35 + sample * 0.65
        }
        drag.accumulated += delta
        drag.lastAngle = angle
        drag.lastTime = now
        dragState = drag
        let rawAngle = drag.baseRotation + drag.accumulated
        updateSelection(for: rawAngle)
        rotation = reduceMotion ? BookshelfRingGeometry.target(slot: selectedSlot, near: rawAngle) : rawAngle
    }

    func endDrag(_ value: DragGesture.Value, center: CGPoint, reduceMotion: Bool) {
        guard dragState != nil else { return }
        updateDrag(value, center: center, reduceMotion: reduceMotion)
        guard let drag = dragState else { return }
        dragState = nil
        let extra = reduceMotion ? 0 : min(max(drag.velocity * 0.12, -67.5), 67.5)
        settle(projected: drag.baseRotation + drag.accumulated + extra, reduceMotion: reduceMotion)
    }

    func cancelDrag() {
        guard dragState != nil else { return }
        cancelAndSnap()
    }

    func cancelAndSnap() {
        stop()
        dragState = nil
        // Equivalent 360-degree positions are normalized only once motion stops.
        rotation = -CGFloat(selectedSlot) * 45
    }

    func select(_ slot: Int, reduceMotion: Bool) {
        guard isActive, (0..<count).contains(slot), dragState == nil else { return }
        stop()
        settle(projected: BookshelfRingGeometry.target(slot: slot, near: rotation), reduceMotion: reduceMotion)
    }

    func confirmReading() {
        cancelAndSnap()
        guard isActive else { return }
        openFeedback.prepare()
        openFeedback.impactOccurred(intensity: 0.72)
    }

    private func settle(projected: CGFloat, reduceMotion: Bool) {
        let slot = BookshelfRingGeometry.nearestSlot(to: projected, count: count)
        let target = BookshelfRingGeometry.target(slot: slot, near: projected)
        guard !reduceMotion, isActive, abs(target - rotation) > 0.01 else {
            updateSelection(for: target)
            rotation = -CGFloat(selectedSlot) * 45
            return
        }
        settling = Settlement(start: rotation, target: target, startedAt: CACurrentMediaTime())
        ticker.start { [weak self, weak ticker = ticker] time in
            guard let self else { ticker?.stop(); return }
            self.tick(time)
        }
    }

    private func tick(_ time: TimeInterval) {
        guard isActive, let settling else { stop(); return }
        let elapsed = time - settling.startedAt
        if elapsed >= 0.56 {
            updateSelection(for: settling.target)
            rotation = -CGFloat(selectedSlot) * 45
            stop()
            return
        }
        // Closed-form damped spring: frame-rate independent, bounded overshoot,
        // and no delayed completion that can outlive a gesture or a new page.
        let t = CGFloat(max(0, elapsed))
        let decay = exp(-14 * t)
        let fraction = 1 - decay * (cos(18 * t) + (14.0 / 18.0) * sin(18 * t))
        rotation = settling.start + (settling.target - settling.start) * fraction
        updateSelection(for: rotation)
    }

    private func updateSelection(for angle: CGFloat) {
        let next = BookshelfRingGeometry.nearestSlot(to: angle, count: count)
        guard next != selectedSlot else { return }
        selectedSlot = next
        let now = CACurrentMediaTime()
        guard isActive, now - lastFeedbackTime >= 0.07 else { return }
        lastFeedbackTime = now
        selectionFeedback.selectionChanged()
        selectionFeedback.prepare()
    }

    private func stop() {
        ticker.stop()
        settling = nil
    }
}

/// Owns a display link only during the sub-second settlement. The link retains
/// this proxy; its callback captures the motion owner weakly, so it cannot retain
/// the view or deliver an old completion after cancellation.
@MainActor
private final class BookshelfRingTicker: NSObject {
    private var link: CADisplayLink?
    private var callback: ((TimeInterval) -> Void)?

    func start(_ callback: @escaping (TimeInterval) -> Void) {
        stop()
        self.callback = callback
        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        self.link = link
        link.add(to: .main, forMode: .common)
    }

    func stop() {
        link?.invalidate()
        link = nil
        callback = nil
    }

    @objc private func tick(_ link: CADisplayLink) {
        callback?(link.timestamp)
    }
}
