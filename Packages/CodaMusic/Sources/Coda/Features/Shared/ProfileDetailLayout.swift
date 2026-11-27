import SwiftUI

/// Shared page geometry for artist and account profiles.
struct ProfileDetailLayout: DynamicProperty {
    @Environment(\.horizontalSizeClass) private var sizeClass

    var phoneLayout = PhonePageLayout()
    var isCompact: Bool { phoneLayout.isEnabled }

    var contentInset: CGFloat { phoneLayout.contentInset }
    var sectionSpacing: CGFloat { Theme.Spacing.section }
}

struct ProfileDetailPage<Content: View>: View {
    var artworkBackdropURL: String?
    var usesArtworkBackdrop: Bool
    @ViewBuilder var content: () -> Content
    private var layout = ProfileDetailLayout()
    @Environment(\.colorScheme) private var colorScheme

    init(artworkBackdropURL: String? = nil, usesArtworkBackdrop: Bool = false,
         @ViewBuilder content: @escaping () -> Content) {
        self.artworkBackdropURL = artworkBackdropURL
        self.usesArtworkBackdrop = usesArtworkBackdrop
        self.content = content
    }

    var body: some View {
        ScenePreservingScrollView() {
            VStack(alignment: .leading, spacing: layout.sectionSpacing) {
                content()
            }
        }
        .modifier(DetailArtworkBackground(artworkURL: artworkBackdropURL,
                                         enabled: usesArtworkBackdrop))
    }
}

struct ProfileDetailHeader<Details: View, Actions: View>: View {
    let imageURL: String?
    let title: String
    let category: LocalizedStringKey
    @ViewBuilder var details: () -> Details
    @ViewBuilder var actions: () -> Actions
    private var layout = ProfileDetailLayout()

    init(imageURL: String?, title: String, category: LocalizedStringKey,
         @ViewBuilder details: @escaping () -> Details,
         @ViewBuilder actions: @escaping () -> Actions) {
        self.imageURL = imageURL
        self.title = title
        self.category = category
        self.details = details
        self.actions = actions
    }

    var body: some View {
        #if os(iOS)
        phoneHeader
        #else
        if layout.isCompact {
            phoneHeader
        } else {
        Group {
            if layout.isCompact {
                VStack(alignment: .leading, spacing: Theme.Spacing.component) {
                    HStack(alignment: .center, spacing: Theme.Spacing.component) {
                        avatar
                        information
                    }
                    actions()
                }
            } else {
                HStack(alignment: .center, spacing: Theme.Spacing.group) {
                    avatar
                    VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                        information
                        Spacer(minLength: 6)
                        actions()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, layout.contentInset)
        }
        #endif
    }

    private var phoneHeader: some View {
        MusicLibraryHeaderLayout(title: title, icon: nil, coverURL: imageURL,
                                 circularCover: true, usesPlaylistActions: true) {
            Text(category)
                .font(Theme.Typography.secondary)
                .foregroundStyle(.secondary)
        } metadata: {
            details()
        } actions: {
            actions()
        }
    }

    private var avatar: some View {
        CachedAsyncImage(url: imageURL?.resizedImageURL(layout.isCompact ? 384 : 512))
            .frame(width: layout.isCompact ? 100 : 180, height: layout.isCompact ? 100 : 180)
            .clipShape(Circle())
            .shadow(color: .black.opacity(layout.isCompact ? 0.2 : 0.25),
                    radius: layout.isCompact ? 10 : 16, y: layout.isCompact ? 4 : 8)
            .accessibilityLabel(Text(title))
    }

    private var information: some View {
        VStack(alignment: .leading, spacing: layout.isCompact ? 5 : 8) {
            if !layout.isCompact {
                Text(category)
                    .font(Theme.Typography.secondary)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
            }
            Text(title)
                .font(Theme.Typography.pageTitle)
                .lineLimit(2)
                .appMainTitle()
                .accessibilityAddTraits(.isHeader)
            details()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ProfileDetailCoverShelf<Content: View>: View {
    let itemCount: Int
    var resetKey: AnyHashable = 0
    var loading = HorizontalPageLoading()
    var circularCover = false
    @ViewBuilder var content: (Int) -> Content
    private var layout = ProfileDetailLayout()

    init(itemCount: Int, resetKey: AnyHashable = 0,
         loading: HorizontalPageLoading = .init(), circularCover: Bool = false,
         @ViewBuilder content: @escaping (Int) -> Content) {
        self.itemCount = itemCount
        self.resetKey = resetKey
        self.loading = loading
        self.circularCover = circularCover
        self.content = content
    }

    var body: some View {
        HorizontalPagingScrollView(itemCount: itemCount, resetKey: resetKey,
                                   loading: loading) { visibleCount in
            HStack(alignment: .top, spacing: Theme.Spacing.component) {
                content(visibleCount)
            }
        } placeholder: {
            HorizontalCardLoadingColumn(width: circularCover ? (layout.isCompact ? 80 : 100) : Theme.Layout.cardSize,
                                        circular: circularCover)
        }
    }
}

/// The circular artist card used by profile shelves.
struct ProfileDetailArtistCardBody: View {
    let artist: ArtistSummary
    private var layout = ProfileDetailLayout()

    init(artist: ArtistSummary) {
        self.artist = artist
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.small) {
            CachedAsyncImage(url: artist.picUrl?.resizedImageURL(256))
                .frame(width: layout.isCompact ? 80 : 100, height: layout.isCompact ? 80 : 100)
                .clipShape(Circle())
            Text(artist.name)
                .font(Theme.Typography.cardTitle)
                .foregroundStyle(.primary)
                .lineLimit(1)
        }
        .frame(width: layout.isCompact ? 80 : 100)
        .contentShape(Rectangle())
    }
}
