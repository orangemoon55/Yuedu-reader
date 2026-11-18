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
    @State private var manualRevision = 0
    @StateObject private var related = HomeRankRelatedModel()
    @ScaledMetric(relativeTo: .subheadline) private var shelfCoverWidth = DSLayout.homeCompactCoverWidth

    private struct TimerKey: Hashable { let ids: [SourceItemKey]; let revision: Int; let active: Bool }
    private struct RelatedKey: Hashable { let id: SourceItemKey?; let pool: [SourceItemKey]; let active: Bool }
    private var current: HomeCardContent? { cards.first { $0.id == rotation.current } ?? cards.first }
    private var live: Bool { visible && phase == .active && !preview && !editing }
    private var timerActive: Bool { visible && phase == .active && !editing && !voiceOver && rotation.ids.count > 1 }
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
                    shelfCards(previewRelated)
                } else if !preview && !editing { relatedContent(current) }
            }
        }
        .onAppear {
            let now = Date()
            rotation.set(cards.map(\.id), now: now)
            rotation.restart(at: now)
            visible = true
            manualRevision += 1
        }
        .onDisappear { visible = false }
        .onChange(of: cards.map(\.id)) { _, ids in rotation.set(ids, now: Date()) }
        .onChange(of: phase) { _, value in if value == .active { rotation.restart(at: Date()) } }
        .onChange(of: voiceOver) { _, value in if !value { rotation.restart(at: Date()) } }
        .task(id: TimerKey(ids: cards.map(\.id), revision: manualRevision, active: timerActive)) {
            guard timerActive else { return }
            // One cancellable loop per visible carousel. Changing the selected card does
            // not cancel/restart its own timer task; manual interaction starts a new interval.
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(HomeRankRotation.interval)) } catch { return }
                guard !Task.isCancelled, timerActive else { return }
                step(by: 1, automatic: true)
            }
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
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(localized("上一本"))
            .accessibilityIdentifier("home.rank.previous")
            Text(countLabel).font(DSFont.caption.monospacedDigit()).foregroundStyle(DSColor.textSecondary)
                .accessibilityIdentifier("home.rank.position")
            Button { move(1) } label: {
                Image(systemName: "chevron.right").accessibilityHidden(true)
                    .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(localized("下一本"))
            .accessibilityIdentifier("home.rank.next")
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .homeRowControl()
    }

    private func move(_ offset: Int) {
        step(by: offset, automatic: false)
    }

    private func step(by offset: Int, automatic: Bool) {
        let now = Date()
        // A control can be tapped before onAppear or while a refreshed pool is applied.
        // Synchronize from the actual cards at the action, not an older task's captured list.
        rotation.set(cards.map(\.id), now: now)
        let before = rotation.current
        withAnimation(reduceMotion ? nil : DSAnimation.standard) { rotation.move(by: offset, at: now) }
        if !automatic { manualRevision += 1 }
        AppLogger.cache("home.rank.move", context: ["automatic": String(automatic),
                        "candidates": String(rotation.ids.count), "changed": String(before != rotation.current)])
    }

    private func shelfCards(_ values: [HomeCardContent]) -> some View {
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: DSSpacing.md) {
                ForEach(values) { card in
                    Button { open(card, values) } label: {
                        HomeBookCard(content: card, coverWidth: min(shelfCoverWidth, DSLayout.homeCardCoverMaxWidth),
                                     reservesTextSpace: true)
                    }
                    .buttonStyle(ExploreTileButtonStyle())
                    .homeRowControl()
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
            shelfCards(related.cards)
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
            .frame(minHeight: shelfCoverWidth / DSLayout.discoverCoverAspectRatio + DSLayout.minimumTapTarget)
        }
    }
}
