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
    @State private var lyricsByTrackID: [String: YingxiaMusicLyrics] = [:]
    @State private var lyricsImportErrorsByTrackID: [String: String] = [:]
    @State private var isImportingLyrics = false
    @State private var lyricsImportTargetTrackID: String?
    @State private var lyricsImportGeneration: UUID?
    @State private var playbackSelectionGeneration = UUID()

    private static let lrcContentType = UTType(filenameExtension: "lrc", conformingTo: .plainText) ?? .plainText

    private var displayedTrack: MediaHubLibraryItem { player.currentTrack ?? item }

    init(item: MediaHubLibraryItem, queue: [MediaHubLibraryItem] = [], autoPlay: Bool = true) {
        self.item = item
        self.queue = queue
        self.autoPlay = autoPlay
    }

    var body: some View {
        NavigationStack {
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
                    }.disabled(player.currentTrack == nil)
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
                    .accessibilityIdentifier("mediaHub.music.play")
                    Button { player.next() } label: {
                        Image(systemName: "forward.fill").font(DSFont.title2)
                    }.disabled(player.currentTrack == nil || player.queue.last?.id == player.currentTrack?.id)
                }
                Button(role: .destructive) { player.stop() } label: {
                    Label(localized("停止播放"), systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
                .disabled(player.currentTrack == nil)
                Spacer()
            }
            .padding(DSSpacing.lg)
            .navigationTitle(localized("音樂播放"))
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
        .onChange(of: player.currentTrack?.id) { _, _ in
            playbackSelectionGeneration = UUID()
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
                Text(localized("歌詞")).font(DSFont.subheadline.weight(.semibold))
                    .foregroundStyle(DSColor.textPrimary)
                Spacer()
                Button(action: beginLyricsImport) {
                    Label(localized("匯入本地 LRC"), systemImage: "doc.badge.plus")
                        .font(DSFont.caption)
                }
                .accessibilityIdentifier("mediaHub.music.lyrics.import")
            }
            if let lyrics = lyricsByTrackID[displayedTrack.id] {
                MusicLyricsTimelineView(
                    lyrics: lyrics,
                    currentTime: player.currentTrack?.id == displayedTrack.id ? player.currentTime : 0,
                    seek: { if player.currentTrack?.id == displayedTrack.id { player.seek(to: $0) } }
                )
            } else if let message = lyricsImportErrorsByTrackID[displayedTrack.id] {
                Text(message)
                    .font(DSFont.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 86)
            } else {
                Text(localized("此播放器目前未接入線上歌詞請求；可匯入你有權使用的本機 .lrc 檔。"))
                    .font(DSFont.caption)
                    .foregroundStyle(DSColor.textSecondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 86)
            }
        }
        .padding(DSSpacing.md)
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .accessibilityIdentifier("mediaHub.music.lyrics")
    }

    private func beginLyricsImport() {
        lyricsImportTargetTrackID = displayedTrack.id
        lyricsImportGeneration = playbackSelectionGeneration
        isImportingLyrics = true
    }

    private func loadLyrics(_ result: Result<URL, Error>) {
        let targetID = lyricsImportTargetTrackID
        let generation = lyricsImportGeneration
        defer {
            lyricsImportTargetTrackID = nil
            lyricsImportGeneration = nil
        }
        guard let targetID,
              MusicLyricsImportOwnership.accepts(
                  targetTrackID: targetID, targetGeneration: generation,
                  currentTrackID: displayedTrack.id, currentGeneration: playbackSelectionGeneration
              ) else { return }

        switch result {
        case .success(let url):
            do {
                lyricsByTrackID[targetID] = try YingxiaMusicLyrics.load(from: url)
                lyricsImportErrorsByTrackID[targetID] = nil
            } catch {
                lyricsImportErrorsByTrackID[targetID] = error.localizedDescription
            }
        case .failure(let error):
            guard (error as NSError).code != NSUserCancelledError else { return }
            lyricsImportErrorsByTrackID[targetID] = error.localizedDescription
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
                    withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
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
                    TextField(localized("音訊直鏈（http/https）"), text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                        .accessibilityIdentifier("mediaHub.music.directURL")
                    TextField(localized("標題（可選）"), text: $title)
                    TextField(localized("演出者（可選）"), text: $artist)
                    TextField(localized("請求頭 JSON（可選）"), text: $headersJSON, axis: .vertical)
                        .lineLimit(2...5)
                        .textInputAutocapitalization(.never)
                } footer: {
                    Text(localized("只會播放你有權使用的直鏈；Readcc 不代替來源取得授權或繞過限制。"))
                }
                Section {
                    Button {
                        onImport(url, title, artist, headersJSON)
                        dismiss()
                    } label: {
                        Label(localized("加入並播放"), systemImage: "plus.circle.fill")
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle(localized("加入音樂直鏈"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button(localized("取消")) { dismiss() } } }
        }
    }
}
