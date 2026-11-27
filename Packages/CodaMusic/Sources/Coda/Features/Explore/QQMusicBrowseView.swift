import SwiftUI

enum QQMusicBrowseKind: Hashable {
    case songRelated(Int)
}

struct QQMusicBrowseView: View {
    let kind: QQMusicBrowseKind
    @Environment(\.openDestination) private var openDestination
    @State private var playlists: [PlaylistSummary] = []
    @State private var tracks: [Track] = []
    @State private var versions: [Track] = []
    @State private var labels: [String] = []
    @State private var favoriteCount: Int?
    @State private var loading = true
    @State private var error: String?

    private var title: String {
        switch kind {
        case .songRelated: return "歌曲相关内容"
        }
    }

    var body: some View {
        ScenePreservingScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.component) {
                if !labels.isEmpty || favoriteCount != nil {
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        if let favoriteCount { Text("收藏数 \(favoriteCount)").foregroundStyle(.secondary) }
                        if !labels.isEmpty { Text(labels.joined(separator: " · ")) }
                    }
                }
                if !versions.isEmpty {
                    Text("其他版本").font(.headline)
                    MusicTrackPanel(tracks: versions, scrollsHorizontally: false)
                }
                if !tracks.isEmpty {
                    if case .songRelated = kind { Text("相似歌曲").font(.headline) }
                    MusicTrackPanel(tracks: tracks, scrollsHorizontally: false)
                }
                if !playlists.isEmpty {
                    if case .songRelated = kind { Text("相关歌单").font(.headline) }
                    CardGrid {
                        ForEach(playlists) { item in
                            Button { openDestination(.playlist(item.id)) } label: {
                                CoverCardBody(coverURL: item.coverURL.flatMap(URL.init(string:)), title: item.name, subtitle: nil)
                            }
                            .buttonStyle(.interactiveCard)
                        }
                    }
                }
                if loading {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 120)
                } else if let error {
                    ErrorStateView(message: error) { Task { await load() } }
                } else if tracks.isEmpty, playlists.isEmpty, versions.isEmpty, labels.isEmpty, favoriteCount == nil {
                    EmptyStateView(icon: "music.note", title: "暂无内容", subtitle: "")
                }
                PlayerClearanceSpacer()
            }
            .padding(.horizontal, Theme.Layout.contentInset)
            .pageHeaderTopPadding(Theme.Spacing.component)
        }
        .appRootNavigationTitle(title)
        .task { await load() }
    }

    @MainActor
    private func load() async {
        let ticket = MusicProviderContext.shared.ticket
        loading = true
        error = nil
        defer { if !Task.isCancelled { loading = false } }
        playlists = []
        tracks = []
        versions = []
        labels = []
        favoriteCount = nil
        do {
            let api = QQMusicAPI.shared
            let platform = PlatformMusicAPI.shared
            switch kind {
            case .songRelated(let id):
                async let similar = try? platform.qqSimilarSongs(id: id, limit: 20)
                async let related = try? platform.qqRelatedPlaylists(id: id)
                async let extras = try? platform.qqSongExtras(id: id)
                let results = await (similar, related, extras)
                try MusicProviderContext.shared.check(ticket)
                tracks = results.0 ?? []
                playlists = results.1 ?? []
                versions = results.2?.versions ?? []
                labels = results.2?.labels ?? []
                favoriteCount = results.2?.count
            }
        } catch is CancellationError { }
        catch { if !Task.isCancelled { self.error = error.localizedDescription } }
    }
}

