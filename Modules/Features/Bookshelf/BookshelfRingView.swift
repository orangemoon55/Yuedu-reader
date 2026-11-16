import SwiftUI
import UIKit
import Observation
import AudioToolbox

/// One sector per visible book, with at most nine books and no ring pagination.
/// Rotation never changes a slot's book, decode size, or view identity.
struct BookshelfRingView: View {
    let books: [ReadingBook]
    let colorScheme: ColorScheme
    let isFattened: (UUID) -> Bool
    let chapterContext: @MainActor (ReadingBook) async -> BookshelfRingChapterContext
    let onOpen: (ReadingBook, BookshelfTappedCover) -> Void
    let onCoverFrameChange: (ReadingBook, CGRect) -> Void
    let onContextAction: (ReadingBook, BookshelfBookContextAction) -> Void
    let onShowMore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var motion = BookshelfRingMotion()
    @State private var selectedID: UUID?
    @State private var isVisible = false
    @State private var coverSources = BookshelfRingCoverSources()
    @State private var loadedChapterContext: (book: ReadingBook, context: BookshelfRingChapterContext)?
    @State private var currentVisibleBooks: [ReadingBook] = []
    @State private var isDrawing = false
    @State private var drawRecommendation: (bookID: UUID, text: String)?
    @State private var displayedBookOverride: UUID?
    @State private var cachedDrawCategory: (bookID: UUID, category: String)?


    private struct ChapterRequest: Equatable {
        let book: ReadingBook?
        let isActive: Bool
    }

    private var visibleBooks: [ReadingBook] {
        guard let displayedBookOverride else {
            return BookshelfDrawRecommendation.visibleBooks(from: books, including: selectedID)
        }
        return BookshelfDrawRecommendation.visibleBooks(from: books, preserving: selectedID,
                                                         including: displayedBookOverride)
    }
    private var selectedBook: ReadingBook? {
        let visible = visibleBooks
        let id = isDrawing ? displayedBookOverride : selectedID
        let slot = BookshelfDrawRecommendation.slot(for: id, in: visible, fallback: motion.selectedSlot)
        return visible.indices.contains(slot) ? visible[slot] : nil
    }

    private func startDrawing() {
        guard !isDrawing else { return }
        let pool = BookshelfDrawRecommendation.eligible(in: books)
        guard !pool.isEmpty else { return }
        var generator = SystemRandomNumberGenerator()
        guard let winner = BookshelfDrawRecommendation.choose(from: pool, using: &generator) else { return }
        let visible = BookshelfDrawRecommendation.visibleBooks(from: pool, preserving: selectedID, including: winner.id)
        guard let slot = visible.firstIndex(where: { $0.id == winner.id }) else { return }
        currentVisibleBooks = visible
        displayedBookOverride = winner.id
        drawRecommendation = nil
        cachedDrawCategory = nil
        isDrawing = true
        reconcileBooks()
        motion.draw(slot: slot, reduceMotion: reduceMotion) { completedSlot in
            guard currentVisibleBooks.indices.contains(completedSlot) else { return }
            let winner = currentVisibleBooks[completedSlot]
            drawRecommendation = (winner.id, BookshelfDrawRecommendation.message(for: winner, category: cachedDrawCategory?.bookID == winner.id ? cachedDrawCategory?.category : nil))
            isDrawing = false
            selectedID = winner.id
            displayedBookOverride = winner.id
            cachedDrawCategory = nil
        }
        let sourceID = winner.bookSourceId
        let infoURL = winner.bookInfoURL?.trimmingCharacters(in: .whitespacesAndNewlines)
        let variables = winner.runtimeVariables
        Task.detached(priority: .utility) {
            let cachedKind: String?
            if let sourceID, let infoURL, !infoURL.isEmpty {
                var source = BookSource()
                source.id = sourceID
                cachedKind = BookSourceFetcher.shared.loadBookInfoPackageSync(
                    url: infoURL, source: source, maximumAge: nil
                )?.kind
            } else {
                cachedKind = nil
            }
            let trimmed = cachedKind?.trimmingCharacters(in: .whitespacesAndNewlines)
            let category = (trimmed?.isEmpty == false ? trimmed : nil)
                ?? ["kind", "category", "genre"].compactMap { variables?[$0] }
                    .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
            await MainActor.run {
                if displayedBookOverride == winner.id {
                    cachedDrawCategory = category.map { (winner.id, $0) }
                }
            }
        }
    }

    private func resetDrawState() {
        isDrawing = false
        currentVisibleBooks = []
        drawRecommendation = nil
        displayedBookOverride = nil
        cachedDrawCategory = nil
        motion.cancelAndSnap()
    }

    var body: some View {
        VStack(spacing: 14) {
            if let book = selectedBook {
                let context = context(for: book)
                BookshelfRingReadingPrompt(
                    book: book, context: context,
                    recommendation: drawRecommendation?.bookID == book.id ? drawRecommendation?.text : nil,
                    onOpen: { open(book) }
                )
                BookshelfRingSelectedCard(book: book, context: context, colorScheme: colorScheme,
                                          onOpen: { open(book) })
                .contextMenu { bookMenu(book) }
            } else if let drawRecommendation {
                VStack(alignment: .leading, spacing: 4) {
                    Text(drawRecommendation.text)
                        .font(.headline)
                        .foregroundStyle(DSColor.textPrimary)
                        .lineLimit(2)
                    Button(localized("再抽一次")) { startDrawing() }
                        .font(.caption)
                        .foregroundStyle(DSColor.accent)
                }
                .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            } else {
                Text(localized("抽签提示语"))
                    .font(.headline)
                    .foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
            }
            GeometryReader { proxy in
                let showsMore = books.count > BookshelfRingGeometry.maximumCount
                let gearSide = max(0, min(440, proxy.size.height, proxy.size.width - (showsMore ? 72 : 0)))
                let sidebar = showsMore ? min(64, max(0, proxy.size.width - gearSide - 8)) : CGFloat(0)
                let sidebarGap: CGFloat = showsMore ? 8 : 0
                ZStack {
                    let rotor = BookshelfRingRotor(
                        books: visibleBooks, colorScheme: colorScheme, motion: motion,
                        reduceMotion: reduceMotion, isFattened: isFattened,
                        coverSources: coverSources, onCoverFrameChange: onCoverFrameChange,
                        onOpen: open,
                        onContextAction: performContextAction,
                        onDraw: startDrawing
                    )
                    .frame(width: gearSide, height: gearSide)
                    if showsMore {
                        HStack(spacing: 8) {
                            rotor
                            Button {
                                guard !isDrawing else { return }
                                motion.cancelAndSnap()
                                onShowMore()
                            } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: "books.vertical")
                                        .font(.title3)
                                    Text(localized("更多書籍"))
                                        .font(.caption.weight(.medium))
                                        .multilineTextAlignment(.center)
                                    Text(books.count, format: .number)
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(DSColor.textSecondary)
                                }
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(DSColor.accent)
                            .accessibilityIdentifier("bookshelf.ring.more")
                            .disabled(isDrawing)
                            .frame(width: sidebar, height: diameter)
                        }
                        .frame(width: gearSide + sidebarGap + sidebar, height: gearSide, alignment: .center)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        rotor
                            .frame(width: diameter, height: diameter)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("bookshelf.ring")
        .task(id: ChapterRequest(book: selectedBook, isActive: scenePhase == .active)) {
            guard scenePhase == .active, let book = selectedBook else { return }
            let context = await chapterContext(book)
            guard !Task.isCancelled else { return }
            loadedChapterContext = (book, context)
        }
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
        .onChange(of: motion.selectedSlot) { _, _ in
            if !isDrawing, displayedBookOverride == nil { selectedID = selectedBook?.id }
        }
    }

    private func context(for book: ReadingBook) -> BookshelfRingChapterContext {
        if let loadedChapterContext, loadedChapterContext.book == book { return loadedChapterContext.context }
        return BookshelfRingChapterContext(book: book, chapters: [], textPosition: nil)
    }

    private func reconcileBooks() {
        let visible = visibleBooks
        let index = selectedID.flatMap { id in visible.firstIndex { $0.id == id } }
            ?? min(motion.selectedSlot, max(0, visible.count - 1))
        coverSources.retain(books: visible)
        motion.configure(count: visible.count, slot: index)
        selectedID = selectedBook?.id
    }

    private func open(_ book: ReadingBook) {
        // Capture the tapped artwork before stopping/snap-aligning the rotor.
        let tapped = coverSources.tappedCover(for: book.id)
        motion.confirmReading()
        onOpen(book, tapped)
    }

    private func performContextAction(_ book: ReadingBook, _ action: BookshelfBookContextAction) {
        if case .open = action { open(book); return }
        motion.cancelAndSnap()
        onContextAction(book, action)
    }

    private func bookMenu(_ book: ReadingBook) -> some View {
        BookshelfBookContextMenu(
            book: book, isFattened: isFattened(book.id),
            onOpen: { performContextAction(book, .open) },
            onShowDetail: { performContextAction(book, .showDetail) },
            onSearchCover: { performContextAction(book, .searchCover) },
            onToggleFatten: { performContextAction(book, .toggleFatten) },
            onDelete: { performContextAction(book, .delete) }
        )
    }
}

// MARK: - Rotor (only this subtree reads the per-frame angle)

/// Reference storage: per-frame geometry reports never publish shelf state.
@MainActor
final class BookshelfRingCoverSources {
    private var boxes: [UUID: BookshelfCoverFrameBox] = [:]

    func box(for id: UUID) -> BookshelfCoverFrameBox {
        if let box = boxes[id] { return box }
        let box = BookshelfCoverFrameBox()
        boxes[id] = box
        return box
    }

    func tappedCover(for id: UUID) -> BookshelfTappedCover {
        box(for: id).tappedCover()
    }

    func open(_ book: ReadingBook, onOpen: (ReadingBook, BookshelfTappedCover) -> Void) {
        onOpen(book, tappedCover(for: book.id))
    }

    func retain(books: [ReadingBook]) {
        let ids = Set(books.map(\.id))
        boxes = boxes.filter { ids.contains($0.key) }
    }
}

private struct BookshelfRingRotor: View {
    let books: [ReadingBook]
    let colorScheme: ColorScheme
    let motion: BookshelfRingMotion
    let reduceMotion: Bool
    let isFattened: (UUID) -> Bool
    let coverSources: BookshelfRingCoverSources
    let onCoverFrameChange: (ReadingBook, CGRect) -> Void
    let onOpen: (ReadingBook) -> Void
    let onContextAction: (ReadingBook, BookshelfBookContextAction) -> Void
    let onDraw: () -> Void
    @GestureState private var gestureIsActive = false
    @State private var coverBackdrops: [UUID: UIImage] = [:]

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let step = BookshelfRingGeometry.step(count: books.count)
            let tileSize = BookshelfRingPresentation.coverSize(diameter: diameter, count: books.count)
            let orbitRadius = BookshelfRingPresentation.orbitRadius(diameter: diameter, count: books.count)
            let angle = motion.rotation
            ZStack {
                ZStack {
                    ForEach(books.indices, id: \.self) { slot in
                        BookshelfRingSectorArtwork(
                            image: coverBackdrops[books[slot].id], slot: slot, count: books.count,
                            diameter: diameter, rotation: angle, isSelected: slot == motion.selectedSlot,
                            colorScheme: colorScheme
                        )
                    }
                }
                .rotationEffect(.degrees(Double(angle)))
                .allowsHitTesting(false)
                BookshelfCyberGear(diameter: diameter, rotation: angle, colorScheme: colorScheme,
                                   isSpinning: motion.isSpinning, selectedSlot: motion.selectedSlot)
                Circle().stroke(BookshelfRingPalette.jade.opacity(0.18), lineWidth: 0.65)
                    .padding(diameter * (0.5 - BookshelfRingGeometry.innerRadius))
                    .allowsHitTesting(false)

                ForEach(Array(books.enumerated()), id: \.element.id) { slot, book in
                    let radians = (CGFloat(slot) * step + angle - 90) * .pi / 180
                    BookshelfRingCoverTile(
                        book: book, colorScheme: colorScheme, size: tileSize,
                        isSelected: slot == motion.selectedSlot,
                        isFattened: isFattened(book.id),
                        coverFrame: coverSources.box(for: book.id),
                        onCoverFrameChange: { onCoverFrameChange(book, $0) },
                        onBackdrop: { coverBackdrops[book.id] = $0 },

                        onSelect: {
                            guard motion.canOpenSector else { return }
                            onOpen(book)
                        },
                        onContextAction: { onContextAction(book, $0) }
                    )
                    // Only the position changes. No parent rotation, counter-rotation,
                    // scale, image rendering, or per-frame change of displaySize.
                    .position(x: center.x + cos(radians) * orbitRadius,
                              y: center.y + sin(radians) * orbitRadius)
                }
                BookshelfRingCenterBadge(
                    diameter: diameter * BookshelfRingGeometry.innerRadius * 2,
                    onDraw: books.isEmpty ? nil : onDraw
                )
                    .position(center)
                if !books.isEmpty {
                    Capsule().fill(BookshelfRingPalette.jade.opacity(0.7))
                        .frame(width: 3, height: 9)
                        .position(x: center.x, y: diameter * 0.043)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                Circle().fill(Color.clear).contentShape(Circle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard motion.canOpenSector, let slot = BookshelfRingGeometry.slot(
                            at: value.location, center: center, diameter: diameter,
                            rotation: motion.rotation, count: books.count
                        ) else { return }
                        onOpen(books[slot])
                    })
            }
            .contentShape(Circle())
            .simultaneousGesture(rotationGesture(center: center, diameter: diameter))
        }
        .onChange(of: gestureIsActive) { _, active in
            // GestureState resets on recognizer cancellation too; onEnded has
            // already cleared the drag on a normal release.
            if !active { motion.cancelDrag() }
        }
        .onChange(of: books.map(\.id)) { _, ids in
            coverBackdrops = coverBackdrops.filter { ids.contains($0.key) }
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
                guard radius >= diameter * BookshelfRingGeometry.innerRadius,
                      radius <= diameter * BookshelfRingGeometry.outerRadius else { return }
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
    let coverFrame: BookshelfCoverFrameBox
    let onCoverFrameChange: (CGRect) -> Void
    let onBackdrop: (UIImage) -> Void
    let onSelect: () -> Void
    let onContextAction: (BookshelfBookContextAction) -> Void
    @State private var tintImage: UIImage?

    var body: some View {
        let cornerRadius = BookshelfCoverStyle.cornerRadius
        Button(action: onSelect) {
            ShelfCoverSlot(book: book, colorScheme: colorScheme, displaySize: BookshelfRingPresentation.coverDecodeSize)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                // Measure only the untransformed front artwork. The paper, board,
                // highlights and shadows must not enter the reader's lift frame.
                .reportBookshelfCoverFrame(into: coverFrame, onChange: onCoverFrameChange, onImage: { tintImage = $0 })
                .overlay {
                    BookshelfRingBookFinish(size: size)
                        .equatable()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isSelected ? BookshelfRingPalette.jade : Color.white.opacity(0.45), lineWidth: isSelected ? 2 : 0.75)
                        .allowsHitTesting(false)
                }
                .background {
                    BookshelfRingBookDepth(size: size, cornerRadius: cornerRadius)
                        .equatable()
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .padding(4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            BookshelfBookContextMenu(
                book: book, isFattened: isFattened,
                onOpen: { onContextAction(.open) },
                onShowDetail: { onContextAction(.showDetail) },
                onSearchCover: { onContextAction(.searchCover) },
                onToggleFatten: { onContextAction(.toggleFatten) },
                onDelete: { onContextAction(.delete) }
            )
        }
        .accessibilityLabel(BookshelfAccessibility.description(for: book))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("bookshelf.ring.book.\(book.id.uuidString)")
        .task(id: tintImage.map(ObjectIdentifier.init)) {
            guard let image = tintImage else { return }
            let backdrop = await Task.detached(priority: .utility) {
                BookshelfRingPresentation.makeBackdrop(from: image)
            }.value
            guard !Task.isCancelled, let backdrop else { return }
            onBackdrop(backdrop)
        }
    }
}

/// A light, static book block behind the measured front cover. Its positive x/y
/// offsets leave the front artwork's frame untouched while exposing paper at the
/// fore-edge and tail edge.
private struct BookshelfRingBookDepth: View, Equatable {
    let size: CGSize
    let cornerRadius: CGFloat

    private static let paper = Color(red: 0.91, green: 0.87, blue: 0.75)
    private static let paperShadow = Color(red: 0.52, green: 0.46, blue: 0.34)
    private static let paperLine = Color(red: 0.45, green: 0.39, blue: 0.28).opacity(0.48)

    var body: some View {
        let depthX = min(max(size.width * 0.06, 2), 4)
        let depthY = min(max(size.height * 0.045, 2.5), 4.5)
        let paperRadius = min(max(1, cornerRadius * 0.82), min(size.width, size.height) * 0.5)

        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: paperRadius, style: .continuous)
                .fill(Color.black.opacity(0.34))
                .frame(width: size.width, height: size.height)
                .offset(x: depthX, y: depthY)
                .shadow(color: .black.opacity(0.28), radius: 2.5, x: 0.8, y: 1.8)

            RoundedRectangle(cornerRadius: paperRadius, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Self.paperShadow, Self.paper, Self.paperShadow.opacity(0.82)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size.width, height: size.height)
                .offset(x: depthX * 0.62, y: depthY * 0.68)

            // Two continuous page cuts follow the same shallow oblique projection
            // around the fore-edge and tail; no image work or rotor state is read.
            Path { path in
                for layer in 1...2 {
                    let fraction = CGFloat(layer) / 3
                    let x = depthX * 0.62 * fraction
                    let y = depthY * 0.68 * fraction
                    path.move(to: CGPoint(x: size.width + x, y: paperRadius + y))
                    path.addLine(to: CGPoint(x: size.width + x, y: size.height - paperRadius + y))
                    path.addQuadCurve(
                        to: CGPoint(x: size.width - paperRadius + x, y: size.height + y),
                        control: CGPoint(x: size.width + x, y: size.height + y)
                    )
                    path.addLine(to: CGPoint(x: paperRadius + x, y: size.height + y))
                }
            }
            .stroke(Self.paperLine, lineWidth: 0.45)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
    }
}

/// Static cover finish applied above the actual `ShelfCoverSlot` artwork. The
/// low-alpha lines suggest a pressed spine and a soft varnish without covering
/// the title or changing the image reported to the transition.
private struct BookshelfRingBookFinish: View, Equatable {
    let size: CGSize

    var body: some View {
        let spineX = max(3, size.width * 0.075)
        let spineWidth = max(0.65, size.width * 0.012)
        let spineHeight = max(4, size.height * 0.82)

        ZStack(alignment: .topLeading) {
            LinearGradient(
                stops: [
                    .init(color: Color.white.opacity(0.16), location: 0),
                    .init(color: Color.white.opacity(0.045), location: 0.23),
                    .init(color: .clear, location: 0.52),
                    .init(color: Color.black.opacity(0.06), location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Capsule()
                .fill(
                    LinearGradient(
                        colors: [Color.black.opacity(0.2), Color.white.opacity(0.12), Color.black.opacity(0.12)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .frame(width: spineWidth, height: spineHeight)
                .offset(x: spineX, y: (size.height - spineHeight) * 0.5)

            Capsule()
                .stroke(Color.white.opacity(0.14), lineWidth: max(0.45, spineWidth * 0.55))
                .frame(width: max(1.2, spineWidth * 1.9), height: max(4, size.height * 0.77))
                .offset(x: spineX + spineWidth * 0.7, y: size.height * 0.115)

            RoundedRectangle(cornerRadius: max(1, size.width * 0.025), style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.2), .clear, Color.black.opacity(0.1)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: max(0.55, size.width * 0.012)
                )
                .padding(max(0.8, size.width * 0.018))
        }
        .frame(width: size.width, height: size.height)
    }
}

private enum BookshelfRingPalette {
    static let coverSize = CGSize(width: 60, height: 84)
    static let jade = Color(red: 0.32, green: 0.49, blue: 0.43)
    static let cream = Color(red: 0.99, green: 0.98, blue: 0.94)
}

struct BookshelfRingSector: Shape {
    let slot: Int
    let count: Int

    func path(in rect: CGRect) -> Path {
        guard count > 0 else { return Path() }
        let diameter = min(rect.width, rect.height)
        let radius = diameter * BookshelfRingGeometry.outerRadius
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let inner = diameter * BookshelfRingGeometry.innerRadius
        if count == 1 {
            // Opposite winding preserves the small hole. Two half-arcs avoid
            // implementations treating a 360° sweep as a zero-length arc.
            var path = Path()
            path.addArc(center: center, radius: radius, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            path.addArc(center: center, radius: radius, startAngle: .degrees(180), endAngle: .degrees(360), clockwise: false)
            path.closeSubpath()
            path.move(to: CGPoint(x: center.x + inner, y: center.y))
            path.addArc(center: center, radius: inner, startAngle: .degrees(360), endAngle: .degrees(180), clockwise: true)
            path.addArc(center: center, radius: inner, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            path.closeSubpath()
            return path
        }
        let step = Double(BookshelfRingGeometry.step(count: count))
        let start = Angle.degrees(Double(slot) * step - 90 - step / 2)
        let end = Angle.degrees(Double(slot) * step - 90 + step / 2)
        var path = Path()
        path.addArc(center: center, radius: radius, startAngle: start, endAngle: end, clockwise: false)
        path.addLine(to: CGPoint(x: center.x + inner * CGFloat(cos(end.radians)),
                                y: center.y + inner * CGFloat(sin(end.radians))))
        path.addArc(center: center, radius: inner, startAngle: end, endAngle: start, clockwise: true)
        path.closeSubpath()
        return path
    }
}

// MARK: - Chapter context

/// Mirrors the reader's restore source; shelf summaries never carry the full TOC.
struct BookshelfRingChapterContext: Equatable, Sendable {
    let currentTitle: String
    let latestTitle: String?
    let isUnread: Bool

    init(book: ReadingBook, chapters: [OnlineChapterRef], textPosition: CoreTextReadingPosition?) {
        let restoredIndex: Int
        switch book.resolvedPipelineKind {
        case .manga, .fixedPage:
            restoredIndex = book.mangaChapterIndex
            isUnread = restoredIndex == 0 && book.mangaPage == 0 && book.currentPosition == 0
        case .audio, .video:
            restoredIndex = book.audioChapterIndex
            isUnread = restoredIndex == 0 && book.audioTimeSeconds == 0
        default:
            restoredIndex = textPosition?.spineIndex ?? 0
            isUnread = textPosition == nil && book.currentPosition == 0
        }
        let total = max(chapters.count, book.totalChapterNum ?? 0)
        let upper = min(total > 0 ? total - 1 : Int(Int32.max) - 1, Int(Int32.max) - 1)
        let index = min(max(restoredIndex, 0), upper)
        let readable = chapters.indices.filter { !chapters[$0].shouldRenderAsVolumeSeparator }
        let chapterIndex = readable.first(where: { $0 >= index }) ?? readable.last
        currentTitle = chapterIndex.flatMap { Self.title(chapters[$0].title) }
            ?? String(format: localized("第 %d 章"), index + 1)
        latestTitle = Self.title(book.latestChapterDisplayTitle ?? book.latestChapterTitle)
            ?? readable.last.flatMap { Self.title(chapters[$0].title) }
    }

    var readingPrompt: String { "\(localized("閱讀")) \(currentTitle)" }
    static func dailyMessage(for title: String) -> String {
        let name = title.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return name.isEmpty ? localized("翻開一頁，讓心慢下來。") : "把片刻留給《\(name)》，讓心慢下來。"
    }
    var currentChapterLine: String {
        "\(localized("目前在讀"))：\(isUnread ? localized("尚未開始") + " · " : "")\(currentTitle)"
    }
    var latestChapterLine: String {
        "\(localized("最新章節"))：\(latestTitle ?? localized("暫無章節資訊"))"
    }

    private static func title(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let text = ReaderHTMLUtilities.displayText(fromHTMLFragment: raw)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.isEmpty ? nil : text
    }
}

// MARK: - Motion and geometry

enum BookshelfRingGeometry {
    static let maximumCount = 9
    static let innerRadius: CGFloat = 0.055
    static let outerRadius: CGFloat = 0.465

    static func step(count: Int) -> CGFloat {
        guard count > 0 else { return 0 }
        return 360 / CGFloat(min(count, maximumCount))
    }

    /// Slot zero starts at twelve o'clock. Each visible book owns one equal
    /// sector; the small center hole and the outside never open a book.
    static func slot(at point: CGPoint, center: CGPoint, diameter: CGFloat, rotation: CGFloat, count: Int) -> Int? {
        guard diameter.isFinite, diameter > 0, rotation.isFinite,
              point.x.isFinite, point.y.isFinite, center.x.isFinite, center.y.isFinite,
              count > 0 else { return nil }
        let radius = hypot(point.x - center.x, point.y - center.y) / diameter
        guard radius >= innerRadius, radius <= outerRadius else { return nil }
        let visibleCount = min(count, maximumCount)
        let step = step(count: visibleCount)
        let raw = (angle(point, around: center) + 90 - rotation + step / 2)
            .truncatingRemainder(dividingBy: 360)
        let normalized = raw < 0 ? raw + 360 : raw
        return Int(floor(normalized / step)) % visibleCount
    }

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

    static func target(slot: Int, near angle: CGFloat, count: Int) -> CGFloat {
        guard count > 0, angle.isFinite else { return 0 }
        let visibleCount = min(count, maximumCount)
        let index = min(max(slot, 0), visibleCount - 1)
        let base = -CGFloat(index) * step(count: visibleCount)
        return base + ((angle - base) / 360).rounded() * 360
    }

    static func nearestSlot(to angle: CGFloat, count: Int) -> Int {
        guard count > 0, angle.isFinite else { return 0 }
        return (0..<min(count, maximumCount)).min {
            abs(target(slot: $0, near: angle, count: count) - angle) < abs(target(slot: $1, near: angle, count: count) - angle)
        } ?? 0
    }
}

@MainActor @Observable
final class BookshelfRingMotion {
    private(set) var rotation: CGFloat = 0
    private(set) var selectedSlot = 0
    private(set) var isSpinning = false
    var isActive = false {
        didSet {
            if !isActive { cancelAndSnap() }
        }
    }

    @ObservationIgnored private var count = 0
    @ObservationIgnored private var dragState: DragState?
    @ObservationIgnored private var settling: Settlement?
    @ObservationIgnored private let ticker = BookshelfRingTicker()
    @ObservationIgnored private let selectionFeedback = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let openFeedback = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private var lastFeedbackTime: TimeInterval = -.infinity
    @ObservationIgnored private var lastDragTime: TimeInterval = -.infinity

    var canOpenSector: Bool {
        isActive && dragState == nil && CACurrentMediaTime() - lastDragTime > 0.12
    }

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
        let drawTarget: CGFloat?
        let drawTargetSlot: Int?
    }

    private var onDrawSettled: ((Int) -> Void)?

    func configure(count: Int, slot: Int) {
        let nextCount = min(max(count, 0), BookshelfRingGeometry.maximumCount)
        guard nextCount != self.count else { return }
        stop()
        dragState = nil
        self.count = nextCount
        selectedSlot = min(max(slot, 0), max(0, self.count - 1))
        rotation = -CGFloat(selectedSlot) * BookshelfRingGeometry.step(count: self.count)
    }

    func draw(slot: Int, reduceMotion: Bool, callback: @escaping (Int) -> Void) {
        guard isActive, count > 0, (0..<count).contains(slot), dragState == nil else { return }
        stop()
        let target = BookshelfDrawMotion.target(slot: slot, count: count, from: rotation)
        onDrawSettled = callback
        isSpinning = true
        if reduceMotion {
            completeDraw(slot: slot)
            return
        }
        settling = Settlement(start: rotation, target: target, startedAt: CACurrentMediaTime(),
                              drawTarget: target, drawTargetSlot: slot)
        ticker.start { [weak self, weak ticker = ticker] time in
            guard let self else { ticker?.stop(); return }
            self.tick(time)
        }
    }

    private func completeDraw(slot: Int) {
        selectedSlot = slot
        rotation = -CGFloat(slot) * BookshelfRingGeometry.step(count: count)
        let completion = onDrawSettled
        onDrawSettled = nil
        settling = nil
        isSpinning = false
        completion?(slot)
    }

    func drag(_ value: DragGesture.Value, center: CGPoint, reduceMotion: Bool) {
        guard isActive, count > 0 else { return }
        lastDragTime = CACurrentMediaTime()
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
        isSpinning = true
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
        rotation = reduceMotion ? BookshelfRingGeometry.target(slot: selectedSlot, near: rawAngle, count: count) : rawAngle
    }

    func endDrag(_ value: DragGesture.Value, center: CGPoint, reduceMotion: Bool) {
        guard dragState != nil else { return }
        updateDrag(value, center: center, reduceMotion: reduceMotion)
        guard let drag = dragState else { return }
        dragState = nil
        let limit = min(90, BookshelfRingGeometry.step(count: count) * 1.5)
        let extra = reduceMotion ? 0 : min(max(drag.velocity * 0.12, -limit), limit)
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
        rotation = -CGFloat(selectedSlot) * BookshelfRingGeometry.step(count: count)
    }

    func select(_ slot: Int, reduceMotion: Bool) {
        guard isActive, (0..<count).contains(slot), dragState == nil else { return }
        stop()
        selectionFeedback.prepare()
        if slot == selectedSlot { feedback(selectionFeedback) }
        settle(projected: BookshelfRingGeometry.target(slot: slot, near: rotation, count: count), reduceMotion: reduceMotion)
    }

    func confirmReading() {
        cancelAndSnap()
        guard isActive else { return }
        openFeedback.prepare()
        feedback(openFeedback)
    }

    private func settle(projected: CGFloat, reduceMotion: Bool) {
        let slot = BookshelfRingGeometry.nearestSlot(to: projected, count: count)
        let target = BookshelfRingGeometry.target(slot: slot, near: projected, count: count)
        guard !reduceMotion, isActive, abs(target - rotation) > 0.01 else {
            updateSelection(for: target)
            rotation = -CGFloat(selectedSlot) * BookshelfRingGeometry.step(count: count)
            isSpinning = false
            return
        }
        isSpinning = true
        settling = Settlement(start: rotation, target: target, startedAt: CACurrentMediaTime(),
                              drawTarget: nil, drawTargetSlot: nil)
        ticker.start { [weak self, weak ticker = ticker] time in
            guard let self else { ticker?.stop(); return }
            self.tick(time)
        }
    }

    private func tick(_ time: TimeInterval) {
        guard isActive, let settling else { stop(); return }
        let elapsed = time - settling.startedAt
        if elapsed >= (settling.drawTarget == nil ? 0.56 : 2.2) {
            if let drawSlot = settling.drawTargetSlot {
                completeDraw(slot: drawSlot)
            } else {
                updateSelection(for: settling.target)
                rotation = -CGFloat(selectedSlot) * BookshelfRingGeometry.step(count: count)
                stop()
            }
            return
        }
        // Closed-form damped spring: frame-rate independent, bounded overshoot,
        // and no delayed completion that can outlive a gesture or book changes.
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
        feedback(selectionFeedback)
    }

    private func feedback(_ generator: UIImpactFeedbackGenerator) {
        let now = CACurrentMediaTime()
        guard isActive, now - lastFeedbackTime >= 0.09 else { return }
        lastFeedbackTime = now
        generator.impactOccurred(intensity: 1)
        // A short system click, synchronized with the detent. The silent switch
        // and system sound volume still apply; do not change AVAudioSession or
        // interrupt audiobook/TTS playback just to force a UI sound to be heard.
        AudioServicesPlaySystemSound(1104)
        generator.prepare()
    }

    private func stop() {
        ticker.stop()
        settling = nil
        isSpinning = false
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
