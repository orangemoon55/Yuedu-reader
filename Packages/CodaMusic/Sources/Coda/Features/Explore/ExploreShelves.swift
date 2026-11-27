import SwiftUI

/// The explore page's browse content: one two-row cover shelf per playlist
/// category, laid out like the recommendation page's playlist shelves.
struct ExploreShelves: View {
    @EnvironmentObject private var account: AccountStore

    /// Charts are not playlists; the recommendation page already lists them.
    private var categories: [String] {
        account.provider.exploreCategories.filter { $0 != "排行榜" }
    }

    var body: some View {
        LazyVStack(alignment: .leading, spacing: HomeLayout.sectionSpacing) {
            ForEach(categories, id: \.self) { category in
                ExploreCategoryShelf(category: category)
            }
        }
        .id(account.provider)
    }
}

private struct ExploreCategoryShelf: View {
    let category: String
    private var phoneLayout = PhonePageLayout()
    @Environment(\.openDestination) private var openDestination
    /// Each shelf pages its own category with its own model.
    @StateObject private var model = ExploreViewModel()

    init(category: String) {
        self.category = category
    }

    /// Same cover size as the home shelves and radar cards.
    private var cardWidth: CGFloat { HomeLayout.coverSize }

    var body: some View {
        VStack(alignment: .leading, spacing: HomeLayout.headerSpacing) {
            SectionHeader(title: LocalizedStringKey(category), action: {
                openDestination(.exploreCategory(category))
            })
                .frame(maxWidth: .infinity, minHeight: HomeLayout.headerHeight, alignment: .leading)
                .padding(.horizontal, phoneLayout.contentInset)

            if model.playlists.isEmpty, let error = model.errorMessage {
                HStack(spacing: Theme.Spacing.control) {
                    Text(error).foregroundStyle(.secondary).lineLimit(2)
                    Button("重试") { Task { await model.refresh(force: true) } }
                }
                .font(Theme.Typography.secondary)
                .frame(maxWidth: .infinity, minHeight: 64)
                .padding(.horizontal, phoneLayout.contentInset)
            } else if model.playlists.isEmpty, !model.isLoading, model.selectedCategory == category {
                Text("暂无歌单")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                HomeCoverShelf(items: model.playlists, loading: pageLoading, cardWidth: cardWidth) { playlist in
                    NavigationLink(value: Destination.playlist(playlist.id)) {
                        PlaylistCoverCard(playlist: playlist, size: cardWidth,
                                          cornerRadius: HomeLayout.coverCornerRadius) {
                            Task { await play(playlist) }
                        }
                    }
                    .buttonStyle(.interactiveCard)
                }
            }
        }
        .accessibilityIdentifier("exploreShelf-\(category)")
        .task {
            if model.selectedCategory != category {
                model.select(category)
            } else {
                await model.refresh()
            }
        }
    }

    private var pageLoading: HorizontalPageLoading {
        .init(hasMore: model.hasMore, isLoading: model.isLoading, error: model.errorMessage,
              loadMore: { await model.loadMore() }, revision: model.playlists.count)
    }

    private func play(_ playlist: PlaylistSummary) async {
        await ExplorePlayback.play(playlist)
    }
}

/// The full playlist list of one 精选 category, opened from its shelf header.
struct ExploreCategoryView: View {
    let category: String
    private var phoneLayout = PhonePageLayout()
    @StateObject private var model = ExploreViewModel()

    init(category: String) { self.category = category }

    var body: some View {
        ScenePreservingScrollView {
            LazyVStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if let error = model.errorMessage {
                    ErrorStateView(message: error) { Task { await model.refresh(force: true) } }
                }
                CardGrid {
                    ForEach(Array(model.playlists.enumerated()), id: \.element.id) { index, playlist in
                        NavigationLink(value: Destination.playlist(playlist.id)) {
                            PlaylistCoverCard(playlist: playlist) {
                                Task { await ExplorePlayback.play(playlist) }
                            }
                        }
                        .buttonStyle(.plain)
                        .staggeredAppearance(index: index % 10, id: "explore-category-\(playlist.id)")
                    }
                }
                .padding(.horizontal, phoneLayout.contentInset)
                .pageHeaderTopPadding(8)

                if model.isLoading {
                    ProgressView().controlSize(.small)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.phonePage)
                } else if model.hasMore && model.errorMessage == nil {
                    Color.clear.frame(height: 1)
                        .onAppear { Task { await model.loadMore() } }
                } else if model.playlists.isEmpty, model.errorMessage == nil, model.selectedCategory == category {
                    EmptyStateView(icon: "music.note.list", title: "暂无歌单")
                        .padding(.vertical, Theme.Spacing.section)
                }

                PlayerClearanceSpacer()
            }
        }
        .navigationTitle(LocalizedStringKey(category))
        .task {
            if model.selectedCategory != category {
                model.select(category)
            } else {
                await model.refresh()
            }
        }
    }
}

private enum ExplorePlayback {
    @MainActor
    static func play(_ playlist: PlaylistSummary) async {
        do {
            let detail = try await NeteaseAPI.playlistDetail(id: playlist.id)
            var tracks = detail.playlist.tracks
            if tracks.isEmpty {
                tracks = try await NeteaseAPI.songDetails(ids: Array(detail.playlist.trackIds.prefix(500).map(\.id))).songs
            }
            guard !Task.isCancelled else { return }
            PlayerService.shared.play(tracks: tracks, source: .playlist(playlist.id),
                                      context: .playlist(id: playlist.id, name: playlist.name))
        } catch {
            ToastCenter.shared.show(error.localizedDescription)
        }
    }
}
