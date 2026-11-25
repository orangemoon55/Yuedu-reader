import Foundation
import SwiftUI

/// Small, testable player surface for imported music. The underlying MusicPlayer remains alive
/// after the sheet closes, so background playback and lock-screen controls continue.
struct MusicPlayerView: View {
    let item: MediaHubLibraryItem
    let queue: [MediaHubLibraryItem]
    let autoPlay: Bool

    @ObservedObject private var player = MusicPlayer.shared
    @Environment(\.dismiss) private var dismiss
    @State private var didStart = false

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
                Text(item.title)
                    .font(DSFont.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(DSColor.textPrimary)
                if let artist = item.remarks, !artist.isEmpty {
                    Text(artist).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
                }
                if let error = player.errorMessage, player.currentTrack?.id == item.id {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(DSFont.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .accessibilityIdentifier("mediaHub.music.error")
                }
                Slider(value: Binding(get: {
                    player.currentTrack?.id == item.id ? player.currentTime : 0
                }, set: { player.seek(to: $0) }), in: 0...max(1, player.duration))
                .disabled(player.currentTrack?.id != item.id || player.duration <= 0)
                HStack {
                    Text(Self.time(player.currentTrack?.id == item.id ? player.currentTime : 0))
                    Spacer()
                    Text(Self.time(player.currentTrack?.id == item.id ? player.duration : 0))
                }
                .font(DSFont.caption.monospacedDigit())
                .foregroundStyle(DSColor.textSecondary)
                HStack(spacing: DSSpacing.lg) {
                    Button { player.previous() } label: {
                        Image(systemName: "backward.fill").font(DSFont.title2)
                    }.disabled(player.currentTrack == nil)
                    Button {
                        if player.currentTrack?.id == item.id && player.isPlaying { player.pause() }
                        else if player.currentTrack?.id == item.id { player.resume() }
                        else { player.play(item, queue: queue) }
                    } label: {
                        Image(systemName: player.currentTrack?.id == item.id && player.isPlaying ? "pause.fill" : "play.fill")
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
        .accessibilityIdentifier("mediaHub.music.player")
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
