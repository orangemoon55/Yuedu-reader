import SwiftUI

#if os(iOS)
/// Independent poster styling; the existing engine and transport buttons still
/// own loading, playback, FM behavior, accessibility and press feedback.
struct NowPlayingPosterTransportControls: View {
    @EnvironmentObject private var player: PlayerService
    let width: CGFloat
    let height: CGFloat

    private var playSide: CGFloat { min(82, width * 0.26) }
    private var sideWidth: CGFloat { max(0, (width - playSide) / 4) }

    var body: some View {
        HStack(spacing: 0) {
            PlayerTransportButton(icon: player.isFMMode ? "trash" : "shuffle",
                                  label: player.isFMMode ? "不喜欢" : "随机播放",
                                  size: 19, width: sideWidth, height: height,
                                  active: !player.isFMMode && player.shuffleEnabled) {
                if player.isFMMode { player.fmTrash() } else { player.toggleShuffle() }
            }
            .background(NowPlayingPosterControlDisc(selected: !player.isFMMode && player.shuffleEnabled))
            PlayerTransportButton(icon: "backward.fill", label: "上一首", size: 26,
                                  width: sideWidth, height: height, disabled: player.isFMMode,
                                  action: player.previous)
                .background(NowPlayingPosterControlDisc())
            PlayerPlayPauseButton(isPlaying: player.isPlaying, isLoading: player.showsPlaybackLoading,
                                  size: 31, width: playSide, tint: Color(red: 0.14, green: 0.11, blue: 0.08),
                                  height: height, action: player.togglePlayPause)
                .background {
                    Circle().fill(Color(red: 0.98, green: 0.77, blue: 0.49))
                        .frame(width: playSide, height: playSide)
                }
                .accessibilityIdentifier("iPadPlayPauseButton")
            PlayerTransportButton(icon: "forward.fill", label: "下一首", size: 26,
                                  width: sideWidth, height: height, action: player.next)
                .background(NowPlayingPosterControlDisc())
            PlayerTransportButton(icon: player.repeatMode == .one ? "repeat.1" : "repeat",
                                  label: "循环模式", size: 19, width: sideWidth, height: height,
                                  active: player.repeatMode != .off, disabled: player.isFMMode,
                                  action: player.cycleRepeatMode)
                .background(NowPlayingPosterControlDisc(selected: player.repeatMode != .off))
        }
        .frame(width: width, height: height)
        .accessibilityIdentifier("posterTransportControls")
    }
}

struct NowPlayingPosterControlDisc: View {
    var selected = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        Circle()
            .fill(reduceTransparency ? Color(white: selected ? 0.30 : 0.16)
                  : Color.white.opacity(selected ? 0.18 : 0.06))
            .overlay {
                Circle().strokeBorder(.white.opacity(contrast == .increased ? 0.45 : 0.10), lineWidth: 1)
            }
            .frame(width: 44, height: 44)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
