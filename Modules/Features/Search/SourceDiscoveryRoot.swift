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

    var body: some View {
        NavigationStack {
            List(sources) { source in
                Button { choose(source) } label: {
                    HStack(spacing: DSSpacing.md) {
                        Text(source.name)
                            .foregroundStyle(DSColor.textPrimary)
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
