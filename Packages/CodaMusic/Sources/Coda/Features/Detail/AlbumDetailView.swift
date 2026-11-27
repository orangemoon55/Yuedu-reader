import SwiftUI

struct AlbumDetailView: View {
    let albumID: Int

    @State private var album: AlbumDetail?
    @State private var tracks: [Track] = []
    @StateObject private var otherAlbumPages = HorizontalPageSource<AlbumSummary>(pageSize: 12)
    @State private var otherAlbumArtistID: Int?
    private var otherAlbums: [AlbumSummary] { otherAlbumPages.items.filter { $0.id != albumID } }
    @State private var isSubscribed = false
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showFullDescription = false
    @State private var refreshGate = PanelRefreshGate()
    @State private var authentication: String?
    @State private var filter = ""
    @State private var searchFocused = false
    @State private var isSubscribing = false
    @ObservedObject private var downloads = DownloadManager.shared

    private let player = PlayerService.shared
    @EnvironmentObject private var account: AccountStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme

    private var isCompact: Bool { phoneLayout.isEnabled }

    var phoneLayout = PhonePageLayout()
    private var usesPlaylistStyle: Bool { phoneLayout.isEnabled }

    private var displayedTracks: [Track] {
        let query = filter.trimmingCharacters(in: .whitespacesAndNewlines)
        return tracks.filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.artistNames.localizedCaseInsensitiveContains(query)
                || $0.album.name.localizedCaseInsensitiveContains(query)
        }
    }

    /// Only a collection with songs to show may replace the online page,
    /// otherwise an empty list would hide the error and its retry button.
    private var savedCollectionID: String? {
        let id = "album:\(albumID)"
        return downloads.downloadedSongs(in: id).isEmpty ? nil : id
    }

    var body: some View {
        Group {
            if let savedCollectionID, !downloads.network.connected || errorMessage != nil {
                DownloadedMusicView(collectionID: savedCollectionID)
            } else { onlineContent }
        }
        .panelRefresh(key: "album:\(albumID):\(account.libraryRevision):\(MusicProviderContext.shared.authenticationKey ?? "guest")") { force in
            if downloads.network.connected || savedCollectionID == nil { await load(force: force) }
        }
        .safeAreaInset(edge: .top) {
            PanelRefreshFailure(message: album == nil || savedCollectionID != nil ? nil : errorMessage) {
                Task { await load() }
            }
        }
        .toolbar {
            if errorMessage != nil, downloads.network.connected, album != nil || savedCollectionID != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("重试")
                        .help("重试")
                }
            }
        }
    }

    private var otherAlbumLoading: HorizontalPageLoading {
        otherAlbumPages.loading { limit, offset in
            guard let id = otherAlbumArtistID else { return .init(items: [], hasMore: false) }
            let result = try await NeteaseAPI.artistAlbums(id: id, limit: limit, offset: offset)
            return .init(items: result.hotAlbums, hasMore: result.more ?? (result.hotAlbums.count == limit))
        }
    }

    private var onlineContent: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if let album {
                    albumHeader(album)
                } else if isLoading {
                    loadingHeader
                    MusicLibraryLoadingView(rowsPerColumn: usesPlaylistStyle ? 6 : 7,
                                            scrollsHorizontally: !usesPlaylistStyle,
                                            showsHorizontalPanel: !usesPlaylistStyle)
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                        .frame(minHeight: 400)
                }
                if !tracks.isEmpty {
                    MusicTrackPanel(tracks: displayedTracks,
                                    scrollsHorizontally: !usesPlaylistStyle,
                                    showsHorizontalPanel: !usesPlaylistStyle,
                                    source: .album(albumID),
                                              context: album.map { .album(id: albumID, name: $0.name) })
                }
                VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                    if !otherAlbums.isEmpty {
                        SectionHeader(title: "该歌手的其他专辑")
                            .padding(.horizontal, Theme.Layout.contentInset)
                            .padding(.top, Theme.Spacing.control)

                        ProfileDetailCoverShelf(itemCount: otherAlbums.count, resetKey: albumID, loading: otherAlbumLoading) { visibleCount in
                            ForEach(otherAlbums.prefix(visibleCount)) { item in
                                NavigationLink(value: Destination.album(item.id)) {
                                    CoverCardBody(coverURL: item.picUrl?.resizedImageURL(384),
                                                  title: item.name,
                                                  subtitle: Formatters.date(fromMS: item.publishTime))
                                }
                                .buttonStyle(.interactiveCard)
                            }
                        }
                    }
                    PlayerClearanceSpacer()
                }
            }
        }
        .loadingCrossfade(album == nil && isLoading)
        .musicLibraryArtworkBackground(album?.picUrl)
        .musicLibraryNavigationTitle(album?.name ?? String(localized: "专辑"), enabled: true)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private func load(force: Bool = true) async {
        guard !isSubscribing else { return }
        let binding = MusicProviderContext.shared.authenticationKey
        if authentication != binding {
            authentication = binding; isSubscribed = false
            otherAlbumPages.replace([], hasMore: false)
            otherAlbumArtistID = nil
        }
        let key = "\(albumID):\(binding ?? "guest"):\(account.libraryRevision):\(downloads.network.connected)"
        guard let ticket = refreshGate.begin(key: key, lifetime: 300, force: force) else { return }
        var success = false
        otherAlbumPages.invalidate()
        isLoading = album == nil
        errorMessage = nil
        defer {
            if refreshGate.isCurrent(ticket) { isLoading = false }
            refreshGate.finish(ticket, success: success)
        }
        do {
            let response = try await NeteaseAPI.album(id: albumID)
            guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
            album = response.album
            tracks = response.songs
            if account.provider != .qq { isLoading = false }
            if account.provider == .qq { isSubscribed = account.likedAlbums.contains { $0.id == albumID } }
            if account.provider == .qishui, account.isLoggedIn {
                await account.refreshSublists(force: force)
                guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
                isSubscribed = account.likedAlbums.contains { $0.id == albumID }
            } else if account.provider.supports(.collectionAlbums), account.isLoggedIn, let dynamic = try? await NeteaseAPI.albumDynamic(id: albumID) {
                guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
                isSubscribed = dynamic.isSub ?? false
            }
            isLoading = false
            if let artistID = response.album.artist?.id,
               let albums = try? await NeteaseAPI.artistAlbums(id: artistID, limit: 12) {
                guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
                otherAlbumArtistID = artistID
                otherAlbumPages.replace(albums.hotAlbums, hasMore: albums.more ?? (albums.hotAlbums.count == 12))
            }
            success = refreshGate.accepts(ticket) && binding == MusicProviderContext.shared.authenticationKey
        } catch {
            guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func albumHeader(_ album: AlbumDetail) -> some View {
        PlaylistHeader(
            artworkURL: album.picUrl, title: album.name,
            subtitle: album.artist?.name ?? String(localized: "专辑"),
            avatarURL: album.artist?.picUrl,
            metadataText: album.publishTime > 0 ? "\(tracks.count) 首歌曲 · \(totalDuration) · \(Formatters.date(fromMS: album.publishTime))" : "\(tracks.count) 首歌曲 · \(totalDuration)",
            filter: $filter, searchFocused: $searchFocused,
            searchPlaceholder: String(localized: "在专辑中搜索")
        ) {
            PlaylistPrimaryActions(
                isSaved: isSubscribed, canSave: account.provider.supports(.collectionAlbums) && account.isLoggedIn && !isLoading,
                canPlay: !displayedTracks.isEmpty, isSaving: isSubscribing,
                onToggleSaved: toggleSubscribe,
                onPlayAll: {
                    player.play(tracks: displayedTracks, source: .album(albumID),
                                context: .album(id: albumID, name: album.name))
                },
                saveAccessibilityLabel: isSubscribed ? String(localized: "取消收藏专辑") : String(localized: "收藏专辑"),
                saveAccessibilityIdentifier: "albumSubscribe"
            ) {
                Menu {
                    if let artist = album.artist {
                        NavigationLink(value: Destination.artist(artist.id)) {
                            Label("查看歌手", systemImage: "person.fill")
                        }
                    }
                    if let description = album.description, !description.isEmpty {
                        Button { showFullDescription = true } label: {
                            Label("专辑简介", systemImage: "text.alignleft")
                        }
                    }
                    DownloadCollectionButton(tracks: tracks, owner: "album:\(albumID)",
                                             name: album.name, menuPresentation: true)
                } label: { PlaylistMoreLabel() }
                .accessibilityLabel("更多操作")
                .accessibilityIdentifier("albumMoreActions")
            }
        }
        .sheet(isPresented: $showFullDescription) {
            NavigationStack {
                ScenePreservingScrollView {
                    Text(album.description ?? "").padding(Theme.Spacing.phonePage)
                }
                .navigationTitle("专辑简介")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") { showFullDescription = false }
                    }
                }
            }
        }
    }

    private var totalDuration: String {
        let totalMS = tracks.reduce(into: 0) { $0 += $1.durationMS }
        return Formatters.longDuration(TimeInterval(totalMS) / 1000)
    }

    private func toggleSubscribe() {
        guard !isSubscribing else { return }
        refreshGate.invalidate()
        isSubscribing = true
        let binding = MusicProviderContext.shared.authenticationKey
        let target = !isSubscribed
        Task {
            defer { isSubscribing = false }
            do {
                try await NeteaseAPI.subscribeAlbum(id: albumID, subscribe: target)
                guard binding == MusicProviderContext.shared.authenticationKey else { return }
                isSubscribed = target
                ToastCenter.shared.show(isSubscribed ? String(localized: "已收藏专辑") : String(localized: "已取消收藏"))
                if account.provider == .qishui || account.provider == .qq { await account.refreshSublists() }
            } catch {
                guard binding == MusicProviderContext.shared.authenticationKey else { return }
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    private var loadingHeader: some View {
        MusicLibraryHeaderSkeleton()
    }
}
