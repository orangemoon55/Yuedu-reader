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
        guard provider.supports(feature) else {
            return .init(songs: nil, albums: nil, artists: nil, playlists: nil, songCount: nil, albumCount: nil, artistCount: nil, playlistCount: nil)
        }
        return try await searchCurrentProvider(keyword, type, limit, offset)
    }

    // Card destinations still use the active platform's IDs. Never obtain
    // cards by temporarily changing the shared provider for a scope chip.
    private(set) var provider = MusicProviderContext.shared.current

    private func searchCurrentProvider(_ keyword: String, _ type: NeteaseAPI.SearchType,
                                       _ limit: Int, _ offset: Int) async throws -> NeteaseAPI.SearchResult {
        let expectedProvider = provider
        let ticket = MusicProviderContext.shared.ticket
        guard MusicProviderContext.shared.current == expectedProvider else { throw CancellationError() }
        let result = try await search(keyword, type, limit, offset)
        try MusicProviderContext.shared.check(ticket)
        guard provider == expectedProvider else { throw CancellationError() }
        return result
    }

    func setProvider(_ provider: MusicProvider) {
        guard self.provider != provider else { return }
        self.provider = provider
        setQuery(query, force: true)
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

    func setQuery(_ newQuery: String, force: Bool = false) {
        guard force || newQuery != query else { return }
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
                let result = try await searchCurrentProvider(trimmed, type, tab == .songs ? 100 : 50, 0)
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
            let result = try await searchCurrentProvider(keyword, .songs, limit, offset)
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
            let result = try await searchCurrentProvider(query.trimmingCharacters(in: .whitespacesAndNewlines), type, limit, page.offset)
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
    @StateObject private var songModel = CodaProviderSongSearchModel()
    @State private var scope: CodaSongSearchScope = .all
    @State private var searchText: String = ""
    @State private var searchKeywords: [String] = []
    @State private var loadedSongRequest: String?
    @State private var loadedCardRequest: String?
    @State private var cardSession: UUID?
    @State private var showSettings = false
    @ObservedObject private var musicAccounts = MusicAccountManager.shared
    @State private var providerSwitchTask: Task<Void, Never>?
    @State private var providerSwitchGeneration = UUID()
    @State private var switchingProvider: MusicProvider?
    @State private var switchFailureProvider: MusicProvider?
    @State private var switchFailureMessage: String?
    @FocusState private var searchFocused: Bool
    @Binding private var focusRequested: Bool
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openDestination) private var openDestination

    init(query: String, focusRequested: Binding<Bool> = .constant(false)) {
        _focusRequested = focusRequested
        let cards = SearchViewModel(query: query)
        cards.tab = .songs
        _model = StateObject(wrappedValue: cards)
        _searchText = State(initialValue: query)
    }

    private var keyword: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isCurrentProviderScope: Bool {
        scope.providers == [account.provider] && account.provider == MusicProviderContext.shared.current
    }
    private var resultKey: String {
        "\(account.sessionRevision):\(account.provider.rawValue):\(scope.rawValue):\(model.tab.rawValue):\(searchText)"
    }
    private var categoryTabs: [SearchViewModel.Tab] {
        [.songs, .artists, .albums, .playlists].filter { supportsCategory($0) }
    }

    private func supportsCategory(_ tab: SearchViewModel.Tab) -> Bool {
        tab == .songs || (isCurrentProviderScope && SearchViewModel.supports(tab, provider: account.provider))
    }

    var body: some View {
        VStack(spacing: 0) {
            searchHeader
            mixedResults
        }
        .appRootNavigationTitle(String(localized: "搜索"))
        .onChange(of: searchText) {
            cancelProviderSwitch()
            model.setQuery($0)
        }
        .onChange(of: scope) { _ in
            cancelProviderSwitch()
            if !supportsCategory(model.tab) { model.tab = .songs }
        }
        .onDisappear { cancelProviderSwitch() }
        .onChange(of: account.provider) { provider in
            model.setProvider(provider)
            if !supportsCategory(model.tab) { model.tab = .songs }
        }
        .task(id: resultKey) { await loadResults() }
        .task(id: "\(resultKey):keywords") {
            searchKeywords = []
            // Suggestions also belong to a single platform, not an aggregate.
            let provider = account.provider
            let query = keyword
            guard !isUIFixture, isCurrentProviderScope, provider.supports(.searchSuggestions) else { return }
            do {
                try await Task.sleep(for: .milliseconds(250))
                let items = try await SearchKeywords.load(provider: provider, keyword: query)
                guard !Task.isCancelled, query == keyword, isCurrentProviderScope,
                      provider == account.provider else { return }
                searchKeywords = Array(items.filter { $0 != query }.prefix(8))
            } catch { }
        }
        .sheet(isPresented: $showSettings) {
            // Same native destination and routing as LibraryView. Embedded
            // SettingsView retains the host's simplified settings policy.
            NavigationStack {
                SettingsView()
                    .navigationTitle("设置")
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showSettings = false }
                        }
                    }
            }
            .environment(\.openDestination, { destination in
                showSettings = false
                openDestination(destination)
            })
        }
    }

    private func loadResults() async {
        let request = resultKey
        let query = keyword
        let selectedScope = scope
        let tab = model.tab
        loadedSongRequest = nil
        loadedCardRequest = nil
        model.setProvider(account.provider)
        model.setQuery(searchText, force: cardSession != account.sessionRevision)
        cardSession = account.sessionRevision
        guard !query.isEmpty else { return }
        do { try await Task.sleep(for: .milliseconds(400)) } catch { return }
        guard !Task.isCancelled, request == resultKey else { return }
        if tab == .songs {
            if !isUIFixture { await songModel.load(query: query, scope: selectedScope) }
            guard !Task.isCancelled, request == resultKey else { return }
            loadedSongRequest = request
        } else {
            guard isCurrentProviderScope, supportsCategory(tab) else { return }
            await model.load(tab: tab)
            guard !Task.isCancelled, request == resultKey else { return }
            loadedCardRequest = request
        }
    }

    // This header is a sibling of the result scroll view on every layout.
    // No nested scroll/header overlay can move or cover the keyword field.
    private var searchHeader: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            HStack(spacing: Theme.Spacing.small) {
                inlineSearchField
                Button {
                    searchFocused = false
                    showSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("设置")
                .accessibilityIdentifier("codaSearch.settings")
            }
            .padding(.horizontal, phoneLayout.contentInset)
            providerChips
            Text(scopeExplanation)
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, phoneLayout.contentInset)
                .accessibilityIdentifier("codaSearch.scopeExplanation")
        }
        .pageHeaderTopPadding(8)
        .padding(.bottom, Theme.Spacing.control)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codaSearch.header")
    }

    private var scopeExplanation: String {
        if scope == .all {
            return "全源聚合仅搜索单曲；歌手、专辑、歌单请先选择当前音乐平台。"
        }
        if !isCurrentProviderScope {
            return "\(scope.title) · 单曲搜索。其他分类需先在「账户」切换到此平台；当前平台为\(account.provider.name)。"
        }
        return "\(scope.title) · \(model.tab.rawValue)；歌手、专辑、歌单仅在当前音乐平台搜索。"
    }

    private var providerChips: some View {
        ScenePreservingScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.small) {
                ForEach(CodaSongSearchScope.allCases) { item in
                    Button {
                        searchFocused = false
                        scope = item
                    } label: {
                        Text(item.title)
                            .font(Theme.Typography.secondary.weight(.medium))
                            .padding(.horizontal, Theme.Spacing.small)
                            .frame(minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(scope == item ? Theme.accent : Color.secondary)
                    .accessibilityAddTraits(scope == item ? .isSelected : [])
                    .accessibilityValue(scope == item ? "已选择" : "未选择")
                    .accessibilityIdentifier("codaSearch.scope.\(item.rawValue)")
                }
            }
            .padding(.horizontal, phoneLayout.contentInset)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("codaSearch.providerChips")
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
                .accessibilityIdentifier("codaSearch.keyword")
            Picker("搜索类型", selection: $model.tab) {
                ForEach(categoryTabs) { tab in
                    Text(LocalizedStringKey(tab.rawValue))
                        .tag(tab)
                        .disabled(!supportsCategory(tab))
                }
            }
            .pickerStyle(.menu)
            .fixedSize()
            .accessibilityIdentifier("codaSearch.category")
            .accessibilityValue(model.tab.rawValue)
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
                .accessibilityIdentifier("codaSearch.clear")
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

    private var mixedResults: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if !searchKeywords.isEmpty, isCurrentProviderScope, !isUIFixture {
                    keywordChips
                        .accessibilityElement(children: .contain)
                        .accessibilityIdentifier("searchKeywordChips")
                        .accessibilityLabel(keyword.isEmpty ? "热搜" : "搜索建议")
                }
                if keyword.isEmpty {
                    if scope == .all || isCurrentProviderScope {
                        // Browse shelves remain Coda's native, current-platform
                        // content. They are not presented as aggregate results.
                        SectionHeader(title: LocalizedStringKey("\(account.provider.name) · 精选"))
                            .padding(.horizontal, phoneLayout.contentInset)
                        ExploreShelves()
                    } else {
                        EmptyStateView(icon: "magnifyingglass", title: "输入关键词搜索此平台的单曲")
                            .frame(minHeight: 220)
                    }
                } else if model.tab == .songs {
                    providerSongResults
                } else if isCurrentProviderScope && supportsCategory(model.tab) {
                    singleProviderResults
                } else {
                    EmptyStateView(icon: "magnifyingglass", title: "此来源仅支持单曲搜索")
                        .frame(minHeight: 220)
                }
                PlayerClearanceSpacer()
            }
            .padding(.top, Theme.Spacing.control)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityIdentifier("codaSearch.resultsScroll")
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

    private var visibleSongTracks: [Track] {
        guard loadedSongRequest == resultKey else { return [] }
        #if DEBUG
        if isUIFixture {
            return scope.providers.flatMap { provider in
                (0..<8).map { index in
                    let source = ProviderSongSource(rawValue: provider.rawValue) ?? .netease
                    let id = -910_000 - (MusicProvider.allCases.firstIndex(of: provider) ?? 0) * 100 - index
                    let song = ProviderSong(id: id, name: "本地界面样例 \(index + 1)", artists: "UI 测试",
                                            album: "非网络结果", coverURL: nil, duration: 60, source: source)
                    return Track(id: id, song: song, artists: [ArtistRef(id: 0, name: "UI 测试")],
                                 album: AlbumRef(id: 0, name: "非网络结果", picUrl: nil))
                }
            }
        }
        #endif
        return songModel.tracks
    }

    // Explicit DEBUG-only local layout fixture. No fake network success and
    // no registration/playback of these view-only rows; production ignores it.
    private var isUIFixture: Bool {
        #if DEBUG
        ProcessInfo.processInfo.arguments.contains("-coda-provider-search-ui-fixture")
        #else
        false
        #endif
    }

    private func trackProvider(_ track: Track) -> MusicProvider {
        // Legacy raw NetEase tracks have no platformSong. Aggregate tracks
        // carry the explicit source registered by the provider-search model.
        track.platformSong.flatMap { MusicProvider(rawValue: $0.source.rawValue) } ?? .netease
    }

    private func matchesActiveProvider(_ provider: MusicProvider) -> Bool {
        provider == account.provider && provider == MusicProviderContext.shared.current
    }

    private func canUseProviderPanel(_ provider: MusicProvider) -> Bool {
        CodaSearchInteractionPolicy.canUseNativePanel(
            source: provider, active: account.provider,
            context: MusicProviderContext.shared.current, fixture: isUIFixture,
            switching: musicAccounts.isSwitching || switchingProvider != nil)
    }

    private func providerPanelState(_ provider: MusicProvider) -> String {
        if !matchesActiveProvider(provider) { return "需切换平台" }
        if isUIFixture { return "本地测试禁止操作" }
        return canUseProviderPanel(provider) ? "当前平台可操作" : "平台切换中"
    }

    private func cancelProviderSwitch() {
        providerSwitchGeneration = UUID()
        providerSwitchTask?.cancel()
        providerSwitchTask = nil
        switchingProvider = nil
        switchFailureProvider = nil
        switchFailureMessage = nil
    }

    private func selectSearchProvider(_ provider: MusicProvider) {
        // Registration is metadata only, not permission to play/write against
        // another account. Only this explicit user action activates a platform.
        guard !isUIFixture, !matchesActiveProvider(provider) else { return }
        cancelProviderSwitch()
        guard !musicAccounts.isSwitching else {
            switchFailureProvider = provider
            switchFailureMessage = "其他平台切换正在进行，请稍后重试。"
            return
        }
        let request = UUID()
        let session = account.sessionRevision
        let ticket = MusicProviderContext.shared.ticket
        providerSwitchGeneration = request
        switchingProvider = provider
        providerSwitchTask = Task { @MainActor in
            defer {
                if providerSwitchGeneration == request {
                    providerSwitchTask = nil
                    switchingProvider = nil
                }
            }
            do {
                try Task.checkCancellation()
                guard providerSwitchGeneration == request, account.sessionRevision == session,
                      MusicProviderContext.shared.ticket == ticket else { return }
                try await musicAccounts.selectProvider(provider)
                try Task.checkCancellation()
                guard providerSwitchGeneration == request else { return }
                guard matchesActiveProvider(provider) else {
                    switchFailureProvider = provider
                    switchFailureMessage = "平台未完成切换，请重试。"
                    return
                }
                // No automatic play, next-track insertion or queue edits here.
                // Normal activation owns its reset; the session key reloads the
                // existing query/scope, including all four aggregate sources.
            } catch is CancellationError {
                // Cancellation cannot roll back a normal activation which has
                // already committed; it only discards this UI continuation.
            } catch {
                guard !Task.isCancelled, providerSwitchGeneration == request else { return }
                switchFailureProvider = provider
                switchFailureMessage = "切换平台失败，请重试或在账户中检查登录状态。"
            }
        }
    }

    @ViewBuilder
    private func providerInteractionNotice(_ provider: MusicProvider) -> some View {
        if !matchesActiveProvider(provider) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                Text("切换到此平台后播放、收藏和查看详情")
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("codaSearch.readOnlyHint.\(provider.rawValue)")
                Text("切换平台将停止当前播放并重置当前队列。")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                Button("切换到\(provider.name)") { selectSearchProvider(provider) }
                    .buttonStyle(.bordered)
                    .disabled(isUIFixture || switchingProvider != nil || musicAccounts.isSwitching)
                    .accessibilityIdentifier("codaSearch.switchProvider.\(provider.rawValue)")
                if switchingProvider == provider {
                    ProgressView("正在切换平台…")
                        .accessibilityIdentifier("codaSearch.switchProgress.\(provider.rawValue)")
                }
                if switchFailureProvider == provider, let message = switchFailureMessage {
                    Text(message)
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("codaSearch.switchFailure.\(provider.rawValue)")
                }
            }
            .padding(.horizontal, phoneLayout.contentInset)
        } else if musicAccounts.isSwitching || switchingProvider != nil {
            ProgressView("正在更新平台账号…")
                .padding(.horizontal, phoneLayout.contentInset)
                .accessibilityIdentifier("codaSearch.switchProgress.\(provider.rawValue)")
        }
    }

    @ViewBuilder
    private var providerSongResults: some View {
        if loadedSongRequest != resultKey || (songModel.isLoading && visibleSongTracks.isEmpty) {
            MusicLibraryLoadingView(rowsPerColumn: 7)
                .accessibilityIdentifier("codaSearch.loading")
        } else {
            if isUIFixture {
                Text("本地 UI 测试数据（非网络结果，禁止播放）")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, phoneLayout.contentInset)
                    .accessibilityIdentifier("codaSearch.localFixture")
            }
            if !isUIFixture, let failure = songModel.failureMessage {
                VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                    Text(visibleSongTracks.isEmpty ? "搜索未完成" : "部分平台搜索失败，已保留其他平台结果")
                        .font(Theme.Typography.body.weight(.medium))
                    Text(failure).font(Theme.Typography.secondary).foregroundStyle(.secondary)
                    Button("重试失败平台") { Task { await songModel.retryFailures() } }
                        .buttonStyle(.bordered)
                        .disabled(songModel.isLoading || songModel.isLoadingMore)
                        .accessibilityIdentifier("codaSearch.retryFailures")
                }
                .padding(.horizontal, phoneLayout.contentInset)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("codaSearch.failure")
            }
            ForEach(scope.providers) { provider in
                let tracks = visibleSongTracks.filter { trackProvider($0) == provider }
                if !tracks.isEmpty {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        Text(provider.name)
                            .font(Theme.Typography.sectionTitle)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityIdentifier("codaSearch.providerLabel.\(provider.rawValue)")
                            .padding(.horizontal, phoneLayout.contentInset)
                        providerInteractionNotice(provider)
                        // The entire native subtree must be inert for foreign
                        // sources: row taps, artwork, menus, likes, playlists,
                        // downloads and artist/album navigation all assume the
                        // active provider. Never weaken the player guards.
                        MusicTrackPanel(tracks: tracks, trailingText: { _ in provider.name })
                            .disabled(!canUseProviderPanel(provider))
                            .allowsHitTesting(canUseProviderPanel(provider))
                            .accessibilityElement(children: .contain)
                            .accessibilityValue(providerPanelState(provider))
                            .accessibilityIdentifier("codaSearch.results.\(provider.rawValue)")
                    }
                }
            }
            if visibleSongTracks.isEmpty, songModel.failureMessage == nil {
                EmptyStateView(icon: "magnifyingglass", title: "没有找到相关单曲")
                    .frame(minHeight: 260)
                    .accessibilityIdentifier("codaSearch.empty")
            }
            if !isUIFixture {
                if songModel.isLoading || songModel.isLoadingMore {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("codaSearch.loadingMore")
                } else if songModel.hasMore {
                    Button("加载更多单曲") { Task { await songModel.loadMore() } }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("codaSearch.loadMore")
                }
            }
        }
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
    private var singleProviderResults: some View {
        if loadedCardRequest != resultKey || model.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 240)
                .accessibilityIdentifier("codaSearch.loading")
        } else if let error = model.errorMessage {
            ErrorStateView(message: error) {
                Task {
                    let request = resultKey
                    guard isCurrentProviderScope else { return }
                    await model.load(tab: model.tab)
                    guard !Task.isCancelled, request == resultKey else { return }
                    loadedCardRequest = request
                }
            }
            .accessibilityIdentifier("codaSearch.failure")
        } else if currentEmpty {
            EmptyStateView(icon: "magnifyingglass", title: "没有找到相关结果")
                .frame(minHeight: 260)
                .accessibilityIdentifier("codaSearch.empty")
        } else {
            Text("\(account.provider.name) · \(model.tab.rawValue)")
                .font(Theme.Typography.sectionTitle)
                .padding(.horizontal, phoneLayout.contentInset)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("codaSearch.cardProviderLabel")
            cardResults
            cardPageFooter
        }
    }

    @ViewBuilder
    private var cardResults: some View {
        switch model.tab {
        case .artists:
            CardGrid(minWidth: 140, fixedColumnWidth: false) { artistCards(model.artists) }
                .padding(.horizontal, phoneLayout.contentInset)
        case .albums:
            CardGrid { albumCards(model.albums) }
                .padding(.horizontal, phoneLayout.contentInset)
        case .playlists:
            CardGrid { playlistCards(model.playlists) }
                .padding(.horizontal, phoneLayout.contentInset)
        case .all, .songs:
            EmptyView() // Entity aggregation is deliberately not offered.
        }
    }

    @ViewBuilder
    private var cardPageFooter: some View {
        let page = model.horizontalLoading(for: model.tab)
        if page.isLoading {
            ProgressView().frame(maxWidth: .infinity, minHeight: 44)
        } else if page.hasMore || page.error != nil {
            VStack(spacing: Theme.Spacing.small) {
                if let error = page.error {
                    Text(error).font(Theme.Typography.secondary).foregroundStyle(.secondary)
                }
                Button(page.error == nil ? "加载更多" : "加载更多失败，点击重试") {
                    Task {
                        guard isCurrentProviderScope else { return }
                        await model.loadMoreCards(model.tab)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("codaSearch.loadMoreCards")
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, phoneLayout.contentInset)
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
