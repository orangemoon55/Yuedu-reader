import SwiftUI

struct HomeDiscoverySections: View {
    @ObservedObject var model: HomeDiscoveryModel
    /// Song-row slots sit above the toplists; playlist and radio shelves stay below.
    let songRows: Bool
    @EnvironmentObject private var account: AccountStore
    @EnvironmentObject private var settings: SettingsManager
    @Environment(\.openDestination) private var openDestination

    private var visibleSlots: [HomeDiscoverySlot] {
        account.provider.homeDiscoverySlots.filter { slot in
            slot.showsSongRows == songRows
                && (account.isLoggedIn || settings.showLoginRequiredRecommendations
                    || !slot.requiresLogin(on: account.provider))
        }
    }

    var body: some View {
        ForEach(visibleSlots, id: \.self) { slot in
            VStack(alignment: .leading, spacing: 0) {
                SectionHeader(title: LocalizedStringKey(slot.title), action: {
                    openDestination(.homeRecommendation(.discovery(slot)))
                })
                    .frame(maxWidth: .infinity, minHeight: HomeLayout.headerHeight, alignment: .leading)
                    .padding(.bottom, HomeLayout.headerSpacing)
                    .padding(.horizontal, Theme.Layout.contentInset)

                if !account.isLoggedIn, slot.requiresLogin(on: account.provider) {
                    HomeLoginPrompt(message: String(localized: "「\(slot.title)」为个性化内容，需登录后查看"))
                        .padding(.horizontal, Theme.Layout.contentInset)
                } else if model.loadingSlots.contains(slot) {
                    if slot == .radios {
                        ProgressView()
                            .frame(maxWidth: .infinity, minHeight: 120)
                            .accessibilityLabel("正在加载电台")
                    } else {
                        MusicLibraryLoadingView(rowsPerColumn: 3, scrollsHorizontally: true,
                                                showsHorizontalPanel: false,
                                                horizontalInset: Theme.Layout.trackListInset,
                                        fixedColumnWidth: Theme.Layout.homeSongColumnWidth)
                    }
                } else if let content = model.contents[slot], !content.isEmpty {
                    contentView(content, slot: slot)
                } else if !model.failedSlots.contains(slot) {
                    Text("暂无内容")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }

                if model.failedSlots.contains(slot), account.isLoggedIn || !slot.requiresLogin(on: account.provider) {
                    HStack(spacing: Theme.Spacing.control) {
                        Text("推荐加载失败，请重试").foregroundStyle(.secondary)
                        Button("重试") {
                            Task { await model.load(loggedIn: account.isLoggedIn, force: true) }
                        }
                    }
                    .font(Theme.Typography.secondary)
                    .frame(maxWidth: .infinity, minHeight: 64)
                }
            }
            .accessibilityIdentifier("homeDiscovery-\(slot.rawValue)")
        }
    }

    @ViewBuilder
    private func contentView(_ content: HomeDiscoveryContent, slot: HomeDiscoverySlot) -> some View {
        switch content {
        case .songs(let songs):
            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(height: 0.5)
                .padding(.bottom, Theme.Spacing.control)
                .padding(.horizontal, Theme.Layout.contentInset)
            MusicTrackPanel(tracks: songs, scrollsHorizontally: true,
                            horizontalRowLimit: 3, horizontalInset: Theme.Layout.trackListInset, fixedColumnWidth: Theme.Layout.homeSongColumnWidth,
                            showsHorizontalPanel: false, showsRowSeparators: false)
        case .playlists(let playlists):
            HomeCoverShelf(items: playlists, cardWidth: HomeLayout.coverSize) { playlist in
                playlistCard(playlist, subtitle: slot == .radios ? playlist.copywriter ?? playlist.creator?.nickname : nil,
                             size: HomeLayout.coverSize)
            }
        }
    }

    private func playlistCard(_ playlist: PlaylistSummary, subtitle: String? = nil,
                              size: CGFloat = Theme.Layout.cardSize) -> some View {
        NavigationLink(value: Destination.playlist(playlist.id)) {
            PlaylistCoverCard(playlist: playlist, subtitle: subtitle, size: size,
                              cornerRadius: HomeLayout.coverCornerRadius) {
                Task { await play(playlist) }
            }
        }
        .buttonStyle(.interactiveCard)
    }

    private func play(_ playlist: PlaylistSummary) async {
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
