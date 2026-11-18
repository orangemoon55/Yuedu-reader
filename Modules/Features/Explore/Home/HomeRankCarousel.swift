import SwiftUI

extension EnvironmentValues {
    @Entry var homeRankPreview = false
}

struct HomeRankCarousel: View {
    let cards: [HomeCardContent]
    let open: (HomeCardContent, [HomeCardContent]) -> Void
    var previewRelated: [HomeCardContent] = []
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityVoiceOverEnabled) private var voiceOver
    @Environment(\.homeRankPreview) private var preview
    @Environment(\.homeDrawsSideways) private var editing
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var rotation = HomeRankRotation()
    @State private var visible = false
    @StateObject private var related = HomeRankRelatedModel()
    @ScaledMetric(relativeTo: .subheadline) private var coverWidth = DSLayout.homeCompactReadingCardCoverWidth
    @ScaledMetric(relativeTo: .subheadline) private var compactWidth = DSLayout.homeContinueCardWidth

    private struct TimerKey: Hashable { let id: SourceItemKey?; let started: Date; let active: Bool }
    private struct RelatedKey: Hashable { let id: SourceItemKey?; let pool: [SourceItemKey]; let active: Bool }
    private var current: HomeCardContent? { cards.first { $0.id == rotation.current } ?? cards.first }
    private var live: Bool { visible && phase == .active && !preview && !editing }
    private var timerActive: Bool { live && !voiceOver && cards.count > 1 }
    private var position: Int {
        guard let current else { return 0 }
        return (cards.firstIndex { $0.id == current.id } ?? 0) + 1
    }
    private var countLabel: String { "\(position) / \(cards.count)" }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            if let current {
                HomeRankHero(content: current, isActive: live) { open($0, cards) }
                    .padding(.horizontal, DSSpacing.lg)
                    .id(current.id)
                    .transition(.opacity)
                if cards.count > 1 { controls }
                if preview && !previewRelated.isEmpty {
                    Text(localized("關聯作品"))
                        .font(DSFont.subheadline.weight(.semibold)).foregroundStyle(DSColor.textSecondary)
                        .padding(.horizontal, DSSpacing.lg)
                    compactCards(previewRelated)
                } else if !preview && !editing { relatedContent(current) }
            }
        }
        .onAppear {
            let now = Date()
            rotation.set(cards.map(\.id), now: now)
            rotation.restart(at: now)
            visible = true
        }
        .onDisappear { visible = false }
        .onChange(of: cards.map(\.id)) { _, ids in rotation.set(ids, now: Date()) }
        .onChange(of: phase) { _, value in if value == .active { rotation.restart(at: Date()) } }
        .onChange(of: voiceOver) { _, value in if !value { rotation.restart(at: Date()) } }
        .task(id: TimerKey(id: rotation.current, started: rotation.started, active: timerActive)) {
            guard timerActive else { return }
            // Product interval, not agent polling: this task is cancelled on disappear/background.
            do { try await Task.sleep(for: .seconds(HomeRankRotation.interval)) } catch { return }
            guard !Task.isCancelled, timerActive else { return }
            withAnimation(reduceMotion ? nil : DSAnimation.standard) { _ = rotation.next(now: Date()) }
        }
        .task(id: RelatedKey(id: current?.id, pool: cards.map(\.id), active: live)) {
            guard live, let current else { return }
            await related.load(for: current, pool: cards)
        }
    }

    private var controls: some View {
        HStack(spacing: DSSpacing.sm) {
            Button { move(-1) } label: {
                Image(systemName: "chevron.left").accessibilityHidden(true)
                    .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
            }
            .accessibilityLabel(localized("上一本"))
            .accessibilityIdentifier("home.rank.previous")
            Text(countLabel).font(DSFont.caption.monospacedDigit()).foregroundStyle(DSColor.textSecondary)
            Button { move(1) } label: {
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
            }
            .accessibilityLabel(localized("下一本"))
            .accessibilityIdentifier("home.rank.next")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .homeRowControl()
    }

    private func move(_ offset: Int) {
        withAnimation(reduceMotion ? nil : DSAnimation.standard) { rotation.move(by: offset, at: Date()) }
    }

    private func compactCards(_ values: [HomeCardContent]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: DSSpacing.md) {
                ForEach(values) { card in
                    Button { open(card, values) } label: {
                        HomeCompactReadingCard(content: card, coverWidth: coverWidth,
                                               stacksVertically: typeSize.isAccessibilitySize)
                    }
                    .buttonStyle(ExploreTileButtonStyle())
                    .homeRowControl()
                    .homeSidewaysCardWidth { min(compactWidth, $0) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(card.accessibilityLabel)
                    .accessibilityValue(card.accessibilityValue)
                    .accessibilityIdentifier("home.rank.related.\(card.id.item)")
                }
            }
        }
        .modifier(HomeSidewaysScroll())
        .id(current?.id)
    }

    @ViewBuilder private func relatedContent(_ current: HomeCardContent) -> some View {
        let matched = related.bookID == current.id
        if matched, !related.cards.isEmpty {
            Text(localized(related.kind == .author ? "同作者其他作品" : "同題材推薦"))
                .font(DSFont.subheadline.weight(.semibold)).foregroundStyle(DSColor.textSecondary)
                .padding(.horizontal, DSSpacing.lg)
            compactCards(related.cards)
        } else if case .onlineBook = current.opening {
            HStack(spacing: DSSpacing.sm) {
                if !matched || related.loading { ProgressView() }
                Text(localized(!matched || related.loading ? "載入關聯作品…" : "暫無同作者或同題材作品"))
                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                if matched && related.error != nil {
                    Button(localized("重試")) { Task { await related.load(for: current, pool: cards, force: true) } }
                        .font(DSFont.footnote)
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .frame(minHeight: coverWidth / DSLayout.discoverCoverAspectRatio + DSLayout.homeContinueCardInset * 2)
        }
    }
}
