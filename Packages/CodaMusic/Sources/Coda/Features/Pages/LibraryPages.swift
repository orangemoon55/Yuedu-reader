import SwiftUI
import UniformTypeIdentifiers

// MARK: - 最近播放

struct RecentsView: View {
    @ObservedObject private var resource = SidebarResources.recents
    private var records: [RecentSongPlayRecord] { resource.value }
    @State private var filter = ""
    @State private var sort: MusicLibrarySort = .original
    private var isLoading: Bool { resource.isLoading }
    private var loadFailed: Bool { resource.error != nil }

    @EnvironmentObject private var account: AccountStore
    private var trackLayout = MusicLibraryTrackLayout()
    private let player = PlayerService.shared

    private var displayedRecords: [RecentSongPlayRecord] {
        let ids = Dictionary(sort.tracks(records.map(\.song), matching: filter).enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        return records.filter { ids[$0.song.id] != nil }.sorted { ids[$0.song.id]! < ids[$1.song.id]! }
    }

    var body: some View {
        TrackListScrollView(trackIDs: displayedRecords.map { $0.song.id }, style: .compact, spacing: Theme.Spacing.component) {
            VStack(alignment: .leading, spacing: Theme.Spacing.component) {
                if isLoading && records.isEmpty {
                    MusicLibraryHeaderSkeleton(showsSaveButton: false)
                } else if trackLayout.usesPanel {
                    MusicLibraryHeader(title: String(localized: "最近播放"), icon: "clock.fill",
                                       tracks: records.map(\.song), filter: $filter, sort: $sort) {
                        player.play(tracks: displayedRecords.map(\.song), source: .none, context: .recents)
                    }
                } else {
                HStack {
                    Spacer()

                    Button {
                        player.play(tracks: records.map(\.song), source: .none, context: .recents)
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.component)
                            .padding(.vertical, Theme.Spacing.small)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(records.isEmpty)
                }
                .padding(.horizontal, Theme.Layout.contentInset)
                .pageHeaderTopPadding(Theme.Spacing.control)

                }

                if isLoading && records.isEmpty {
                    MusicLibraryLoadingView()
                } else if loadFailed && records.isEmpty {
                    VStack(spacing: Theme.Spacing.control) {
                        EmptyStateView(icon: "wifi.exclamationmark", title: "最近播放加载失败")
                        Button("重试") { Task { await load() } }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, minHeight: 300)
                } else if records.isEmpty {
                    EmptyStateView(icon: "clock", title: "暂无播放记录")
                        .frame(minHeight: 300)
                }
            }
        } rows: { layout in
            recordList(layout: layout)
                .musicLibraryTrackPanel(trackLayout.usesPanel)
        } footer: {
            PlayerClearanceSpacer()
        }
        .loadingCrossfade(isLoading && records.isEmpty)
        .musicLibraryArtworkBackground(records.first?.song.album.picUrl)
        .musicLibraryNavigationTitle(String(localized: "最近播放"), enabled: trackLayout.usesPanel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .panelRefresh(key: "recents") { await load(force: $0) }
        .safeAreaInset(edge: .top) {
            PanelRefreshFailure(message: records.isEmpty ? nil : resource.error) { Task { await load() } }
        }
    }

    private func recordList(layout: TrackListView.Layout) -> some View {
        let displayed = displayedRecords
        return TrackListView(
            tracks: displayed.map(\.song),
            rowIDs: displayed.map(\.id),
            style: trackLayout.usesPanel ? .likedMusic : .compact,
            showsLikeButton: !trackLayout.usesPanel,
            showsAlbumSubtitle: trackLayout.usesPanel,
            columns: trackLayout.columns,
            context: .recents,
            layout: layout)
    }

    private func load(force: Bool = true) async {
        await resource.load(lifetime: 60, force: force) {
            guard account.isLoggedIn else { throw NeteaseAPIError.needLogin }
            return try await NeteaseAPI.recentSongs(limit: account.provider == .kugou ? 500 : 100)
        }
    }
}

// MARK: - 音乐云盘

struct CloudView: View {
    @EnvironmentObject private var account: AccountStore
    private var canChangeCloud: Bool { account.provider.supports(.cloudChanges) }
    /// 云盘写操作绑定发起时的账号；账号切换后丢弃结果。
    private var cloudSession: String? {
        guard account.isLoggedIn else { return nil }
        return account.provider == .netease ? NeteaseClient.shared.authenticationFingerprint : account.offlineScope
    }
    private var trackLayout = MusicLibraryTrackLayout()
    @ObservedObject private var resource = SidebarResources.cloud
    private var items: [CloudSongItem] { resource.value?.data ?? [] }
    private var sizeInfo: String? {
        guard let size = resource.value?.size, let max = resource.value?.maxSize, max > 0 else { return nil }
        let used = String(format: "%.1f", Double(size) / 1_073_741_824)
        let total = String(format: "%.0f", Double(max) / 1_073_741_824)
        return String(localized: "已使用 \(used) GB / \(total) GB")
    }
    @State private var showsFileImporter = false
    @State private var isUploading = false
    @State private var pendingDeletion: Track?
    @State private var showsDeleteConfirmation = false
    @State private var deletingIDs: Set<Int> = []
    @State private var operationError: String?
    @State private var filter = ""
    @State private var sort: MusicLibrarySort = .original
    private var isLoading: Bool { resource.isLoading }

    private let player = PlayerService.shared

    var body: some View {
        let displayed = trackLayout.usesPanel ? sort.tracks(tracks, matching: filter) : tracks
        TrackListScrollView(trackIDs: displayed.map(\.id), style: .compact, spacing: Theme.Spacing.component) {
            VStack(alignment: .leading, spacing: Theme.Spacing.component) {
                if isLoading && items.isEmpty {
                    MusicLibraryHeaderSkeleton(showsSaveButton: false)
                } else if trackLayout.usesPanel {
                    MusicLibraryHeader(title: String(localized: "音乐云盘"), icon: "icloud.fill",
                                       tracks: tracks, subtitle: sizeInfo, filter: $filter, sort: $sort,
                                       upload: canChangeCloud ? { showsFileImporter = true } : nil, isUploading: isUploading) {
                        player.play(tracks: displayed, source: .cloud, context: .cloud)
                    }
                } else {
                HStack {
                    if let sizeInfo {
                        Text(sizeInfo)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if canChangeCloud {
                    Button { showsFileImporter = true } label: {
                        Label(isUploading ? "正在上传…" : "上传", systemImage: "square.and.arrow.up")
                            .font(Theme.Typography.body.weight(.semibold))
                            .padding(.horizontal, Theme.Spacing.component)
                            .padding(.vertical, Theme.Spacing.small)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isUploading || cloudSession == nil)
                    .accessibilityIdentifier("cloud-upload")
                    }
                    Button {
                        player.play(tracks: tracks, source: .cloud, context: .cloud)
                    } label: {
                        Label("播放全部", systemImage: "play.fill")
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.component)
                            .padding(.vertical, Theme.Spacing.small)
                            .background(Theme.accentGradient, in: Capsule())
                    }
                    .buttonStyle(.pressable)
                    .disabled(items.isEmpty)
                }
                .padding(.horizontal, Theme.Layout.contentInset)
                .pageHeaderTopPadding(Theme.Spacing.control)

                }

                if isLoading && items.isEmpty {
                    MusicLibraryLoadingView()
                } else if let error = resource.error, items.isEmpty {
                    ErrorStateView(message: error) { Task { await load() } }
                } else if items.isEmpty {
                    EmptyStateView(icon: "icloud", title: "云盘还没有歌曲",
                                   subtitle: canChangeCloud ? "点击上传，将本地音乐添加到云盘" : "在音乐平台客户端上传后，可在这里刷新查看")
                        .frame(minHeight: 300)
                }
            }
        } rows: { layout in
            TrackListView(tracks: displayed, style: trackLayout.usesPanel ? .likedMusic : .compact,
                          showsLikeButton: !trackLayout.usesPanel, showsAlbumSubtitle: trackLayout.usesPanel,
                          columns: trackLayout.columns, source: .cloud, context: .cloud,
                          onDeleteFromCloud: canChangeCloud ? { track in
                              guard deletingIDs.isEmpty else { return }
                              pendingDeletion = track
                              showsDeleteConfirmation = true
                          } : nil, layout: layout)
                .musicLibraryTrackPanel(trackLayout.usesPanel)
        } footer: {
            if account.provider == .qq {
                ForEach(items.filter { $0.simpleSong == nil }) { item in
                    HStack {
                        Label(item.songName ?? "云盘文件", systemImage: "doc")
                        Spacer()
                        Text("未匹配曲库").foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, Theme.Layout.contentInset)
                    .padding(.vertical, Theme.Spacing.control)
                }
            }
            PlayerClearanceSpacer()
        }
        .loadingCrossfade(isLoading && items.isEmpty)
        .musicLibraryArtworkBackground(tracks.first?.album.picUrl)
        .musicLibraryNavigationTitle(String(localized: "音乐云盘"), enabled: trackLayout.usesPanel)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .fileImporter(isPresented: $showsFileImporter, allowedContentTypes: [.audio], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls):
                guard !urls.isEmpty, !isUploading else { return }
                isUploading = true
                Task { await upload(urls) }
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { operationError = error.localizedDescription }
            }
        }
        .alert("从云盘中删除？", isPresented: $showsDeleteConfirmation, presenting: pendingDeletion) { track in
            Button("删除", role: .destructive) { Task { await delete(track) } }
            Button("取消", role: .cancel) { pendingDeletion = nil }
        } message: { track in
            Text("将从云盘中删除「\(track.name)」，此操作无法撤销。")
        }
        .alert("云盘操作失败", isPresented: Binding(get: { operationError != nil }, set: { if !$0 { operationError = nil } })) {
            Button("好", role: .cancel) { operationError = nil }
        } message: { Text(operationError ?? "") }
        .overlay(alignment: .bottom) {
            if isUploading {
                HStack(spacing: Theme.Spacing.control) {
                    ProgressView().controlSize(.small)
                    Text("正在上传音乐，请保持应用打开…").font(Theme.Typography.caption)
                }
                .padding().background(.regularMaterial, in: Capsule())
                .padding(.bottom, 90)
            }
        }
        .panelRefresh(key: "cloud") { await load(force: $0) }
        .safeAreaInset(edge: .top) {
            PanelRefreshFailure(message: items.isEmpty ? nil : resource.error) { Task { await load() } }
        }
    }

    private func upload(_ urls: [URL]) async {
        defer { isUploading = false }
        guard canChangeCloud else { return }
        guard let authentication = cloudSession else {
            operationError = NeteaseAPIError.needLogin.localizedDescription
            return
        }
        var completed = 0
        var failures: [String] = []
        for url in urls {
            guard authentication == cloudSession else { break }
            do {
                try await NeteaseAPI.cloudUpload(fileAt: url)
                completed += 1
            } catch is CancellationError {
                break
            } catch {
                failures.append("\(url.lastPathComponent)：\(error.localizedDescription)")
            }
        }
        guard authentication == cloudSession else { return }
        if completed > 0 {
            await load()
            ToastCenter.shared.show(String(localized: "已上传 \(completed) 首歌曲"))
        }
        if !failures.isEmpty { operationError = failures.joined(separator: "\n") }
    }

    private func delete(_ track: Track) async {
        guard canChangeCloud else { return }
        // Cloud songId may differ from the matched catalogue track ID.
        guard let item = items.first(where: { $0.simpleSong?.id == track.id }), item.songId != 0,
              deletingIDs.insert(item.songId).inserted else { return }
        defer { deletingIDs.remove(item.songId); pendingDeletion = nil }
        let authentication = cloudSession
        do {
            if account.provider == .kugou {
                try await PlatformMusicAPI.shared.cloudDelete(track: track)
            } else {
                try await NeteaseAPI.cloudDelete(id: item.songId)
            }
            guard authentication == cloudSession else { return }
            await load()
            ToastCenter.shared.show(String(localized: "已从云盘中删除"))
        } catch is CancellationError {
            return
        } catch {
            guard authentication == cloudSession else { return }
            operationError = error.localizedDescription
        }
    }

    private var tracks: [Track] {
        items.compactMap(\.simpleSong)
    }

    private func load(force: Bool = true) async {
        await resource.load(lifetime: 300, force: force) {
            guard account.isLoggedIn else { throw NeteaseAPIError.needLogin }
            return try await NeteaseAPI.cloudSongs()
        }
    }
}
