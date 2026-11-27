import SwiftUI

/// 私人漫游 — immersive personal FM page.
struct FMView: View {
    @EnvironmentObject private var player: PlayerService
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openLogin) private var openLogin
    @Environment(\.colorScheme) private var colorScheme

    var phoneLayout = PhonePageLayout()
    private var isPhone: Bool { phoneLayout.isEnabled }

    var body: some View {
        ZStack {
            backdrop
            if account.hasAuthCookie {
                content
            } else {
                loginPrompt
            }
        }
        .navigationTitle("漫游")
        .compatHiddenToolbarBackground()
    }

    private var track: Track? {
        player.isFMMode ? player.currentTrack : nil
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        ZStack {
            Platform.windowBackgroundColor
            if let cover = track?.album.picUrl?.resizedImageURL(384) {
                CachedAsyncImage(url: cover)
                    .scaledToFill()
                    .blur(radius: 80)
                    .opacity(colorScheme == .dark ? 0.45 : 0.3)
                    .saturation(1.4)
            }
            LinearGradient(
                colors: [.clear, Platform.windowBackgroundColor.opacity(0.6)],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .animation(AppAnimation.smooth, value: track?.id)
    }

    // MARK: - Content

    private var content: some View {
        GeometryReader { geo in
            let maxDim: CGFloat = isPhone ? 240 : 300
            let coverDimension = max(110, min(maxDim, min(geo.size.width - 48, geo.size.height * 0.38)))
            let spacing: CGFloat = isPhone && geo.size.height < 520 ? Theme.Spacing.control : Theme.Spacing.section

            VStack(spacing: spacing) {
                Spacer()

                ZStack {
                    if let cover = track?.album.picUrl?.resizedImageURL(768) {
                        CachedAsyncImage(url: cover)
                            .frame(width: coverDimension, height: coverDimension)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .shadow(color: .black.opacity(0.35), radius: 28, y: 14)
                    } else {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(.quaternary.opacity(0.4))
                            .frame(width: coverDimension, height: coverDimension)
                            .overlay(
                                Image(systemName: "wave.3.right.circle")
                                    .font(
                                        .system(
                                            size: max(32, coverDimension * 0.25),
                                            weight: .light
                                        )
                                    )
                                    .foregroundStyle(.tertiary)
                            )
                    }
                }
                .scaleEffect(player.isPlaying && player.isFMMode ? 1 : 0.94)
                .animation(AppAnimation.bouncy, value: player.isPlaying && player.isFMMode)

                VStack(spacing: Theme.Spacing.small) {
                    HStack(spacing: Theme.Spacing.small) {
                        Text(track?.name ?? String(localized: "私人漫游"))
                            .font(isPhone && geo.size.height < 520 ? Theme.Typography.cardTitle : Theme.Typography.detailTitle)
                            .lineLimit(1)
                        if track?.fee == 1 {
                            VIPBadge()
                        }
                    }
                    Text(track?.artistNames ?? String(localized: "根据你的口味漫游好音乐"))
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: 420)

                if player.isFMMode {
                    controls
                } else {
                    Button {
                        player.startFM()
                    } label: {
                        Label("开始漫游", systemImage: "wave.3.right")
                            .font(Theme.Typography.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, Theme.Spacing.page)
                            .padding(.vertical, Theme.Spacing.control)
                            .background(Theme.accentGradient, in: Capsule())
                            .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 3)
                    }
                    .buttonStyle(.pressable)
                }

                Spacer()
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, Theme.Layout.contentInset)
        }
    }

    private var controls: some View {
        HStack(spacing: Theme.Spacing.group) {
            Button {
                player.fmTrash()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
            .help("不喜欢，换一首")

            Button {
                player.togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(Theme.accentGradient)
                        .frame(width: 64, height: 64)
                        .shadow(color: Theme.accent.opacity(0.4), radius: 12, y: 4)
                    if player.showsPlaybackLoading {
                        ProgressView().tint(.white)
                    } else {
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                            .modifier(PlayerSymbolTransition(symbol: player.isPlaying ? "pause.fill" : "play.fill"))
                    }
                }
            }
            .buttonStyle(.pressable)

            Button {
                player.fmNext()
            } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
            .buttonStyle(.pressable)
            .help("下一首")

            if let track {
                LikeButton(trackID: track.id, size: 16)
                    .frame(width: 48, height: 48)
                    .background(.primary.opacity(0.06), in: Circle())
            }
        }
    }

    private var loginPrompt: some View {
        VStack(spacing: Theme.Spacing.component) {
            Image(systemName: "wave.3.right.circle")
                .font(.system(size: 52, weight: .light))
                .foregroundStyle(.tertiary)
            Text("登录后开启私人漫游")
                .font(Theme.Typography.cardTitle)
            Text("网易云会根据你的听歌口味推荐音乐")
                .font(Theme.Typography.secondary)
                .foregroundStyle(.secondary)
            Button("登录") { openLogin() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
    }
}
