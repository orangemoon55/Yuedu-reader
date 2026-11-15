import SwiftUI

/// The Search tab opens the remembered source's own discovery page. Parsing, paging,
/// login, variables and book destinations remain on the existing discovery pipeline.
struct SourceDiscoveryRoot: View {
    @State private var selection = SourceDiscoverySelection()
    @State private var showsSources = false
    @Environment(\.searchTabNavigation) private var navigation
    let openBrowser: (BrowserEntry) -> Void

    var body: some View {
        Group {
            if !selection.isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let source = selection.selectedSource {
                ExploreSourcePage(
                    source: source,
                    layoutOverride: .magazine,
                    rankedSectionsFirst: true,
                    onSearch: {
                        navigation?.path.append(ExploreNavigationRoute.searchInSource(sourceURL: source.bookSourceUrl))
                    },
                    onSwitchSource: { showsSources = true },
                    onNavigate: { openBrowser(.open($0)) }
                )
                .id("\(source.bookSourceUrl)|\(source.lastUpdateTime)")
            } else {
                ContentUnavailableView {
                    UnavailableLabel(localized("沒有來源配置"), systemImage: "books.vertical")
                } description: {
                    Text(localized("請先匯入並啟用支援發現的書源"))
                } actions: {
                    NavigationLink(value: ExploreNavigationRoute.sourceManager) {
                        Text(localized("來源配置"))
                    }
                }
                .navigationTitle(localized("搜索"))
                .toolbarTitleDisplayMode(.inline)
            }
        }
        .task { selection.start() }
        .sheet(isPresented: $showsSources) {
            DiscoverySourcePicker(
                sources: selection.sources,
                selectedURL: selection.selectedSource?.bookSourceUrl
            ) { source in
                selection.select(source)
                showsSources = false
            }
        }
    }
}

private struct DiscoverySourcePicker: View {
    let sources: [DiscoverableBookSource]
    let selectedURL: String?
    let choose: (DiscoverableBookSource) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var matches: [DiscoverableBookSource]
    @State private var pins = DiscoverySourcePins()
    @State private var showsPinConfirmation = false

    private var pinActionTitle: String {
        localized(pins.pendingChange?.shouldPin == false ? "取消置頂" : "置頂")
    }

    private struct SearchInput: Equatable {
        let query: String
        let sources: [DiscoverableBookSource]
    }

    init(
        sources: [DiscoverableBookSource], selectedURL: String?,
        choose: @escaping (DiscoverableBookSource) -> Void
    ) {
        self.sources = sources
        self.selectedURL = selectedURL
        self.choose = choose
        _matches = State(initialValue: sources)
    }

    var body: some View {
        NavigationStack {
            List(pins.ordered(matches)) { source in
                Button { choose(source) } label: {
                    HStack(spacing: DSSpacing.md) {
                        if pins.isPinned(source.id) {
                            Image(systemName: "pin.fill")
                                .foregroundStyle(DSColor.accent)
                                .accessibilityLabel(localized("置頂"))
                        }
                        Text(source.displayName)
                            .foregroundStyle(DSColor.textPrimary)
                            .lineLimit(2)
                        Spacer()
                        if source.url == selectedURL {
                            Image(systemName: "checkmark")
                                .foregroundStyle(DSColor.accent)
                                .accessibilityHidden(true)
                        }
                    }
                    .frame(minHeight: DSLayout.minimumTapTarget)
                }
                .accessibilityAddTraits(source.url == selectedURL ? .isSelected : [])
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    Button {
                        pins.requestChange(for: source.id)
                        showsPinConfirmation = true
                    } label: {
                        Label(
                            localized(pins.isPinned(source.id) ? "取消置頂" : "置頂"),
                            systemImage: pins.isPinned(source.id) ? "pin.slash" : "pin"
                        )
                    }
                    .tint(DSColor.accent)
                }
            }
            .alert(pinActionTitle, isPresented: $showsPinConfirmation) {
                Button(pinActionTitle) {
                    pins.confirmPendingChange(availableIDs: Set(sources.map(\.id)))
                }
                Button(localized("取消"), role: .cancel) {
                    pins.cancelPendingChange()
                }
            } message: {
                // Show only the display name, never the source's URL or credentials.
                Text(sources.first { $0.id == pins.pendingChange?.sourceID }?.displayName ?? "")
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: localized("搜尋來源配置名稱或網址")
            )
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .scrollDismissesKeyboard(.interactively)
            .overlay {
                if matches.isEmpty, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .task(id: SearchInput(query: query, sources: sources)) {
                let snapshot = sources
                let search = query
                let work = Task.detached(priority: .userInitiated) {
                    DiscoverySourceSearch.matching(snapshot, query: search)
                }
                let result = await withTaskCancellationHandler {
                    await work.value
                } onCancel: {
                    work.cancel()
                }
                guard !Task.isCancelled else { return }
                matches = result
            }
            .navigationTitle(localized("切換來源配置"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark").accessibilityHidden(true)
                    }
                    .accessibilityLabel(localized("關閉"))
                }
            }
        }
    }
}

#Preview("書源發現 tab") {
    NavigationStack {
        SourceDiscoveryRoot(openBrowser: { _ in })
    }
    .environmentObject(BookStore())
}
