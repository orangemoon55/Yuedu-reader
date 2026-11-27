import SwiftUI

// MARK: - Cover card (playlists / albums)

struct CoverCard: View {
    let coverURL: URL?
    let title: String
    var subtitle: String?
    var playCount: Int = 0
    var size: CGFloat = Theme.Layout.cardSize
    var onPlay: (() -> Void)?
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                ZStack(alignment: .bottomLeading) {
                    CachedAsyncImage(url: coverURL)
                        .frame(width: size, height: size)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Theme.Radius.standard, style: .continuous)
                                .strokeBorder(.primary.opacity(0.08), lineWidth: 0.5)
                        )
                    if playCount > 0 {
                        PlayCountBadge(count: playCount)
                            .padding(Theme.Spacing.small)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
                    if let onPlay {
                        PlayOverlayButton(visible: isHovering, action: onPlay)
                            .padding(Theme.Spacing.small)
                    }
                }
                .frame(width: size, height: size)

                VStack(alignment: .leading, spacing: Theme.Spacing.tight) {
                    Text(title)
                        .font(Theme.Typography.cardTitle)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .foregroundStyle(.primary)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(Theme.Typography.secondary)
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: size, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.interactiveCard)
        .scrollAwareHover { isHovering = $0 }
    }
}

struct PlaylistCoverCard: View {
    let playlist: PlaylistSummary
    var subtitle: String?
    var size: CGFloat = Theme.Layout.cardSize
    var cornerRadius: CGFloat = Theme.Radius.cover
    var onPlay: (() -> Void)?

    var body: some View {
        CoverCardBody(coverURL: playlist.coverURL?.resizedImageURL(384),
                      playlistID: playlist.id, title: playlist.name, subtitle: subtitle,
                      playCount: playlist.playCount, size: size, cornerRadius: cornerRadius,
                      reservesTitleSpace: true, onPlay: onPlay)
    }
}

// MARK: - Artist card (circular)

// MARK: - Horizontal shelf

/// A horizontal scroll section whose track reaches the column edges;
/// the resting inset lives inside the HStack (kaset's slide-under trick).
struct Shelf<Content: View>: View {
    let title: LocalizedStringKey
    var seeAll: (() -> Void)?
    var spacing: CGFloat = Theme.Spacing.component
    var rowHeight: CGFloat?
    var itemCount: Int
    var resetKey: AnyHashable = 0
    var loading = HorizontalPageLoading()
    var circularCover = false
    var cardWidth: CGFloat = Theme.Layout.cardSize
    @ViewBuilder var content: (Int) -> Content
    @ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.component) {
            SectionHeader(title: title, action: seeAll)
                .padding(.horizontal, Theme.Layout.contentInset)
            HorizontalPagingScrollView(itemCount: itemCount, resetKey: resetKey,
                                       spacing: spacing, loading: loading) { visibleCount in
                cards(visibleCount)
            } placeholder: {
                HorizontalCardLoadingColumn(width: cardWidth, circular: circularCover)
            }
            .compatScrollClipDisabled()
        }
    }

    @ViewBuilder
    private func cards(_ visibleCount: Int) -> some View {
        if let rowHeight {
            LazyHStack(alignment: .top, spacing: spacing) {
                content(visibleCount)
            }
            .frame(height: rowHeight + 96 * max(0, textScale - 1))
        } else {
            HStack(alignment: .top, spacing: spacing) {
                content(visibleCount)
            }
        }
    }
}

// MARK: - Adaptive card grid

/// Set by `CardGrid` on compact iOS so cards fill their (even) column instead
/// of staying a fixed 160pt — which on narrow iPhones only fit one per row.
private struct FlexibleCardWidthKey: EnvironmentKey { static let defaultValue = false }
extension EnvironmentValues {
    var flexibleCardWidth: Bool {
        get { self[FlexibleCardWidthKey.self] }
        set { self[FlexibleCardWidthKey.self] = newValue }
    }
}

struct CardGrid<Content: View>: View {
    var minWidth: CGFloat = Theme.Layout.cardSize
    /// Cover grids keep every column at exactly the shared card size.
    var fixedColumnWidth = true
    @ViewBuilder var content: () -> Content

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    private var isCompact: Bool { horizontalSizeClass == .compact }
    #else
    private var isCompact: Bool { false }
    #endif

    private var columns: [GridItem] {
        isCompact
            ? [GridItem(.flexible(), spacing: Theme.Spacing.component, alignment: .top),
               GridItem(.flexible(), spacing: Theme.Spacing.component, alignment: .top)]
            : [GridItem(.adaptive(minimum: minWidth, maximum: fixedColumnWidth ? minWidth : minWidth + 40),
                        spacing: Theme.Spacing.component, alignment: .top)]
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.group) {
            content()
        }
        .environment(\.flexibleCardWidth, isCompact)
    }
}

// MARK: - Error / empty states

struct ErrorStateView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        VStack(spacing: Theme.Spacing.component) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            VStack(spacing: Theme.Spacing.small) {
                Text("加载失败").font(Theme.Typography.cardTitle)
                Text(message)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Button("重试", action: retry)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, Theme.Spacing.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Theme.Layout.emptyStateInset)
    }
}

/// Replaces a home section whose content the platform only serves to signed-in
/// accounts, so guests see why it is missing and how to unlock it.
struct HomeLoginPrompt: View {
    let message: String
    var expired = false
    var minHeight: CGFloat = 160
    @EnvironmentObject private var account: AccountStore
    @Environment(\.openLogin) private var openLogin

    var body: some View {
        VStack(spacing: Theme.Spacing.control) {
            Image(systemName: expired ? "person.crop.circle.badge.exclamationmark" : "person.crop.circle")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text(expired ? String(localized: "\(account.provider.name)登录已失效") : String(localized: "登录\(account.provider.name)后查看"))
                .font(Theme.Typography.cardTitle)
            Text(message)
                .font(Theme.Typography.secondary)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(expired ? String(localized: "重新登录") : String(localized: "登录\(account.provider.name)"), action: openLogin)
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
                .padding(.top, Theme.Spacing.small)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(Theme.Spacing.component)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("homeLoginPrompt")
    }
}

struct EmptyStateView: View {
    let icon: String
    let title: LocalizedStringKey
    var subtitle: LocalizedStringKey?

    var body: some View {
        VStack(spacing: Theme.Spacing.component) {
            Image(systemName: icon)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
            VStack(spacing: Theme.Spacing.small) {
                Text(title)
                    .font(Theme.Typography.cardTitle)
                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.secondary)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
