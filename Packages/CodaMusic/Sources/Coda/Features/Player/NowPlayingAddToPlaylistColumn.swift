import SwiftUI

/// Uses the same right-hand viewport as comments and the playback queue.
struct NowPlayingAddToPlaylistColumn: View {
    let track: Track
    let onClose: () -> Void

    var body: some View {
        AddToPlaylistContent(track: track, isPlayerPanel: true, onClose: onClose)
            .accessibilityIdentifier("nowPlayingAddToPlaylist")
    }
}

/// Shared by detail-page sheets and the player's responsive side panel.
struct AddToPlaylistContent: View {
    let track: Track
    var isPlayerPanel = false
    let onClose: () -> Void
    @EnvironmentObject private var account: AccountStore
    @Environment(\.nowPlayingFlushPanelEdges) private var flushPanelEdges
    @State private var query = ""
    @State private var newName = ""
    @State private var showsCreate = false
    @FocusState private var isNameFocused: Bool
    @State private var isSaving = false
    @State private var included: Set<Int> = []

    private var foreground: Color { isPlayerPanel ? .white : .primary }
    private var secondaryForeground: Color { isPlayerPanel ? .white.opacity(0.6) : .secondary }
    private var separator: Color { isPlayerPanel ? .white.opacity(0.08) : .primary.opacity(0.08) }

    private var playlists: [PlaylistSummary] {
        account.createdPlaylists.filter {
            query.isEmpty || $0.name.localizedStandardContains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.component) {
            HStack {
                Text("添加到歌单")
                    .font(Theme.Typography.sectionTitle.weight(.bold))
                Spacer()
                Button {
                    isNameFocused = false
                    onClose()
                } label: {
                    actionIcon("PlaylistClose", size: 22)
                        .frame(width: 36, height: 36)
                        .modifier(PlaylistControlSurface(isPlayerPanel: isPlayerPanel,
                            playerFill: .white.opacity(0.08), shape: Circle(), interactive: true))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlaylistCreationButtonStyle())
                .accessibilityLabel("关闭添加歌单")
                .disabled(isSaving)
            }

            HStack(spacing: Theme.Spacing.control) {
                Image(systemName: "magnifyingglass")
                TextField("搜索歌单", text: $query)
                    .textFieldStyle(.plain)
                    #if os(iOS)
                    .submitLabel(.search)
                    #endif
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill") }
                        .accessibilityLabel("清除搜索")
                }
            }
            .foregroundStyle(secondaryForeground)
            .padding(Theme.Spacing.control)
            .modifier(PlaylistControlSurface(isPlayerPanel: isPlayerPanel,
                playerFill: .black.opacity(0.18), shape: Capsule()))

            ScrollView(showsIndicators: false) {
                LazyVStack(spacing: 0) {
                    creationRow
                    Divider().overlay(separator)
                    ForEach(playlists) { playlist in
                        playlistRow(playlist)
                        Divider().overlay(separator)
                    }
                    if playlists.isEmpty {
                        Text(query.isEmpty ? "还没有创建歌单" : "没有找到匹配的歌单")
                            .foregroundStyle(secondaryForeground)
                            .frame(maxWidth: .infinity, minHeight: 100)
                    }
                }
            }
            #if os(iOS)
            .scrollDismissesKeyboard(.interactively)
            #endif
        }
        .buttonStyle(.plain)
        .foregroundStyle(foreground)
        .padding(.horizontal, isPlayerPanel && flushPanelEdges ? 0 : Theme.Layout.contentInset)
        .padding(.top, isPlayerPanel && flushPanelEdges ? 0 : Theme.Spacing.component)
        .padding(.bottom, isPlayerPanel && flushPanelEdges ? 0 : Theme.Spacing.small)
        .disabled(isSaving)
        .overlay { if isSaving { ProgressView().tint(foreground) } }
        .task(id: account.authenticatedAccountID) { await loadMembership() }
        .onDisappear { isNameFocused = false }
    }

    private var creationRow: some View {
        HStack(spacing: Theme.Spacing.component) {
            Button {
                if !showsCreate { newName = "" }
                showsCreate = true
                isNameFocused = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 25, weight: .medium))
                    .frame(width: 48, height: 48)
                    .modifier(PlaylistControlSurface(isPlayerPanel: isPlayerPanel,
                        playerFill: Theme.accent.opacity(0.13),
                        shape: RoundedRectangle(cornerRadius: 10), interactive: true))
            }
            .accessibilityLabel("新建歌单")
            if showsCreate {
                TextField("歌单名称", text: $newName)
                    .foregroundStyle(foreground)
                    .tint(foreground)
                    .font(Theme.Typography.body.weight(.semibold))
                    .textFieldStyle(.plain)
                    .focused($isNameFocused)
                    #if os(iOS)
                    .submitLabel(.done)
                    #endif
                    .onSubmit { save() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityIdentifier("newPlaylistName")
                    .onAppear { isNameFocused = true }
                Button {
                    isNameFocused = false
                    showsCreate = false
                    newName = ""
                } label: {
                    actionIcon("PlaylistClose", size: 24)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("取消新建歌单")
                Button { save() } label: {
                    actionIcon("PlaylistConfirm", size: 24)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("创建并收藏")
                .disabled(newName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                Button {
                    newName = ""
                    showsCreate = true
                } label: {
                    Text("新建歌单并收藏")
                        .font(Theme.Typography.body.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
        .foregroundStyle(Theme.accent)
        .buttonStyle(PlaylistCreationButtonStyle())
        .padding(.vertical, Theme.Spacing.control)
    }

    // PlainButtonStyle fades disabled labels on iPadOS 16. Keep all creation
    // actions on the same accent while the empty-name guard disables submission.
    private struct PlaylistCreationButtonStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .foregroundStyle(Theme.accent)
                .opacity(configuration.isPressed ? 0.65 : 1)
        }
    }

    private func actionIcon(_ name: String, size: CGFloat) -> some View {
        Image(name)
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .frame(width: size, height: size)
            .foregroundStyle(foreground)
    }

    private func playlistRow(_ playlist: PlaylistSummary) -> some View {
        let contains = included.contains(playlist.id)
        return Button {
            if contains {
                ToastCenter.shared.show("歌单已包含这首歌")
                onClose()
            } else {
                save(to: playlist)
            }
        } label: {
            HStack(spacing: Theme.Spacing.component) {
                PlaylistArtwork(playlist: playlist, pixelSize: 120, animated: false)
                    .frame(width: 48, height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(playlist.name).font(Theme.Typography.body.weight(.semibold))
                    Text("\(playlist.trackCount) 首" + (contains ? " · 已包含这首歌" : ""))
                        .font(Theme.Typography.secondary).foregroundStyle(secondaryForeground)
                }
                .lineLimit(1)
                Spacer(minLength: 4)
                if contains {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 25, weight: .regular))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 44, height: 44)
                }
            }
            .padding(.vertical, Theme.Spacing.control)
            .contentShape(Rectangle())
        }
        .accessibilityValue(contains ? "已包含这首歌" : "未收藏")
    }

    private func loadMembership() async {
        included = []
        let scope = account.offlineScope
        for playlist in account.createdPlaylists {
            guard !Task.isCancelled, account.offlineScope == scope else { return }
            if let scope, let snapshot = await PlaylistSnapshotStore.shared.load(id: playlist.id, scope: scope),
               snapshot.detail.trackIds.contains(where: { $0.id == track.id }) {
                included.insert(playlist.id)
            }
            if let detail = try? await NeteaseAPI.playlistDetail(id: playlist.id).playlist {
                guard !Task.isCancelled, account.offlineScope == scope else { return }
                if detail.trackIds.contains(where: { $0.id == track.id }) { included.insert(playlist.id) }
                else { included.remove(playlist.id) }
            }
        }
    }

    private func save(to playlist: PlaylistSummary? = nil) {
        guard !isSaving else { return }
        guard account.isLoggedIn else {
            ToastCenter.shared.show("登录后即可收藏歌曲")
            return
        }
        let name = playlist?.name ?? newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            ToastCenter.shared.show("请输入歌单名称")
            return
        }
        isNameFocused = false
        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let id: Int
                if let playlist { id = playlist.id }
                else {
                    guard let created = try await NeteaseAPI.createPlaylist(name: name, isPrivate: false) else {
                        ToastCenter.shared.show("收藏失败：未能创建歌单")
                        return
                    }
                    id = created
                }
                try await NeteaseAPI.playlistTracks(op: "add", playlistID: id, trackIDs: [track.id])
                ToastCenter.shared.show("已收藏到「\(name)」")
                onClose()
                await account.refreshLibrary()
            } catch {
                ToastCenter.shared.show("收藏失败：\(error.localizedDescription)")
                await account.refreshLibrary()
            }
        }
    }
}


/// Player controls retain their original fills over the artwork backdrop.
/// Standalone sheets use the app's shared glass surfaces.
private struct PlaylistControlSurface<S: Shape>: ViewModifier {
    let isPlayerPanel: Bool
    let playerFill: Color
    let shape: S
    var interactive = false

    @ViewBuilder
    func body(content: Content) -> some View {
        if isPlayerPanel {
            content.background(playerFill, in: shape)
        } else {
            content.compatGlass(interactive: interactive, in: shape)
        }
    }
}
