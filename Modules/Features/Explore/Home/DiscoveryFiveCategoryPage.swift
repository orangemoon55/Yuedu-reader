import SwiftUI

struct DiscoveryFiveCategoryPage: View {
    @ObservedObject var model: DiscoveryCategoryModel
    let configuration: String
    let page: HomePage?
    let sources: [BookSource]
    let editRequest: UUID
    @State private var settings: SlotSettingsRequest?

    private struct SlotSettingsRequest: Identifiable { let id = UUID(); let index: Int? }
    private var prepareKey: [AnyHashable] {
        [configuration, page, sources.map { "\($0.id)@\($0.lastUpdateTime)" }]
    }

    var body: some View {
        VStack(spacing: 0) {
            DiscoveryCategoryBar(slots: model.slots, selection: model.selection, select: { index in
                if model.slots.choices[index] == nil { settings = .init(index: index) }
                else { model.select(index) }
            }, edit: { settings = .init(index: $0) })

            HStack(spacing: DSSpacing.sm) {
                if let choice = model.current {
                    Text(sources.first { $0.bookSourceUrl == choice.reference.sourceURL }?.bookSourceName ?? choice.reference.sourceURL)
                        .lineLimit(1)
                } else { Text(localized("選擇來源配置與分類")) }
                Spacer(minLength: DSSpacing.xs)
                Button { settings = .init(index: model.selection) } label: {
                    Label(localized("切換"), systemImage: "arrow.triangle.2.circlepath")
                }
                .accessibilityIdentifier("discovery.category.change")
                Button { settings = .init(index: nil) } label: {
                    Image(systemName: "slider.horizontal.3")
                        .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel(localized("設定五個分類"))
                .accessibilityIdentifier("discovery.category.settings")
            }
            .font(DSFont.caption)
            .foregroundStyle(DSColor.textSecondary)
            .padding(.leading, DSSpacing.lg)
            .padding(.trailing, DSSpacing.xs)
            .buttonStyle(.plain)

            content
        }
        .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
        .rootTabTitle(localized("底部發現"), onScroll: .minimizesBar)
        .pageBackgroundToolbar(for: .explore)
        .task(id: prepareKey) {
            await model.prepare(configuration: configuration, page: page, sources: sources)
        }
        .onChange(of: editRequest) { _, _ in settings = .init(index: nil) }
        .sheet(item: $settings) { request in
            DiscoverySlotSettings(slots: model.slots, openSlot: request.index, choose: { choice, index in
                model.choose(choice, at: index)
                settings = nil
            }, close: { settings = nil })
        }
    }

    @ViewBuilder private var content: some View {
        if let choice = model.current {
            if let source = sources.first(where: { $0.bookSourceUrl == choice.reference.sourceURL }) {
                DiscoveryBookList(model: model.list(for: choice, source: source))
                    .id(choice.id)
            } else {
                ContentUnavailableView {
                    UnavailableLabel(localized("來源配置已停用或移除"), systemImage: "books.vertical")
                } actions: {
                    Button(localized("更換分類")) { settings = .init(index: model.selection) }
                }
            }
        } else if model.isLoadingCatalog {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                UnavailableLabel(localized("尚未設定分類"), systemImage: "square.grid.2x2")
            } description: {
                Text(model.catalogError ?? localized("選擇已啟用書源的真實欄目，設定上方五個分類。"))
            } actions: {
                Button(localized("設定五個分類")) { settings = .init(index: nil) }
            }
        }
    }
}

struct DiscoveryBookList: View {
    @ObservedObject var model: DiscoveryBookListModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var coverWidth: CGFloat = 72

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                Color.clear.frame(height: 0).rootTabTitleScrollAnchor()
                if let section = model.section {
                    ForEach(Array(model.books.enumerated()), id: \.element.id) { index, display in
                        NavigationLink(value: ExploreNavigationRoute.book(display.book)) {
                            row(display, section: section)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discovery.book.\(index)")
                    }
                }
                if model.isLoading {
                    ProgressView().frame(maxWidth: .infinity).padding()
                } else if let reason = model.error {
                    VStack(spacing: DSSpacing.sm) {
                        Text(reason).font(DSFont.caption).foregroundStyle(DSColor.textSecondary).lineLimit(3)
                        Button(localized("載入失敗，點按重試")) { Task { await model.retry() } }
                    }
                    .padding()
                } else if model.hasMore, model.loaded {
                    Button(localized("載入更多")) { Task { await model.loadMore() } }
                        .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget)
                        .onAppear { Task { await model.loadMore() } }
                }
            }
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.lg)
        }
        .overlay {
            if model.loaded && model.books.isEmpty && !model.isLoading && model.error == nil {
                ContentUnavailableView { UnavailableLabel(localized("暫無發現內容"), systemImage: "books.vertical") }
            }
        }
        .softScrollEdges()
        .refreshable { await model.loadFirst(force: true) }
        .task { await model.loadFirst() }
        .accessibilityIdentifier("discovery.bookList")
    }

    private func row(_ display: DiscoverBookDisplay, section: DiscoverShowcaseSection) -> some View {
        HStack(alignment: .top, spacing: DSSpacing.md) {
            DiscoverCover(display: display, section: section,
                          size: CGSize(width: coverWidth, height: coverWidth / DSLayout.discoverCoverAspectRatio))
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text(display.book.name)
                    .font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
                    .lineLimit(typeSize.isAccessibilitySize ? 3 : 2)
                Text([display.book.author, display.book.kind].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
                    .lineLimit(typeSize.isAccessibilitySize ? 4 : 2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, DSSpacing.xs)
        }
        .padding(.vertical, DSSpacing.md)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
