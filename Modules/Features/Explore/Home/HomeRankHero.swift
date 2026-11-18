import SwiftUI

/// Detail enrichment belongs to the visible home card, never to the Save transaction.
struct HomeRankHero: View {
    let content: HomeCardContent
    let isActive: Bool
    let open: (HomeCardContent) -> Void
    @State private var enriched: HomeCardContent?

    private struct LoadKey: Hashable { let id: SourceItemKey; let active: Bool }
    private var shown: HomeCardContent {
        guard let enriched, enriched.id == content.id else { return content }
        return enriched
    }

    var body: some View {
        Button { open(shown) } label: { HomeCoverIntroCard(content: shown) }
            .buttonStyle(ExploreTileButtonStyle())
            .homeRowControl()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(shown.accessibilityLabel)
            .accessibilityValue(shown.featuredAccessibilityValue)
            .accessibilityIdentifier("home.rank.current")
            .task(id: LoadKey(id: content.id, active: isActive)) {
                guard isActive, content.blurb?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false,
                      case .onlineBook(let frozen) = content.opening,
                      let source = await HomeRankSourceLookup.source(url: content.id.instance.id,
                                                                     id: frozen.book.sourceId),
                      !Task.isCancelled else { return }
                do {
                    var updated = try await BookSourceFetcher.shared.fetchBookInfo(
                        url: frozen.book.bookUrl, source: source,
                        runtimeVariables: frozen.book.runtimeVariables, knownBook: frozen.book)
                    updated.bookUrl = frozen.book.bookUrl
                    updated.id = frozen.book.id
                    if updated.name.isEmpty { updated.name = frozen.book.name }
                    let entries = try await CollectionEntry.preparedRankBooks([updated], source: source)
                    try Task.checkCancellation()
                    enriched = entries.first.flatMap { HomeCardContent($0, status: { _ in nil }, shelfBooks: [:]) }
                } catch {
                    guard !Task.isCancelled, !(error is CancellationError) else { return }
                    AppLogger.network("home ranking introduction unavailable", error: SourceFailure.loggable(error),
                                      context: ["source": source.bookSourceName])
                }
            }
    }
}
