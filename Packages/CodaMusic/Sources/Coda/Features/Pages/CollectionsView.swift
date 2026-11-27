import SwiftUI

/// 我的收藏 — liked albums and followed artists.
struct CollectionsView: View {
    private enum Tab: String, CaseIterable, Identifiable {
        case albums = "专辑"
        case artists = "歌手"

        var id: String { rawValue }
    }

    private var trackLayout = MusicLibraryTrackLayout()
    @State private var tab: Tab = .albums
    @State private var isLoading = true

    @EnvironmentObject private var account: AccountStore

    var body: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if isLoading && account.likedAlbums.isEmpty && account.likedArtists.isEmpty {
                    MusicLibraryHeaderSkeleton(collectionHeader: true)
                } else {
                    MusicLibraryHeaderLayout(title: String(localized: "我的收藏"), icon: "heart.fill",
                                             coverURL: account.likedAlbums.first?.picUrl) {
                        Text("我的音乐")
                            .font(Theme.Typography.body.weight(.medium)).foregroundStyle(.secondary)
                    } metadata: {
                        Text("\(account.likedAlbums.count) 张专辑 · \(account.likedArtists.count) 位歌手")
                            .font(Theme.Typography.body).foregroundStyle(.secondary)
                    } actions: {
                        Picker("收藏类型", selection: $tab) {
                            ForEach(Tab.allCases.filter { account.provider.supports(.collectionAlbums) || $0 == .artists }) { tab in
                                Text(LocalizedStringKey(tab.rawValue)).tag(tab)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(maxWidth: 240)
                    }

                }

                if isLoading, account.likedAlbums.isEmpty, account.likedArtists.isEmpty {
                    MusicLibraryCardLoadingView(circularCover: tab == .artists)
                } else if let error = account.sublistsError, account.likedAlbums.isEmpty, account.likedArtists.isEmpty {
                    ErrorStateView(message: error) { Task { await account.refreshSublists() } }
                } else {
                    switch tab {
                    case .albums:
                        if account.likedAlbums.isEmpty {
                            EmptyStateView(icon: "square.stack", title: "还没有收藏专辑")
                                .frame(minHeight: 300)
                        } else {
                            CardGrid {
                                ForEach(account.likedAlbums) { album in
                                    NavigationLink(value: Destination.album(album.id)) {
                                        CoverCardBody(
                                            coverURL: album.picUrl?.resizedImageURL(384),
                                            title: album.name,
                                            subtitle: album.artistName
                                        )
                                    }
                                    .buttonStyle(.interactiveCard)
                                    .accessibilityIdentifier("collectionAlbum-\(album.id)")
                                }
                            }
                            .padding(.horizontal, Theme.Layout.contentInset)
                        }
                    case .artists:
                        if account.likedArtists.isEmpty {
                            EmptyStateView(icon: "music.microphone", title: "还没有关注歌手")
                                .frame(minHeight: 300)
                        } else {
                            CardGrid(minWidth: 140, fixedColumnWidth: false) {
                                ForEach(account.likedArtists) { artist in
                                    NavigationLink(value: Destination.artist(artist.id)) {
                                        ProfileDetailArtistCardBody(artist: artist)
                                    }
                                    .buttonStyle(.interactiveCard)
                                    .accessibilityIdentifier("collectionArtist-\(artist.id)")
                                }
                            }
                            .padding(.horizontal, Theme.Layout.contentInset)
                        }
                    }
                }
                PlayerClearanceSpacer()
            }
        }
        .loadingCrossfade(isLoading && account.likedAlbums.isEmpty && account.likedArtists.isEmpty)
        .contentCrossfade(on: tab)
        .background(trackLayout.background)
        .musicLibraryNavigationTitle(String(localized: "我的收藏"), enabled: trackLayout.usesPanel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear { if !account.provider.supports(.collectionAlbums) { tab = .artists } }
        .panelRefresh(key: "collections") { force in
            await account.refreshSublists(force: force)
            isLoading = false
        }
    }
}


enum LibrarySection: Hashable {
    case createdPlaylists, subscribedPlaylists, albums, artists

    var title: String {
        switch self {
        case .createdPlaylists: return String(localized: "创建的歌单")
        case .subscribedPlaylists: return String(localized: "收藏的歌单")
        case .albums: return String(localized: "收藏的专辑")
        case .artists: return String(localized: "收藏的歌手")
        }
    }
}

struct LibrarySectionView: View {
    let section: LibrarySection
    @EnvironmentObject private var account: AccountStore
    @State private var isLoading = true

    private var playlists: [PlaylistSummary] {
        if section == .subscribedPlaylists { return account.subscribedPlaylists }
        guard let liked = account.likedSongsPlaylist else { return account.createdPlaylists }
        return [liked] + account.createdPlaylists.filter { $0.id != liked.id }
    }

    private var isEmpty: Bool {
        switch section {
        case .createdPlaylists, .subscribedPlaylists: return playlists.isEmpty
        case .albums: return account.likedAlbums.isEmpty
        case .artists: return account.likedArtists.isEmpty
        }
    }

    var body: some View {
        ScenePreservingScrollView {
            VStack(spacing: Theme.Spacing.section) {
                if isLoading && isEmpty {
                    MusicLibraryCardLoadingView(circularCover: section == .artists)
                } else if let error = account.sublistsError, isEmpty,
                          section == .albums || section == .artists {
                    ErrorStateView(message: error) { Task { await refresh(force: true) } }
                } else if isEmpty {
                    EmptyStateView(icon: "square.stack", title: "暂无内容")
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    CardGrid {
                        switch section {
                        case .createdPlaylists, .subscribedPlaylists:
                            ForEach(playlists) { playlist in
                                NavigationLink(value: Destination.playlist(playlist.id)) {
                                    PlaylistCoverCard(playlist: playlist, subtitle: "\(playlist.trackCount) 首")
                                }.buttonStyle(.interactiveCard)
                            }
                        case .albums:
                            ForEach(account.likedAlbums) { album in
                                NavigationLink(value: Destination.album(album.id)) {
                                    CoverCardBody(coverURL: album.picUrl?.resizedImageURL(384),
                                                  title: album.name, subtitle: album.artistName)
                                }.buttonStyle(.interactiveCard)
                            }
                        case .artists:
                            ForEach(account.likedArtists) { artist in
                                NavigationLink(value: Destination.artist(artist.id)) {
                                    ProfileDetailArtistCardBody(artist: artist)
                                }.buttonStyle(.interactiveCard)
                            }
                        }
                    }
                    .padding(.horizontal, Theme.Layout.contentInset)
                }
                PlayerClearanceSpacer()
            }.padding(.top, Theme.Spacing.component)
        }
        .loadingCrossfade(isLoading && isEmpty)
        .navigationTitle(section == .createdPlaylists ? account.provider.playlistSectionTitle : section.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .panelRefresh(key: "library-section:\(section):\(account.authenticatedAccountID.map(String.init) ?? "guest")") {
            await refresh(force: $0)
        }
    }

    private func refresh(force: Bool) async {
        isLoading = true
        defer { isLoading = false }
        switch section {
        case .createdPlaylists, .subscribedPlaylists: await account.refreshLibrary(force: force)
        case .albums, .artists: await account.refreshSublists(force: force)
        }
    }
}
