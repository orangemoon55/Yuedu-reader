import SwiftUI

enum HomeRecommendationPage: Hashable {
    case liked, song
    case discovery(HomeDiscoverySlot)
}

/// Browse the same snapshot as the homepage, with the full loaded song list or
/// playlist grid. Returning home does not reroll the recommendations.
struct HomeRecommendationPageView: View {
    let page: HomeRecommendationPage
    @ObservedObject private var suggestions = HomeSongSuggestionsModel.shared
    @ObservedObject private var discovery = HomeDiscoveryModel.shared
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openLogin) private var openLogin

    private var title: String {
        switch page {
        case .liked: return String(localized: "根据你喜爱的歌曲推荐")
        case .song:
            return suggestions.seed.map { String(localized: "根据「\($0.name)」为你推荐") }
                ?? String(localized: "根据歌曲为你推荐")
        case .discovery(let slot): return slot.title
        }
    }

    private var content: HomeDiscoveryContent? {
        switch page {
        case .liked: return .songs(suggestions.likedTracks)
        case .song: return .songs(suggestions.songTracks)
        case .discovery(let slot): return discovery.contents[slot]
        }
    }

    private var isLoading: Bool {
        switch page {
        case .liked, .song: return suggestions.isLoading
        case .discovery: return discovery.isLoading
        }
    }

    private var error: String? {
        switch page {
        case .liked: return suggestions.likedError
        case .song: return suggestions.songError
        case .discovery(let slot):
            return discovery.failedSlots.contains(slot) ? String(localized: "推荐加载失败，请重试") : nil
        }
    }

    var body: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                if !account.isLoggedIn, requiresLogin {
                    HomeLoginPrompt(message: String(localized: "此内容为个性化推荐，需登录后查看"), minHeight: 240)
                } else if let error {
                    ErrorStateView(message: error) { Task { await refresh(force: true) } }
                }
                if !account.isLoggedIn, requiresLogin {
                    EmptyView()
                } else if let content, !content.isEmpty {
                    switch content {
                    case .songs(let songs):
                        MusicTrackPanel(tracks: songs, showsHorizontalPanel: false)
                    case .playlists(let playlists):
                        CardGrid {
                            ForEach(playlists) { playlist in
                                NavigationLink(value: Destination.playlist(playlist.id)) {
                                    PlaylistCoverCard(playlist: playlist, subtitle: page == .discovery(.radios)
                                        ? playlist.copywriter ?? playlist.creator?.nickname : nil)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else if isLoading {
                    MusicLibraryLoadingView()
                } else if error == nil {
                    VStack(spacing: Theme.Spacing.component) {
                        Text(emptyMessage).foregroundStyle(.secondary)
                        if page == .liked, !account.isLoggedIn {
                            Button("登录\(account.provider.name)", action: openLogin)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 240)
                }
                PlayerClearanceSpacer()
            }
            .padding(.horizontal, Theme.Layout.contentInset)
            .padding(.top, Theme.Layout.contentInset)
        }
        .navigationTitle(title)
        .panelRefresh(key: "homeRecommendation-\(page)") { force in await refresh(force: force) }
    }

    private var requiresLogin: Bool {
        switch page {
        case .liked: return true
        case .song: return false
        case .discovery(let slot): return slot.requiresLogin(on: account.provider)
        }
    }

    private var emptyMessage: String {
        switch page {
        case .liked:
            return account.isLoggedIn ? String(localized: "收藏一些喜欢的歌曲，发现更多相似音乐")
                : String(localized: "登录后发现你喜欢的音乐")
        case .song: return String(localized: "播放一首歌曲，发现更多相似音乐")
        case .discovery: return String(localized: "暂无内容")
        }
    }

    private func refresh(force: Bool) async {
        switch page {
        case .liked, .song:
            let context = HomeSongSuggestionsModel.Context.current(account)
            if force {
                await suggestions.load(context: context, currentTrack: PlayerService.shared.currentTrack)
            } else {
                await suggestions.loadIfNeeded(context: context, currentTrack: PlayerService.shared.currentTrack)
            }
        case .discovery:
            await discovery.load(loggedIn: account.isLoggedIn, force: force)
        }
    }
}
