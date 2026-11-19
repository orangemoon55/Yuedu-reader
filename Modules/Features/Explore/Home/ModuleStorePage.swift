import SwiftUI

// Adapted from Yuedu-reader (MPL-2.0), d6cfdb980346c3b82b8e56cb343d00b4fefb5de1.
// Each category opens the module and parameters shipped inside the supplied original IPA.
struct ModuleStorePage: View {
    let route: ModuleStoreRoute
    @EnvironmentObject private var store: BookStore
    var body: some View { ModuleStoreContent(route: route, store: store) }
}

private struct ModuleStoreContent: View {
    let route: ModuleStoreRoute
    let store: BookStore
    @StateObject private var model: HomeModel
    @ObservedObject private var modules = RuleModuleLibrary.shared
    @ObservedObject private var aggregation = AggregationSettingsStore.shared
    @ObservedObject private var aozora = AozoraCatalogStore.shared
    @Environment(\.explorePush) private var push
    @State private var pageWidth: CGFloat = 0

    init(route: ModuleStoreRoute, store: BookStore) {
        self.route = route
        self.store = store
        _model = StateObject(wrappedValue: HomeModel.live(shelf: store))
    }

    private var page: HomePage? {
        guard let module = modules.module(id: route.moduleID)?.module,
              let entry = module.modules.first(where: { $0.id == route.entryID }) else { return nil }
        return ModuleStores.page(of: entry, in: module, language: aggregation.readingLanguages.language)
    }

    private var groups: [HomeSectionGroup] {
        let lookup = store.copyLookup()
        return model.groups(in: nil, languages: aggregation.readingLanguages,
                            readFilter: HomeReadFilter(hides: aggregation.hidesRead, isRead: lookup.isRead))
    }

    private var syncKey: [AnyHashable] {
        [page, aggregation.readingLanguages.language, modules.module(id: route.moduleID)?.module.version]
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(groups) { group in
                    HomeSectionSlot(entry: HomeSectionEntry(section: group.section, homeGroup: group, editableIndex: nil),
                                    isEditing: false, pageWidth: pageWidth, count: 0, openSettings: { _ in }) { group in
                        HomeRowHost(group: group, store: store, aozoraIndex: aozora.catalog,
                                    model: model, isEditable: false, push: { push?($0) }, openSettings: {})
                    }
                }
            }
            .padding(.vertical, DSSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pageWidth = $0 }
        }
        .overlay {
            if !modules.isLoaded || !model.isReady { ProgressView() }
            else if page == nil {
                ContentUnavailableView {
                    UnavailableLabel(localized("找不到這個類型"), systemImage: "square.stack")
                } description: { Text(localized("提供它的模組已移除或更新。")) }
            } else if groups.allSatisfy(\.isSettledEmpty) {
                ContentUnavailableView {
                    UnavailableLabel(localized("這個類型還沒有作品"), systemImage: "books.vertical")
                }
            }
        }
        .softScrollEdges()
        .navigationTitle(route.title)
        .navigationBarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task(id: syncKey) {
            await modules.loadIfNeeded()
            guard let page else { return }
            await model.sync(with: page)
        }
        .task(id: model.rows.map(\.id)) { model.homeAppeared(in: nil) }
        .onAppear { model.reloadLocal() }
        .refreshable { model.reload() }
        .accessibilityIdentifier("moduleStore.\(route.moduleID).\(route.entryID)")
    }
}

struct ModuleGenresPage: View {
    @ObservedObject private var modules = RuleModuleLibrary.shared
    private var listings: [ModuleStoreListing] { ModuleStores.listings(in: modules) }

    var body: some View {
        List {
            Section {
                ForEach(listings) { listing in
                    NavigationLink(value: ExploreNavigationRoute.moduleStore(listing.route)) {
                        Label {
                            Text(listing.title).foregroundStyle(DSColor.textPrimary)
                        } icon: {
                            Image(systemName: HomeCategoryFace(name: listing.title).symbol)
                                .foregroundStyle(DSColor.accent)
                        }
                        .font(DSFont.body)
                        .padding(.vertical, DSSpacing.xs)
                    }
                    .accessibilityIdentifier("genres.\(listing.entryID)")
                }
            }
            .interfaceSectionSurface()
        }
        .listStyle(.insetGrouped)
        .themedAppSurface(for: .explore)
        .overlay {
            if !modules.isLoaded { ProgressView() }
            else if listings.isEmpty {
                ContentUnavailableView {
                    UnavailableLabel(localized("還沒有類型"), systemImage: "square.stack")
                } description: {
                    Text(localized("安裝提供類型的模組後會列在這裡。"))
                }
            }
        }
        .navigationTitle(localized("所有類型"))
        .navigationBarTitleDisplayMode(.inline)
        .task { await modules.loadIfNeeded() }
        .accessibilityIdentifier("discovery.genreDirectory")
    }
}
