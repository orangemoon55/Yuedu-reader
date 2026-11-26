import Combine
import SwiftUI

/// Music uses the existing shared player, never a second playback or navigation owner.
enum MusicPlaybackCapsulePolicy {
    static func isPresented(hasTrack: Bool, musicOwnsSession: Bool,
                            tabBarHidden: Bool, keyboardVisible: Bool) -> Bool {
        hasTrack && musicOwnsSession && !tabBarHidden && !keyboardVisible
    }
}

/// Project only session changes into the root. Playback's clock redraws the small capsule,
/// not all of the tab navigation content four times a second.
@MainActor
private final class MusicCapsulePresentationModel: ObservableObject {
    @Published private(set) var track: MediaHubLibraryItem?
    @Published private(set) var musicOwnsSession = false
    private var observations = Set<AnyCancellable>()

    init() {
        let player = MusicPlayer.shared
        let hub = NowPlayingHub.shared
        track = player.currentTrack
        musicOwnsSession = hub.source == .music
        player.$currentTrack.sink { [weak self] in self?.track = $0 }.store(in: &observations)
        hub.$source.map { $0 == .music }.removeDuplicates()
            .sink { [weak self] in self?.musicOwnsSession = $0 }.store(in: &observations)
    }
}

/// Use the root's existing measured overlay and scroll margins. On phones the capsule sits
/// above the floating tabs; on native iPad tabs only the capsule is reserved. Navigation
/// stacks and the audiobook/TTS popup retain their original lifetimes and ownership.
struct MusicPlaybackRootAccessory<Bar: View>: ViewModifier {
    let showsFloatingBar: Bool
    let tabBarHidden: Bool
    let keyboardVisible: Bool
    @ViewBuilder var floatingBar: () -> Bar
    @StateObject private var presentation = MusicCapsulePresentationModel()
    @State private var showsPlayer = false

    private var showsCapsule: Bool {
        MusicPlaybackCapsulePolicy.isPresented(
            hasTrack: presentation.track != nil, musicOwnsSession: presentation.musicOwnsSession,
            tabBarHidden: tabBarHidden, keyboardVisible: keyboardVisible)
    }

    func body(content: Content) -> some View {
        content
            .modifier(FloatingRootTabBarContainer(isPresented: showsFloatingBar || showsCapsule) {
                VStack(spacing: 6) {
                    if showsCapsule {
                        MusicPlaybackCapsule(openPlayer: { showsPlayer = true })
                            .padding(.top, 8)
                            .padding(.bottom, showsFloatingBar ? 0 : 8)
                    }
                    if showsFloatingBar { floatingBar() }
                }
            })
            .sheet(isPresented: $showsPlayer) {
                if let item = MusicPlayer.shared.currentTrack {
                    // Expanding a paused session must not restart playback or replace its queue.
                    MusicPlayerView(item: item, queue: MusicPlayer.shared.queue, autoPlay: false)
                }
            }
            .onChange(of: presentation.track?.id) { _, id in
                if id == nil { showsPlayer = false }
            }
    }
}

struct MusicPlaybackCapsule: View {
    let openPlayer: () -> Void
    @ObservedObject private var player = MusicPlayer.shared
    @ObservedObject private var lyrics = MusicLyricsModel.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var subtitle: String {
        if let error = player.errorMessage { return error }
        if lyrics.trackID == player.currentTrack?.id, let value = lyrics.lyrics,
           let index = value.index(at: player.currentTime), value.lines.indices.contains(index),
           !value.lines[index].text.isEmpty { return value.lines[index].text }
        return player.currentTrack?.remarks ?? localized("音樂播放")
    }

    private var progress: Double {
        guard player.duration.isFinite, player.duration > 0, player.currentTime.isFinite else { return 0 }
        return min(1, max(0, player.currentTime / player.duration))
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: openPlayer) {
                HStack(spacing: 10) {
                    MusicCatalogArtwork(poster: player.currentTrack?.poster ?? "", size: 40, cornerRadius: 20)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(player.currentTrack?.title ?? localized("音樂播放"))
                            .font(.subheadline.weight(.semibold)).lineLimit(1)
                        Text(subtitle).font(.caption).foregroundStyle(player.errorMessage == nil ? Color.secondary : Color.red)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(minHeight: 48).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("展開音樂播放器"))
            .accessibilityValue([player.currentTrack?.title ?? "", subtitle].joined(separator: "，"))
            .accessibilityIdentifier("mediaHub.music.capsule.open")
            Button { player.togglePlayPause() } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.title3).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized(player.isPlaying ? "暫停" : "播放"))
            .accessibilityIdentifier("mediaHub.music.capsule.playPause")
            if !dynamicTypeSize.isAccessibilitySize {
                Button { player.next() } label: {
                    Image(systemName: "forward.end.fill").font(.body).frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.plain)
                .disabled(player.queue.last?.id == player.currentTrack?.id)
                .accessibilityLabel(localized("下一首"))
                .accessibilityIdentifier("mediaHub.music.capsule.next")
            }
        }
        .foregroundStyle(.primary)
        .padding(.leading, 10).padding(.trailing, 8).padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(alignment: .bottom) {
            ProgressView(value: progress).tint(DSColor.accent)
                .padding(.horizontal, 32).padding(.bottom, 4)
                .accessibilityLabel(localized("播放進度"))
        }
        .overlay { Capsule().strokeBorder(.primary.opacity(0.07), lineWidth: 0.5) }
        .frame(maxWidth: 560)
        .padding(.horizontal, 16)
        .contextMenu {
            Button(action: openPlayer) { Label(localized("音樂播放"), systemImage: "music.note") }
            Button { player.next() } label: { Label(localized("下一首"), systemImage: "forward.end") }
                .disabled(player.queue.last?.id == player.currentTrack?.id)
            Button(role: .destructive) { player.stop() } label: {
                Label(localized("停止播放"), systemImage: "stop.fill")
            }
        }
        .task(id: player.currentTrack?.id) { await lyrics.load(for: player.currentTrack) }
        .accessibilityIdentifier("mediaHub.music.capsule")
    }
}
