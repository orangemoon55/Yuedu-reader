import SwiftUI
import UIKit
import Observation
import AudioToolbox

/// The stage never scrolls; only the wheel rotates within its fixed square.
struct BookshelfRingView: View {
    let books: [ReadingBook]
    let allBooksForDraw: [ReadingBook]
    let colorScheme: ColorScheme
    let isFattened: (UUID) -> Bool
    let chapterContext: @MainActor (ReadingBook) async -> BookshelfRingChapterContext
    let onOpen: (ReadingBook, BookshelfTappedCover) -> Void
    let onCoverFrameChange: (ReadingBook, CGRect) -> Void
    let onContextAction: (ReadingBook, BookshelfBookContextAction) -> Void
    let onShowMore: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .headline) private var promptLineHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .subheadline) private var chapterLineHeight: CGFloat = 22
    @ScaledMetric(relativeTo: .subheadline) private var cardHeight: CGFloat = 156
    @State private var motion = BookshelfRingMotion()
    @State private var draw = BookshelfRingDrawState()
    @State private var isVisible = false
    @State private var coverSources = BookshelfRingCoverSources()
    @State private var loadedChapterContext: (book: ReadingBook, context: BookshelfRingChapterContext)?

    private struct ChapterRequest: Equatable {
        let book: ReadingBook?
        let isActive: Bool
    }
    private var pool: [ReadingBook] { allBooksForDraw.isEmpty ? books : allBooksForDraw }
    private var shownBooks: [ReadingBook] {
        draw.displayedBooks.isEmpty ? Array(BookshelfDrawRecommendation.eligible(in: books).prefix(9)) : draw.displayedBooks
    }
    private var selectedBook: ReadingBook? { draw.selectedBook ?? shownBooks.first }

    var body: some View {
        GeometryReader { proxy in
            let layout = BookshelfRingStageLayout(
                size: proxy.size, headerHeight: promptLineHeight + chapterLineHeight + 6 + cardHeight + 12
            )
            VStack(spacing: 12) {
                if let book = selectedBook {
                    let context = context(for: book)
                    BookshelfRingReadingPrompt(
                        book: book, context: context, recommendation: draw.recommendation,
                        onOpen: { open(book) }
                    )
                    .disabled(draw.isDrawing)
                    BookshelfRingSelectedCard(book: book, context: context, colorScheme: colorScheme,
                                              onOpen: { open(book) })
                        .contextMenu { if !draw.isDrawing { bookMenu(book) } }
                        .disabled(draw.isDrawing)
                }
                ZStack(alignment: .topTrailing) {
                    BookshelfRingRotor(
                        books: shownBooks, colorScheme: colorScheme, motion: motion,
                        reduceMotion: reduceMotion, isFattened: isFattened,
                        coverSources: coverSources, onCoverFrameChange: onCoverFrameChange,
                        onOpen: open, onContextAction: performContextAction, onDraw: startDrawing
                    )
                    .frame(width: layout.diameter, height: layout.diameter)
                    if pool.filter(\.isInBookshelf).count > 9 {
                        Button {
                            guard !draw.isDrawing else { return }
                            motion.cancelAndSnap()
                            onShowMore()
                        } label: {
                            Text(localized("更多書籍"))
                                .font(.caption.weight(.semibold))
                                .lineLimit(1).minimumScaleFactor(0.7)
                                .frame(width: layout.moreSize.width, height: layout.moreSize.height)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(DSColor.accent)
                        .disabled(draw.isDrawing)
                        .accessibilityIdentifier("bookshelf.ring.more")
                        .offset(x: 12, y: -12)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .accessibilityIdentifier("bookshelf.ring")
        .task(id: ChapterRequest(book: selectedBook, isActive: scenePhase == .active)) {
            guard scenePhase == .active, let book = selectedBook else { return }
            let result = await chapterContext(book)
            guard !Task.isCancelled else { return }
            loadedChapterContext = (book, result)
        }
        .task(id: draw.run?.id) {
            guard let run = draw.run else { return }
            let query = BookshelfDrawCategoryQuery(book: run.winner)
            let work = Task.detached(priority: .utility) { query.load() }
            let category = await withTaskCancellationHandler {
                await work.value
            } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            draw.setCategory(category, runID: run.id)
        }
        .onAppear {
            isVisible = true
            draw.synchronize(base: books, all: pool)
            motion.configure(count: shownBooks.count, slot: selectedSlot)
            coverSources.retain(books: shownBooks)
            motion.isActive = scenePhase == .active
        }
        .onDisappear {
            isVisible = false
            motion.isActive = false
        }
        .onChange(of: scenePhase) { _, phase in
            motion.isActive = isVisible && phase == .active
            if motion.isActive, !draw.isDrawing {
                motion.configure(count: shownBooks.count, slot: selectedSlot)
            }
        }
        .onChange(of: reduceMotion) { _, _ in
            if draw.isDrawing { motion.finishDrawing() } else { motion.cancelAndSnap() }
        }
        .onChange(of: books.map(\.id)) { _, _ in synchronizeShelf() }
        .onChange(of: pool.map(\.id)) { _, _ in synchronizeShelf() }
        .onChange(of: pool) { _, updated in draw.refreshInformation(from: updated) }
        .onChange(of: motion.selectedSlot) { _, slot in draw.select(slot: slot) }
    }

    private var selectedSlot: Int { shownBooks.firstIndex { $0.id == draw.selectedID } ?? 0 }
    private func context(for book: ReadingBook) -> BookshelfRingChapterContext {
        if let loadedChapterContext, loadedChapterContext.book == book { return loadedChapterContext.context }
        return BookshelfRingChapterContext(book: book, chapters: [], textPosition: nil)
    }
    private func synchronizeShelf() {
        if draw.isDrawing, let run = draw.run, !pool.contains(where: { $0.id == run.winner.id && $0.isInBookshelf }) {
            motion.cancelAndSnap()
        }
        draw.synchronize(base: books, all: pool)
        coverSources.retain(books: shownBooks)
        if !draw.isDrawing { motion.configure(count: shownBooks.count, slot: selectedSlot) }
    }

    private func startDrawing() {
        guard motion.isActive, !draw.isDrawing else { return }
        var random = SystemRandomNumberGenerator()
        guard let run = draw.begin(base: books, all: pool, using: &random) else { return }
        coverSources.retain(books: draw.displayedBooks)
        motion.configure(count: draw.displayedBooks.count, slot: run.previousSlot)
        let started = motion.draw(slot: run.slot, reduceMotion: reduceMotion,
                                  onCancel: { draw.cancel(base: books) }) { slot in
            _ = draw.finish(runID: run.id, slot: slot)
        }
        if !started { draw.cancel(base: books) }
    }
    private func open(_ book: ReadingBook) {
        guard !draw.isDrawing else { return }
        let tapped = coverSources.tappedCover(for: book.id)
        motion.confirmReading()
        onOpen(book, tapped)
    }
    private func performContextAction(_ book: ReadingBook, _ action: BookshelfBookContextAction) {
        guard !draw.isDrawing else { return }
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

struct BookshelfRingStageLayout {
    let diameter: CGFloat
    let moreSize: CGSize

    init(size: CGSize, headerHeight: CGFloat) {
        guard size.width.isFinite, size.height.isFinite, headerHeight.isFinite else {
            diameter = 0; moreSize = .zero; return
        }
        let width = max(0, size.width - 24)
        let height = max(0, size.height - headerHeight - 28)
        diameter = min(440, width, height)
        // The wheel is a circle inside this square. Its top-right corner is free
        // without shrinking the wheel or creating a full-height side column.
        moreSize = CGSize(width: min(64, diameter * 0.21), height: min(44, diameter * 0.145))
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

    var body: some View {
        GeometryReader { proxy in
            let diameter = min(proxy.size.width, proxy.size.height)
            let center = CGPoint(x: proxy.size.width / 2, y: proxy.size.height / 2)
            let step = BookshelfRingGeometry.step(count: books.count)
            let tileSize = BookshelfRingPresentation.mirrorCoverSize(diameter: diameter, count: books.count)
            let orbitRadius = BookshelfRingPresentation.mirrorOrbitRadius(diameter: diameter, count: books.count)
            let angle = motion.rotation
            ZStack {
                BookshelfTangMirror(diameter: diameter, rotation: angle, count: books.count,
                                    selectedSlot: motion.selectedSlot, isSpinning: motion.isSpinning,
                                    isDrawing: motion.isDrawing)

                ForEach(Array(books.enumerated()), id: \.element.id) { slot, book in
                    let radians = (CGFloat(slot) * step + angle - 90) * .pi / 180
                    BookshelfRingCoverTile(
                        book: book, colorScheme: colorScheme, size: tileSize,
                        isSelected: slot == motion.selectedSlot,
                        isFattened: isFattened(book.id),
                        coverFrame: coverSources.box(for: book.id),
                        onCoverFrameChange: { onCoverFrameChange(book, $0) },
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
                    diameter: diameter * 0.166,
                    isDrawing: motion.isDrawing,
                    onDraw: books.isEmpty ? nil : onDraw
                )
                    .position(center)
                if !books.isEmpty {
                    Capsule().fill(BookshelfTangPalette.highlight.opacity(0.9))
                        .frame(width: 3, height: 9)
                        .position(x: center.x, y: diameter * 0.043)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .background {
                Circle().fill(Color.clear).contentShape(Circle())
                    .gesture(SpatialTapGesture().onEnded { value in
                        guard motion.canOpenSector,
                              hypot(value.location.x - center.x, value.location.y - center.y) > max(22, diameter * 0.083),
                              let slot = BookshelfRingGeometry.slot(
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
        .accessibilityElement(children: .contain)
        .accessibilityAdjustableAction { direction in
            guard !books.isEmpty, !motion.isDrawing else { return }
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
                guard !motion.isDrawing, radius >= max(22, diameter * 0.083),
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
    let onSelect: () -> Void
    let onContextAction: (BookshelfBookContextAction) -> Void

    var body: some View {
        let cornerRadius = BookshelfCoverStyle.cornerRadius
        Button(action: onSelect) {
            ShelfCoverSlot(book: book, colorScheme: colorScheme, displaySize: BookshelfRingPresentation.coverDecodeSize)
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                // Measure only the untransformed front artwork. The paper, board,
                // highlights and shadows must not enter the reader's lift frame.
                .reportBookshelfCoverFrame(into: coverFrame, onChange: onCoverFrameChange)
                .overlay {
                    BookshelfRingBookFinish(size: size)
                        .equatable()
                        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                }
                .overlay {
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .stroke(isSelected ? BookshelfTangPalette.highlight : BookshelfTangPalette.gold.opacity(0.45), lineWidth: isSelected ? 2 : 0.75)
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
    private(set) var isDrawing = false
    private(set) var angularVelocity: CGFloat = 0
    var isActive = false {
        didSet { if !isActive { cancelAndSnap() } }
    }

    @ObservationIgnored private var count = 0
    @ObservationIgnored private var dragState: DragState?
    @ObservationIgnored private var settling: Settlement?
    @ObservationIgnored private let ticker = BookshelfRingTicker()
    @ObservationIgnored private let selectionFeedback = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private let openFeedback = UIImpactFeedbackGenerator(style: .rigid)
    @ObservationIgnored private var lastFeedbackTime: TimeInterval = -.infinity
    @ObservationIgnored private var lastDragTime: TimeInterval = -.infinity
    @ObservationIgnored private var completion: (@MainActor (Int) -> Void)?
    @ObservationIgnored private var cancellation: (@MainActor () -> Void)?
    @ObservationIgnored private let usesDisplayLink: Bool
    @ObservationIgnored private let clock: @MainActor () -> TimeInterval

    init(usesDisplayLink: Bool = true, clock: @escaping @MainActor () -> TimeInterval = { CACurrentMediaTime() }) {
        self.usesDisplayLink = usesDisplayLink
        self.clock = clock
    }
    var canOpenSector: Bool {
        isActive && !isDrawing && !isSpinning && dragState == nil && clock() - lastDragTime > 0.12
    }
    private struct DragState {
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
        let drawSlot: Int?
    }
    func configure(count: Int, slot: Int) {
        cancelAndSnap()
        self.count = min(max(count, 0), BookshelfRingGeometry.maximumCount)
        selectedSlot = min(max(slot, 0), max(0, self.count - 1))
        rotation = -CGFloat(selectedSlot) * BookshelfRingGeometry.step(count: self.count)
    }
    @discardableResult
    func draw(slot: Int, reduceMotion: Bool, onCancel: @escaping @MainActor () -> Void = {},
              callback: @escaping @MainActor (Int) -> Void) -> Bool {
        guard isActive, !isDrawing, dragState == nil, (0..<count).contains(slot) else { return false }
        stopLink()
        completion = callback
        cancellation = onCancel
        isDrawing = true
        let target = BookshelfDrawMotion.target(slot: slot, count: count, from: rotation)
        settling = Settlement(start: rotation, target: target, startedAt: clock(), drawSlot: slot)
        if reduceMotion { finishDrawing(); return true }
        isSpinning = true
        selectionFeedback.prepare()
        startLink()
        return true
    }
    func finishDrawing() {
        guard isDrawing, let slot = settling?.drawSlot else { return }
        let callback = completion
        completion = nil
        cancellation = nil
        stopLink()
        isDrawing = false
        selectedSlot = slot
        rotation = -CGFloat(slot) * BookshelfRingGeometry.step(count: count)
        feedback(openFeedback)
        callback?(slot)
    }
    func cancelAndSnap() {
        let onCancel = isDrawing ? cancellation : nil
        completion = nil
        cancellation = nil
        stopLink()
        dragState = nil
        isDrawing = false
        rotation = -CGFloat(selectedSlot) * BookshelfRingGeometry.step(count: count)
        onCancel?()
    }
    func drag(_ value: DragGesture.Value, center: CGPoint, reduceMotion: Bool) {
        guard isActive, !isDrawing, count > 0 else { return }
        lastDragTime = clock()
        if dragState == nil {
            stopLink()
            selectionFeedback.prepare()
            dragState = DragState(baseRotation: rotation,
                lastAngle: BookshelfRingGeometry.angle(value.startLocation, around: center),
                lastTime: value.time.timeIntervalSinceReferenceDate - 1 / 60)
        }
        isSpinning = true
        updateDrag(value, center: center, reduceMotion: reduceMotion)
    }
    private func updateDrag(_ value: DragGesture.Value, center: CGPoint, reduceMotion: Bool) {
        guard var drag = dragState else { return }
        let now = value.time.timeIntervalSinceReferenceDate
        let angle = BookshelfRingGeometry.angle(value.location, around: center)
        guard hypot(value.location.x - center.x, value.location.y - center.y) > 18 else {
            drag.lastAngle = nil; drag.lastTime = now; drag.velocity = 0
            dragState = drag; angularVelocity = 0; return
        }
        let delta = drag.lastAngle.map { BookshelfRingGeometry.shortest(angle - $0) } ?? 0
        let elapsed = now - drag.lastTime
        if elapsed > 0 {
            let sample = min(max(delta / CGFloat(max(elapsed, 1 / 240)), -720), 720)
            drag.velocity = elapsed > 0.12 ? sample : drag.velocity * 0.35 + sample * 0.65
        }
        drag.accumulated += delta
        drag.lastAngle = angle; drag.lastTime = now; dragState = drag
        angularVelocity = reduceMotion ? 0 : drag.velocity
        let raw = drag.baseRotation + drag.accumulated
        updateSelection(for: raw)
        rotation = reduceMotion ? BookshelfRingGeometry.target(slot: selectedSlot, near: raw, count: count) : raw
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
    func cancelDrag() { if dragState != nil { cancelAndSnap() } }
    func select(_ slot: Int, reduceMotion: Bool) {
        guard isActive, !isDrawing, (0..<count).contains(slot), dragState == nil else { return }
        stopLink()
        selectionFeedback.prepare()
        if slot == selectedSlot { feedback(selectionFeedback) }
        settle(projected: BookshelfRingGeometry.target(slot: slot, near: rotation, count: count), reduceMotion: reduceMotion)
    }
    func confirmReading() {
        guard !isDrawing else { return }
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
            stopLink(); return
        }
        isSpinning = true
        settling = Settlement(start: rotation, target: target, startedAt: clock(), drawSlot: nil)
        startLink()
    }
    /// Deterministic timestamp entry point also used by the integration regression.
    func advance(to time: TimeInterval) {
        guard isActive, time.isFinite, let state = settling else { return }
        let elapsed = max(0, time - state.startedAt)
        if state.drawSlot != nil {
            let progress = Double(elapsed / 2.8)
            let previous = rotation
            rotation = BookshelfDrawMotion.angle(from: state.start, to: state.target, progress: progress)
            // Derivative of the same ease-out curve. It supplies the actual
            // direction to the flame trail, not the sign of a normalized angle.
            angularVelocity = (state.target - state.start) * 4 * pow(max(0, 1 - CGFloat(progress)), 3) / 2.8
            if previous != rotation { updateSelection(for: rotation) }
            if progress >= 1 { finishDrawing() }
            return
        }
        if elapsed >= 0.56 {
            updateSelection(for: state.target)
            rotation = -CGFloat(selectedSlot) * BookshelfRingGeometry.step(count: count)
            stopLink(); return
        }
        let t = CGFloat(elapsed)
        let fraction = 1 - exp(-14 * t) * (cos(18 * t) + (14.0 / 18.0) * sin(18 * t))
        let previous = rotation
        rotation = state.start + (state.target - state.start) * fraction
        angularVelocity = (rotation - previous) * 60
        updateSelection(for: rotation)
    }
    private func updateSelection(for angle: CGFloat) {
        let next = BookshelfRingGeometry.nearestSlot(to: angle, count: count)
        guard next != selectedSlot else { return }
        selectedSlot = next
        feedback(selectionFeedback)
    }
    private func feedback(_ generator: UIImpactFeedbackGenerator) {
        let now = clock()
        guard isActive, now - lastFeedbackTime >= 0.09 else { return }
        lastFeedbackTime = now
        generator.impactOccurred(intensity: 1)
        AudioServicesPlaySystemSound(1104)
        generator.prepare()
    }
    private func startLink() {
        guard usesDisplayLink else { return }
        ticker.start { [weak self, weak ticker = ticker] time in
            guard let self else { ticker?.stop(); return }
            self.advance(to: time)
        }
    }
    private func stopLink() {
        ticker.stop()
        settling = nil
        isSpinning = false
        angularVelocity = 0
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
