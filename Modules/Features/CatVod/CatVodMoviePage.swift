import SwiftUI

struct CatVodMoviePage: View {
    let sourceID: String, siteKey: String, videoID: String, title: String
    var mediaKind: MediaHubKind = .video
    var siteName: String = ""
    @ObservedObject private var mediaLibrary = MediaHubLibrary.shared
    @State private var saveFailure: String?
    @State private var detail: CatVodVideo?
    @State private var failure: String?
    @State private var playFailure: String?
    @State private var selectedRoute = ""
    @State private var playingTitle = ""
    @State private var retry = 0
    @State private var pending: Task<Void, Never>?
    @State private var player: CatVodPlayTicket?
    @State private var lease: UUID?
    @EnvironmentObject private var store: BookStore
    @State private var poster: UIImage?

    var body: some View {
        Group {
            if let detail {
                CatVodMovieDetailPresentation(
                    detail: detail, poster: poster, selectedRoute: $selectedRoute,
                    isResolving: pending != nil, isBookmarked: isBookmarked,
                    playFailure: playFailure, saveFailure: saveFailure,
                    onPlay: { episode, flag in play(episode, flag: flag) },
                    onBookmark: { toggleBookmark(detail) }
                )
            } else {
                CatVodMovieLoadState(title: title, failure: failure) { retry += 1 }
                    .navigationTitle(title).toolbarTitleDisplayMode(.inline)
                    .themedAppSurface(for: .explore)
            }
        }
        .task(id: retry) {
            guard detail == nil else { return }; failure = nil
            do {
                let result = try await CatVodCatalog.shared.detail(sourceID: sourceID, siteKey: siteKey, videoID: videoID, fallbackTitle: title)
                try Task.checkCancellation(); detail = result; selectedRoute = result.routes.first?.id ?? ""
            } catch { if !Task.isCancelled { failure = CatVodCatalog.message(error) } }
        }
        .task(id: detail?.poster) {
            poster = nil
            guard let raw = detail?.poster,
                  let url = CatVodCatalog.shared.poster(raw, sourceID: sourceID) else { return }
            let address = url.absoluteString
            poster = BookCoverLoader.cachedImage(for: address)
            if poster == nil {
                // CatVod exposes artwork, not a separate cover-header rule. Use the shared
                // browser headers/cache; never guess a Referer or bypass mediaURL ownership.
                let image = await BookCoverLoader.loadImage(
                    urlString: address,
                    headers: BookCoverLoader.headers(sourceBaseURL: nil, sourceHeaders: [:])
                )
                guard !Task.isCancelled else { return }
                poster = image
            }
        }
        .fullScreenCover(item: $player, onDismiss: releasePlayer) { ticket in
            VideoPlayerView(content: .link(ticket.stream, title: playingTitle)) { player = nil }.environmentObject(store)
        }
        .onDisappear { pending?.cancel(); pending = nil; if player == nil { releasePlayer() } }
    }

    private var isBookmarked: Bool {
        mediaLibrary.contains(sourceID: sourceID, siteKey: siteKey, videoID: videoID)
    }

    private func toggleBookmark(_ detail: CatVodVideo) {
        do {
            let item = MediaHubLibraryItem(sourceID: sourceID, siteKey: siteKey, videoID: videoID,
                                          title: detail.title, poster: detail.poster,
                                          kind: mediaKind, siteName: siteName.isEmpty ? siteKey : siteName)
            if isBookmarked { try mediaLibrary.remove(item) } else { try mediaLibrary.save(item) }
            saveFailure = nil
        } catch { saveFailure = error.localizedDescription }
    }

    private func releasePlayer() { if let lease { CatVodCatalog.shared.release(lease); self.lease = nil } }
    private func play(_ episode: CatVodEpisode, flag: String) {
        guard pending == nil else { return }; playFailure = nil
        pending = Task { @MainActor in
            defer { pending = nil }
            do {
                let ticket = try await CatVodCatalog.shared.play(sourceID: sourceID, siteKey: siteKey, videoID: videoID, flag: flag, episode: episode)
                if Task.isCancelled { CatVodCatalog.shared.release(ticket.id); return }
                lease = ticket.id; playingTitle = "\(detail?.title ?? title) · \(episode.title)"; player = ticket
            } catch { if !Task.isCancelled { playFailure = CatVodCatalog.message(error) } }
        }
    }
}

/// Source metadata plus explicitly attributed ratings in the app's native detail scaffold.
/// Optional TMDB metadata never changes source artwork, episodes or playback routes.
struct CatVodMovieDetailPresentation: View {
    let detail: CatVodVideo
    let poster: UIImage?
    @Binding var selectedRoute: String
    let isResolving: Bool
    let isBookmarked: Bool
    let playFailure: String?
    let saveFailure: String?
    let onPlay: (CatVodEpisode, String) -> Void
    let onBookmark: () -> Void

    @State private var introExpanded = false
    @State private var posterFoot: CoverTint.RGB?
    @State private var leadingEpisode: Int?
    @Environment(\.colorSchemeContrast) private var contrast

    private var route: CatVodRoute? {
        detail.routes.first { $0.id == selectedRoute } ?? detail.routes.first
    }
    private var pageTint: Color {
        guard let posterFoot else { return CoverTint.placeholder.color }
        return CoverTint.background(for: posterFoot, minimumContrast: contrast == .increased ? 7 : 4.5).color
    }
    private var facts: [String] {
        var values = [detail.year, detail.area, detail.remarks].filter { !$0.isEmpty }
        if let count = route?.episodes.count, count > 0 {
            values.append(String(format: localized("共 %d 集"), count))
        }
        return values
    }
    private var playAction: BookDetailAction {
        BookDetailAction(title: localized("开始播放"), systemImage: "play.fill",
                         isBusy: isResolving, isEnabled: route?.episodes.isEmpty == false,
                         detail: route?.episodes.first?.title) {
            guard !isResolving, let route, let episode = route.episodes.first else { return }
            onPlay(episode, route.flag)
        }
    }

    var body: some View {
        BookDetailScaffold(title: detail.title, compactAction: playAction,
                           heroUnderBars: true, pageTint: pageTint) {
            VideoDetailHero(poster: poster, title: detail.title, facts: facts) {
                GeneratedBookCover(title: detail.title, author: nil)
            } actions: {
                VideoHeroActions {
                    playButton
                } buttons: {
                    Button(action: onBookmark) {
                        Image(systemName: isBookmarked ? "bookmark.fill" : "bookmark")
                            .modifier(VideoHeroCapsuleIcon())
                    }
                    .accessibilityLabel(isBookmarked ? localized("移除收藏") : localized("加入媒体库"))
                    .accessibilityIdentifier("catvod.detail.bookmark")
                }
            } intro: {
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    MovieRatingsView(video: detail)
                    if !detail.actor.isEmpty {
                        Text(detail.actor).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    }
                    if !detail.summary.isEmpty {
                        BookDetailIntroSection(text: ReaderHTMLUtilities.displayText(fromHTMLFragment: detail.summary),
                                               isExpanded: $introExpanded, readsSourceFormats: false, placement: .hero)
                    }
                    if let saveFailure { errorText(saveFailure, id: "catvod.detail.saveError") }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } content: {
            episodesSection
        }
        .task(id: poster) {
            guard let poster else { posterFoot = nil; return }
            let color = await Task.detached(priority: .utility) {
                CoverTint.average(of: poster, bottomFraction: DSLayout.videoPosterFootFraction)
            }.value
            guard !Task.isCancelled else { return }
            posterFoot = color
        }
    }

    private var playButton: some View {
        let action = playAction
        return Button(action: action.action) {
            HStack(spacing: DSLayout.videoPlayIconSpacing) {
                if isResolving {
                    ProgressView().tint(DSColor.cardPrimaryActionLabel)
                } else {
                    Image(systemName: action.systemImage).accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 0) {
                    Text(action.title).font(DSFont.footnote.weight(.semibold))
                    if let detail = action.detail {
                        Text(detail).font(DSFont.caption2).foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
            }
            .padding(.vertical, DSSpacing.sm)
            .padding(.horizontal, DSSpacing.lg)
            .frame(maxWidth: DSLayout.videoPlayButtonMaxWidth)
        }
        .buttonStyle(BookDetailCardActionStyle(fill: DSColor.cardPrimaryActionFill,
                                               label: DSColor.cardPrimaryActionLabel,
                                               minHeight: DSLayout.videoPlayButtonHeight))
        .disabled(!action.isEnabled || isResolving)
        .accessibilityLabel(action.title)
        .accessibilityValue(action.detail ?? "")
        .accessibilityIdentifier("catvod.detail.play")
    }

    private var episodesSection: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            VStack(alignment: .leading, spacing: DSSpacing.sm) {
                if detail.routes.count > 1, let route {
                    Menu {
                        Picker(localized("播放线路"), selection: $selectedRoute) {
                            ForEach(detail.routes) { Text($0.name).tag($0.id) }
                        }
                    } label: {
                        HStack(spacing: DSLayout.videoPlayIconSpacing) {
                            Text(route.name).font(DSFont.headline.weight(.bold))
                            Image(systemName: "chevron.down").accessibilityHidden(true)
                        }
                        .foregroundStyle(DSColor.textPrimary)
                        .frame(minHeight: DSLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isResolving)
                    .accessibilityLabel(localized("播放线路"))
                    .accessibilityValue(route.name)
                    .accessibilityIdentifier("catvod.detail.route")
                } else {
                    Text(localized("选集")).font(DSFont.headline.weight(.bold))
                        .accessibilityAddTraits(.isHeader)
                }
                if isResolving {
                    ProgressView(localized("加载中…"))
                        .accessibilityIdentifier("catvod.detail.resolving")
                }
                if let playFailure { errorText(playFailure, id: "catvod.detail.playError") }
            }
            .padding(.horizontal, DSLayout.videoDetailMargin)
            if let route, !route.episodes.isEmpty {
                episodeCards(route)
            } else {
                Text(localized("这部视频没有可播放的集数"))
                    .font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: DSLayout.videoEpisodeCardHeight)
                    .padding(.horizontal, DSLayout.videoDetailMargin)
                    .accessibilityIdentifier("catvod.detail.emptyEpisodes")
            }
        }
        .onChange(of: selectedRoute) { _, _ in leadingEpisode = nil }
    }

    private func episodeCards(_ route: CatVodRoute) -> some View {
        let ranges = VideoEpisodeRange.ranges(of: Array(route.episodes.indices)) { $0 + 1 }
        return VStack(alignment: .leading, spacing: DSSpacing.lg) {
            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: DSSpacing.md) {
                    ForEach(Array(route.episodes.enumerated()), id: \.element.id) { index, episode in
                        VideoEpisodeCard(number: index + 1, sourceName: episode.title, name: episode.title,
                                         isResume: false, stillKey: nil, loadStill: { nil }) {
                            guard !isResolving else { return }
                            onPlay(episode, route.flag)
                        }
                        .disabled(isResolving)
                        .accessibilityIdentifier("catvod.detail.episode.\(episode.id)")
                        .id(index)
                    }
                }
                .scrollTargetLayout()
                .padding(.vertical, DSLayout.videoEpisodeResumeRingOutset)
            }
            .id(route.id)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, DSSpacing.lg, for: .scrollContent)
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $leadingEpisode, anchor: .leading)
            VideoEpisodeRangeBar(
                ranges: ranges,
                selected: ranges.first { $0.episodes.contains(leadingEpisode ?? 0) }?.id,
                onSelect: { leadingEpisode = $0.episodes.first },
                onLast: { leadingEpisode = route.episodes.indices.last }
            )
            .padding(.horizontal, DSSpacing.lg)
        }
    }

    private func errorText(_ message: String, id: String) -> some View {
        Text(message).font(DSFont.footnote).foregroundStyle(DSColor.warning)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier(id)
    }
}

/// Kept separate from fetching so offline tests exercise the real loading/error UI.
struct CatVodMovieLoadState: View {
    let title: String
    let failure: String?
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: DSSpacing.lg) {
            if let failure {
                Text(failure).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("catvod.detail.loadError")
                Button(action: onRetry) {
                    Text(localized("重试"))
                        .frame(minWidth: DSLayout.minimumTapTarget, minHeight: DSLayout.minimumTapTarget)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("catvod.detail.retry")
            } else {
                ProgressView(localized("加载中…"))
                    .accessibilityIdentifier("catvod.detail.loading")
            }
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
