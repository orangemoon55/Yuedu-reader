import SwiftUI

struct DiscoveryFiveCategoryPage: View {
    @ObservedObject var model: DiscoveryCategoryModel
    let configuration: String
    let page: HomePage?
    let sources: [BookSource]
    let editRequest: UUID
    var onAllTypes: (() -> Void)? = nil
    @State private var settings: SlotSettingsRequest?
    @Environment(\.searchTabNavigation) private var searchTabNavigation

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

            if let choice = model.current,
               let source = sources.first(where: { $0.bookSourceUrl == choice.reference.sourceURL }) {
                DiscoverySourceControls(source: source, filterValues: choice.filters, onSearch: {
                    searchTabNavigation?.path.append(ExploreNavigationRoute.searchInSource(sourceURL: source.bookSourceUrl))
                }, onSwitchSource: {
                    settings = .init(index: model.selection)
                }, onAllTypes: onAllTypes, onReload: { values, items, error, refreshBooks in
                    model.reconcileSource(sourceURL: source.bookSourceUrl, values: values, items: items, error: error,
                                          refreshBooks: refreshBooks)
                })
                .id("\(configuration)|\(source.bookSourceUrl)|\(source.lastUpdateTime)")
            }

            content
        }
        .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
        // SearchCategoryHome owns the single navigation title above the field and chips.
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
            if model.invalidReferences.contains(choice.reference) {
                ContentUnavailableView {
                    UnavailableLabel(localized("所選分類已失效"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.sourceErrors[choice.reference.sourceURL]
                         ?? localized("目前篩選條件下找不到原先選擇的欄目，請重新選擇分類。"))
                } actions: {
                    Button(localized("更換分類")) { settings = .init(index: model.selection) }
                }
            } else if let source = sources.first(where: { $0.bookSourceUrl == choice.reference.sourceURL }) {
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
                if let onAllTypes {
                    Button(localized("所有類型"), action: onAllTypes)
                        .accessibilityIdentifier("search.allTypes")
                }
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
                if let section = model.section {
                    ForEach(Array(model.books.enumerated()), id: \.element.id) { index, display in
                        NavigationLink(value: ExploreNavigationRoute.book(display.book)) {
                            row(display, section: section)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("discovery.book.\(index)")
                        .task(id: model.loaded) {
                            await model.loadMoreIfNeeded(after: display.id)
                        }
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
                }
            }
            // Measure the content container, not a separately recycled zero-height row.
            .rootTabTitleScrollAnchor()
            .padding(.horizontal, DSSpacing.lg)
            .padding(.bottom, DSSpacing.lg)
        }
        .overlay {
            if model.loaded && model.books.isEmpty && !model.isLoading && model.error == nil {
                ContentUnavailableView { UnavailableLabel(localized("暫無發現內容"), systemImage: "books.vertical") }
            }
        }
        // The fixed controls above this nested scroll view already occupy the top
        // safe area. Keep its own content margin explicit (not the refresh inset).
        .contentMargins(.top, 0, for: .scrollContent)
        .softScrollEdges()
        .refreshable { await model.loadFirst(force: true) }
        .task(id: ObjectIdentifier(model)) { await model.loadFirst() }
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
