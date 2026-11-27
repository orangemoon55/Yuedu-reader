import SwiftUI

struct PlaylistSearchActionKey: LayoutValueKey {
    static let defaultValue = false
}

/// Fill one horizontal bar. Text controls share the available width while
/// icon-only actions retain a compact hit target; search participates in the row.
struct PlaylistActionLayout: Layout {
    var spacing: CGFloat

    private func frames(width: CGFloat, subviews: Subviews) -> [CGRect] {
        guard !subviews.isEmpty else { return [] }
        let gap = min(spacing, width / CGFloat(max(1, subviews.count * 4)))
        let icons = subviews.map { !$0[PlaylistSearchActionKey.self] && $0.sizeThatFits(.unspecified).width <= 44 }
        let iconCount = icons.filter { $0 }.count
        let flexibleCount = subviews.count - iconCount
        let usable = max(0, width - gap * CGFloat(subviews.count - 1))
        let iconWidth = min(44, usable / CGFloat(subviews.count))
        let flexibleWidth = flexibleCount > 0
            ? max(0, usable - CGFloat(iconCount) * iconWidth) / CGFloat(flexibleCount) : iconWidth
        var x: CGFloat = 0
        return icons.map { icon in
            let itemWidth = icon ? iconWidth : flexibleWidth
            defer { x += itemWidth + gap }
            return CGRect(x: x, y: 0, width: itemWidth, height: 44)
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let idealWidth = subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width }
            + spacing * CGFloat(max(0, subviews.count - 1))
        return CGSize(width: max(1, proposal.width ?? idealWidth), height: subviews.isEmpty ? 0 : 44)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (view, frame) in zip(subviews, frames(width: bounds.width, subviews: subviews)) {
            view.place(at: CGPoint(x: bounds.minX + frame.midX, y: bounds.minY + frame.midY),
                       anchor: .center, proposal: ProposedViewSize(frame.size))
        }
    }
}


struct PlaylistDetailView: View {
    let playlistID: Int
    var isLikedList = false
    var recommendationContext: RecommendationContext?
    var onDeleted: (() -> Void)?

    @State private var refreshGate = PanelRefreshGate()
    @StateObject private var model: PlaylistContent
    @ObservedObject private var downloads = DownloadManager.shared
    // This page only sends playback commands; individual rows observe playback.
    private let player = PlayerService.shared
    @EnvironmentObject private var account: AccountStore
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @State private var showFullDescription = false
    @State private var isSubscribing = false
    @State private var isDeleting = false
    @State private var confirmDelete = false
    @State private var showRename = false
    @State private var isRenaming = false
    @State private var playlistName = ""
    @Environment(\.dismiss) private var dismiss
    @State private var searchFocused = false
    #if os(iOS)
    @State private var showSearch = false
    #endif

    init(playlistID: Int, isLikedList: Bool = false, recommendationContext: RecommendationContext? = nil, onDeleted: (() -> Void)? = nil) {
        self.playlistID = playlistID
        self.isLikedList = isLikedList
        self.recommendationContext = recommendationContext
        self.onDeleted = onDeleted
        _model = StateObject(wrappedValue: PlaylistContent(playlistID: playlistID))
    }

    /// Account metadata is already available when the sidebar opens liked songs.
    /// Keep its real header mounted while the async snapshot/network load fills
    /// in the tracks, rather than swapping a skeleton for a different hierarchy.
    private var displayedDetail: PlaylistDetail? {
        if model.loadedScope == account.offlineScope, var detail = model.detail {
            if account.provider == .qq, let summary = account.createdPlaylists.first(where: { $0.id == playlistID }) {
                detail.name = summary.name
            }
            return detail
        }
        guard account.authenticatedAccountID != nil,
              let summary = account.userPlaylists.first(where: { $0.id == playlistID }),
              isLikedList || summary.isLikedSongsList else { return nil }
        return PlaylistDetail(summary: summary)
    }

    private var isOwnPlaylist: Bool {
        guard let userID = account.profile?.userId else { return false }
        return displayedDetail?.creator?.userId == userID
    }

    private var isLikedPlaylist: Bool {
        isLikedList || (displayedDetail?.specialType == 5 && isOwnPlaylist)
    }

    private var isCompact: Bool { phoneLayout.isEnabled }
    private var isOffline: Bool { downloads.network.isKnown && !downloads.network.connected }

    var phoneLayout = PhonePageLayout()
    private var usesPhoneHeader: Bool { phoneLayout.isEnabled }

    private var supportsPlaylistSearch: Bool {
        #if os(iOS)
        return true
        #else
        return false
        #endif
    }

    private var isSearchActive: Bool {
        #if os(iOS)
        return supportsPlaylistSearch && showSearch
        #else
        return false
        #endif
    }

    var body: some View {
        ScrollViewReader { proxy in
            onlineContent
                .panelRefresh(key: "playlist:\(playlistID):\(account.libraryRevision):\(downloads.network.isKnown):\(downloads.network.connected)") {
                    await loadPlaylist(force: $0)
                }

        }
        .confirmationDialog("删除歌单？", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("删除歌单", role: .destructive) { deletePlaylist() }
            Button("取消", role: .cancel) {}
        } message: { Text("歌单将从当前音乐账户中删除。") }
        .alert("重命名歌单", isPresented: $showRename) {
            TextField("歌单名称", text: $playlistName)
            Button("保存") { renamePlaylist() }
            Button("取消", role: .cancel) {}
        }
    }

    private func renamePlaylist() {
        guard !isRenaming, !isDeleting, isOwnPlaylist, !isLikedPlaylist else { return }
        let name = playlistName
        isRenaming = true
        Task {
            defer { isRenaming = false }
            do {
                let verified = try await PlatformMusicAPI.shared.renamePlaylist(id: playlistID, name: name)
                model.detail?.name = verified
                ToastCenter.shared.show("歌单已重命名")
            } catch { ToastCenter.shared.show(error.localizedDescription) }
        }
    }

    private func deletePlaylist() {
        guard !isDeleting, isOwnPlaylist, !isLikedPlaylist else { return }
        isDeleting = true
        Task {
            defer { isDeleting = false }
            do {
                try await NeteaseAPI.deletePlaylist(id: playlistID)
                await account.refreshLibrary()
                ToastCenter.shared.show("歌单已删除")
                if let onDeleted { onDeleted() } else { dismiss() }
            } catch { ToastCenter.shared.show("删除失败：\(error.localizedDescription)") }
        }
    }

    private func loadPlaylist(force: Bool = true) async {
        let key = "\(playlistID):\(account.offlineScope ?? "pending"):\(account.libraryRevision):\(isOffline)"
        guard let ticket = refreshGate.begin(key: key, lifetime: 300, force: force) else { return }
        let allowNetwork = !isOffline
        await model.load(allowNetwork: allowNetwork,
                         summary: account.userPlaylists.first { $0.id == playlistID })
        refreshGate.finish(ticket, success: allowNetwork && model.errorMessage == nil && model.detail != nil)
    }

    @ViewBuilder
    private var onlineContent: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.section) {
                playlistContents
            }
            .id("playlistTop")
        }
        .loadingCrossfade(model.isLoading)
        .modifier(DetailArtworkBackground(artworkURL: displayedDetail?.coverURL))
        .musicLibraryNavigationTitle(displayedDetail?.name ?? String(localized: "歌单"), enabled: true)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .scrollDismissesKeyboard(.interactively)
        #endif
    }

    @ViewBuilder
    private var playlistContents: some View {
        if let detail = displayedDetail {
            let filteredTracks = model.loadedScope == account.offlineScope ? model.filteredTracks : []
            collectionHeader(detail)

            #if os(iOS)
            if isSearchActive && !usesPhoneHeader {
                HStack(spacing: Theme.Spacing.tight) {
                    PlaylistSearchField(text: $model.filter, isFocused: $searchFocused)
                    Button("取消") {
                        model.filter = ""
                        searchFocused = false
                        withAnimation(AppAnimation.standard) { showSearch = false }
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, Theme.Spacing.small)
                }
                .frame(height: 52)
                .padding(.horizontal, isCompact ? 8 : Theme.Layout.contentInset - 8)
                .padding(.top, Theme.Spacing.small)
                .transition(.opacity)
            }

            if supportsPlaylistSearch && !model.filter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                HStack {
                    Text("找到 \(filteredTracks.count) 首匹配歌曲")
                    if !isSearchActive {
                        Spacer()
                        Button("清空搜索") { model.filter = "" }
                    }
                }
                .font(Theme.Typography.secondary)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Layout.contentInset)

                if filteredTracks.isEmpty && !model.isLoading && !model.isLoadingMore && model.errorMessage == nil {
                    EmptyStateView(icon: "magnifyingglass", title: "没有匹配的歌曲",
                                   subtitle: "试试其他歌名、歌手或专辑")
                        .frame(minHeight: 180)
                }
            }
            #endif

            if !filteredTracks.isEmpty {
                MusicTrackPanel(
                    tracks: filteredTracks,
                    source: detail.playSource,
                    context: .playlist(id: playlistID, name: detail.name),
                    showsLikeButton: !isLikedPlaylist,
                    removableFromPlaylistID: isOwnPlaylist ? playlistID : nil,
                    onRemoved: { track in Task { await model.remove(track) } },
                    recommendationContext: recommendationContext,
                    onRecommendationReduced: { model.replaceRecommendation($0, with: $1) }
                )
            }

            playlistStatus(detail)
        } else if model.isLoading {
            loadingHeader
            MusicLibraryLoadingView()
        } else if isOffline {
            EmptyStateView(icon: "music.note.list", title: "联网后载入歌曲")
                .frame(minHeight: 400)
        } else {
            ErrorStateView(message: model.errorMessage ?? String(localized: "无法加载歌单，请重试")) {
                Task { await loadPlaylist() }
            }
            .frame(minHeight: 400)
        }
        PlayerClearanceSpacer()
    }

    @ViewBuilder
    private func playlistStatus(_ detail: PlaylistDetail) -> some View {
        if model.isLoading || model.isLoadingMore {
            MusicLibraryLoadingView(rowsPerColumn: model.tracks.isEmpty ? 6 : 2)
        } else if model.tracks.isEmpty {
            if let message = model.errorMessage {
                ErrorStateView(message: message) { Task { await loadPlaylist() } }
            } else if detail.trackCount > 0, !isOffline {
                ErrorStateView(message: String(localized: "歌单数据不完整，请重试")) { Task { await loadPlaylist() } }
            } else {
                Text(detail.trackCount == 0 ? String(localized: "歌单暂无歌曲") : String(localized: "联网后载入歌曲"))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.largeSection)
            }
        } else if model.tracks.count < detail.trackCount {
            Text("已载入 \(model.tracks.count)/\(detail.trackCount) 首")
                .font(Theme.Typography.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, Theme.Layout.contentInset)
        }

        if !model.tracks.isEmpty {
            PanelRefreshFailure(message: model.errorMessage) { Task { await loadPlaylist() } }
                .padding(.horizontal, Theme.Layout.contentInset)
        }
    }

    private func collectionHeader(_ detail: PlaylistDetail) -> some View {
        PlaylistHeader(
            artworkURL: detail.coverURL,
            title: detail.name,
            subtitle: detail.creator?.nickname ?? account.provider.name,
            avatarURL: detail.creator?.avatarUrl,
            metadataText: "\(detail.trackCount) 首歌曲 · \(Formatters.playCount(detail.playCount)) 次播放",
            filter: $model.filter, searchFocused: $searchFocused
        ) {
            detailActions(detail)
        }
    }

    private func detailActions(_ detail: PlaylistDetail, horizontalPadding: CGFloat? = nil) -> some View {
        PlaylistPrimaryActions(
            isSaved: detail.subscribed || isOwnPlaylist,
            canSave: canSubscribe(detail),
            canPlay: !playable.isEmpty,
            isSaving: isSubscribing,
            onToggleSaved: { toggleSubscribe(detail) },
            onPlayAll: {
                player.play(tracks: playable, source: detail.playSource,
                            context: .playlist(id: playlistID, name: detail.name))
            },
            horizontalPadding: horizontalPadding
        ) {
            playlistMoreMenu(detail)
        }
    }
    private func playlistMoreMenu(_ detail: PlaylistDetail) -> some View {
        Menu {
                if let description = detail.description, !description.isEmpty {
                    Button { showFullDescription = true } label: {
                        Label("歌单简介", systemImage: "text.alignleft")
                    }
                }
                if isLikedPlaylist {
                    Button(action: startHeartbeat) { Label("心动", image: "HeartPulse") }
                        .disabled(playable.isEmpty)
                }
            if isOwnPlaylist, !isLikedPlaylist, account.provider.supportsPlaylistRename {
                Button("重命名歌单") {
                    playlistName = detail.name
                    showRename = true
                }
                .disabled(isRenaming || isDeleting)
            }
            if isOwnPlaylist, !isLikedPlaylist, account.provider.supports(.playlistDeletion) {
                Button("删除歌单", role: .destructive) { confirmDelete = true }
                    .disabled(isDeleting)
            }
            Menu {
                Picker("排序方式", selection: $model.sortOrder) {
                    ForEach(PlaylistTrackSort.allCases, id: \.self) { order in
                        Text(LocalizedStringKey(order.rawValue)).tag(order)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: { Label("排序方式", systemImage: "arrow.up.arrow.down") }
            DownloadCollectionButton(tracks: model.tracks, owner: "playlist:\(playlistID)", name: detail.name,
                                     enabled: model.canDownloadAll, menuPresentation: true)
        } label: {
            PlaylistMoreLabel()
        }
        .sheet(isPresented: $showFullDescription) {
            ScenePreservingScrollView {
                Text(detail.description ?? "")
                    .padding(Theme.Spacing.page)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
        .accessibilityLabel("更多操作")
        .accessibilityIdentifier("playlistMoreActions")
    }

    /// Gray tracks resolve from other sources, so every track is playable.
    private var playable: [Track] { model.orderedTracks }

    private func startHeartbeat() {
        Task {
            guard let seed = playable.randomElement() else { return }
            do {
                let tracks = try await NeteaseAPI.intelligenceList(songID: seed.id, playlistID: playlistID)
                guard !tracks.isEmpty else {
                    ToastCenter.shared.show(String(localized: "心动模式暂时不可用"))
                    return
                }
                player.play(tracks: tracks, source: .playlist(playlistID), context: .heartbeat)
                ToastCenter.shared.show(String(localized: "已开启心动模式"))
            } catch {
                ToastCenter.shared.show(error.localizedDescription)
            }
        }
    }

    private func canSubscribe(_ detail: PlaylistDetail) -> Bool {
        account.provider.supports(.playlistSubscriptions) && account.isLoggedIn && !isOwnPlaylist && !PlatformMusicAPI.shared.isQQRadio(detail.id) &&
            (account.provider != .qishui || (detail.qishuiFeed == nil && detail.specialType != 5 &&
                !PlatformMusicAPI.shared.isQishuiChart(detail.id)))
    }

    private func toggleSubscribe(_ detail: PlaylistDetail) {
        guard !isSubscribing, canSubscribe(detail) else { return }
        let binding = MusicProviderContext.shared.authenticationKey
        let target = !detail.subscribed
        isSubscribing = true
        Task {
            defer { isSubscribing = false }
            do {
                try await NeteaseAPI.subscribePlaylist(id: detail.id, subscribe: target)
                guard binding == MusicProviderContext.shared.authenticationKey else { return }
                model.detail?.subscribed = target
                await account.refreshLibrary()
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
