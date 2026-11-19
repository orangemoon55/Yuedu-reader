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

    private enum Route: Hashable { case types, keywordSearch }

    var body: some View {
        DiscoveryFiveCategoryPage(model: categories,
            configuration: pageStore.selectedConfiguration.rawValue,
            page: pageStore.page, sources: sources, editRequest: editRequest,
            titleKey: "搜索")
            .accessibilityIdentifier("search.fiveCategoryHome")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigation?.path.append(Route.types) } label: {
                        Image(systemName: "square.grid.2x2")
                    }
                    .accessibilityLabel(localized("所有類型"))
                    .accessibilityIdentifier("search.allTypes")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { navigation?.path.append(Route.keywordSearch) } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 20))
                            .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                            .contentShape(Rectangle())
                    }
                    .accessibilityLabel(localized("搜索"))
                    .accessibilityIdentifier("search.keywordEntry")
                }
            }
            .navigationDestination(for: Route.self) { route in
                switch route {
                case .types:
                    ModuleGenresPage()
                case .keywordSearch:
                    SearchView()
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

    /// Filtering the library once per source update, not during each book-row body.
    @concurrent private static func explorable(_ snapshot: [BookSource]) async -> [BookSource] {
        DiscoverViewModel.exploreSources(in: snapshot)
    }
}
