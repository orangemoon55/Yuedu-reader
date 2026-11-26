import SwiftUI

struct MusicCatalogArtwork: View {
    let poster: String
    let size: CGFloat
    var cornerRadius: CGFloat? = nil
    private var url: URL? {
        guard MediaHubLibraryItem.persistablePoster(poster) == poster,
              let url = URL(string: poster), url.scheme == "https", MusicJSRuntime.allowedRemoteURL(url) else { return nil }
        return url
    }
    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image): image.resizable().scaledToFill()
            case .empty: placeholder.overlay { if url != nil { ProgressView().controlSize(.small) } }
            case .failure: placeholder
            @unknown default: placeholder
            }
        }
        .frame(width: size, height: size).clipped()
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? (size > 100 ? 20 : 10)))
        .accessibilityHidden(true)
    }
    private var placeholder: some View {
        ZStack {
            Color(uiColor: .tertiarySystemFill)
            Image(systemName: "music.note").font(.system(size: size * 0.28)).foregroundStyle(.secondary)
        }
    }
}

struct MusicCatalogStatus: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(message, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
            Button(localized("重试"), action: retry).font(.subheadline)
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("mediaHub.music.catalogError")
    }
}

struct MusicCatalogSongRow: View {
    let title: String
    let subtitle: String
    let poster: String
    let busy: Bool
    let onPlay: () -> Void
    let onSave: () -> Void
    var isSaved = false
    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                MusicCatalogArtwork(poster: poster, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline).lineLimit(2)
                    if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
                }
                Spacer(minLength: 0)
                Image(systemName: "play.circle").font(.title2).foregroundStyle(.secondary)
            }.frame(minHeight: 56).foregroundStyle(.primary)
        }
        .buttonStyle(.plain).disabled(busy)
        .contextMenu {
            Button(role: isSaved ? .destructive : nil, action: onSave) {
                Label(localized(isSaved ? "移除收藏" : "加入媒体库"), systemImage: isSaved ? "bookmark.slash" : "bookmark")
            }
        }
    }
}

/// The home chevrons open real metadata, using the existing parent NavigationStack.
struct MusicCatalogDirectoryView: View {
    let title: String
    let entries: [MusicCatalogEntry]
    let showingOrigin: Bool
    let onPlay: (MusicCatalogTrack) -> Void
    let onSave: (MusicCatalogTrack) -> Void

    var body: some View {
        List(entries) { entry in
            NavigationLink {
                MusicCatalogCollectionView(entry: entry, onPlay: onPlay, onSave: onSave)
            } label: {
                HStack(spacing: 12) {
                    MusicCatalogArtwork(poster: entry.poster, size: 52)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(entry.title).font(.headline).lineLimit(2)
                        Text(MusicHomePresentation.catalogCaption(for: entry, showingOrigin: showingOrigin))
                            .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                }.padding(.vertical, 4)
            }
        }
        .navigationTitle(localized(title)).toolbarTitleDisplayMode(.inline)
        .accessibilityIdentifier("mediaHub.music.catalogDirectory")
    }
}

struct MusicCatalogCollectionView: View {
    let entry: MusicCatalogEntry
    let onPlay: (MusicCatalogTrack) -> Void
    let onSave: (MusicCatalogTrack) -> Void
    @State private var songs: [MusicCatalogEntry] = []
    @State private var loading = true
    @State private var failure: String?
    @State private var refreshID = UUID()
    @State private var generation = UUID()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    MusicCatalogArtwork(poster: entry.poster, size: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(entry.title).font(.title3.bold())
                        Text(entry.subtitle).font(.subheadline).foregroundStyle(.secondary)
                        Text(localized(entry.platform.providerName)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if loading { ProgressView(localized("载入歌曲资料…")).frame(maxWidth: .infinity) }
                else if let failure { MusicCatalogStatus(message: failure, retry: { refreshID = UUID() }) }
                else if songs.isEmpty { Text(localized("服务未返回可显示的歌曲。")) .foregroundStyle(.secondary) }
                else {
                    Text(localized("仅显示服务返回的前 100 首歌曲；部分内容可能需要授权，播放仍须由 JS 音源解析。"))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(songs) { song in
                        if let track = song.track {
                            MusicCatalogSongRow(title: track.title, subtitle: song.subtitle, poster: track.poster, busy: false,
                                                onPlay: { onPlay(track) }, onSave: { onSave(track) })
                            Divider()
                        }
                    }
                }
            }.padding(20)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(localized(entry.kind.title)).toolbarTitleDisplayMode(.inline)
        .accessibilityIdentifier("mediaHub.music.catalogDetail")
        .task(id: refreshID) {
            let token = UUID(); generation = token
            loading = true; failure = nil; songs = []
            do {
                let values = try await MusicPlatformCatalog.tracks(in: entry)
                guard !Task.isCancelled, generation == token else { return }
                songs = values; loading = false
            } catch {
                guard !Task.isCancelled, generation == token else { return }
                failure = error.localizedDescription; loading = false
            }
        }
    }
}
