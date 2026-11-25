import SwiftUI
import UniformTypeIdentifiers

/// Standalone destinations; the existing caller owns root-tab and long-press routing.
struct MediaHubRootView: View {
    let kind: MediaHubKind
    let isLibrary: Bool
    let onClose: () -> Void

    @ObservedObject private var sourceLibrary = Md5SourceLibrary.shared
    @ObservedObject private var mediaLibrary = MediaHubLibrary.shared
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.rootTabMediaMenuContext) private var mediaMenuContext
    @AppStorage(MediaPreferences.homeShowsHeroKey) private var homeShowsHero = MediaPreferences.homeShowsHero
    @AppStorage(MediaPreferences.posterColumnsKey) private var posterColumns = MediaPreferences.posterColumns
    @AppStorage(MediaPreferences.musicArtworkSquareKey) private var musicArtworkSquare = MediaPreferences.musicArtworkSquare
    // No continue row: library records are bookmarks, not evidence of playback.
    @State private var selectedSourceID: String?
    @State private var selectedSiteKey: String?
    @State private var sites: [CatVodSite] = []
    @State private var home: CatVodHome?
    @State private var videos: [CatVodVideo] = []
    @State private var rails: [MediaHubVideoRail] = []
    @State private var railFailures: [String: String] = [:]
    @State private var selectedCategoryID: String?
    @State private var searchText = ""
    @State private var submittedSearch = ""
    @State private var page = 1
    @State private var hasMore = false
    @State private var loadingSites = false
    @State private var loadingContent = false
    @State private var loadingRails = false
    @State private var failure: String?
    @State private var siteFailure: String?
    @State private var saveFailure: String?
    @State private var requestID = UUID()
    @State private var siteRequestID = UUID()
    @State private var sourceSheetPresented = false
    @State private var selectedMusicItem: MediaHubLibraryItem?
    @State private var musicImportPresented = false
    @State private var musicDirectImportPresented = false
    @State private var musicImportFailure: String?
    @State private var librarySourceID: String?
    @State private var heroIndex = 0
    @State private var viewportWidth: CGFloat = 390
    @ScaledMetric(relativeTo: .body) private var heroHeight: CGFloat = 390

    init(kind: MediaHubKind, isLibrary: Bool, onClose: @escaping () -> Void) {
        self.kind = kind
        self.isLibrary = isLibrary
        self.onClose = onClose
        _selectedSourceID = State(initialValue: Self.savedSourceID(for: kind))
        _selectedSiteKey = State(initialValue: Self.savedSiteKey(for: kind))
    }

    private var availableSources: [Md5Source] { sourceLibrary.sources }
    private var selectedSource: Md5Source? { availableSources.first { $0.id == selectedSourceID } }
    private var selectedSite: CatVodSite? { sites.first { $0.key == selectedSiteKey } }
    private var visibleItems: [MediaHubLibraryItem] {
        MediaHubPresentation.savedItems(mediaLibrary.items, kind: kind,
            query: isLibrary || kind == .music ? searchText : "", sourceID: librarySourceID)
    }
    private var heroVideos: [CatVodVideo] { MediaHubPresentation.heroVideos(home?.videos ?? []) }
    private var isHomeFeed: Bool { submittedSearch.isEmpty && selectedCategoryID == nil }
    private var columnCount: Int {
        MediaHubPresentation.posterColumnCount(posterColumns, accessibility: dynamicTypeSize.isAccessibilitySize)
    }
    private var cardWidth: CGFloat {
        if dynamicTypeSize.isAccessibilitySize { return min(240, max(180, viewportWidth - 64)) }
        return min(210, max(88, (viewportWidth - 32 - CGFloat(columnCount - 1) * DSSpacing.md) / CGFloat(columnCount)))
    }
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md, alignment: .top), count: columnCount)
    }

    var body: some View {
        NavigationStack {
            Group {
                if kind == .music { MusicJSSourceView(isLibrary: isLibrary) }
                else if isLibrary { libraryBody }
                else { discoveryBody }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewportWidth = $0 }
            .navigationTitle(localized(isLibrary ? kind.libraryTitleKey : kind.titleKey))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) { Label(localized("關閉"), systemImage: "xmark") }
                        .accessibilityIdentifier("mediaHub.close")
                }
                if let mediaMenuContext {
                    RootTabMediaToolbar(tab: mediaMenuContext.tab, onSelect: mediaMenuContext.onSelect,
                                        onDefault: mediaMenuContext.onDefault)
                }
                if kind != .music {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { sourceSheetPresented = true } label: {
                            Label(localized("來源與篩選"), systemImage: "slider.horizontal.3")
                        }
                        .accessibilityIdentifier("mediaHub.sourceControls")
                    }
                }
            }
            .themedAppSurface(for: .explore)
            .sheet(isPresented: $sourceSheetPresented) { sourceSheet }
            .sheet(item: $selectedMusicItem) { item in savedMusicSheet(item) }
            .alert(localized("媒體庫保存失敗"), isPresented: Binding(
                get: { saveFailure != nil }, set: { if !$0 { saveFailure = nil } })) {
                Button(localized("關閉"), role: .cancel) { saveFailure = nil }
            } message: { Text(saveFailure ?? "") }
        }
        .task { sourceLibrary.loadIfNeeded(); mediaLibrary.reload() }
        .onChange(of: availableSources.map(\.id)) { _, ids in
            guard kind == .video, !isLibrary, let sourceID = selectedSourceID,
                  !ids.contains(sourceID) else { return }
            selectedSiteKey = nil
            persistSite(nil)
            sites = []
            siteFailure = nil
            resetContent()
            siteRequestID = UUID()
        }
        .task(id: siteRequestID) {
            guard !isLibrary, kind == .video else { return }
            sourceLibrary.loadIfNeeded()
            await loadSitesIfNeeded()
        }
        .task(id: requestID) {
            guard !isLibrary, kind == .video else { return }
            await loadContent()
        }
    }

    @ViewBuilder private var discoveryBody: some View {
        if selectedSite?.isConfigurationSite == true, let selectedSource {
            VStack(spacing: 0) {
                sourceBadge.padding(.horizontal, DSSpacing.md)
                // Configuration is an editable native destination, never a fake film/QR card.
                PanCookieSettingsView(source: selectedSource, sites: sites)
            }
            .accessibilityIdentifier("mediaHub.siteConfiguration")
        } else {
            videoDiscoveryBody
        }
    }

    private var videoDiscoveryBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.lg) {
                if kind == .video, selectedSite != nil {
                    if isHomeFeed, homeShowsHero, !heroVideos.isEmpty { heroCarousel }
                    VStack(alignment: .leading, spacing: DSSpacing.md) {
                        sourceBadge
                        searchField(music: false)
                        categoryControls
                    }.padding(.horizontal, DSSpacing.md)
                    contentBody
                } else {
                    sourceBadge.padding(.horizontal, DSSpacing.md)
                    discoveryAvailability.padding(.horizontal, DSSpacing.md)
                }
            }
            .padding(.top, DSSpacing.sm)
            .padding(.bottom, DSSpacing.lg)
        }
        .accessibilityIdentifier("mediaHub.videoHome")
        .refreshable { if selectedSite != nil { requestID = UUID() } }
    }

    @ViewBuilder private var discoveryAvailability: some View {
        if kind != .video {
            emptyCard(title: localized("尚無相容來源"),
                      message: localized("目前接口只提供影視站點，尚未聲明此媒體類型。"), symbol: kind.systemImage)
        } else if loadingSites {
            loadingCard(localized("載入站點"))
        } else if let siteFailure {
            retryCard(siteFailure) { siteRequestID = UUID() }
        } else if availableSources.isEmpty {
            emptyCard(title: localized("尚無可用接口"),
                      message: localized("請先在模組中導入 MD5 源。"), symbol: "square.stack.3d.up")
            importSourcesLink
        } else if selectedSource == nil {
            emptyCard(title: localized("請選擇接口"), message: localized("此頁只使用已導入的 MD5 源。"), symbol: "globe")
            Button(localized("選擇接口")) { sourceSheetPresented = true }.buttonStyle(.bordered)
        } else if sites.isEmpty {
            emptyCard(title: localized("此接口沒有可用站點"), message: localized("源未回傳可用的影視站點。"), symbol: "film")
        } else {
            emptyCard(title: localized("請選擇站點"), message: localized("選擇站點後即可載入發現內容。"), symbol: "globe")
            Button(localized("選擇站點")) { sourceSheetPresented = true }.buttonStyle(.bordered)
        }
    }

    private var heroCarousel: some View {
        VStack(spacing: DSSpacing.sm) {
            if dynamicTypeSize.isAccessibilitySize {
                if let video = heroVideos.first {
                    NavigationLink { moviePage(video) } label: {
                        MediaHubHeroCard(sourceID: selectedSourceID ?? "", video: video, expanded: true)
                    }.buttonStyle(.plain)
                }
            } else {
                TabView(selection: $heroIndex) {
                    ForEach(Array(heroVideos.enumerated()), id: \.element.id) { index, video in
                        NavigationLink { moviePage(video) } label: {
                            MediaHubHeroCard(sourceID: selectedSourceID ?? "", video: video, expanded: false)
                        }
                        .buttonStyle(.plain)
                        .tag(index)
                        .accessibilityIdentifier("mediaHub.hero.\(video.id)")
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: heroHeight)
                if heroVideos.count > 1 {
                    HStack(spacing: DSSpacing.xs) {
                        ForEach(heroVideos.indices, id: \.self) { index in
                            Button { withAnimation { heroIndex = index } } label: {
                                Circle().fill(index == heroIndex ? DSColor.accent : DSColor.textSecondary.opacity(0.35))
                                    .frame(width: 7, height: 7)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(format: localized("第 %d 項，共 %d 項"), index + 1, heroVideos.count))
                            .accessibilityAddTraits(index == heroIndex ? .isSelected : [])
                        }
                    }.accessibilityIdentifier("mediaHub.heroDots")
                }
            }
        }.accessibilityIdentifier("mediaHub.hero")
    }

    @ViewBuilder private var sourceBadge: some View {
        if kind == .video, selectedSource != nil, !sites.isEmpty {
            // The same system menu as the settings Picker, opened directly at the badge.
            // UIKit supplies scrolling for long site lists and a checkmark for the selection.
            Menu {
                Picker(localized("選擇站點"), selection: siteBinding) {
                    Text(localized("選擇站點")).tag(nil as String?)
                    ForEach(sites) { site in Text(site.name).tag(Optional(site.key)) }
                }
                .pickerStyle(.inline)
            } label: { sourceBadgeLabel }
            .menuOrder(.fixed)
            .disabled(loadingSites)
            .accessibilityIdentifier("mediaHub.activeSource")
            .accessibilityValue(selectedSite?.name ?? localized("選擇站點"))
        } else {
            Button { sourceSheetPresented = true } label: { sourceBadgeLabel }
                .buttonStyle(.plain).accessibilityIdentifier("mediaHub.activeSource")
        }
    }

    private var sourceBadgeLabel: some View {
        HStack(spacing: DSSpacing.xs) {
            Image(systemName: "globe")
            Text(selectedSite.map { $0.name } ?? selectedSource?.title ?? localized("選擇接口"))
                .lineLimit(1)
            Image(systemName: "chevron.down").font(DSFont.caption2)
            Spacer(minLength: 0)
        }
        .font(DSFont.footnote.weight(.semibold)).foregroundStyle(DSColor.textSecondary)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
    }

    private func searchField(music: Bool) -> some View {
        HStack(spacing: DSSpacing.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(DSColor.textSecondary)
            TextField(localized(music ? "搜尋已收藏音樂" : isLibrary ? "搜尋媒體庫" : "片名搜索"), text: $searchText)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onSubmit { if !music && !isLibrary { submitSearch() } }
                .accessibilityIdentifier("mediaHub.searchField")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                    if !music && !isLibrary { submitSearch() }
                } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(DSColor.textSecondary) }
                .accessibilityLabel(localized("清除搜索"))
            }
            if !music && !isLibrary {
                Button(action: submitSearch) { Image(systemName: "arrow.right.circle.fill") }
                    .accessibilityLabel(localized("搜索"))
                    .disabled(searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(DSSpacing.md)
        .floatingSurfaceBackground(in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
    }

    @ViewBuilder private var categoryControls: some View {
        if let home, !home.categories.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    categoryChip(title: localized("全部"), id: nil)
                    ForEach(home.categories) { category in categoryChip(title: category.name, id: category.id) }
                }.padding(.vertical, 2)
            }.accessibilityIdentifier("mediaHub.categories")
        }
    }

    private func categoryChip(title: String, id: String?) -> some View {
        let selected = selectedCategoryID == id && submittedSearch.isEmpty
        return Button { chooseCategory(id) } label: {
            Text(title).font(DSFont.footnote.weight(.semibold))
                .foregroundStyle(selected ? DSColor.accent : DSColor.textPrimary)
                .padding(.horizontal, DSSpacing.md).padding(.vertical, DSSpacing.sm)
                .floatingSurfaceBackground(in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    @ViewBuilder private var contentBody: some View {
        if loadingContent && videos.isEmpty {
            loadingCard(localized("載入中")).padding(.horizontal, DSSpacing.md)
        } else if let failure, videos.isEmpty {
            retryCard(failure) { requestID = UUID() }.padding(.horizontal, DSSpacing.md)
        } else if isHomeFeed {
            if let failure { retryCard(failure) { requestID = UUID() }.padding(.horizontal, DSSpacing.md) }
            if !videos.isEmpty { videoRail(title: localized("站點推薦"), items: videos, category: nil) }
            ForEach(rails) { rail in videoRail(title: rail.category.name, items: rail.videos, category: rail.category) }
            if loadingRails { loadingCard(localized("載入分類")).padding(.horizontal, DSSpacing.md) }
            if let home {
                ForEach(MediaHubPresentation.categoryCandidates(home.categories)) { category in
                    if let message = railFailures[category.id] {
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text(category.name).font(DSFont.headline)
                            retryCard(message) { requestID = UUID() }
                        }.padding(.horizontal, DSSpacing.md)
                    }
                }
            }
            if videos.isEmpty && rails.isEmpty && !loadingRails {
                emptyCard(title: localized("暫無發現內容"), message: localized("可嘗試上方分類或切換站點。"), symbol: "film")
                    .padding(.horizontal, DSSpacing.md)
            }
        } else {
            VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text(submittedSearch.isEmpty ? (home?.categories.first { $0.id == selectedCategoryID }?.name ?? localized("全部")) : localized("搜尋結果"))
                    .font(DSFont.title2.weight(.bold))
                if videos.isEmpty {
                    emptyCard(title: localized("暫無發現內容"), message: localized("沒有搜尋結果。"), symbol: "magnifyingglass")
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: DSSpacing.lg) {
                        ForEach(videos) { video in videoLink(video, category: selectedCategory) }
                    }
                    resultsFooter
                }
            }.padding(.horizontal, DSSpacing.md)
        }
    }

    private var selectedCategory: CatVodCategory? { home?.categories.first { $0.id == selectedCategoryID } }

    private func videoRail(title: String, items: [CatVodVideo], category: CatVodCategory?) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                Text(title).font(DSFont.title2.weight(.bold)).foregroundStyle(DSColor.textPrimary)
                Spacer()
                if let category {
                    Button { chooseCategory(category.id) } label: {
                        Image(systemName: "chevron.right").frame(minWidth: 44, minHeight: 44)
                    }.accessibilityLabel(localized("查看全部") + " · " + title)
                }
            }.padding(.horizontal, DSSpacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DSSpacing.md) {
                    ForEach(items) { video in videoLink(video, category: category).frame(width: cardWidth) }
                }.padding(.horizontal, DSSpacing.md).padding(.bottom, DSSpacing.xs)
            }
        }.accessibilityIdentifier("mediaHub.rail.\(category?.id ?? "home")")
    }

    private func videoLink(_ video: CatVodVideo, category: CatVodCategory?) -> some View {
        NavigationLink { moviePage(video) } label: {
            MediaHubArtworkCard(sourceID: selectedSourceID ?? "", poster: video.poster,
                title: video.title, subtitle: MediaHubPresentation.facts(for: video), kind: kind, square: false)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if mediaLibrary.contains(sourceID: selectedSourceID ?? "", siteKey: selectedSiteKey ?? "", videoID: video.id) {
                Button(role: .destructive) { removeVideo(video) } label: { Label(localized("移除收藏"), systemImage: "trash") }
            } else {
                Button { saveVideo(video, category: category) } label: { Label(localized("加入媒體庫"), systemImage: "bookmark") }
            }
        }.accessibilityIdentifier("mediaHub.video.\(video.id)")
    }

    private func moviePage(_ video: CatVodVideo) -> some View {
        CatVodMoviePage(sourceID: selectedSourceID ?? "", siteKey: selectedSiteKey ?? "",
            videoID: video.id, title: video.title, mediaKind: kind, siteName: selectedSite?.name ?? "")
    }

    @ViewBuilder private var resultsFooter: some View {
        if loadingContent { loadingCard(localized("載入中")) }
        else if let failure { retryCard(failure) { requestID = UUID() } }
        else if hasMore {
            Button { Task { await loadMore() } } label: {
                Label(localized("載入更多"), systemImage: "arrow.down.circle").frame(maxWidth: .infinity, minHeight: 44)
            }.accessibilityIdentifier("mediaHub.loadMore")
        }
    }

    private var libraryBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.lg) {
                searchField(music: false).padding(.horizontal, DSSpacing.md)
                libraryFailure
                if visibleItems.isEmpty && mediaLibrary.loadFailure == nil {
                    emptyCard(title: localized(searchText.isEmpty && librarySourceID == nil ? "媒體庫是空的" : "沒有搜尋結果。"),
                        message: localized("在影視首頁長按海報，或在詳情頁加入媒體庫。收藏不是觀看紀錄。"), symbol: "bookmark")
                        .padding(.horizontal, DSSpacing.md)
                } else if !visibleItems.isEmpty {
                    recentBookmarks
                    ForEach(MediaHubPresentation.savedRails(visibleItems)) { rail in savedRail(rail) }
                }
            }.padding(.vertical, DSSpacing.md)
        }.accessibilityIdentifier("mediaHub.videoLibrary")
    }

    private var recentBookmarks: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(localized("最近收藏")).font(DSFont.title2.weight(.bold)).padding(.horizontal, DSSpacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DSSpacing.md) {
                    ForEach(Array(visibleItems.prefix(6))) { item in
                        NavigationLink { savedVideoPage(item) } label: {
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                ZStack(alignment: .bottomLeading) {
                                    MediaHubPoster(sourceID: item.sourceID, rawURL: item.poster, fallback: "film")
                                        .aspectRatio(16 / 9, contentMode: .fit)
                                    LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .center, endPoint: .bottom)
                                    Label(localized("已收藏"), systemImage: "bookmark.fill")
                                        .font(DSFont.caption.weight(.semibold)).foregroundStyle(.white).padding(DSSpacing.sm)
                                }.clipShape(RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                                Text(item.title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                                Text(item.siteName).font(DSFont.caption).foregroundStyle(DSColor.textSecondary).lineLimit(1)
                            }.frame(width: min(320, max(220, viewportWidth * 0.72)), alignment: .leading)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { removeBookmarkButton(item) }
                        .accessibilityIdentifier("mediaHub.recentBookmark.\(item.id)")
                    }
                }.padding(.horizontal, DSSpacing.md)
            }
        }.accessibilityIdentifier("mediaHub.recentBookmarks")
    }

    private func savedRail(_ rail: MediaHubSavedRail) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                Text(rail.title.isEmpty ? localized("我的收藏") : rail.title).font(DSFont.title2.weight(.bold))
                if !rail.subtitle.isEmpty { Text(rail.subtitle).font(DSFont.caption).foregroundStyle(DSColor.textSecondary) }
            }.padding(.horizontal, DSSpacing.md)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: DSSpacing.md) {
                    ForEach(rail.items) { item in
                        savedItemLink(item).frame(width: cardWidth)
                    }
                }.padding(.horizontal, DSSpacing.md).padding(.bottom, DSSpacing.xs)
            }
        }.accessibilityIdentifier("mediaHub.savedRail.\(rail.id)")
    }

    private func savedItemLink(_ item: MediaHubLibraryItem) -> some View {
        Group {
            if item.kind == .music {
                Button { selectedMusicItem = item } label: { savedArtwork(item) }
            } else {
                NavigationLink { savedVideoPage(item) } label: { savedArtwork(item) }
            }
        }
        .buttonStyle(.plain)
        .contextMenu { removeBookmarkButton(item) }
        .accessibilityIdentifier("mediaHub.saved.\(item.id)")
    }

    private func savedArtwork(_ item: MediaHubLibraryItem) -> some View {
        let facts = MediaHubPresentation.facts(for: item)
        return MediaHubArtworkCard(sourceID: item.sourceID, poster: item.poster, title: item.title,
            subtitle: facts.isEmpty ? item.siteName : facts, kind: item.kind,
            square: item.kind == .music && musicArtworkSquare)
    }

    private func savedVideoPage(_ item: MediaHubLibraryItem) -> some View {
        CatVodMoviePage(sourceID: item.sourceID, siteKey: item.siteKey, videoID: item.videoID,
            title: item.title, mediaKind: item.kind, siteName: item.siteName)
    }

    private func removeBookmarkButton(_ item: MediaHubLibraryItem) -> some View {
        Button(role: .destructive) { removeItem(item) } label: { Label(localized("移除收藏"), systemImage: "trash") }
    }

    @ViewBuilder private var libraryFailure: some View {
        if let message = mediaLibrary.loadFailure {
            retryCard(message) { mediaLibrary.reload() }.padding(.horizontal, DSSpacing.md)
        }
    }

    private var musicBody: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DSSpacing.lg) {
                musicImportControls.padding(.horizontal, DSSpacing.md)
                searchField(music: true).padding(.horizontal, DSSpacing.md)
                libraryFailure
                if let item = visibleItems.first {
                    Button { selectedMusicItem = item } label: {
                        HStack(spacing: DSSpacing.md) {
                            MediaHubPoster(sourceID: item.sourceID, rawURL: item.poster, fallback: "music.note")
                                .frame(width: 68, height: musicArtworkSquare ? 68 : 88)
                                .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
                            VStack(alignment: .leading, spacing: DSSpacing.xs) {
                                Text(localized("最近收藏")).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                                Text(item.title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                                Text(item.siteName).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Image(systemName: "bookmark.circle.fill").font(DSFont.title).foregroundStyle(DSColor.accent)
                        }.padding(DSSpacing.md)
                            .floatingSurfaceBackground(in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, DSSpacing.md)
                    .accessibilityIdentifier("mediaHub.music.latestSaved")
                    ForEach(MediaHubPresentation.savedRails(visibleItems)) { rail in savedRail(rail) }
                } else if !searchText.isEmpty || librarySourceID != nil {
                    emptyCard(title: localized("沒有搜尋結果。"), message: localized("搜尋僅涵蓋已收藏的音樂。"), symbol: "magnifyingglass")
                        .padding(.horizontal, DSSpacing.md)
                }
                musicAvailability.padding(.horizontal, DSSpacing.md)
            }.padding(.vertical, DSSpacing.md)
        }.accessibilityIdentifier(isLibrary ? "mediaHub.musicLibrary" : "mediaHub.musicHome")
    }

    private var musicImportControls: some View {
        HStack(spacing: DSSpacing.sm) {
            Button { musicImportPresented = true } label: {
                Label(localized("導入音訊 / M3U"), systemImage: "square.and.arrow.down")
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("mediaHub.music.importFile")
            Button { musicDirectImportPresented = true } label: {
                Label(localized("加入直鏈"), systemImage: "link")
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("mediaHub.music.importURL")
        }
    }

    private func importMusicFiles(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else {
            if case .failure(let error) = result { musicImportFailure = error.localizedDescription }
            return
        }
        Task { @MainActor in
            do {
                var imported: [MediaHubLibraryItem] = []
                for url in urls {
                    imported.append(contentsOf: try await MusicImportService.localFile(url))
                }
                for item in imported { try mediaLibrary.save(item) }
                guard let first = imported.first else { return }
                selectedMusicItem = first
            } catch {
                musicImportFailure = error.localizedDescription
            }
        }
    }

    private func importDirectMusic(url: String, title: String, artist: String, headersJSON: String) {
        do {
            let headers = try MusicImportService.parseHeaders(headersJSON)
            let item = try MusicImportService.remote(title: title, urlString: url, artist: artist, headers: headers)
            try mediaLibrary.save(item)
            selectedMusicItem = item
        } catch {
            musicImportFailure = error.localizedDescription
        }
    }

    private var musicAvailability: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            HStack {
                Image(systemName: "music.note.list").font(.system(size: 36, weight: .light))
                    .foregroundStyle(DSColor.accent).padding(DSSpacing.lg)
                    .background(DSColor.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
                Spacer()
                Image(systemName: "waveform").font(DSFont.title).foregroundStyle(DSColor.textSecondary.opacity(0.5))
                    .accessibilityHidden(true)
            }
            Text(localized("可導入本機音訊、M3U/M3U8 或有授權的 HTTP(S) 直鏈"))
                .font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary).fixedSize(horizontal: false, vertical: true)
            Text(localized("播放使用系統 AVPlayer / AVQueuePlayer，支援背景音訊、隊列、鎖屏控制；來源失敗會顯示具體 AVPlayer 錯誤。"))
                .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            if mediaLibrary.items.contains(where: { $0.kind == .music }) {
                Text(localized("已導入的音樂會保存在本機媒體庫；本機檔案會複製到 app 儲存區。"))
                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
            }
            Button { sourceSheetPresented = true } label: { Label(localized("來源與篩選"), systemImage: "slider.horizontal.3") }
                .buttonStyle(.bordered)
        }
        .padding(DSSpacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .floatingSurfaceBackground(in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .accessibilityIdentifier("mediaHub.music.noCompatibleSource")
    }

    private func savedMusicSheet(_ item: MediaHubLibraryItem) -> some View {
        MusicPlayerView(item: item, queue: visibleItems, autoPlay: true)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) { removeItem(item) } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel(localized("移除收藏"))
                }
            }
            .accessibilityIdentifier("mediaHub.music.savedDetail")
    }

    private var sourceSheet: some View {
        NavigationStack {
            Form {
                if kind == .video && !isLibrary {
                    Section {
                        Picker(localized("接口"), selection: sourceBinding) {
                            Text(localized("選擇接口")).tag(nil as String?)
                            ForEach(availableSources) { source in Text(source.title).tag(Optional(source.id)) }
                        }.accessibilityIdentifier("mediaHub.sourcePicker")
                        Picker(localized("站點"), selection: siteBinding) {
                            Text(localized("選擇站點")).tag(nil as String?)
                            ForEach(sites) { site in Text(site.name).tag(Optional(site.key)) }
                        }
                        .disabled(selectedSource == nil || sites.isEmpty || loadingSites)
                        .accessibilityIdentifier("mediaHub.sitePicker")
                        if loadingSites { ProgressView(localized("載入站點")) }
                        if let siteFailure { retryCard(siteFailure) { siteRequestID = UUID() } }
                    } header: { Text(localized("影視來源")) } footer: {
                        Text(localized("內容與分類直接來自所選站點；不會自動替換已移除的接口。"))
                    }
                    Section { importSourcesLink }
                } else if kind == .music {
                    Section {
                        Label(localized("尚無相容音樂源"), systemImage: "music.note")
                        Text(localized("CatVod 的 video.sites 不是音樂接口，影視站點不會被列為音樂來源。"))
                            .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                } else if !isLibrary {
                    Section { Text(localized("目前接口尚未聲明此媒體類型。")) }
                }
                if isLibrary || kind == .music {
                    Section {
                        Picker(localized("收藏來源"), selection: $librarySourceID) {
                            Text(localized("全部")).tag(nil as String?)
                            ForEach(librarySourceOptions) { item in
                                Text(sourceLibrary.sources.first { $0.id == item.sourceID }?.title ?? item.siteName)
                                    .tag(Optional(item.sourceID))
                            }
                        }.accessibilityIdentifier("mediaHub.librarySourcePicker")
                    } footer: { Text(localized("僅篩選此媒體類型的真實收藏，不會向其他類型來源搜尋。")) }
                }
            }
            .navigationTitle(localized("來源與篩選")).toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(localized("關閉")) { sourceSheetPresented = false }
                }
            }
            .themedAppSurface(for: .explore)
        }.accessibilityIdentifier("mediaHub.sourceSheet")
    }

    private var librarySourceOptions: [MediaHubLibraryItem] {
        var seen = Set<String>()
        return mediaLibrary.items.filter { $0.kind == kind && seen.insert($0.sourceID).inserted }
    }

    private var importSourcesLink: some View {
        NavigationLink { Md5SourceManagerView(library: sourceLibrary) } label: {
            Label(localized("前往模組導入"), systemImage: "square.and.arrow.down")
        }.accessibilityIdentifier("mediaHub.importSources")
    }

    private var sourceBinding: Binding<String?> {
        Binding(get: { selectedSource?.id }, set: { value in
            guard selectedSourceID != value else { return }
            selectedSourceID = value
            selectedSiteKey = nil
            sites = []
            siteFailure = nil
            resetContent()
            persistSource(value)
            siteRequestID = UUID()
        })
    }

    private var siteBinding: Binding<String?> {
        Binding(get: { selectedSiteKey }, set: { value in
            guard selectedSiteKey != value else { return }
            selectedSiteKey = value
            persistSite(value)
            resetContent()
        })
    }

    private func loadingCard(_ title: String) -> some View {
        ProgressView(title).font(DSFont.subheadline)
            .frame(maxWidth: .infinity, minHeight: 96)
            .accessibilityIdentifier("mediaHub.loading")
    }

    private func retryCard(_ message: String, retry: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label(localized("載入失敗"), systemImage: "exclamationmark.circle").font(DSFont.headline)
            Text(message).font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: retry) { Label(localized("重試"), systemImage: "arrow.clockwise") }.buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(DSSpacing.md)
        .floatingSurfaceBackground(in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .accessibilityIdentifier("mediaHub.error")
    }

    private func emptyCard(title: String, message: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Image(systemName: symbol).font(DSFont.title).foregroundStyle(DSColor.accent).accessibilityHidden(true)
            Text(title).font(DSFont.headline).foregroundStyle(DSColor.textPrimary)
            Text(message).font(DSFont.subheadline).foregroundStyle(DSColor.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(DSSpacing.lg)
        .floatingSurfaceBackground(in: RoundedRectangle(cornerRadius: DSRadius.lg, style: .continuous))
        .accessibilityIdentifier("mediaHub.empty")
    }

    private func resetContent() {
        home = nil
        videos = []
        rails = []
        railFailures = [:]
        selectedCategoryID = nil
        searchText = ""
        submittedSearch = ""
        heroIndex = 0
        resetResultsOnly()
        loadingContent = false
        loadingRails = false
        requestID = UUID()
    }

    private func loadSitesIfNeeded() async {
        guard !isLibrary, kind == .video else { return }
        let token = siteRequestID
        guard let sourceID = selectedSourceID, availableSources.contains(where: { $0.id == sourceID }) else {
            // A missing persisted source stays unselected; never silently replace it.
            selectedSiteKey = nil
            sites = []
            loadingSites = false
            siteFailure = nil
            return
        }
        loadingSites = true
        siteFailure = nil
        do {
            let found = try await CatVodCatalog.shared.sites(sourceID: sourceID)
            try Task.checkCancellation()
            guard token == siteRequestID, selectedSourceID == sourceID else { return }
            sites = MediaHubPresentation.compatibleSites(found, kind: kind)
            if let key = selectedSiteKey, !sites.contains(where: { $0.key == key }) {
                selectedSiteKey = nil
                persistSite(nil)
                resetContent()
            }
            loadingSites = false
            if selectedSite != nil { requestID = UUID() }
        } catch {
            if token == siteRequestID && !Task.isCancelled {
                siteFailure = CatVodCatalog.message(error)
                loadingSites = false
            }
        }
    }

    private func loadContent() async {
        guard !isLibrary, kind == .video, let sourceID = selectedSourceID,
              let siteKey = selectedSiteKey, let selectedSite, !selectedSite.isConfigurationSite,
              availableSources.contains(where: { $0.id == sourceID }) else { return }
        let token = requestID
        loadingContent = true
        failure = nil
        defer { if token == requestID { loadingContent = false } }
        do {
            if home == nil && !isHomeFeed {
                let seed = try await CatVodCatalog.shared.home(sourceID: sourceID, siteKey: siteKey)
                try Task.checkCancellation()
                guard token == requestID else { return }
                home = seed
            }
            if !submittedSearch.isEmpty {
                let result = try await CatVodCatalog.shared.search(sourceID: sourceID, siteKey: siteKey,
                    query: submittedSearch, page: 1)
                try Task.checkCancellation()
                guard token == requestID else { return }
                videos = MediaHubPresentation.uniqueVideos(result.videos)
                page = result.page
                hasMore = result.hasMore
            } else if let category = selectedCategoryID {
                let result = try await CatVodCatalog.shared.category(sourceID: sourceID, siteKey: siteKey,
                    id: category, page: 1, filters: [:])
                try Task.checkCancellation()
                guard token == requestID else { return }
                videos = MediaHubPresentation.uniqueVideos(result.videos)
                page = result.page
                hasMore = result.hasMore
            } else {
                let result = try await CatVodCatalog.shared.home(sourceID: sourceID, siteKey: siteKey)
                try Task.checkCancellation()
                guard token == requestID else { return }
                home = result
                videos = MediaHubPresentation.uniqueVideos(result.videos)
                heroIndex = 0
                page = 1
                hasMore = false
                rails = []
                railFailures = [:]
                loadingContent = false
                await loadCategoryRails(result.categories, sourceID: sourceID, siteKey: siteKey, token: token)
            }
        } catch {
            if token == requestID && !Task.isCancelled { failure = CatVodCatalog.message(error) }
        }
    }

    /// Bounded, serial requests use the catalog's existing source/lease protection.
    private func loadCategoryRails(_ categories: [CatVodCategory], sourceID: String, siteKey: String, token: UUID) async {
        let candidates = MediaHubPresentation.categoryCandidates(categories)
        loadingRails = !candidates.isEmpty
        defer { if token == requestID { loadingRails = false } }
        for category in candidates {
            guard token == requestID, !Task.isCancelled else { return }
            do {
                let result = try await CatVodCatalog.shared.category(sourceID: sourceID, siteKey: siteKey,
                    id: category.id, page: 1, filters: [:])
                try Task.checkCancellation()
                guard token == requestID else { return }
                let items = MediaHubPresentation.uniqueVideos(result.videos)
                if !items.isEmpty { rails.append(MediaHubVideoRail(category: category, videos: items)) }
            } catch {
                guard token == requestID, !Task.isCancelled else { return }
                railFailures[category.id] = CatVodCatalog.message(error)
            }
        }
    }

    private func loadMore() async {
        guard !loadingContent, hasMore, kind == .video, let sourceID = selectedSourceID,
              let siteKey = selectedSiteKey, selectedSite != nil, availableSources.contains(where: { $0.id == sourceID }) else { return }
        let token = requestID
        let nextPage = page + 1
        loadingContent = true
        failure = nil
        defer { if token == requestID { loadingContent = false } }
        do {
            let result: CatVodPage
            if !submittedSearch.isEmpty {
                result = try await CatVodCatalog.shared.search(sourceID: sourceID, siteKey: siteKey,
                    query: submittedSearch, page: nextPage)
            } else if let category = selectedCategoryID {
                result = try await CatVodCatalog.shared.category(sourceID: sourceID, siteKey: siteKey,
                    id: category, page: nextPage, filters: [:])
            } else { return }
            try Task.checkCancellation()
            guard token == requestID else { return }
            videos = MediaHubPresentation.uniqueVideos(videos + result.videos)
            page = result.page
            hasMore = result.hasMore
        } catch {
            if token == requestID && !Task.isCancelled { failure = CatVodCatalog.message(error) }
        }
    }

    private func chooseCategory(_ id: String?) {
        searchText = ""
        submittedSearch = ""
        selectedCategoryID = id
        resetResultsOnly()
        requestID = UUID()
    }

    private func submitSearch() {
        submittedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        selectedCategoryID = nil
        resetResultsOnly()
        requestID = UUID()
    }

    private func resetResultsOnly() {
        videos = []
        page = 1
        hasMore = false
        failure = nil
        loadingRails = false
    }

    private func saveVideo(_ video: CatVodVideo, category: CatVodCategory?) {
        guard let sourceID = selectedSourceID, let siteKey = selectedSiteKey else { return }
        let item = MediaHubLibraryItem(sourceID: sourceID, siteKey: siteKey, videoID: video.id,
            title: video.title, poster: video.poster, kind: kind, siteName: selectedSite?.name ?? siteKey,
            categoryName: category?.name, year: video.year.isEmpty ? nil : video.year,
            area: video.area.isEmpty ? nil : video.area, remarks: video.remarks.isEmpty ? nil : video.remarks)
        do { try mediaLibrary.save(item) } catch { saveFailure = error.localizedDescription }
    }

    private func removeVideo(_ video: CatVodVideo) {
        guard let sourceID = selectedSourceID, let siteKey = selectedSiteKey else { return }
        let item = MediaHubLibraryItem(sourceID: sourceID, siteKey: siteKey, videoID: video.id,
            title: video.title, poster: video.poster, kind: kind, siteName: selectedSite?.name ?? siteKey)
        removeItem(item)
    }

    private func removeItem(_ item: MediaHubLibraryItem) {
        do {
            try mediaLibrary.remove(item)
            if selectedMusicItem?.id == item.id { selectedMusicItem = nil }
        } catch { saveFailure = error.localizedDescription }
    }

    private func persistSource(_ value: String?) {
        let defaults = UserDefaults.standard
        if let value { defaults.set(value, forKey: Self.sourceDefaultsKey(for: kind)) }
        else { defaults.removeObject(forKey: Self.sourceDefaultsKey(for: kind)) }
        defaults.removeObject(forKey: Self.siteDefaultsKey(for: kind))
    }

    private func persistSite(_ value: String?) {
        let defaults = UserDefaults.standard
        if let value { defaults.set(value, forKey: Self.siteDefaultsKey(for: kind)) }
        else { defaults.removeObject(forKey: Self.siteDefaultsKey(for: kind)) }
    }

    private static func sourceDefaultsKey(for kind: MediaHubKind) -> String { "readcc.mediaHub.source.\(kind.rawValue)" }
    private static func siteDefaultsKey(for kind: MediaHubKind) -> String { "readcc.mediaHub.site.\(kind.rawValue)" }
    private static func savedSourceID(for kind: MediaHubKind) -> String? { UserDefaults.standard.string(forKey: sourceDefaultsKey(for: kind)) }
    private static func savedSiteKey(for kind: MediaHubKind) -> String? { UserDefaults.standard.string(forKey: siteDefaultsKey(for: kind)) }
}

private struct MediaHubArtworkCard: View {
    let sourceID: String
    let poster: String
    let title: String
    let subtitle: String
    let kind: MediaHubKind
    let square: Bool
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.xs) {
            MediaHubPoster(sourceID: sourceID, rawURL: poster, fallback: kind.systemImage)
                .aspectRatio(square ? 1 : DSLayout.discoverCoverAspectRatio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
            Text(title).font(DSFont.subheadline.weight(.semibold)).foregroundStyle(DSColor.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !subtitle.isEmpty {
                Text(subtitle).font(DSFont.caption).foregroundStyle(DSColor.textSecondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct MediaHubHeroCard: View {
    let sourceID: String
    let video: CatVodVideo
    let expanded: Bool

    var body: some View {
        Group {
            if expanded {
                VStack(alignment: .leading, spacing: 0) {
                    artwork.aspectRatio(16 / 10, contentMode: .fit)
                    metadata.padding(DSSpacing.lg)
                }.background(Color.black)
            } else {
                ZStack(alignment: .bottomLeading) {
                    artwork
                    LinearGradient(stops: [.init(color: .clear, location: 0),
                                           .init(color: .black.opacity(0.20), location: 0.35),
                                           .init(color: .black.opacity(0.94), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                    metadata.padding(DSSpacing.lg)
                }
            }
        }
        .foregroundStyle(.white)
        .clipped()
        .accessibilityElement(children: .combine)
        .accessibilityHint(localized("開啟詳情"))
    }

    private var artwork: some View {
        MediaHubPoster(sourceID: sourceID, rawURL: video.poster, fallback: "film")
    }

    private var metadata: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Label(localized("站點推薦"), systemImage: "sparkles").font(DSFont.caption.weight(.semibold))
            Text(video.title).font(DSFont.title.weight(.bold)).lineLimit(expanded ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
            let facts = MediaHubPresentation.facts(for: video)
            if !facts.isEmpty { Text(facts).font(DSFont.footnote.weight(.semibold)).lineLimit(expanded ? nil : 2) }
            let summary = MediaHubPresentation.plainText(video.summary)
            if !summary.isEmpty {
                Text(summary).font(DSFont.subheadline).lineLimit(expanded ? nil : 3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Label(localized("開啟詳情"), systemImage: "arrow.up.right.circle.fill")
                .font(DSFont.footnote.weight(.semibold)).padding(.top, DSSpacing.xs)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Uses the catalog's source-aware URL resolver and the app's native cover surface tokens.
private struct MediaHubPoster: View {
    let sourceID: String
    let rawURL: String
    let fallback: String

    var body: some View {
        GeometryReader { proxy in
            AsyncImage(url: CatVodCatalog.shared.poster(rawURL, sourceID: sourceID)
                       ?? MediaHubPresentation.publicArtworkURL(rawURL)) { phase in
                if let image = phase.image { image.resizable().scaledToFill() }
                else {
                    ZStack {
                        DSColor.surfaceTertiary
                        Image(systemName: fallback).font(DSFont.title).foregroundStyle(DSColor.textSecondary)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }.accessibilityHidden(true)
    }
}
