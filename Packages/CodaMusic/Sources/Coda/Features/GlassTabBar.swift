import SwiftUI

enum IOSTab: Hashable {
    case home, search, library
}

extension IOSTab {
    /// Bottom navigation order shared by iPhone and compact windows.
    static let barItems: [GlassTabBar.Item] = [
        .init(tab: .home, title: "推荐", icon: "house"),
        .init(tab: .search, title: "探索", icon: "magnifyingglass"),
        .init(tab: .library, title: "我的", icon: "person.crop.circle"),
    ]
}

private struct CompactWindowLayoutKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var compactWindowLayout: Bool {
        get { self[CompactWindowLayoutKey.self] }
        set { self[CompactWindowLayoutKey.self] = newValue }
    }
}

/// The phone presentation is shared by iPhone and every compact app window.
struct PhonePageLayout: DynamicProperty {
    var contentInset: CGFloat { isEnabled ? Theme.Spacing.phonePage : Theme.Layout.contentInset }
    @Environment(\.compactWindowLayout) private var compactWindowLayout
    var isEnabled: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone || compactWindowLayout
        #else
        compactWindowLayout
        #endif
    }
}

enum WindowLayout {
    static let compactWidth: CGFloat = 760
    #if os(macOS)
    // Playback needs more room for two columns than browsing with a sidebar.
    static let singleColumnPlayerWidth: CGFloat = 1180
    #endif
    static let minimumWidth: CGFloat = 360
}


/// The navigation capsule stays fully expanded; every tab, search included,
/// is a regular item in it.
struct GlassTabBar: View {
    struct Item: Identifiable {
        let tab: IOSTab
        let title: LocalizedStringKey
        let icon: String
        var id: IOSTab { tab }
    }

    let items: [Item]
    @Binding var selection: IOSTab
    var onReselect: (IOSTab) -> Void = { _ in }

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Finger x (in content space) while actively dragging the pill; nil at rest.
    @State private var dragX: CGFloat?
    @State private var isDragging = false

    private let innerInset: CGFloat = 4
    private let contentHeight: CGFloat = 56
    private var settle: Animation {
        reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.35, dampingFraction: 0.82)
    }

    var body: some View {
        GeometryReader { geo in
            let count = max(items.count, 1)
            let cellW = max(geo.size.width, 1) / CGFloat(count)
            let selectedIndex = items.firstIndex { $0.tab == selection } ?? 0
            let restX = cellW * (CGFloat(selectedIndex) + 0.5)
            let pillX = isDragging
                ? min(max(dragX ?? restX, cellW / 2), geo.size.width - cellW / 2)
                : restX

            ZStack(alignment: .leading) {
                selectionPill
                    .frame(width: cellW - 8, height: contentHeight)
                    .position(x: pillX, y: geo.size.height / 2)

                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        if selection == item.tab { onReselect(item.tab) }
                        else { withAnimation(settle) { selection = item.tab } }
                    } label: {
                        itemLabel(item)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(selection == item.tab ? .isSelected : [])
                    .frame(width: cellW, height: contentHeight)
                    .position(x: cellW * (CGFloat(index) + 0.5), y: contentHeight / 2)
                }
            }
            .contentShape(Rectangle())
            .simultaneousGesture(dragGesture(cellW: cellW, count: count))
        }
        .frame(height: contentHeight)
        .padding(innerInset)
        .blocksTouchPassThrough(in: Capsule())
        .modifier(LegacyTabSurface())
    }

    private func itemLabel(_ item: GlassTabBar.Item) -> some View {
        let isSelected = selection == item.tab
        return VStack(spacing: 3) {
            Image(systemName: item.icon)
                .font(.system(size: 23, weight: .semibold))
                .symbolVariant(.fill)
            Text(item.title)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(isSelected
                         ? AnyShapeStyle(Theme.accent)
                         : AnyShapeStyle(Color.primary.opacity(0.8)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }

    /// The sliding indicator — a bar-height capsule with Telegram's faint tint.
    private var selectionPill: some View {
        Capsule(style: .continuous)
            .fill(colorScheme == .dark
                  ? Color.white.opacity(0.10)
                  : Color.black.opacity(0.075))
    }

    private func index(for x: CGFloat, cellW: CGFloat, count: Int) -> Int {
        min(max(Int(x / cellW), 0), count - 1)
    }

    private func dragGesture(cellW: CGFloat, count: Int) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Wait for a clear horizontal intent before "lifting" the pill,
                // so a plain tap slides rather than teleporting to the finger.
                guard abs(value.translation.width) > abs(value.translation.height), !items.isEmpty else { return }
                if !isDragging && abs(value.translation.width) < 8 { return }
                isDragging = true
                dragX = value.location.x
                let tab = items[index(for: value.location.x, cellW: cellW, count: count)].tab
                if tab != selection { selection = tab }   // live switch, pill tracks finger
            }
            .onEnded { value in
                guard isDragging, !items.isEmpty else { return }
                let tab = items[index(for: value.location.x, cellW: cellW, count: count)].tab
                withAnimation(settle) { selection = tab; dragX = nil; isDragging = false }
            }
    }
}

/// Shared floating glass material for the tab capsule.
struct LegacyTabSurface: ViewModifier {
    func body(content: Content) -> some View {
        content.modifier(FloatingGlassSurface(shape: Capsule()))
    }
}

/// Renders mini-player content inside either a system-owned tab accessory or
/// the material-backed compatibility overlay used before iOS 26.
///
/// Do not add a background for `bottomAccessory` or `inlineAccessory`: the
/// tab view owns their Liquid Glass surface and adding another material creates
/// a visibly nested card.
struct IOSMiniPlayerBar: View {
    enum Presentation {
        case bottomAccessory
        case inlineAccessory
        case legacyOverlay
        case compactOverlay

        var isInline: Bool { self == .inlineAccessory || self == .compactOverlay }
        var drawsBackground: Bool { self == .legacyOverlay || self == .compactOverlay }
    }

    @EnvironmentObject private var player: PlayerService
    let presentation: Presentation

    var body: some View {
        playerBarSurface
            .simultaneousGesture(expandGesture)
    }

    @ViewBuilder
    private var playerBarSurface: some View {
        if presentation.drawsBackground {
            content
                .blocksTouchPassThrough(in: Capsule())
                .modifier(FloatingGlassSurface(shape: Capsule()))
        } else {
            content
        }
    }

    // Cover, type, control sizes and spacing follow MeloX's iOS mini player.
    private var content: some View {
        HStack(spacing: presentation.isInline ? 8 : 10) {
            Button(action: showNowPlaying) {
                trackSummary
            }
            .buttonStyle(.plain)
            .accessibilityLabel(nowPlayingAccessibilityLabel)
            .accessibilityHint("打开正在播放")

            if !presentation.isInline {
                PlayerTransportButton(icon: "backward.fill", label: "上一首", size: controlIconSize,
                                      width: controlSize, tint: PlayerControlAppearance.barTint, height: controlSize, disabled: player.isFMMode,
                                      action: player.previous)
                    .transition(presentation.drawsBackground ? .identity : .opacity)
            }

            PlayerPlayPauseButton(isPlaying: player.isPlaying, isLoading: player.showsPlaybackLoading,
                                  size: controlIconSize, width: controlSize, tint: PlayerControlAppearance.barTint,
                                  height: controlSize, action: player.togglePlayPause)

            if !presentation.isInline {
                PlayerTransportButton(icon: "forward.fill", label: "下一首", size: controlIconSize,
                                      width: controlSize, tint: PlayerControlAppearance.barTint, height: controlSize, action: player.next)
                    .transition(presentation.drawsBackground ? .identity : .opacity)
            }
        }
        .padding(.horizontal, presentation.isInline ? 8 : 12)
        .padding(.vertical, presentation.isInline ? 3 : 6)
        .frame(maxWidth: .infinity)
    }

    private var trackSummary: some View {
        HStack(spacing: presentation.isInline ? 8 : 10) {
            CachedAsyncImage(url: player.currentTrack?.album.picUrl?.resizedImageURL(128))
                .frame(
                    width: artworkSize,
                    height: artworkSize
                )
                .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                .shadow(color: .black.opacity(0.15), radius: 4, y: 1)

            VStack(alignment: .leading, spacing: 1) {
                Text(player.currentTrack?.name ?? String(localized: "未在播放"))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                // The compact inline accessory has room for the title only.
                if !presentation.isInline {
                    Text(player.currentTrack?.artistNames ?? "Coda")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artworkSize: CGFloat {
        presentation.isInline ? 30 : 40
    }

    /// 36pt hit area with a `.title3`-sized (20pt) symbol.
    private let controlSize: CGFloat = 36
    private let controlIconSize: CGFloat = 20

    private var nowPlayingAccessibilityLabel: String {
        let title = player.currentTrack?.name ?? String(localized: "正在播放")
        guard let artist = player.currentTrack?.artistNames, !artist.isEmpty else {
            return title
        }
        return "\(title)，\(artist)"
    }

    private var expandGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .onEnded { value in
                #if os(iOS)
                guard NowPlayingPresentationMetrics.shouldExpandFromMiniPlayer(
                    translation: value.translation.height,
                    predictedTranslation: value.predictedEndTranslation.height
                ) else { return }
                #else
                guard value.translation.height < -24 || value.predictedEndTranslation.height < -60 else { return }
                #endif
                showNowPlaying()
            }
    }

    private func showNowPlaying() {
        // The bar stays visible while idle; there is no player page to open yet.
        guard player.hasCurrentTrack else { return }
        #if os(iOS)
        if #available(iOS 18.0, *) {
            player.showNowPlaying = true
        } else {
            withAnimation(NowPlayingPresentationMetrics.presentationAnimation) {
                player.showNowPlaying = true
            }
        }
        #else
        withAnimation(AppAnimation.smooth) { player.showNowPlaying = true }
        #endif
    }
}
