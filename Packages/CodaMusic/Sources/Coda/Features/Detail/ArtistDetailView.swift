import SwiftUI

struct ArtistDetailView: View {
    let artistID: Int

    @State private var artist: ArtistSummary?
    @State private var hotSongs: [Track] = []
    @StateObject private var albumPages = HorizontalPageSource<AlbumSummary>(pageSize: 60)
    private var albums: [AlbumSummary] { albumPages.items.filter { !$0.isEPOrSingle } }
    private var epsAndSingles: [AlbumSummary] { albumPages.items.filter { $0.isEPOrSingle } }
    @State private var similar: [ArtistSummary] = []
    @State private var isFollowed = false
    @State private var isUpdatingFollow = false
    @State private var isLoadingFollow = true
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var refreshGate = PanelRefreshGate()
    @State private var authentication: String?

    private let player = PlayerService.shared
    @Environment(\.openDestination) private var openDestination
    @EnvironmentObject private var account: AccountStore
    private var layout = ProfileDetailLayout()

    private var isCompact: Bool { layout.isCompact }

    var phoneLayout = PhonePageLayout()
    private var usesPhoneHeader: Bool { phoneLayout.isEnabled }

    init(artistID: Int) {
        self.artistID = artistID
    }

    var body: some View {
        ProfileDetailPage(artworkBackdropURL: artist?.picUrl, usesArtworkBackdrop: true) {
            if let artist {
                profileHeader(artist)
                if !hotSongs.isEmpty {
                    SectionHeader(title: "热门单曲", action: {
                    openDestination(.artistSection(artistID, .songs))
                })
                        .padding(.horizontal, layout.contentInset)
                }
            } else if isLoading {
                loadingHeader
                SkeletonView(cornerRadius: 4)
                    .frame(width: 100, height: 22)
                    .padding(.horizontal, layout.contentInset)
                    .accessibilityHidden(true)
                MusicLibraryLoadingView(rowsPerColumn: 7, scrollsHorizontally: true,
                                        showsHorizontalPanel: !usesPhoneHeader)
            } else if let errorMessage {
                ErrorStateView(message: errorMessage) { Task { await load() } }
                    .frame(minHeight: 400)
            }

            if !hotSongs.isEmpty {
                hotSongsShelf
            }
            if !albums.isEmpty {
                SectionHeader(title: "专辑", action: {
                    openDestination(.artistSection(artistID, .albums))
                })
                    .padding(.horizontal, layout.contentInset)
                ProfileDetailCoverShelf(itemCount: albums.count, resetKey: artistID, loading: albumLoading) { visibleCount in
                    ForEach(albums.prefix(visibleCount)) { album in albumCard(album) }
                }
            }
            if !epsAndSingles.isEmpty {
                SectionHeader(title: "EP 与单曲", action: {
                    openDestination(.artistSection(artistID, .singles))
                })
                    .padding(.horizontal, layout.contentInset)
                ProfileDetailCoverShelf(itemCount: epsAndSingles.count, resetKey: artistID, loading: albumLoading) { visibleCount in
                    ForEach(epsAndSingles.prefix(visibleCount)) { album in albumCard(album) }
                }
            }
            if !similar.isEmpty {
                SectionHeader(title: "相似歌手", action: {
                    openDestination(.artistSection(artistID, .similar))
                })
                    .padding(.horizontal, layout.contentInset)
                ProfileDetailCoverShelf(itemCount: similar.count, resetKey: similar.first?.id) { visibleCount in
                    ForEach(similar.prefix(visibleCount)) { sim in
                        NavigationLink(value: Destination.artist(sim.id)) {
                            ProfileDetailArtistCardBody(artist: sim)
                        }
                        .buttonStyle(.interactiveCard)
                    }
                }
            }
            PlayerClearanceSpacer()
        }
        .loadingCrossfade(artist == nil && isLoading)
        .musicLibraryNavigationTitle(artist?.name ?? String(localized: "歌手"), enabled: true)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .panelRefresh(key: "artist:\(artistID):\(account.libraryRevision):\(MusicProviderContext.shared.authenticationKey ?? "guest")") {
            await load(force: $0)
        }
        .safeAreaInset(edge: .top) {
            PanelRefreshFailure(message: artist == nil ? nil : errorMessage) { Task { await load() } }
        }
    }

    private var albumLoading: HorizontalPageLoading {
        albumPages.loading { limit, offset in
            let result = try await NeteaseAPI.artistAlbums(id: artistID, limit: limit, offset: offset)
            return HorizontalRemotePage(items: result.hotAlbums,
                                        hasMore: result.more ?? (result.hotAlbums.count == limit))
        }
    }

    private var hotSongsShelf: some View {
        MusicTrackPanel(tracks: hotSongs, scrollsHorizontally: true,
                                  showsHorizontalPanel: !usesPhoneHeader, source: .artist(artistID),
                                  context: artist.map { .artist(id: artistID, name: $0.name) })
    }

    private func load(force: Bool = true) async {
        guard !isUpdatingFollow else { return }
        let binding = MusicProviderContext.shared.authenticationKey
        if authentication != binding {
            authentication = binding; isFollowed = false; similar = []
            albumPages.replace([], hasMore: false)
        }
        let key = "\(artistID):\(binding ?? "guest"):\(account.libraryRevision)"
        guard let ticket = refreshGate.begin(key: key, lifetime: 300, force: force) else { return }
        var success = false
        albumPages.invalidate()
        isLoading = artist == nil
        isLoadingFollow = true
        defer {
            if refreshGate.isCurrent(ticket) { isLoading = false; isLoadingFollow = false }
            refreshGate.finish(ticket, success: success)
        }
        errorMessage = nil
        do {
            let response = try await NeteaseAPI.artist(id: artistID)
            guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
            artist = response.artist
            hotSongs = response.hotSongs
            isFollowed = response.artist.followed || account.likedArtists.contains { $0.id == artistID }
            isLoading = false

            if account.provider == .qq, account.isLoggedIn {
                let followed = try? await PlatformMusicAPI.shared.qqArtistFollowed(id: artistID)
                guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
                if let followed { isFollowed = followed }
            } else if account.isLoggedIn {
                await account.refreshSublists(force: force)
                guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
                isFollowed = account.likedArtists.contains {
                    $0.id == artistID || (account.provider == .kugou && $0.name == response.artist.name)
                } || response.artist.followed
            }
            isLoadingFollow = false

            do {
                let result = try await NeteaseAPI.artistAlbums(id: artistID, limit: 60)
                guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
                albumPages.replace(result.hotAlbums, hasMore: result.more ?? (result.hotAlbums.count == 60))
            }
            catch { errorMessage = error.localizedDescription }
            if account.isLoggedIn && account.provider.supports(.similarArtists) {
                if let result = try? await NeteaseAPI.similarArtists(id: artistID) {
                    guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
                    similar = result
                }
            } else { similar = [] }
            success = refreshGate.accepts(ticket) && binding == MusicProviderContext.shared.authenticationKey
        } catch {
            guard refreshGate.accepts(ticket), binding == MusicProviderContext.shared.authenticationKey else { return }
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    @ViewBuilder
    private func profileHeader(_ artist: ArtistSummary) -> some View {
        detailHeader(artist)
    }

    private func detailHeader(_ artist: ArtistSummary) -> some View {
        PlaylistDetailHero(
            artworkURL: artist.picUrl,
            title: artist.name,
            subtitle: artist.alias.isEmpty ? String(localized: "歌手") : artist.alias.joined(separator: " / "),
            avatarURL: nil,
            metadataText: account.provider == .netease ? "\(artist.musicSize) 首歌曲 · \(artist.albumSize) 张专辑" : "\(hotSongs.count) 首热门歌曲",
            circularArtwork: true, showsAvatar: false
        ) {
            detailActions(artist)
        }
    }

    private func detailActions(_ artist: ArtistSummary, horizontalPadding: CGFloat? = nil) -> some View {
        PlaylistPrimaryActions(
            isSaved: isFollowed,
            canSave: account.provider.supports(.collectionArtists) && account.isLoggedIn && !isLoadingFollow,
            canPlay: !hotSongs.isEmpty,
            isSaving: isUpdatingFollow,
            onToggleSaved: toggleFollow,
            onPlayAll: {
                player.play(tracks: hotSongs, source: .artist(artistID),
                            context: .artist(id: artistID, name: artist.name))
            },
            saveAccessibilityLabel: isFollowed ? String(localized: "取消关注歌手") : String(localized: "关注歌手"),
            saveAccessibilityIdentifier: "artistFollow",
            horizontalPadding: horizontalPadding
        ) {
            Menu {
                DownloadCollectionButton(tracks: hotSongs, owner: "artist:\(artistID)",
                                         name: "\(artist.name) · 热门单曲", menuPresentation: true)
            } label: { PlaylistMoreLabel() }
            .accessibilityLabel("更多操作")
            .accessibilityIdentifier("artistMoreActions")
        }
    }
    private func albumCard(_ album: AlbumSummary) -> some View {
        NavigationLink(value: Destination.album(album.id)) {
            CoverCardBody(
                coverURL: album.picUrl?.resizedImageURL(384),
                title: album.name,
                subtitle: album.publishYear
            )
        }
        .buttonStyle(.interactiveCard)
    }

    private func toggleFollow() {
        guard !isUpdatingFollow, !isLoadingFollow, account.isLoggedIn else { return }
        refreshGate.invalidate()
        isUpdatingFollow = true
        let target = !isFollowed
        let binding = MusicProviderContext.shared.authenticationKey
        Task {
            defer { isUpdatingFollow = false }
            do {
                try await NeteaseAPI.subscribeArtist(id: artistID, subscribe: target)
                guard binding == MusicProviderContext.shared.authenticationKey else { return }
                isFollowed = target
                ToastCenter.shared.show(isFollowed ? String(localized: "已关注歌手") : String(localized: "已取消关注"))
                await account.refreshSublists()
            } catch {
                guard binding == MusicProviderContext.shared.authenticationKey else { return }
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    private var loadingHeader: some View {
        MusicLibraryHeaderSkeleton(circularCover: true)
    }
}


enum ArtistSection: String, Hashable {
    case songs, albums, singles, similar

    var title: String {
        switch self {
        case .songs: return String(localized: "热门单曲")
        case .albums: return String(localized: "专辑")
        case .singles: return String(localized: "EP 与单曲")
        case .similar: return String(localized: "相似歌手")
        }
    }
}

struct ArtistSectionView: View {
    let artistID: Int
    let section: ArtistSection
    @State private var artistName: String?
    @State private var songs: [Track] = []
    @State private var albums: [AlbumSummary] = []
    @State private var artists: [ArtistSummary] = []
    @State private var offset = 0
    @State private var hasMore = true
    @State private var isLoading = false
    @State private var didLoad = false
    @State private var error: String?

    var body: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if section == .songs {
                    MusicTrackPanel(tracks: songs, source: .artist(artistID),
                                    context: artistName.map { .artist(id: artistID, name: $0) })
                } else {
                    CardGrid {
                        if section == .similar {
                            ForEach(artists) { artist in
                                NavigationLink(value: Destination.artist(artist.id)) {
                                    ProfileDetailArtistCardBody(artist: artist)
                                }.buttonStyle(.interactiveCard)
                            }
                        } else {
                            ForEach(albums) { album in
                                NavigationLink(value: Destination.album(album.id)) {
                                    CoverCardBody(coverURL: album.picUrl?.resizedImageURL(384),
                                                  title: album.name, subtitle: album.publishYear)
                                }.buttonStyle(.interactiveCard)
                            }
                        }
                    }.padding(.horizontal, Theme.Layout.contentInset)
                }
                if isLoading {
                    if section == .songs {
                        MusicLibraryLoadingView(rowsPerColumn: songs.isEmpty ? 6 : 2)
                    } else {
                        MusicLibraryCardLoadingView(circularCover: section == .similar)
                    }
                } else if let error {
                    ErrorStateView(message: error) { Task { await loadMore() } }
                } else if hasMore {
                    Button("加载更多") { Task { await loadMore() } }
                        .frame(maxWidth: .infinity, minHeight: 44)
                } else if songs.isEmpty && albums.isEmpty && artists.isEmpty {
                    Text("暂无内容").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
                PlayerClearanceSpacer()
            }.padding(.top, Theme.Spacing.component)
        }
        .navigationTitle(section.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { if !didLoad { await loadMore() } }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            switch section {
            case .songs:
                if MusicProviderContext.shared.current == .qishui {
                    let page = try await PlatformMusicAPI.shared.qishuiArtistTracks(id: artistID, limit: 50, offset: offset)
                    try Task.checkCancellation()
                    artistName = page.name
                    songs += page.tracks
                    offset += page.tracks.count
                    hasMore = page.hasMore && !page.tracks.isEmpty
                } else {
                    let result = try await NeteaseAPI.artist(id: artistID)
                    try Task.checkCancellation()
                    artistName = result.artist.name
                    songs = result.hotSongs
                    hasMore = false
                }
            case .similar:
                let result = try await NeteaseAPI.similarArtists(id: artistID)
                try Task.checkCancellation()
                artists = result
                hasMore = false
            case .albums, .singles:
                let result = try await NeteaseAPI.artistAlbums(id: artistID, limit: 60, offset: offset)
                try Task.checkCancellation()
                let existing = Set(albums.map(\.id))
                albums += result.hotAlbums.filter {
                    !existing.contains($0.id) && (section == .albums ? !$0.isEPOrSingle : $0.isEPOrSingle)
                }
                offset += result.hotAlbums.count
                hasMore = !result.hotAlbums.isEmpty && (result.more ?? (result.hotAlbums.count == 60))
            }
            didLoad = true
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
