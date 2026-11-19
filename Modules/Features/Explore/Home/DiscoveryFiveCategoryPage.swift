import SwiftUI

struct DiscoveryFiveCategoryPage: View {
    @ObservedObject var model: DiscoveryCategoryModel
    let configuration: String
    let page: HomePage?
    let sources: [BookSource]
    var onAllTypes: (() -> Void)? = nil
    @State private var settings: SlotSettingsRequest?
    @State private var showsSources = false

    private struct SlotSettingsRequest: Identifiable { let id = UUID(); let index: Int }

    private var active: BookSource? {
        guard let activation = model.activeSource else { return nil }
        return sources.first { activation.matches($0) }
    }
    private var prepareKey: [AnyHashable] {
        [configuration, page, sources.map { "\($0.id)@\($0.lastUpdateTime)" }]
    }

    var body: some View {
        VStack(spacing: 0) {
            if let source = active, let activation = model.activeSource {
                DiscoverySourceControls(source: source, filterValues: model.current?.filters ?? [:],
                    onSwitchSource: { showsSources = true },
                    onReload: { values, items, error, refreshBooks in
                        model.reconcileSource(sourceURL: source.bookSourceUrl, values: values, items: items,
                                              error: error, refreshBooks: refreshBooks, activation: activation)
                    }) {
                    if model.slots.choices.contains(where: { $0 != nil }) {
                        DiscoveryCategoryBar(slots: model.slots, selection: model.selection,
                            select: { model.select($0) }, edit: { settings = .init(index: $0) })
                    }
                }
                .id(activation)
            }

            content
        }
        .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
        // SearchCategoryHome owns the single navigation title above the field and chips.
        .task(id: prepareKey) {
            model.prepare(configuration: configuration, page: page, sources: sources)
        }
        .sheet(isPresented: $showsSources) {
            DiscoverySearchSourcePicker(sources: sources, selectedURL: model.activeSource?.sourceURL,
                choose: { source in
                    guard sources.contains(where: { $0.id == source.id && $0.lastUpdateTime == source.lastUpdateTime }) else {
                        showsSources = false
                        return
                    }
                    model.switchSource(to: source, page: page)
                    showsSources = false
                }, close: { showsSources = false })
        }
        .sheet(item: $settings) { request in
            DiscoverySlotSettings(slots: model.slots, catalog: model.catalog, openSlot: request.index, choose: { choice, index in
                model.choose(choice, at: index)
                settings = nil
            }, close: { settings = nil })
        }
    }

    @ViewBuilder private var content: some View {
        if let source = active, let choice = model.current, choice.reference.sourceURL == source.bookSourceUrl {
            if model.invalidReferences.contains(choice.reference) {
                ContentUnavailableView {
                    UnavailableLabel(localized("所選分類已失效"), systemImage: "exclamationmark.triangle")
                } description: {
                    Text(model.sourceErrors[choice.reference.sourceURL]
                         ?? localized("目前篩選條件下找不到原先選擇的欄目，請重新選擇分類。"))
                } actions: {
                    Button(localized("切換來源配置")) { showsSources = true }
                }
            } else {
                DiscoveryBookList(model: model.list(for: choice, source: source))
                    .id(choice.id)
            }
        } else if model.isLoadingCatalog {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                UnavailableLabel(localized(active == nil ? "尚未設定分類" : "暫無發現內容"), systemImage: "square.grid.2x2")
            } description: {
                if let error = model.catalogError { Text(error) }
            } actions: {
                Button(localized("切換來源配置")) { showsSources = true }
                    .disabled(sources.isEmpty)
                    .accessibilityIdentifier("discovery.category.changeEmpty")
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

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                if let section = model.section {
                    ForEach(Array(model.books.enumerated()), id: \.element.id) { index, display in
                        if index > 0 {
                            Divider()
                                .padding(.leading, DSLayout.discoverRowCoverWidth + DSSpacing.md)
                        }
                        NavigationLink(value: ExploreNavigationRoute.book(display.book)) {
                            DiscoverBookRow(
                                rank: section.style == .ranked ? index + 1 : nil,
                                display: display,
                                section: section,
                                showsIntro: true
                            )
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
}
