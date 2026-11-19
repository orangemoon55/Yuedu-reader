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
    private var currentSearchSource: BookSource? {
        guard let source = categories.activeSource else { return nil }
        return sources.first {
            source.matches($0) && !$0.searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            sourceSearchEntry
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.xs)
            DiscoveryFiveCategoryPage(model: categories,
                configuration: pageStore.selectedConfiguration.rawValue,
                page: pageStore.page, sources: sources,
                onAllTypes: { navigation?.path.append(ExploreNavigationRoute.genres) })
        }
            .rootTabTitle(localized("搜索"), onScroll: .fadesTitle)
            .pageBackgroundToolbar(for: .explore)
            .background(PageBackgroundView(scope: .explore).ignoresSafeArea())
            .accessibilityIdentifier("search.fiveCategoryHome")
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

    private var sourceSearchEntry: some View {
        Button {
            guard let source = currentSearchSource else { return }
            navigation?.path.append(ExploreNavigationRoute.searchInSource(sourceURL: source.bookSourceUrl))
        } label: {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .accessibilityHidden(true)
                Text(localized("搜尋書名或作者"))
                    .font(DSFont.body)
            }
            .foregroundStyle(DSColor.textSecondary)
            .padding(.horizontal, DSSpacing.md)
            .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget, alignment: .leading)
            .background { NavigationGlassCapsule(tint: DSColor.accent) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint(localized("源內搜索"))
        .accessibilityIdentifier("search.keywordEntry")
        .disabled(currentSearchSource == nil || navigation == nil)
    }

    /// Filtering the library once per source update, not during each book-row body.
    @concurrent private static func explorable(_ snapshot: [BookSource]) async -> [BookSource] {
        DiscoverViewModel.exploreSources(in: snapshot)
    }
}
