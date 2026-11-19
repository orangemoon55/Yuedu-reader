import SwiftUI

/// The five-category book list belongs to Search. Discovery keeps its user's HomePage.
struct SearchCategoryHome: View {
    @StateObject private var categories = DiscoveryCategoryModel()
    @ObservedObject private var pageStore = HomePageStore.shared
    @ObservedObject private var sourceStore = BookSourceStore.shared
    @Environment(\.searchTabNavigation) private var navigation
    @State private var sources: [BookSource] = []
    @State private var publishedSources: [BookSource] = []
    @State private var sourceRevision = 0
    @State private var editRequest = UUID()
    @State private var keyword = ""
    @FocusState private var keywordFocused: Bool

    private enum Route: Hashable { case types, keywordSearch(String) }

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            searchField
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.xs)
            DiscoveryFiveCategoryPage(model: categories,
                configuration: pageStore.selectedConfiguration.rawValue,
                page: pageStore.page, sources: sources, editRequest: editRequest,
                onAllTypes: { navigation?.path.append(Route.types) })
        }
            .rootTabTitle(localized("搜索"), onScroll: .fadesTitle)
            .pageBackgroundToolbar(for: .explore)
            .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
            .accessibilityIdentifier("search.fiveCategoryHome")
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .types:
                    ModuleGenresPage()
                case .keywordSearch(let term):
                    SearchView(initialQuery: term)
                }
            }
            .navigationDestination(for: DiscoveryCategoryChoice.self) { choice in
                if let source = sources.first(where: { $0.bookSourceUrl == choice.reference.sourceURL }) {
                    DiscoveryBookList(model: categories.list(for: choice, source: source))
                        .navigationTitle(choice.title)
                        .navigationBarTitleDisplayMode(.inline)
                        .themedAppSurface(for: .explore)
                } else {
                    ContentUnavailableView {
                        UnavailableLabel(localized("來源配置已停用或移除"), systemImage: "books.vertical")
                    }
                }
            }
            .task(id: sourceRevision) {
                await sourceStore.waitUntilLoaded()
                let snapshot = publishedSources.isEmpty ? sourceStore.sources : publishedSources
                let found = await Self.explorable(snapshot)
                guard !Task.isCancelled else { return }
                sources = found
            }
            .onReceive(sourceStore.sourcesPublisher) { snapshot in
                guard sourceStore.isLoaded else { return }
                publishedSources = snapshot
                sourceRevision &+= 1
            }
    }

    private var searchField: some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass").font(.system(size: 16, weight: .semibold)).foregroundStyle(DSColor.textSecondary)
            TextField(localized("搜尋書名或作者"), text: $keyword)
                .font(DSFont.body).focused($keywordFocused).submitLabel(.search)
                .onSubmit { submitKeywordSearch() }
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("search.keywordField")
            if !keyword.isEmpty {
                Button { keyword = "" } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(DSColor.textSecondary)
                }.buttonStyle(.plain).accessibilityLabel(localized("清除"))
            }
        }
        .padding(.horizontal, DSSpacing.md)
        .frame(minHeight: DSLayout.minimumTapTarget)
        .background { NavigationGlassCapsule(tint: DSColor.accent) }
    }

    private func submitKeywordSearch() {
        let term = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        keywordFocused = false
        navigation?.path.append(Route.keywordSearch(term))
    }

    /// Filtering the library once per source update, not during each book-row body.
    @concurrent private static func explorable(_ snapshot: [BookSource]) async -> [BookSource] {
        DiscoverViewModel.exploreSources(in: snapshot)
    }
}
