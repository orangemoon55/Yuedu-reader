import SwiftUI

@MainActor
final class SearchViewModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case all = "综合"
        case songs = "单曲"
        case artists = "歌手"
        case albums = "专辑"
        case playlists = "歌单"

        var id: String { rawValue }
    }

    static func supports(_ tab: Tab, provider: MusicProvider) -> Bool {
        switch tab {
        case .all: return true
        case .songs: return provider.supports(.searchSongs)
        case .artists: return provider.supports(.searchArtists)
        case .albums: return provider.supports(.searchAlbums)
        case .playlists: return provider.supports(.searchPlaylists)
        }
    }

    private func searchSupported(_ keyword: String, _ type: NeteaseAPI.SearchType, _ limit: Int, _ offset: Int) async throws -> NeteaseAPI.SearchResult {
        let feature: MusicServiceFeature
        switch type { case .songs: feature = .searchSongs; case .artists: feature = .searchArtists; case .albums: feature = .searchAlbums; case .playlists: feature = .searchPlaylists }
        guard MusicProviderContext.shared.current.supports(feature) else {
            return .init(songs: nil, albums: nil, artists: nil, playlists: nil, songCount: nil, albumCount: nil, artistCount: nil, playlistCount: nil)
        }
        return try await search(keyword, type, limit, offset)
    }

    private struct CardPage {
        var offset: Int
        var hasMore: Bool
    }

    private struct Snapshot {
        let songs: [Track]
        let artists: [ArtistSummary]
        let albums: [AlbumSummary]
        let playlists: [PlaylistSummary]
        let songOffset: Int
        let hasMoreSongs: Bool
        let cardPages: [Tab: CardPage]
    }
    private var snapshots: [Tab: Snapshot] = [:]
    private var generation = UUID()
    @Published var errorMessage: String?
    var query: String
    @Published var tab: Tab = .all
    @Published var songs: [Track] = []
    @Published var artists: [ArtistSummary] = []
    @Published var albums: [AlbumSummary] = []
    @Published var playlists: [PlaylistSummary] = []
    @Published var isLoading = false
    @Published var loadedTabs: Set<Tab> = []

    typealias Loader = (String, NeteaseAPI.SearchType, Int, Int) async throws -> NeteaseAPI.SearchResult
    @Published private(set) var isLoadingMoreSongs = false
    @Published private(set) var hasMoreSongs = false
    @Published private(set) var songPageError: String?
    private var songOffset = 0
    private var cardPages: [Tab: CardPage] = [:]
    @Published private var loadingCards: Set<Tab> = []
    @Published private var cardErrors: [Tab: String] = [:]
    private let search: Loader

    init(query: String, search: @escaping Loader = { try await NeteaseAPI.search($0, type: $1, limit: $2, offset: $3) }) {
        self.query = query
        self.search = search
    }

    func setQuery(_ newQuery: String) {
        guard newQuery != query else { return }
        generation = UUID()
        isLoading = false
        errorMessage = nil
        query = newQuery
        isLoadingMoreSongs = false
        hasMoreSongs = false
        songPageError = nil
        songOffset = 0
        cardPages = [:]
        loadingCards = []
        cardErrors = [:]
        loadedTabs.removeAll()
        snapshots = [:]
        songs = []
        artists = []
        albums = []
        playlists = []
    }

    func load(tab: Tab) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isLoadingMoreSongs = false
        songPageError = nil
        loadingCards = []
        cardErrors = [:]
        if let saved = snapshots[tab] {
            generation = UUID(); isLoading = false; errorMessage = nil
            songs = saved.songs; artists = saved.artists
            albums = saved.albums; playlists = saved.playlists
            songOffset = saved.songOffset; hasMoreSongs = saved.hasMoreSongs
            cardPages = saved.cardPages
            return
        }
        let request = UUID()
        generation = request
        isLoading = true
        errorMessage = nil
        defer { if generation == request { isLoading = false } }
        do {
            switch tab {
            case .all:
                async let songsTask = searchSupported(trimmed, .songs, 28, 0)
                async let artistsTask = searchSupported(trimmed, .artists, 10, 0)
                async let albumsTask = searchSupported(trimmed, .albums, 10, 0)
                async let playlistsTask = searchSupported(trimmed, .playlists, 10, 0)
                let result = try await (songsTask, artistsTask, albumsTask, playlistsTask)
                guard !Task.isCancelled, generation == request, query.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed else { return }
                updateSongPage(result.0, limit: 28)
                updateCardPage(.artists, count: result.1.artists?.count ?? 0, total: result.1.artistCount, limit: 10)
                updateCardPage(.albums, count: result.2.albums?.count ?? 0, total: result.2.albumCount, limit: 10)
                updateCardPage(.playlists, count: result.3.playlists?.count ?? 0, total: result.3.playlistCount, limit: 10)
                songs = result.0.songs ?? []; artists = result.1.artists ?? []
                albums = result.2.albums ?? []; playlists = result.3.playlists ?? []
            default:
                let type: NeteaseAPI.SearchType
                switch tab {
                case .songs: type = .songs
                case .artists: type = .artists
                case .albums: type = .albums
                default: type = .playlists
                }
                let result = try await search(trimmed, type, tab == .songs ? 100 : 50, 0)
                guard !Task.isCancelled, generation == request else { return }
                switch tab {
                case .songs:
                    songs = result.songs ?? []
                    updateSongPage(result, limit: 100)
                case .artists:
                    artists = result.artists ?? []
                    updateCardPage(tab, count: artists.count, total: result.artistCount, limit: 50)
                case .albums:
                    albums = result.albums ?? []
                    updateCardPage(tab, count: albums.count, total: result.albumCount, limit: 50)
                default:
                    playlists = result.playlists ?? []
                    updateCardPage(tab, count: playlists.count, total: result.playlistCount, limit: 50)
                }
            }
            snapshots[tab] = Snapshot(songs: songs, artists: artists, albums: albums, playlists: playlists, songOffset: songOffset, hasMoreSongs: hasMoreSongs, cardPages: cardPages)
            loadedTabs.insert(tab)
        } catch {
            guard !Task.isCancelled, generation == request else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func updateSongPage(_ result: NeteaseAPI.SearchResult, limit: Int) {
        let count = result.songs?.count ?? 0
        songOffset = count
        hasMoreSongs = count == limit && (result.songCount.map { count < $0 } ?? true)
    }

    func loadMoreSongs() async {
        let activeTab = tab
        guard activeTab == .all || activeTab == .songs,
              loadedTabs.contains(activeTab), hasMoreSongs, !isLoading, !isLoadingMoreSongs else { return }
        let request = generation
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let offset = songOffset
        let limit = activeTab == .all ? 28 : 100
        isLoadingMoreSongs = true
        songPageError = nil
        defer { if generation == request { isLoadingMoreSongs = false } }
        do {
            let result = try await search(keyword, .songs, limit, offset)
            guard !Task.isCancelled, generation == request, tab == activeTab else { return }
            let page = result.songs ?? []
            var seen = Set(songs.map(\.id))
            let additions = page.filter { seen.insert($0.id).inserted }
            songs.append(contentsOf: additions)
            songOffset += page.count
            hasMoreSongs = !additions.isEmpty && page.count == limit
                && (result.songCount.map { songOffset < $0 } ?? true)
            snapshots[activeTab] = Snapshot(songs: songs, artists: artists, albums: albums,
                playlists: playlists, songOffset: songOffset, hasMoreSongs: hasMoreSongs, cardPages: cardPages)
        } catch {
            guard !Task.isCancelled, generation == request, tab == activeTab else { return }
            songPageError = error.localizedDescription
        }
    }

    private func updateCardPage(_ kind: Tab, count: Int, total: Int?, limit: Int) {
        cardPages[kind] = CardPage(offset: count,
            hasMore: count == limit && (total.map { count < $0 } ?? true))
    }

    func horizontalLoading(for kind: Tab) -> HorizontalPageLoading {
        .init(hasMore: cardPages[kind]?.hasMore ?? false,
              isLoading: loadingCards.contains(kind), error: cardErrors[kind],
              loadMore: { [weak self] in await self?.loadMoreCards(kind) }, revision: cardPages[kind]?.offset ?? 0)
    }

    func loadMoreCards(_ kind: Tab) async {
        let activeTab = tab
        guard [.artists, .albums, .playlists].contains(kind),
              activeTab == .all || activeTab == kind,
              loadedTabs.contains(activeTab), !isLoading, !loadingCards.contains(kind),
              let page = cardPages[kind], page.hasMore else { return }
        let request = generation
        let limit = activeTab == .all ? 10 : 50
        let type: NeteaseAPI.SearchType = kind == .artists ? .artists : kind == .albums ? .albums : .playlists
        loadingCards.insert(kind)
        cardErrors[kind] = nil
        defer { if generation == request { loadingCards.remove(kind) } }
        do {
            let result = try await search(query.trimmingCharacters(in: .whitespacesAndNewlines), type, limit, page.offset)
            guard !Task.isCancelled, generation == request, tab == activeTab else { return }
            let count: Int
            let total: Int?
            let added: Int
            switch kind {
            case .artists:
                count = result.artists?.count ?? 0; total = result.artistCount
                added = Self.appendUnique(result.artists ?? [], to: &artists)
            case .albums:
                count = result.albums?.count ?? 0; total = result.albumCount
                added = Self.appendUnique(result.albums ?? [], to: &albums)
            default:
                count = result.playlists?.count ?? 0; total = result.playlistCount
                added = Self.appendUnique(result.playlists ?? [], to: &playlists)
            }
            let offset = page.offset + count
            cardPages[kind] = CardPage(offset: offset,
                hasMore: added > 0 && count == limit && (total.map { offset < $0 } ?? true))
            snapshots[activeTab] = Snapshot(songs: songs, artists: artists, albums: albums,
                playlists: playlists, songOffset: songOffset, hasMoreSongs: hasMoreSongs, cardPages: cardPages)
        } catch {
            guard !Task.isCancelled, generation == request, tab == activeTab else { return }
            cardErrors[kind] = error.localizedDescription
        }
    }

    private static func appendUnique<Item: Identifiable>(_ page: [Item], to items: inout [Item]) -> Int {
        var seen = Set(items.map(\.id))
        let additions = page.filter { seen.insert($0.id).inserted }
        items += additions
        return additions.count
    }

}

struct SearchView: View {
    private var phoneLayout = PhonePageLayout()
    @StateObject private var model: SearchViewModel
    @State private var searchText: String = ""
    @State private var searchKeywords: [String] = []
    @FocusState private var searchFocused: Bool
    @Binding private var focusRequested: Bool
    #if os(iOS)
    @Environment(\.iPadChrome) private var iPadChrome
    #endif

    init(query: String, focusRequested: Binding<Bool> = .constant(false)) {
        _focusRequested = focusRequested
        _model = StateObject(wrappedValue: SearchViewModel(query: query))
        _searchText = State(initialValue: query)
    }

    var body: some View {
        searchPage
        .onSubmit(of: .search) {
            model.setQuery(searchText)
            #if os(iOS)
            if UIDevice.current.userInterfaceIdiom == .pad, iPadChrome == .legacy {
                searchFocused = false
            }
            #endif
        }
        .onChange(of: searchText) { newValue in
            model.setQuery(newValue)
        }
        .appRootNavigationTitle(searchText.isEmpty
                                ? String(localized: "探索")
                                : String(localized: "搜索：\(searchText)"))
        .task(id: "\(model.tab.rawValue):\(searchText)") {
            do { try await Task.sleep(nanoseconds: 400_000_000) } catch { return }
            await model.load(tab: model.tab)
        }
        .task(id: "\(MusicProviderContext.shared.current.rawValue):keywords:\(searchText)") {
            searchKeywords = []
            let provider = MusicProviderContext.shared.current
            let keyword = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard provider.supports(.searchSuggestions) else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let items = try await SearchKeywords.load(provider: provider, keyword: keyword)
                guard !Task.isCancelled, keyword == searchText.trimmingCharacters(in: .whitespacesAndNewlines) else { return }
                searchKeywords = Array(items.filter { $0 != keyword }.prefix(8))
            } catch { }
        }
        .overlay(alignment: .top) {
            if let error = model.errorMessage {
                ErrorStateView(message: error) { Task { await model.load(tab: model.tab) } }
            }
        }
    }

    @ViewBuilder
    private var searchPage: some View {
        if phoneLayout.isEnabled {
            // The field scrolls with the page instead of living in the tab bar.
            searchContent
        } else {
            #if os(iOS)
            searchContent
            #else
            VStack(spacing: 0) {
                inlineSearchField
                    .padding(.horizontal, Theme.Layout.contentInset)
                    .pageHeaderTopPadding(8)
                    .padding(.bottom, Theme.Spacing.component)
                searchContent
            }
            #endif
        }
    }

    private var inlineSearchField: some View {
        HStack(spacing: Theme.Spacing.small) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("搜索歌曲、歌手、专辑、歌单", text: $searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                #if os(iOS)
                .submitLabel(.search)
                .textInputAutocapitalization(.never)
                #endif
                .autocorrectionDisabled()
                .onSubmit { searchFocused = false }
                .accessibilityLabel("搜索歌曲、歌手、专辑、歌单")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("清除搜索")
            }
        }
        .padding(.leading, Theme.Spacing.component)
        .padding(.trailing, searchText.isEmpty ? 16 : 4)
        .frame(minHeight: 48)
        .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("iPadSearchBar")
        .task(id: focusRequested) {
            guard focusRequested else { return }
            // Only a sidebar click requests focus. Consume it once the field is
            // visible so returning from a pushed destination cannot replay it.
            await Task.yield()
            guard !Task.isCancelled, focusRequested else { return }
            focusRequested = false
            searchFocused = true
        }
        .onDisappear { searchFocused = false }
    }

    @ViewBuilder
    private var searchContent: some View {
        mixedResults
    }

    private var mixedResults: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                #if os(iOS)
                if UIDevice.current.userInterfaceIdiom == .pad || phoneLayout.isEnabled {
                    inlineSearchField
                        .padding(.horizontal, phoneLayout.contentInset)
                        .pageHeaderTopPadding(8)
                }
                #else
                if phoneLayout.isEnabled {
                    inlineSearchField
                        .padding(.horizontal, phoneLayout.contentInset)
                        .pageHeaderTopPadding(8)
                }
                #endif
                if !searchKeywords.isEmpty {
                    keywordChips
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("searchKeywordChips")
                        .accessibilityLabel(searchText.isEmpty ? "热搜" : "搜索建议")
                }
                if !searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                    tabPicker

                    Group {
                        if model.isLoading && currentEmpty {
                            if model.tab == .all || model.tab == .songs {
                                MusicLibraryLoadingView(rowsPerColumn: 7, scrollsHorizontally: model.tab == .all,
                                                        showsHorizontalPanel: searchSongsShowPanel)
                            } else {
                                ProgressView().frame(maxWidth: .infinity, minHeight: 300)
                            }
                        } else {
                            tabContent
                        }
                    }
                    .contentCrossfade(on: model.tab)
                    .loadingCrossfade(model.isLoading && currentEmpty)
                } else {
                    // 探索 has no separate 精选 page in any layout: browse here.
                    ExploreShelves()
                }
                PlayerClearanceSpacer()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Shared scrolling gives the row room for a finger's contact radius on
    /// iPadOS 16; the minimum width and spacing keep one finger contact from
    /// also covering the neighbouring chip, which iOS 16 resolves as no tap.
    private var keywordChips: some View {
        ScenePreservingScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(searchKeywords, id: \.self) { keyword in
                    Button { applyKeyword(keyword) } label: {
                        Text(keyword).frame(minWidth: 52)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(.horizontal, Theme.Layout.contentInset)
        }
    }

    /// End text input before replacing the query: an active iPad input
    /// session can otherwise keep its own text and swallow the chip tap.
    private func applyKeyword(_ keyword: String) {
        searchFocused = false
        searchText = keyword
        model.setQuery(keyword)
    }

    private var tabPicker: some View {
        Picker("", selection: $model.tab) {
            ForEach(SearchViewModel.Tab.allCases.filter { SearchViewModel.supports($0, provider: MusicProviderContext.shared.current) }) { tab in
                Text(LocalizedStringKey(tab.rawValue)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, Theme.Layout.contentInset)
        .padding(.top, Theme.Spacing.control)
    }

    private var currentEmpty: Bool {
        switch model.tab {
        case .all: return model.songs.isEmpty && model.artists.isEmpty
        case .songs: return model.songs.isEmpty
        case .artists: return model.artists.isEmpty
        case .albums: return model.albums.isEmpty
        case .playlists: return model.playlists.isEmpty
        }
    }

    @ViewBuilder
    private func songResults(_ tracks: [Track]) -> some View {
        MusicTrackPanel(tracks: tracks, onLastTrackAppear: requestMoreSongs)
    }

    private func requestMoreSongs() {
        guard model.songPageError == nil else { return }
        Task { await model.loadMoreSongs() }
    }

    @ViewBuilder
    private var songPageFooter: some View {
        if model.isLoadingMoreSongs, model.tab == .songs {
            MusicLibraryLoadingView(rowsPerColumn: 2)
        } else if model.songPageError != nil {
            Button("加载更多失败，点击重试") {
                Task { await model.loadMoreSongs() }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var searchSongsShowPanel: Bool { !phoneLayout.isEnabled }

    @ViewBuilder
    private var tabContent: some View {
        switch model.tab {
        case .all:
            if !model.songs.isEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    SectionHeader(title: "单曲") {
                        model.tab = .songs
                    }
                    .padding(.horizontal, Theme.Layout.contentInset)
                    MusicTrackPanel(tracks: model.songs, scrollsHorizontally: true,
                                    showsHorizontalPanel: searchSongsShowPanel,
                                    horizontalLoading: .init(hasMore: model.hasMoreSongs,
                                        isLoading: model.isLoadingMoreSongs, error: model.songPageError,
                                        loadMore: { await model.loadMoreSongs() }))
                }
            }
            if !model.artists.isEmpty {
                Shelf(title: "歌手", seeAll: { model.tab = .artists },
                      itemCount: model.artists.count, resetKey: model.artists.first?.id,
                      loading: model.horizontalLoading(for: .artists), circularCover: true, cardWidth: 140) { visibleCount in
                    artistCards(model.artists.prefix(visibleCount))
                }
            }
            if !model.albums.isEmpty {
                Shelf(title: "专辑", seeAll: { model.tab = .albums },
                      itemCount: model.albums.count, resetKey: model.albums.first?.id,
                      loading: model.horizontalLoading(for: .albums)) { visibleCount in
                    albumCards(model.albums.prefix(visibleCount))
                }
            }
            if !model.playlists.isEmpty {
                Shelf(title: "歌单", seeAll: { model.tab = .playlists },
                      itemCount: model.playlists.count, resetKey: model.playlists.first?.id,
                      loading: model.horizontalLoading(for: .playlists)) { visibleCount in
                    playlistCards(model.playlists.prefix(visibleCount))
                }
            }
            if currentEmpty, !model.isLoading {
                EmptyStateView(icon: "magnifyingglass", title: "没有找到相关结果")
                    .frame(minHeight: 300)
            }
        case .songs:
            songResults(model.songs)
            songPageFooter
        case .artists:
            CardGrid(minWidth: 140, fixedColumnWidth: false) {
                artistCards(model.artists)
            }
            .padding(.horizontal, Theme.Layout.contentInset)
        case .albums:
            CardGrid {
                albumCards(model.albums)
            }
            .padding(.horizontal, Theme.Layout.contentInset)
        case .playlists:
            CardGrid {
                playlistCards(model.playlists)
            }
            .padding(.horizontal, Theme.Layout.contentInset)
        }
    }

    private func artistCards(_ items: some Collection<ArtistSummary>) -> some View {
        ForEach(Array(items)) { artist in
            // Use the shared route so pushed pages receive iPad clearance,
            // the back row, and navigation-path lifecycle handling.
            NavigationLink(value: Destination.artist(artist.id)) {
                VStack(spacing: Theme.Spacing.small) {
                    CachedAsyncImage(url: artist.picUrl?.resizedImageURL(256))
                        .frame(width: 128, height: 128)
                        .clipShape(Circle())
                    Text(artist.name)
                        .font(Theme.Typography.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }
                .frame(width: 140)
            }
            .buttonStyle(.plain)
        }
    }

    private func albumCards(_ items: some Collection<AlbumSummary>) -> some View {
        ForEach(Array(items)) { album in
            NavigationLink(value: Destination.album(album.id)) {
                CoverCardBody(
                    coverURL: album.picUrl?.resizedImageURL(384),
                    title: album.name,
                    subtitle: album.artistName
                )
            }
            .buttonStyle(.plain)
        }
    }

    private func playlistCards(_ items: some Collection<PlaylistSummary>) -> some View {
        ForEach(Array(items)) { playlist in
            NavigationLink(value: Destination.playlist(playlist.id)) {
                PlaylistCoverCard(playlist: playlist)
            }
            .buttonStyle(.plain)
        }
    }
}
