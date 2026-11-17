import SwiftUI

struct HomeRankPicker: View {
    let current: HomeSectionBinding?; let pushed: Bool; let choose: (HomeContentChoice, BookSource) -> Void; let cancel: () -> Void
    @ObservedObject private var store = BookSourceStore.shared
    @State private var search = ""; @State private var source: BookSource?
    var body: some View {
        List {
            if let source {
                HomeRankCategories(source: source, current: current, choose: choose)
            } else {
                ForEach(store.sources.filter { DiscoverViewModel.isExploreSource($0) && (search.isEmpty || $0.bookSourceName.localizedCaseInsensitiveContains(search)) }) { source in
                    Button(source.bookSourceName) { self.source = source }.foregroundStyle(DSColor.textPrimary)
                }
            }
        }
        .searchable(text: $search, prompt: localized("搜尋來源配置"))
        .navigationTitle(source == nil ? localized("選擇榜單來源") : localized("選擇排行榜"))
        .toolbarTitleDisplayMode(.inline)
        .toolbar { if !pushed { ToolbarItem(placement: .cancellationAction) { Button(localized("取消"), action: cancel) } } }
        .themedAppSurface(for: .explore)
    }
}

private struct HomeRankCategories: View {
    let source: BookSource; let current: HomeSectionBinding?; let choose: (HomeContentChoice, BookSource) -> Void
    @StateObject private var listing: SourceCategoryListing
    init(source: BookSource, current: HomeSectionBinding?, choose: @escaping (HomeContentChoice, BookSource) -> Void) { self.source=source;self.current=current;self.choose=choose;_listing=StateObject(wrappedValue: SourceCategoryListing(source: source)) }
    var body: some View {
        List {
            ForEach(listing.groups) { group in
                let items = group.items.filter { DiscoverViewModel.sectionStyle(for: $0.title) == .ranked }
                if !items.isEmpty { Section(group.title) { ForEach(items, id: \.stableKey) { item in if let ref=listing.reference(for:item) { Button(item.title) { choose(HomeContentChoice(binding:.sourceCategories([ref]), parameters:HomeSection.filterParameters(listing.filterValues, sourceURL:ref.sourceURL), itemTitle:item.title), source) }.foregroundStyle(DSColor.textPrimary) } } } }
            }
        }
        .overlay { if case .loading = listing.state { ProgressView() } }
        .task { await listing.load() }
        .themedAppSurface(for: .explore)
    }
}
