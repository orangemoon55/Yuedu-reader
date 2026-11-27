import SwiftUI

// MARK: - Lyrics panel

struct LyricsPanel: View {
    @EnvironmentObject private var player: PlayerService
    @ObservedObject private var lyricsCursor = PlayerService.shared.lyricsCursor
    @EnvironmentObject private var settings: SettingsManager

    @State private var activeIndex: Int?
    @State private var isUserScrolling = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            content
        }
        .frame(width: 320)
        .frame(maxHeight: .infinity)
        .blocksTouchPassThrough(in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .compatGlass(interactive: true, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.micro) {
                Text("歌词")
                    .font(Theme.Typography.cardTitle)
                if let contributor = player.lyrics?.contributor {
                    Text("贡献者：\(contributor)")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            Button {
                player.activePanel = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Theme.Spacing.component)
        .padding(.vertical, Theme.Spacing.component)
    }

    @ViewBuilder
    private var content: some View {
        if let lyrics = player.lyrics, !lyrics.isEmpty {
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.component) {
                        Color.clear.frame(height: 120)
                        ForEach(lyrics.lines) { line in
                            lyricLine(line, isActive: lyricsCursor.activeIndices.contains(line.id))
                                .id(line.id)
                        }
                        Color.clear.frame(height: 160)
                    }
                    .padding(.horizontal, Theme.Spacing.page)
                }
                .onChange(of: lyricsCursor.activeIndex) { index in
                    guard index != activeIndex else { return }
                    activeIndex = index
                    guard !isUserScrolling, let index else { return }
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
                .onAppear {
                    adoptCursor(proxy: proxy)
                }
                .onChange(of: player.currentTrack?.id) { _ in
                    activeIndex = nil
                    proxy.scrollTo(0, anchor: .top)
                }
                .lyricsScrollTracking(isUserScrolling: $isUserScrolling) {
                    guard let index = lyricsCursor.activeIndex else { return }
                    activeIndex = index
                    withAnimation(.spring(response: 0.7, dampingFraction: 0.85)) {
                        proxy.scrollTo(index, anchor: .center)
                    }
                }
            }
        } else if player.lyrics?.isInstrumental == true {
            EmptyStateView(icon: "music.quarternote.3", title: "纯音乐", subtitle: "请欣赏")
        } else if player.hasCurrentTrack {
            VStack(spacing: Theme.Spacing.control) {
                ProgressView().controlSize(.small)
                Text("歌词加载中…")
                    .font(Theme.Typography.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            EmptyStateView(icon: "quote.bubble", title: "暂无歌词")
        }
    }


    /// Jump straight to the line the song is on. Used when the view appears,
    /// where waiting for the next line change would leave the lyrics parked at
    /// the top. Scrolling is deferred a turn: the list has not laid out yet
    /// while `onAppear` runs, and `scrollTo` on an unlaid list does nothing.
    private func adoptCursor(proxy: ScrollViewProxy) {
        let index = lyricsCursor.activeIndex
        activeIndex = index
        guard let index else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(index, anchor: .center)
        }
    }

    private func lyricLine(_ line: LyricLine, isActive: Bool) -> some View {
        Button {
            player.seek(to: line.time - player.lyricsTimeOffset)
        } label: {
            VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                if settings.lyricsAnnotation == .romaji, let romaji = line.romaji {
                    Text(romaji)
                        .font(.system(size: isActive ? 12 : 11))
                        .foregroundStyle(isActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                }
                LyricText(
                    line: line,
                    size: isActive ? 16 : 14,
                    weight: isActive ? .bold : .medium,
                    // Core Text needs a resolved colour, so the hierarchical
                    // styles the other rows use are spelled out here.
                    color: isActive ? .primary : .secondary
                )
                if settings.showLyricsTranslation, let translation = line.translation {
                    Text(translation)
                        .font(.system(size: isActive ? 13 : 12))
                        .foregroundStyle(isActive ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
                }
            }
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(isActive ? 1 : 0.75)
            .blur(radius: isActive || isUserScrolling ? 0 : 0.3)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: isActive)
        .animation(.easeOut(duration: 0.25), value: isUserScrolling)
    }
}

// MARK: - Queue panel

struct QueuePanel: View {
    @EnvironmentObject private var player: PlayerService

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.3)
            if let current = player.currentTrack {
                ScrollView(showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: Theme.Spacing.micro) {
                        PlaybackHandoffList()
                            .padding(.bottom, Theme.Spacing.small)
                        sectionLabel("正在播放")
                        QueueRow(track: current, isCurrent: true)

                        if !player.upcomingTracks.isEmpty {
                            sectionLabel("即将播放")
                                .padding(.top, Theme.Spacing.control)
                            ForEach(Array(player.upcomingTracks.prefix(100).enumerated()),
                                    id: \.offset) { index, track in
                                QueueRow(track: track, isCurrent: false, upcomingIndex: index)
                            }
                        }
                    }
                    .padding(Theme.Spacing.control)
                }
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: Theme.Spacing.control) {
                        PlaybackHandoffList()
                        EmptyStateView(icon: "list.bullet", title: "播放队列是空的",
                                       subtitle: "播放一些音乐吧")
                    }
                    .padding(Theme.Spacing.control)
                }
            }
        }
        .frame(width: 340)
        .frame(maxHeight: .infinity)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    private var header: some View {
        HStack {
            Text("播放队列")
                .font(Theme.Typography.cardTitle)
            Text("\(player.upcomingTracks.count + (player.hasCurrentTrack ? 1 : 0)) 首")
                .font(Theme.Typography.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button {
                player.activePanel = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 22, height: 22)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
        }
        .padding(.horizontal, Theme.Spacing.component)
        .padding(.vertical, Theme.Spacing.component)
    }

    private func sectionLabel(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(Theme.Typography.caption.weight(.semibold))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, Theme.Spacing.small)
            .padding(.vertical, Theme.Spacing.tight)
    }
}

private struct QueueRow: View {
    let track: Track
    let isCurrent: Bool
    var upcomingIndex: Int? = nil

    @EnvironmentObject private var player: PlayerService
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: Theme.Spacing.small) {
            Button {
                guard !isCurrent else { return }
                if let upcomingIndex { player.jumpToUpcoming(at: upcomingIndex, matching: track.id) }
                else { player.jumpTo(track) }
            } label: {
                HStack(spacing: Theme.Spacing.control) {
                    CachedAsyncImage(url: track.album.picUrl?.resizedImageURL(96), animated: false)
                        .frame(width: 36, height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    VStack(alignment: .leading, spacing: Theme.Spacing.micro) {
                        Text(track.name)
                            .font(Theme.Typography.caption.weight(.medium))
                            .foregroundStyle(isCurrent ? Theme.accent : .primary)
                            .lineLimit(1)
                        Text(track.artistNames)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            #if os(macOS)
            TrackDownloadButton(track: track, isVisible: isHovering)
            #endif

            ZStack {
                if isCurrent {
                    PlayingIndicator(animating: player.isPlaying)
                } else if isHovering {
                    Button {
                        if let upcomingIndex { player.removeUpcoming(at: upcomingIndex, matching: track.id) }
                        else { player.removeFromUpcoming(track) }
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.pressable)
                    .accessibilityLabel("移除")
                    .help("移除")
                } else {
                    Text(Formatters.duration(track.duration))
                        .font(Theme.Typography.caption.monospacedDigit())
                        .foregroundStyle(.quaternary)
                }
            }
            .frame(width: 32)
        }
        .padding(.horizontal, Theme.Spacing.small)
        .padding(.vertical, Theme.Spacing.tight)
        .background(.primary.opacity(isHovering ? 0.06 : 0), in: RoundedRectangle(cornerRadius: Theme.Radius.standard))
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
