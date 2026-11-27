import SwiftUI

/// Stable columns keep cards in place when another page is appended.
struct HomeCoverShelf<Item: Identifiable, Card: View>: View {
    let items: [Item]
    var loading = HorizontalPageLoading()
    var cardWidth: CGFloat = Theme.Layout.cardSize
    @ViewBuilder let card: (Item) -> Card

    var body: some View {
        HorizontalPagingScrollView(itemCount: items.count, resetKey: items.first?.id,
                                   loading: loading) { visibleCount in
            LazyHStack(alignment: .top, spacing: Theme.Spacing.component) {
                ForEach(0..<((visibleCount + 1) / 2), id: \.self) { column in
                    VStack(alignment: .leading, spacing: Theme.Spacing.group) {
                        card(items[column * 2])
                        if column * 2 + 1 < visibleCount { card(items[column * 2 + 1]) }
                    }
                }
            }
        } placeholder: {
            HorizontalCardLoadingColumn(rows: 2, width: cardWidth, cornerRadius: HomeLayout.coverCornerRadius)
        }
        .compatScrollClipDisabled()
    }
}
