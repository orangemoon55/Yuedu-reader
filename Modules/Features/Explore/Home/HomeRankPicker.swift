import SwiftUI

struct HomeRankPicker: View {
    let current: HomeSectionBinding?
    let pushed: Bool
    let choose: (HomeContentChoice, BookSource) -> Void
    let cancel: () -> Void
    @State private var search = ""
    @State private var sources: [DiscoverableBookSource] = []
    @State private var loaded = false
    @State private var opened: UUID?

    var body: some View {
        List {
            ForEach(sources) { source in
                Button { opened = source.id } label: {
                    HStack {
                        Text(source.displayName).foregroundStyle(DSColor.textPrimary)
                        Spacer()
                        Image(systemName: "chevron.right").foregroundStyle(DSColor.textTertiary).accessibilityHidden(true)
                    }
                    .contentShape(Rectangle())
                }
                .accessibilityIdentifier("home.rank.source.\(source.id)")
            }
            if loaded && sources.isEmpty {
                ContentUnavailableView {
                    UnavailableLabel(localized("沒有可用的排行榜書源"), systemImage: "list.number")
                }
            }
        }
        .overlay { if !loaded { ProgressView() } }
        .task(id: search) {
            let filter = search.trimmingCharacters(in: .whitespacesAndNewlines)
            let task = Task.detached(priority: .userInitiated) {
                BookSourceStore.shared.discoverableSources().filter {
                    filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) || $0.url.localizedCaseInsensitiveContains(filter)
                }
            }
            let listed = await withTaskCancellationHandler { await task.value } onCancel: { task.cancel() }
            guard !Task.isCancelled else { return }
            sources = listed
            loaded = true
        }
        .searchable(text: $search, prompt: localized("搜尋來源配置"))
        .navigationTitle(localized("選擇榜單來源"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            if !pushed {
                ToolbarItem(placement: .cancellationAction) { Button(localized("取消"), action: cancel) }
            }
        }
        .navigationDestination(item: $opened) { id in
            if let source = BookSourceStore.shared.source(id: id) {
                HomeRankCategories(source: source, current: current, choose: choose)
            }
        }
        .themedAppSurface(for: .explore)
    }
}

struct HomeRankCategories: View {
    let source: BookSource
    let current: HomeSectionBinding?
    let choose: (HomeContentChoice, BookSource) -> Void
    @StateObject private var listing: SourceCategoryListing
    @State private var search = ""

    init(source: BookSource, current: HomeSectionBinding?, filterValues: [String: String] = [:],
         choose: @escaping (HomeContentChoice, BookSource) -> Void) {
        self.source = source
        self.current = current
        self.choose = choose
        _listing = StateObject(wrappedValue: SourceCategoryListing(source: source, filterValues: filterValues, loadItems: { source, values in
            await BookSourceFetcher.shared.primeDiscoverCookies(in: source)
            return try await BookSourceFetcher.shared.discoverItems(page: 1, in: source, variableOverlay: values)
        }))
    }

    private var groups: [DiscoverCategoryGroup] {
        let matched = DiscoverCategoryGroup.filtered(listing.groups, matching: search.trimmingCharacters(in: .whitespacesAndNewlines))
        return matched.compactMap { group in
            let ranked = HomeRankCategoryPolicy.rankedItems(group)
            return ranked.isEmpty ? nil : DiscoverCategoryGroup(id: group.id, title: group.title, items: ranked)
        }
    }

    var body: some View {
        List {
            if !listing.filters.isEmpty {
                Section(localized("篩選")) {
                    ForEach(listing.filters, id: \.paramKey) { filter in
                        Picker(filter.title, selection: Binding(get: { filter.selected }, set: { value in
                            Task { await listing.select(filter, value: value) }
                        })) {
                            ForEach(filter.options, id: \.self) { Text($0).tag($0) }
                        }
                    }
                }
            }
            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items, id: \.stableKey) { item in
                        if let ref = listing.reference(for: item) {
                            Button {
                                // This callback is local; it enables Save before a book page or preview loads.
                                choose(HomeContentChoice(binding: .sourceCategories([ref]),
                                                         parameters: HomeSection.filterParameters(listing.filterValues, sourceURL: ref.sourceURL),
                                                         itemTitle: item.title), source)
                            } label: {
                                HStack {
                                    Text(item.title).foregroundStyle(DSColor.textPrimary)
                                    Spacer()
                                    if current == .sourceCategories([ref]) {
                                        Image(systemName: "checkmark").foregroundStyle(DSColor.accent).accessibilityHidden(true)
                                    }
                                }
                                .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("home.rank.category.\(item.stableKey)")
                        }
                    }
                }
                .interfaceSectionSurface()
            }
            if listing.state == .loaded && groups.isEmpty || listing.state == .empty {
                Text(localized("這個書源沒有可用的排行榜"))
                    .foregroundStyle(DSColor.textSecondary)
            }
        }
        .overlay {
            switch listing.state {
            case .loading: ProgressView()
            case .failed(let error):
                ContentUnavailableView {
                    UnavailableLabel(localized("載入失敗"), systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button(localized("重試")) { Task { await listing.load() } }
                }
            case .empty, .loaded: EmptyView()
            }
        }
        .searchable(text: $search, prompt: localized("搜尋排行榜名稱"))
        .navigationTitle(source.bookSourceName)
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task { await listing.load() }
    }
}

enum HomeRankCategoryPolicy {
    static func rankedItems(_ group: DiscoverCategoryGroup) -> [DiscoverCardItem] {
        let rankGroup = DiscoverViewModel.sectionStyle(for: group.title) == .ranked
        return group.items.filter { $0.isFetchable && (rankGroup || DiscoverViewModel.sectionStyle(for: $0.title) == .ranked) }
    }
}
