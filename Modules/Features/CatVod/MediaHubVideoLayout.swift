import SwiftUI

/// One presentation contract for the video root, site browser and site search.
/// Video-only settings choose an explicit fixed template, never a width-adaptive column count.
/// Legacy source preferences remain scoped to the saved-library rails.
enum MediaHubVideoLayout {
    static let posterColumnCount = 3
    static let posterAspectRatio: CGFloat = 2.0 / 3.0
    static let spacing: CGFloat = 12
    static let horizontalPadding: CGFloat = 16
    static let skeletonCount = 9

    // Keep the original default contract for callers/tests that do not supply preferences.
    static var columns: [GridItem] {
        columns(count: posterColumnCount, density: .comfortable)
    }

    static func columns(count: Int, density: MediaVideoCardDensity = .comfortable) -> [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 0), spacing: spacing(for: density), alignment: .top),
              count: min(max(count, 2), 5))
    }

    static func spacing(for density: MediaVideoCardDensity) -> CGFloat {
        density == .comfortable ? spacing : 8
    }

    static func rowSpacing(for density: MediaVideoCardDensity) -> CGFloat {
        density == .comfortable ? 20 : 12
    }

    static func cardSpacing(for density: MediaVideoCardDensity) -> CGFloat {
        density == .comfortable ? 5 : 3
    }

    static func skeletonCount(forColumnCount count: Int) -> Int {
        min(max(count, 2), 5) * 3
    }

    /// Describe the selected site's published API, never its display name or an assumed runtime.
    /// Extensionless CatVod routes do not identify a script language.
    static func sourceKindLabel(for site: CatVodSite) -> String {
        let path = URLComponents(string: site.api)?.path ?? site.api
        switch (path as NSString).pathExtension.lowercased() {
        case "js", "mjs", "cjs": return localized("JavaScript 源")
        case "py": return localized("Python 源")
        default: return String(format: localized("CatVod 源 · 類型 %d"), site.type)
        }
    }

    static func showsSkeleton(loading: Bool, itemCount: Int) -> Bool {
        loading && itemCount == 0
    }
}

struct MediaHubVideoSourceLabel: View {
    let title: String
    var selectable = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.secondary)
            Text(title).lineLimit(1)
            if selectable { Image(systemName: "chevron.down").font(.caption.weight(.semibold)) }
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.primary)
        .padding(.horizontal, 12)
        .frame(minHeight: 44)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
        .contentShape(Capsule())
    }
}

struct MediaHubVideoSourceKindPill: View {
    let site: CatVodSite

    var body: some View {
        Label(MediaHubVideoLayout.sourceKindLabel(for: site), systemImage: "chevron.left.forwardslash.chevron.right")
            .font(.subheadline.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .background(Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .accessibilityIdentifier("mediaHub.video.sourceKind")
            .accessibilityHint(localized("類型來自所選站點的接口聲明，不代表新增本機執行環境。"))
    }
}

struct MediaHubVideoGrid<Item: Identifiable, Content: View>: View {
    @AppStorage(MediaPreferences.videoPosterColumnsKey) private var videoPosterColumns = 3
    @AppStorage(MediaPreferences.videoCardDensityKey) private var videoCardDensity = MediaVideoCardDensity.comfortable
    let videos: [Item]
    let identifier: String
    private let content: (Item) -> Content

    init(videos: [Item], identifier: String = "mediaHub.video.fixedGrid",
         @ViewBuilder content: @escaping (Item) -> Content) {
        self.videos = videos
        self.identifier = identifier
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: MediaHubVideoLayout.columns(count: videoPosterColumns, density: videoCardDensity),
                  alignment: .leading, spacing: MediaHubVideoLayout.rowSpacing(for: videoCardDensity)) {
            ForEach(videos) { video in content(video).frame(maxWidth: .infinity, alignment: .topLeading) }
        }
        .accessibilityIdentifier(identifier)
    }
}

struct MediaHubVideoPosterCard: View {
    @AppStorage(MediaPreferences.videoShowsFactsKey) private var videoShowsFacts = true
    @AppStorage(MediaPreferences.videoCardDensityKey) private var videoCardDensity = MediaVideoCardDensity.comfortable
    let sourceID: String
    let video: CatVodVideo

    private var subtitle: String { MediaHubPresentation.facts(for: video) }

    var body: some View {
        VStack(alignment: .leading, spacing: MediaHubVideoLayout.cardSpacing(for: videoCardDensity)) {
            MediaHubPoster(sourceID: sourceID, rawURL: video.poster, fallback: "film")
                .aspectRatio(MediaHubVideoLayout.posterAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            Text(video.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            if videoShowsFacts {
                // Reserve the metadata line only while enabled, even if a site supplies no facts.
                Text(subtitle.isEmpty ? " " : subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .accessibilityHidden(subtitle.isEmpty)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(localized("開啟詳情"))
    }
}

/// This is request state, not placeholder content. Callers must gate it on active loading.
struct MediaHubVideoSkeletonGrid: View {
    @AppStorage(MediaPreferences.videoPosterColumnsKey) private var videoPosterColumns = 3
    @AppStorage(MediaPreferences.videoShowsFactsKey) private var videoShowsFacts = true
    @AppStorage(MediaPreferences.videoCardDensityKey) private var videoCardDensity = MediaVideoCardDensity.comfortable

    var body: some View {
        LazyVGrid(columns: MediaHubVideoLayout.columns(count: videoPosterColumns, density: videoCardDensity),
                  alignment: .leading, spacing: MediaHubVideoLayout.rowSpacing(for: videoCardDensity)) {
            ForEach(0..<MediaHubVideoLayout.skeletonCount(forColumnCount: videoPosterColumns), id: \.self) { _ in
                VStack(alignment: .leading, spacing: MediaHubVideoLayout.cardSpacing(for: videoCardDensity)) {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .aspectRatio(MediaHubVideoLayout.posterAspectRatio, contentMode: .fit)
                    RoundedRectangle(cornerRadius: 3).frame(height: 11)
                    if videoShowsFacts {
                        RoundedRectangle(cornerRadius: 3).frame(width: 46, height: 9).opacity(0.65)
                    }
                }
            }
        }
        .foregroundStyle(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(localized("載入中"))
        .accessibilityIdentifier("mediaHub.video.loadingGrid")
    }
}

/// Search is explicitly scoped to the current authorized site, as in the existing catalog API.
struct MediaHubVideoSearchField: View {
    @Binding var text: String
    let loading: Bool
    var enabled = true
    var prompt = "搜尋本站片名"
    var fieldIdentifier = "mediaHub.searchField"
    var buttonIdentifier = "mediaHub.video.searchSubmit"
    let submit: () -> Void
    let clear: () -> Void

    private var canSubmit: Bool {
        enabled && !loading && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                TextField(localized(prompt), text: $text)
                    .submitLabel(.search)
                    .autocorrectionDisabled()
                    .onSubmit { if canSubmit { submit() } }
                    .disabled(!enabled)
                    .accessibilityIdentifier(fieldIdentifier)
                if !text.isEmpty {
                    Button(action: clear) {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(localized("清除搜索"))
                    .accessibilityIdentifier("\(fieldIdentifier).clear")
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, text.isEmpty ? 12 : 0)
            .frame(minHeight: 48)
            .background(Color(uiColor: .secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            Button(action: submit) {
                Group {
                    if loading { ProgressView().accessibilityLabel(localized("載入中")) }
                    else { Text(localized("搜索")).font(.subheadline.weight(.semibold)) }
                }
                .frame(minWidth: 52, minHeight: 48)
                .padding(.horizontal, 6)
                .background(Color(uiColor: .tertiarySystemFill),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(!canSubmit)
            .accessibilityLabel(localized(loading ? "載入中" : "搜索"))
            .accessibilityIdentifier(buttonIdentifier)
        }
    }
}

/// A pushed site route has a fixed identity; only the root's real Menu shows a chevron.
struct CatVodVideoSiteHeader: View {
    let site: CatVodSite

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                MediaHubVideoSourceLabel(title: site.name)
                MediaHubVideoSourceKindPill(site: site)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 6) {
                MediaHubVideoSourceLabel(title: site.name)
                MediaHubVideoSourceKindPill(site: site)
            }
        }
    }
}
