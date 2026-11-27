import SwiftUI

struct HomeBrowseView: View {
    enum Kind {
        case albums, artists

        var title: LocalizedStringKey {
            switch self {
            case .albums: return "新碟上架"
            case .artists: return "推荐歌手"
            }
        }
    }

    let kind: Kind
    private let player = PlayerService.shared
    @State private var albums: [AlbumSummary] = []
    @State private var artists: [ArtistSummary] = []
    @State private var isLoading = false
    @State private var hasMore = true
    @State private var error: String?
    @State private var didLoad = false
    @State private var albumOffset = 0

    var body: some View {
        ScenePreservingScrollView {
            VStack(spacing: Theme.Spacing.section) {
                CardGrid {
                    switch kind {
                    case .albums:
                        ForEach(albums) { album in
                            NavigationLink(value: Destination.album(album.id)) {
                                CoverCardBody(coverURL: album.picUrl?.resizedImageURL(384),
                                              title: album.name, subtitle: album.artistName) {
                                    Task {
                                        if let detail = try? await NeteaseAPI.album(id: album.id) {
                                            player.play(tracks: detail.songs, source: .album(album.id),
                                                        context: .album(id: album.id, name: album.name))
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    case .artists:
                        ForEach(artists) { artist in
                            NavigationLink(value: Destination.artist(artist.id)) {
                                VStack(spacing: Theme.Spacing.small) {
                                    CachedAsyncImage(url: artist.picUrl?.resizedImageURL(384))
                                        .aspectRatio(1, contentMode: .fit)
                                        .clipShape(Circle())
                                    Text(artist.name)
                                        .font(Theme.Typography.cardTitle)
                                        .lineLimit(1)
                                        .foregroundStyle(.primary)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, Theme.Layout.contentInset)

                if isLoading {
                    ProgressView().frame(minHeight: 44)
                } else if let error {
                    ErrorStateView(message: error) { Task { await loadMore() } }
                } else if hasMore {
                    Button("加载更多") { Task { await loadMore() } }
                        .frame(minHeight: 44)
                } else if albums.isEmpty && artists.isEmpty {
                    Text("暂无内容").foregroundStyle(.secondary)
                }
                PlayerClearanceSpacer()
            }
            .padding(.top, Theme.Layout.contentInset)
        }
        .navigationTitle(kind.title)
        .task {
            guard !didLoad else { return }
            await loadMore()
        }
    }

    @MainActor
    private func loadMore() async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            switch kind {
            case .albums:
                let page = try await NeteaseAPI.newAlbums(limit: 60, offset: albumOffset)
                try Task.checkCancellation()
                let existing = Set(albums.map(\.id))
                albums += page.filter { !existing.contains($0.id) }
                albumOffset += page.count
                hasMore = page.count == 60
            case .artists:
                let result = try await NeteaseAPI.topArtists()
                try Task.checkCancellation()
                artists = result
                hasMore = false
            }
            didLoad = true
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
    }
}
