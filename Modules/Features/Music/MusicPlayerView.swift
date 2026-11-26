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
    @State private var scrub = MusicPlayerScrubState()

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
                    MusicCatalogArtwork(poster: displayedTrack.poster, size: 136)
                        .accessibilityIdentifier("mediaHub.music.artwork")
                    Text(displayedTrack.title)
                        .font(DSFont.title2.weight(.bold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(DSColor.textPrimary)
                    if let artist = displayedTrack.remarks, !artist.isEmpty {
                        Text(artist).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
                    }
                    if let quality = displayedTrack.musicQuality?.trimmingCharacters(in: .whitespacesAndNewlines), !quality.isEmpty {
                        VStack(spacing: DSSpacing.xs) {
                            Text(String(format: localized("请求音质：%@"), quality))
                                .accessibilityIdentifier("mediaHub.music.sourceQuality")
                            Text(localized("源请求档位，非实测音质。"))
                        }
                        .font(DSFont.caption)
                        .foregroundStyle(DSColor.textSecondary)
                    }
                    if player.isBuffering, player.currentTrack?.id == displayedTrack.id {
                        ProgressView(localized("正在缓冲…"))
                            .font(DSFont.caption)
                            .foregroundStyle(DSColor.textSecondary)
                            .accessibilityIdentifier("mediaHub.music.buffering")
                    }
                    if let error = player.errorMessage, player.currentTrack?.id == displayedTrack.id {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .font(DSFont.footnote)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("mediaHub.music.error")
                    }
                    progressPanel
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
                    lyricsPanel
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
        .onChange(of: player.currentTrack?.id) { _, _ in scrub.cancel() }
        .onChange(of: player.playbackInstanceID) { _, _ in scrub.cancel() }
        .onDisappear { scrub.cancel() }
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

    private var progressPanel: some View {
        let trackID = displayedTrack.id
        let instanceID = player.playbackInstanceID
        let scope = MusicPlayerScrubState.scope(trackID: trackID, instanceID: instanceID)
        let isCurrent = player.currentTrack?.id == trackID
        let duration = isCurrent && player.duration.isFinite ? max(0, player.duration) : 0
        let elapsed = scrub.previewTime(for: scope) ?? (isCurrent ? player.currentTime : 0)
        return VStack(spacing: DSSpacing.sm) {
            Slider(value: Binding(get: {
                min(max(0, elapsed), max(1, duration))
            }, set: { value in
                guard player.currentTrack?.id == trackID, player.playbackInstanceID == instanceID else { return }
                scrub.preview(value, trackID: scope, duration: duration)
            }), in: 0...max(1, duration), onEditingChanged: { editing in
                if editing {
                    guard player.currentTrack?.id == trackID, player.playbackInstanceID == instanceID else { return }
                    scrub.begin(trackID: scope, time: player.currentTime, duration: duration)
                } else if let target = scrub.finish(
                    trackID: scope,
                    currentTrackID: player.currentTrack.map {
                        MusicPlayerScrubState.scope(trackID: $0.id, instanceID: player.playbackInstanceID)
                    }, duration: player.duration
                ) {
                    player.seek(to: target)
                }
            })
            .id(scope)
            .disabled(!isCurrent || duration <= 0)
            .accessibilityLabel(localized("播放进度"))
            .accessibilityValue(Self.time(elapsed) + " / " + Self.time(duration))
            .accessibilityHint(localized("上下轻扫可前进或后退 5 秒。"))
            .accessibilityAdjustableAction { direction in
                guard player.currentTrack?.id == trackID, player.playbackInstanceID == instanceID else { return }
                let delta: TimeInterval
                switch direction {
                case .increment: delta = 5
                case .decrement: delta = -5
                @unknown default: return
                }
                guard let target = MusicPlayerScrubState.accessibilityTarget(
                    currentTime: player.currentTime, duration: player.duration, delta: delta
                ) else { return }
                // VoiceOver does not necessarily send Slider editing callbacks.
                scrub.cancel()
                player.seek(to: target)
            }
            .accessibilityIdentifier("mediaHub.music.progress")
            HStack {
                Text(Self.time(elapsed))
                Spacer()
                Text(Self.time(duration))
            }
            .font(DSFont.caption.monospacedDigit())
            .foregroundStyle(DSColor.textSecondary)
        }
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
            if let lyrics = lyricsModel.lyrics, let trackID = player.currentTrack?.id, lyricsModel.trackID == trackID {
                let instanceID = player.playbackInstanceID
                MusicLyricsTimelineView(
                    lyrics: lyrics,
                    currentTime: player.currentTime,
                    seek: {
                        if player.currentTrack?.id == trackID, player.playbackInstanceID == instanceID { player.seek(to: $0) }
                    }
                )
                // SwiftUI identity scopes every lyric adjustment to this track, not the sheet.
                .id(trackID)
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
            || current?.musicHeaders != proposed.musicHeaders
            || current?.musicQuality != proposed.musicQuality || hasError
    }

    private static func time(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0 else { return "0:00" }
        let total = Int(value.rounded(.down))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }
}

/// A drag is a local preview until its matching end event. Stale callbacks cannot seek or
/// cancel another track's drag, and a second end event cannot commit the same preview twice.
struct MusicPlayerScrubState {
    private var trackID: String?
    private var pendingTime: TimeInterval?

    /// The UUID prefix has a fixed width, so track IDs containing separators stay distinct.
    /// Replacing an item (including A→B→A) invalidates callbacks captured for an old instance.
    static func scope(trackID: String, instanceID: UUID) -> String {
        instanceID.uuidString + ":" + trackID
    }

    mutating func begin(trackID: String, time: TimeInterval, duration: TimeInterval) {
        guard duration.isFinite, duration > 0 else { return }
        self.trackID = trackID
        pendingTime = Self.clamp(time, duration: duration)
    }

    mutating func preview(_ time: TimeInterval, trackID: String, duration: TimeInterval) {
        guard self.trackID == trackID, time.isFinite, duration.isFinite, duration > 0 else { return }
        pendingTime = Self.clamp(time, duration: duration)
    }

    func previewTime(for trackID: String) -> TimeInterval? {
        self.trackID == trackID ? pendingTime : nil
    }

    mutating func finish(trackID: String, currentTrackID: String?, duration: TimeInterval) -> TimeInterval? {
        guard self.trackID == trackID else { return nil }
        defer { cancel() }
        guard currentTrackID == trackID, duration.isFinite, duration > 0, let pendingTime else { return nil }
        return Self.clamp(pendingTime, duration: duration)
    }

    mutating func cancel() {
        trackID = nil
        pendingTime = nil
    }

    static func accessibilityTarget(currentTime: TimeInterval, duration: TimeInterval, delta: TimeInterval) -> TimeInterval? {
        guard currentTime.isFinite, duration.isFinite, duration > 0, delta.isFinite else { return nil }
        return clamp(currentTime + delta, duration: duration)
    }

    private static func clamp(_ time: TimeInterval, duration: TimeInterval) -> TimeInterval {
        time.isFinite ? max(0, min(time, duration)) : 0
    }
}

/// Positive adjustment advances the lyric display; inverse mapping keeps line taps aligned.
enum MusicLyricsTiming {
    static let offsetRange = -10.0...10.0
    static let offsetStep = 0.5

    static func lyricTime(currentTime: TimeInterval, offset: TimeInterval) -> TimeInterval {
        currentTime + offset
    }

    static func seekTime(lineTime: TimeInterval, offset: TimeInterval) -> TimeInterval {
        max(0, lineTime - offset)
    }
}

/// Lyrics are driven from the shared player's published clock; tapping a timed line seeks
/// that same AVPlayer rather than starting a separate audio session.
private struct MusicLyricsTimelineView: View {
    let lyrics: YingxiaMusicLyrics
    let currentTime: TimeInterval
    let seek: (TimeInterval) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isExpanded = false
    @State private var showsTranslations = true
    @State private var followsPlayback = true
    @State private var syncOffset: TimeInterval = 0

    private var activeIndex: Int? {
        lyrics.index(at: MusicLyricsTiming.lyricTime(currentTime: currentTime, offset: syncOffset))
    }

    var body: some View {
        VStack(spacing: DSSpacing.sm) {
            HStack {
                Button {
                    isExpanded.toggle()
                } label: {
                    Label(localized(isExpanded ? "收起歌词" : "展开歌词"),
                          systemImage: isExpanded ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                }
                .accessibilityIdentifier("mediaHub.music.lyrics.expand")
                Spacer()
                if lyrics.synced && !followsPlayback {
                    Button(localized("恢复跟随")) { followsPlayback = true }
                        .accessibilityIdentifier("mediaHub.music.lyrics.resumeFollowing")
                }
            }
            .font(DSFont.caption)
            if lyrics.synced {
                Toggle(localized("自动跟随"), isOn: $followsPlayback)
                    .font(DSFont.caption)
                    .tint(DSColor.accent)
                    .accessibilityHint(localized("手动滚动歌词会暂停跟随。"))
                    .accessibilityIdentifier("mediaHub.music.lyrics.follow")
            }
            if lyrics.lines.contains(where: { !($0.translation ?? "").isEmpty }) {
                Toggle(localized("显示翻译"), isOn: $showsTranslations)
                    .font(DSFont.caption)
                    .tint(DSColor.accent)
                    .accessibilityIdentifier("mediaHub.music.lyrics.translation")
            }
            Group {
                if lyrics.synced {
                    synchronizedTimeline
                } else {
                    ScrollView {
                        LazyVStack(spacing: DSSpacing.sm) {
                            ForEach(lyrics.lines.indices, id: \.self) { index in
                                lyricContent(lyrics.lines[index], isActive: false)
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
            .frame(height: isExpanded ? 320 : 160)
            .accessibilityIdentifier("mediaHub.music.lyrics.timeline")
            if lyrics.synced { synchronizationControls }
        }
    }

    private var synchronizedTimeline: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: DSSpacing.sm) {
                    ForEach(lyrics.lines.indices, id: \.self) { index in
                        let line = lyrics.lines[index]
                        let target = MusicLyricsTiming.seekTime(lineTime: line.time, offset: syncOffset)
                        Button { seek(target) } label: {
                            lyricContent(line, isActive: index == activeIndex)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint(localized("跳至") + " " + MusicHomePresentation.time(target))
                        .id(index)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { value in
                if abs(value.translation.height) > abs(value.translation.width) { followsPlayback = false }
            })
            .onAppear { scrollToActive(proxy, animated: false) }
            .onChange(of: activeIndex) { _, _ in
                guard followsPlayback else { return }
                scrollToActive(proxy)
            }
            .onChange(of: followsPlayback) { _, following in
                if following { scrollToActive(proxy) }
            }
            .onChange(of: isExpanded) { _, _ in
                if followsPlayback { scrollToActive(proxy, animated: false) }
            }
            .onChange(of: showsTranslations) { _, _ in
                if followsPlayback { scrollToActive(proxy, animated: false) }
            }
        }
    }

    private var synchronizationControls: some View {
        DisclosureGroup {
            Stepper(value: $syncOffset, in: MusicLyricsTiming.offsetRange, step: MusicLyricsTiming.offsetStep) {
                Text(String(format: localized("同步偏移：%@ 秒"), String(format: "%+.1f", syncOffset)))
                    .monospacedDigit()
            }
            .accessibilityIdentifier("mediaHub.music.lyrics.offset")
            Text(localized("正数提前，负数延后；仅对当前歌曲生效。"))
                .foregroundStyle(DSColor.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(localized("重置偏移")) { syncOffset = 0 }
                .disabled(syncOffset == 0)
                .accessibilityIdentifier("mediaHub.music.lyrics.resetOffset")
        } label: {
            Text(localized("同步调整"))
        }
        .font(DSFont.caption)
        .accessibilityIdentifier("mediaHub.music.lyrics.synchronization")
    }

    private func scrollToActive(_ proxy: ScrollViewProxy, animated: Bool = true) {
        guard !lyrics.lines.isEmpty else { return }
        let index = activeIndex ?? 0
        if reduceMotion || !animated { proxy.scrollTo(index, anchor: .center) }
        else { withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) } }
    }

    private func lyricContent(_ line: YingxiaLyricLine, isActive: Bool) -> some View {
        VStack(spacing: 2) {
            Text(line.text.isEmpty ? "♪" : line.text)
                .font(DSFont.subheadline.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? DSColor.accent : DSColor.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            if showsTranslations, let translation = line.translation, !translation.isEmpty {
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
