import Foundation
import SwiftUI
import UniformTypeIdentifiers

/// Small, testable player surface for imported music. The underlying MusicPlayer remains alive
/// after the sheet closes, so background playback and lock-screen controls continue.
struct MusicPlayerView: View {
    let item: MediaHubLibraryItem
    let queue: [MediaHubLibraryItem]
    let autoPlay: Bool

    @ObservedObject private var player = MusicPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var didStart = false
    @ObservedObject private var lyricsModel = MusicLyricsModel.shared
    @State private var lyricsImportError: String?
    @State private var isImportingLyrics = false
    @State private var lyricsImportTargetTrackID: String?
    @State private var lyricsImportGeneration: UUID?

    private static let lrcContentType = UTType(filenameExtension: "lrc", conformingTo: .plainText) ?? .plainText

    private var displayedTrack: MediaHubLibraryItem { player.currentTrack ?? item }

    init(item: MediaHubLibraryItem, queue: [MediaHubLibraryItem] = [], autoPlay: Bool = true) {
        self.item = item
        self.queue = queue
        self.autoPlay = autoPlay
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    Spacer(minLength: DSSpacing.md)
                    Image(systemName: "music.note.list")
                        .font(.system(size: 72, weight: .light))
                        .foregroundStyle(DSColor.accent)
                        .accessibilityHidden(true)
                    Text(displayedTrack.title)
                        .font(DSFont.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DSColor.textPrimary)
                    if let artist = displayedTrack.remarks, !artist.isEmpty {
                        Text(artist).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
                    }
                    if let error = player.errorMessage, player.currentTrack?.id == displayedTrack.id {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(DSFont.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("mediaHub.music.error")
                    }
                    Slider(value: Binding(get: {
                        player.currentTrack?.id == displayedTrack.id ? player.currentTime : 0
                    }, set: { player.seek(to: $0) }), in: 0...max(1, player.duration))
                    .disabled(player.currentTrack?.id != displayedTrack.id || player.duration <= 0)
                    .accessibilityLabel(localized("播放进度"))
                    .accessibilityValue(Self.time(player.currentTime) + " / " + Self.time(player.duration))
                    HStack {
                        Text(Self.time(player.currentTrack?.id == displayedTrack.id ? player.currentTime : 0))
                        Spacer()
                        Text(Self.time(player.currentTrack?.id == displayedTrack.id ? player.duration : 0))
                    }
                    .font(DSFont.caption.monospacedDigit())
                    .foregroundStyle(DSColor.textSecondary)
                    lyricsPanel
                    HStack(spacing: DSSpacing.lg) {
                        Button { player.previous() } label: {
                            Image(systemName: "backward.fill").font(DSFont.title2)
                                .frame(minWidth: 44, minHeight: 44)
                        }.disabled(player.currentTrack == nil)
                        .accessibilityLabel(localized("上一首"))
                        Button {
                            if player.currentTrack?.id == displayedTrack.id && player.isPlaying { player.pause() }
                            else if player.currentTrack?.id == displayedTrack.id { player.resume() }
                            else { player.play(displayedTrack, queue: queue) }
                        } label: {
                            Image(systemName: player.currentTrack?.id == displayedTrack.id && player.isPlaying ? "pause.fill" : "play.fill")
                                .font(DSFont.title)
                                .frame(width: 58, height: 58)
                        }
                        .buttonStyle(.onAccentProminent)
                        .accessibilityLabel(localized(player.isPlaying ? "暂停" : "播放"))
                        .accessibilityIdentifier("mediaHub.music.play")
                        Button { player.next() } label: {
                            Image(systemName: "forward.fill").font(DSFont.title2)
                                .frame(minWidth: 44, minHeight: 44)
                        }.disabled(player.currentTrack == nil || player.queue.last?.id == player.currentTrack?.id)
                        .accessibilityLabel(localized("下一首"))
                    }
                    Button(role: .destructive) { player.stop() } label: {
                        Label(localized("停止播放"), systemImage: "stop.fill")
                    }
                    .buttonStyle(.bordered)
                    .disabled(player.currentTrack == nil)
                    Spacer()
                }
                .padding(DSSpacing.lg)
            }
            .navigationTitle(localized("音乐播放"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("完成")) { dismiss() }
                }
            }
            .themedAppSurface(for: .explore)
        }
        .task {
            guard autoPlay, !didStart else { return }
            didStart = true
            if Self.shouldReplace(current: player.currentTrack, with: item, hasError: player.errorMessage != nil) {
                player.play(item, queue: queue)
            }
        }
        .task(id: player.currentTrack?.id) {
            await lyricsModel.load(for: player.currentTrack)
        }
        .onChange(of: lyricsModel.generation) { _, _ in
            lyricsImportError = nil
            lyricsImportTargetTrackID = nil
            lyricsImportGeneration = nil
        }
        .fileImporter(isPresented: $isImportingLyrics, allowedContentTypes: [Self.lrcContentType]) { result in
            loadLyrics(result)
        }
        .accessibilityIdentifier("mediaHub.music.player")
    }

    private var lyricsPanel: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack {
                Text(localized("歌词")).font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Button(action: beginLyricsImport) {
                    Label(localized("汇入本地 LRC"), systemImage: "doc.badge.plus")
                        .font(DSFont.caption)
                }
                .accessibilityIdentifier("mediaHub.music.lyrics.import")
                .disabled(player.currentTrack == nil)
            }
            if let message = lyricsImportError {
                Text(message).font(DSFont.caption).foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if let lyrics = lyricsModel.lyrics, lyricsModel.trackID == player.currentTrack?.id, player.currentTrack != nil {
                MusicLyricsTimelineView(
                    lyrics: lyrics,
                    currentTime: player.currentTrack?.id == displayedTrack.id ? player.currentTime : 0,
                    seek: { if player.currentTrack?.id == displayedTrack.id { player.seek(to: $0) } }
                )
            } else {
                VStack(spacing: DSSpacing.sm) {
                    if lyricsModel.state == .loading { ProgressView() }
                    Text(lyricsStatusMessage)
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                        .multilineTextAlignment(.center)
                    if player.currentTrack != nil {
                        switch lyricsModel.state {
                        case .failed, .unavailable, .instrumental:
                            Button(localized("重试线上歌词")) { Task { await lyricsModel.retry() } }
                                .font(DSFont.caption)
                                .accessibilityIdentifier("mediaHub.music.lyrics.retry")
                        default: EmptyView()
                        }
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 86)
                .accessibilityIdentifier("mediaHub.music.lyrics.status")
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("mediaHub.music.lyrics")
    }

    private var lyricsStatusMessage: String {
        switch lyricsModel.state {
        case .idle: return localized("开始播放后可载入原平台歌词，或汇入你有权使用的本地 LRC。")
        case .loading: return localized("正在载入原平台歌词…")
        case .ready: return localized("此曲暂无可显示的歌词。")
        case .instrumental: return localized("平台标记此曲为纯音乐，没有歌词。")
        case .unavailable: return localized("原平台暂未收录此曲歌词；可重试或汇入本地 LRC。")
        case .unsupported: return localized("此曲无可用的网易云／QQ 原平台识别码；可汇入本地 LRC。")
        case .failed(let message): return message
        }
    }

    private func beginLyricsImport() {
        guard let currentTrack = player.currentTrack, lyricsModel.trackID == currentTrack.id else { return }
        lyricsImportTargetTrackID = currentTrack.id
        lyricsImportGeneration = lyricsModel.generation
        isImportingLyrics = true
    }

    private func loadLyrics(_ result: Result<URL, Error>) {
        let targetID = lyricsImportTargetTrackID
        let generation = lyricsImportGeneration
        defer {
            lyricsImportTargetTrackID = nil
            lyricsImportGeneration = nil
        }
        guard let targetID, let generation,
              MusicLyricsImportOwnership.accepts(
                  targetTrackID: targetID, targetGeneration: generation,
                  currentTrackID: player.currentTrack?.id ?? "", currentGeneration: lyricsModel.generation
              ), lyricsModel.trackID == targetID else { return }

        switch result {
        case .success(let url):
            do {
                let value = try YingxiaMusicLyrics.load(from: url)
                if lyricsModel.importLyrics(value, trackID: targetID, generation: generation) { lyricsImportError = nil }
            } catch {
                lyricsImportError = error.localizedDescription
            }
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            lyricsImportError = error.localizedDescription
        }
    }

    static func shouldReplace(current: MediaHubLibraryItem?, with proposed: MediaHubLibraryItem, hasError: Bool) -> Bool {
        current?.id != proposed.id || current?.musicURL != proposed.musicURL
            || current?.musicHeaders != proposed.musicHeaders || hasError
    }

    private static func time(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

/// Lyrics are driven from the shared player's published clock; tapping a timed line seeks
/// that same AVPlayer rather than starting a separate audio session.
private struct MusicLyricsTimelineView: View {
    let lyrics: YingxiaMusicLyrics
    let currentTime: TimeInterval
    let seek: (TimeInterval) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var activeIndex: Int? { lyrics.index(at: currentTime) }

    var body: some View {
        if lyrics.synced {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: DSSpacing.sm) {
                        ForEach(lyrics.lines.indices, id: \.self) { index in
                            let line = lyrics.lines[index]
                            Button { seek(line.time) } label: {
                                lyricContent(line, isActive: index == activeIndex)
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint(localized("跳至") + " " + MusicHomePresentation.time(line.time))
                            .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(height: 128)
                .onAppear {
                    if let activeIndex { proxy.scrollTo(activeIndex, anchor: .center) }
                }
                .onChange(of: activeIndex) { _, index in
                    guard let index else { return }
                    if reduceMotion { proxy.scrollTo(index, anchor: .center) }
                    else { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) } }
                }
            }
        } else {
            ScrollView {
                LazyVStack(spacing: DSSpacing.sm) {
                    ForEach(lyrics.lines.indices, id: \.self) { index in
                        lyricContent(lyrics.lines[index], isActive: false)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(height: 128)
        }
    }

    private func lyricContent(_ line: YingxiaLyricLine, isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(DSFont.subheadline.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? DSColor.accent : DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if let translation = line.translation {
                Text(translation)
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

struct MusicDirectImportSheet: View {
    let onImport: (String, String, String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    @State private var title = ""
    @State private var artist = ""
    @State private var headersJSON = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(localized("音讯直链（http/https）"), text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("mediaHub.music.directURL")
                    TextField(localized("标题（可选）"), text: $title)
                    TextField(localized("演出者（可选）"), text: $artist)
                    TextField(localized("请求头 JSON（可选）"), text: $headersJSON, axis: .vertical)
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text(localized("只会播放你有权使用的直链；Readcc 不代替来源取得授权或绕过限制。"))
                }
                Section {
                    Button {
                        onImport(url, title, artist, headersJSON)
                        dismiss()
                    } label: {
                        Label(localized("加入并播放"), systemImage: "plus.circle.fill")
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(localized("加入音乐直链"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(localized("取消")) { dismiss() } } }
        }
    }
}
