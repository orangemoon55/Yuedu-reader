import SwiftUI

struct SearchView: View {
    var initialQuery: String = ""
    var sessionScope: SearchSourceScope?
    /// The 搜索 tab's own root, which carries a tab root's title.
    var isTabRoot = false

    var body: some View {
        BookSearchView(initialQuery: initialQuery, sessionScope: sessionScope, isTabRoot: isTabRoot)
    }
}

/// The 搜索 tab's stack, for the pages on it that push by value: 作品詳情 and 青空文庫's full
/// list. One path for every page past the root, so back pops one page (postmortem guardrail
/// 11: an item-based push under a bound path lost its place, and back from 作品詳情 on
/// Gutenberg's results returned to the root). A reference that never changes, so the search
/// page can hold it without its body depending on the path (guardrail 13).
@MainActor @Observable
final class SearchTabNavigation {
    var path = NavigationPath()

    func open(_ route: ExplorePush, store: BookStore) {
        route.open(in: &path, store: store)
    }
}

extension EnvironmentValues {
    /// The 搜索 tab's stack; nil anywhere else.
    @Entry var searchTabNavigation: SearchTabNavigation?
}

/// The 搜索 tab: its stack, with the store's pages for the public libraries it searches
/// (unified library 5d-1b, Phase 5 plan decision 17). A public-library book opens 作品詳情, as
/// on 探索; the card carousel is off here too (decision 27, extended to 搜索 after 5f-2).
struct SearchTabRoot: View {
    @State private var navigation = SearchTabNavigation()
    @State private var browserPresentation: BrowserPresentation?
    @EnvironmentObject private var store: BookStore
    let browser: BrowserState
    var close: (() -> Void)? = nil

    private struct BrowserPresentation: Identifiable {
        let id = UUID()
        let entry: BrowserEntry
    }

    init(browser: BrowserState, close: (() -> Void)? = nil) {
        self.browser = browser
        self.close = close
    }

    var body: some View {
        @Bindable var navigation = navigation
        NavigationStack(path: $navigation.path) {
            SourceDiscoveryRoot { entry in
                browserPresentation = BrowserPresentation(entry: entry)
            }
            .toolbar {
                if let close, navigation.path.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: close) { Image(systemName: "xmark").accessibilityHidden(true) }
                            .accessibilityLabel(localized("關閉"))
                            .accessibilityIdentifier("explore.search.close")
                    }
                }
            }
            .exploreRouteDestinations { entry in
                browserPresentation = BrowserPresentation(entry: entry)
            }
            .remoteLibraryDestinations()
            .publicLibraryDestinations()
        }
        .environment(\.searchTabNavigation, navigation)
        .environment(\.explorePush) { route in navigation.open(route, store: store) }
        .environment(\.openPublicLibraryBooks) { [navigation] selection in
            if let book = selection.selectedBook { navigation.path.append(WorkDetailRoute(book)) }
        }
        .fullScreenCover(item: $browserPresentation) { presentation in
            NavigationStack {
                BrowserPage(browser: browser, entry: presentation.entry)
            }
            .environmentObject(store)
        }
    }
}

#Preview("搜索 tab") {
    SearchTabRoot(browser: BrowserState())
        .environmentObject(BookStore())
}
