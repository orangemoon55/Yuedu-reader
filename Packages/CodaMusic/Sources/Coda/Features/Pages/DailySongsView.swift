import SwiftUI

struct DailySongsView: View {
    @ObservedObject private var resource = SidebarResources.daily
    @State private var filter = ""
    @State private var sort: MusicLibrarySort = .original
    private var trackLayout = MusicLibraryTrackLayout()
    @State private var replacements: [Int: Track] = [:]
    private var tracks: [Track] { resource.value.map { replacements[$0.id] ?? $0 } }
    private var pageTitle: String { account.provider.dailySongsTitle }
    private var isLoading: Bool { resource.isLoading && resource.value.isEmpty }
    private var errorMessage: String? { resource.value.isEmpty ? resource.error : nil }

    @State private var searchFocused = false

    var phoneLayout = PhonePageLayout()
    private var usesPhoneHeader: Bool { phoneLayout.isEnabled }

    private let player = PlayerService.shared
    @EnvironmentObject private var account: AccountStore

    var body: some View {
        let displayed = isLoading || errorMessage != nil ? [] : sort.tracks(tracks, matching: filter)
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: usesPhoneHeader ? 16 : 20) {
                if isLoading {
                    MusicLibraryHeaderSkeleton(showsSaveButton: false)
                } else {
                    if usesPhoneHeader {
                        phoneHeader(displayed: displayed)
                    } else {
                        libraryHeader(displayed: displayed)
                    }

                }
                if isLoading {
                    MusicLibraryLoadingView()
                } else if let errorMessage {
                    ErrorStateView(message: errorMessage) { Task { await load() } }
                        .frame(minHeight: 300)
                } else if tracks.isEmpty {
                    EmptyStateView(icon: "calendar.badge.clock", title: "暂无推荐歌曲",
                                   subtitle: account.provider == .netease ? "多听几首歌培养口味，每天 6:00 更新" : "稍后刷新重试")
                        .frame(minHeight: 300)
                }
                if !displayed.isEmpty {
                    MusicTrackPanel(
                        tracks: displayed,
                        source: .daily,
                        context: .daily,
                        recommendationContext: account.provider.supports(.recommendationFeedback) ? .daily : nil,
                        onRecommendationReduced: { rejected, replacement in
                            replacements[rejected.id] = replacement
                        }
                    )
                }
                PlayerClearanceSpacer()
            }
        }
        .loadingCrossfade(isLoading)
        // Applied to the content (not inside `.background`) so the artwork's
        // light/dark verdict also drives the foreground color scheme.
        .modifier(DetailArtworkBackground(artworkURL: tracks.first?.album.picUrl))
        .musicLibraryNavigationTitle(pageTitle,
                                     enabled: trackLayout.usesPanel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        #endif
        .panelRefresh(key: "daily") { await load(force: $0, afresh: $0) }
        .safeAreaInset(edge: .top) {
            PanelRefreshFailure(message: tracks.isEmpty ? nil : resource.error) { Task { await load() } }
        }
        .onChange(of: account.offlineScope) { _ in replacements = [:] }
    }

    private func libraryHeader(displayed: [Track]) -> some View {
        MusicLibraryHeader(title: pageTitle, icon: "calendar",
                           tracks: tracks,
                           subtitle: account.provider == .netease ? String(localized: "根据你的音乐口味 · 每天 6:00 更新") : account.provider.name,
                           filter: $filter, sort: $sort) {
            player.play(tracks: displayed, source: .daily, context: .daily)
        }
    }

    private func phoneHeader(displayed: [Track]) -> some View {
        PlaylistHeader(
            artworkURL: tracks.first?.album.picUrl,
            title: pageTitle,
            subtitle: account.provider.name,
            avatarURL: nil,
            metadataText: account.provider == .netease ? "\(tracks.count) 首歌曲 · 每天 6:00 更新" : "\(tracks.count) 首歌曲",
            filter: $filter, searchFocused: $searchFocused,
            searchPlaceholder: String(localized: "在推荐中搜索")
        ) {
            PlaylistPrimaryActions(
                isSaved: false, canSave: false, canPlay: !displayed.isEmpty,
                isSaving: false, onToggleSaved: {},
                onPlayAll: { player.play(tracks: displayed, source: .daily, context: .daily) },
                showsSaveButton: false
            ) {
                Menu {
                    Menu {
                        Picker("排序方式", selection: $sort) {
                            ForEach(MusicLibrarySort.allCases, id: \.self) { order in
                                Text(LocalizedStringKey(order.rawValue)).tag(order)
                            }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    } label: { Label("排序方式", systemImage: "arrow.up.arrow.down") }
                    DownloadCollectionButton(tracks: tracks, owner: "daily:\(SidebarResources.dailyPeriod())",
                                             name: pageTitle,
                                             enabled: !tracks.isEmpty && !isLoading,
                                             menuPresentation: true)
                } label: { PlaylistMoreLabel() }
                .accessibilityLabel("更多操作")
                .accessibilityIdentifier("dailyMoreActions")
            }
        }
    }

    private func load(force: Bool = true, afresh: Bool = false) async {
        let binding = MusicProviderContext.shared.authenticationKey
        await resource.load(lifetime: 86_400, key: SidebarResources.dailyPeriod(), force: force) {
            guard account.isLoggedIn else { throw NeteaseAPIError.needLogin }
            return try await NeteaseAPI.dailyRecommendSongs(afresh: afresh)
        }
        if afresh, !Task.isCancelled, resource.error == nil,
           binding == MusicProviderContext.shared.authenticationKey { replacements = [:] }
    }
}
