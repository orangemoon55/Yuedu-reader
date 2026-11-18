import Foundation

extension CollectionEntry {
    /// Like DiscoverViewModel.makeDisplays, this nonisolated async entry runs on the
    /// generic executor. HTML, mode inference and JS headers never run in a Form body.
    nonisolated static func preparedRankBooks(_ books: [OnlineBook], source: BookSource) async throws -> [CollectionEntry] {
        try Task.checkCancellation()
        let displays = await DiscoverViewModel.makeDisplays(books, source: source)
        let headers = await source.resolvedHeaders()
        try Task.checkCancellation()
        return displays.map { display in
            .onlineBook(display.book, source: source, contentKind: display.contentKind,
                        blurb: display.intro, headers: headers)
        }
    }
}

enum HomeRankSourceLookup {
    nonisolated static func source(url: String, id: UUID? = nil,
                                  store: BookSourceStore = .shared) async -> BookSource? {
        // Nonisolated async uses the generic executor: even a large imported library
        // or its initial disk read cannot hold the navigation toolbar.
        if let id, let found = store.source(id: id), found.enabled, found.bookSourceUrl == url { return found }
        return store.sources.first { $0.enabled && $0.bookSourceUrl == url }
    }
}
