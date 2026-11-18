import SwiftUI
import Combine

extension EnvironmentValues {
    @Entry var homeRankPreview = false
}

@MainActor
final class HomeRankRelatedModel: ObservableObject {
    @Published private(set) var cards: [HomeCardContent] = []
    @Published private(set) var title: String?
    private var task: Task<Void, Never>?
    private var loadedID: SourceItemKey?

    func load(for card: HomeCardContent, pool: [HomeCardContent]) {
        guard loadedID != card.id else { return }
        loadedID = card.id
        task?.cancel()
        cards = []
        title = nil
        guard case .onlineBook(let frozen) = card.opening,
              let source = BookSourceStore.shared.source(id: frozen.book.sourceId) else { return }
        let books = pool.compactMap { candidate -> OnlineBook? in
            guard case .onlineBook(let value) = candidate.opening else { return nil }
            return value.book
        }
        task = Task { [weak self] in
            do {
                let result = try await HomeRankingRecommendationService().recommendations(
                    for: frozen.book, source: source, pool: books)
                guard !Task.isCancelled else { return }
                let cards = result.books.compactMap { book in
                    HomeCardContent(CollectionEntry.onlineBook(book, source: source),
                                    status: { _ in nil }, shelfBooks: [:])
                }
                await MainActor.run {
                    guard self?.loadedID == card.id else { return }
                    self?.cards = cards
                    self?.title = switch result.kind {
                    case .author: localized("同作者其他作品")
                    case .genre: localized("同题材推荐")
                    case .none: nil
                    }
                }
            } catch is CancellationError {
            } catch {
                AppLogger.network("home ranking related cards failed", error: SourceFailure.loggable(error),
                                  context: ["book": frozen.book.name])
            }
        }
    }

    deinit { task?.cancel() }
}

struct HomeRankCarousel: View {
    let cards: [HomeCardContent]
    let open: (HomeCardContent, [HomeCardContent]) -> Void
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @State private var rotation = HomeRankRotation()
    @StateObject private var related = HomeRankRelatedModel()

    private var current: HomeCardContent? { cards.first { $0.id == rotation.current } ?? cards.first }

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            if let current {
                Button { open(current, cards) } label: { HomeCoverIntroCard(content: current) }
                    .buttonStyle(ExploreTileButtonStyle()).homeRowControl()
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(current.accessibilityLabel)
                    .accessibilityValue(current.featuredAccessibilityValue)
                    .accessibilityIdentifier("home.rank.current")
                    .padding(.horizontal, DSSpacing.lg)
            }
            if cards.count > 1 {
                HStack(spacing: DSSpacing.sm) {
                    Button { move(-1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                    Text("\((cards.firstIndex { $0.id == current?.id } ?? 0) + 1) / \(cards.count)")
                        .font(DSFont.caption.monospacedDigit()).foregroundStyle(DSColor.textSecondary)
                    Button { move(1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                }.buttonStyle(.plain)
            }
            if !homeRankPreview, let label = related.title, !related.cards.isEmpty {
                Text(label).font(DSFont.subheadline.weight(.semibold)).foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, DSSpacing.lg)
                ScrollView(.horizontal) {
                    LazyHStack(spacing: DSSpacing.md) {
                        ForEach(related.cards) { card in
                            Button { open(card, related.cards) } label: {
                                HomeCompactReadingCard(content: card, coverWidth: DSLayout.homeCompactReadingCardCoverWidth)
                            }.buttonStyle(ExploreTileButtonStyle()).homeRowControl()
                        }
                    }
                }.modifier(HomeSidewaysScroll()).id(current?.id)
            }
        }
        .onAppear { rotation.set(cards.map(\.id), now: Date()); if let current { related.load(for: current, pool: cards) } }
        .onChange(of: cards.map(\.id)) { _, ids in rotation.set(ids, now: Date()) }
        .onChange(of: rotation.current) { _, id in
            if let current = cards.first(where: { $0.id == id }) { related.load(for: current, pool: cards) }
        }
        .onChange(of: phase) { _, value in if value == .active { rotation.restart(at: Date()) } }
        .task(id: rotation.current) {
            guard phase == .active, !voiceOver, cards.count > 1 else { return }
            do { try await Task.sleep(for: .seconds(HomeRankRotation.interval)) } catch { return }
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : DSAnimation.standard) { _ = rotation.next(now: Date()) }
        }
    }

    private func move(_ offset: Int) {
        guard !cards.isEmpty else { return }
        let i = cards.firstIndex { $0.id == rotation.current } ?? 0
        rotation.current = cards[(i + offset + cards.count) % cards.count].id
        rotation.started = Date()
    }
}
