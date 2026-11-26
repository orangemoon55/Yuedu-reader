import SwiftUI

/// Metadata discovery and JS URL resolution are deliberately separate capabilities.
/// A resolver-only LX source is useful here without pretending it implements search.
struct MusicJSSourceView: View {
    let isLibrary: Bool
    @ObservedObject private var store = MusicJSSourceStore.shared
    @ObservedObject private var library = MediaHubLibrary.shared
    @ObservedObject private var player = MusicPlayer.shared
    @StateObject private var catalog = MusicHomeCatalogModel()
    @AppStorage("readcc.musicJS.selectedSource.v1") private var selectedSourceID = ""
    @AppStorage("readcc.musicJS.selectedProvider.v1") private var providerID = ""
    @AppStorage("readcc.musicJS.selectedQuality.v1") private var quality = "128k"
    @State private var query = ""
    @State private var metadataPlatform: MusicCatalogPlatform = .wy
    @State private var searchKind = MusicCatalogKind.song
    @State private var searchInScript = false
    @State private var catalogResults: [MusicCatalogEntry] = []
    @State private var scriptResults: [MusicJSSong] = []
    @State private var submitted = false
    @State private var submittedQuery = ""
    @State private var searchLoading = false
    @State private var searchFailure: String?
    @State private var settings = false
    @State private var failure: String?
    @State private var playing: MediaHubLibraryItem?
    @State private var busy = false
    @State private var searchTask: Task<Void, Never>?
    @State private var actionTask: Task<Void, Never>?
    @State private var searchGeneration = UUID()
    @State private var actionGeneration = UUID()
    @State private var refreshID = UUID()
    @Environment(\.colorScheme) private var colorScheme

    // The reference is a cool, almost-white canvas rather than grouped-list grey.
    // Keep the system's dark surfaces when the user is in dark mode.
    private var homeCanvas: Color {
        colorScheme == .dark ? Color(uiColor: .systemGroupedBackground) : Color(red: 243 / 255, green: 246 / 255, blue: 251 / 255)
    }
    private var continueSurface: Color {
        colorScheme == .dark ? Color(uiColor: .secondarySystemGroupedBackground) : Color(red: 238 / 255, green: 240 / 255, blue: 242 / 255)
    }

    private var source: MusicJSSource? { store.sources.first { $0.id == selectedSourceID } }
    private var provider: MusicJSProvider? { source?.providers.first { $0.id == providerID } }
    private var saved: [MusicJSSong] {
        library.items.compactMap(MusicJSSong.from).filter {
            !isLibrary || query.isEmpty || ($0.title + $0.artist + $0.album).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: isLibrary ? 26 : 24) {
                searchField.padding(.bottom, isLibrary || submitted ? 0 : 8)
                if !isLibrary { metadataPicker }
                if isLibrary { librarySection }
                else {
                    if submitted { searchResults }
                    else {
                        if let item = MusicHomePresentation.continuation(currentTrack: player.currentTrack) { continueCard(item) }
                        catalogRail(title: "排行榜", entries: catalog.charts, loading: catalog.chartsLoading, error: catalog.chartsError, showingOrigin: true)
                        catalogRail(title: "推薦歌單", entries: catalog.playlists, loading: catalog.playlistsLoading, error: catalog.playlistsError)
                        Text(localized("歌單來自") + localized(metadataPlatform.title) + localized("公開熱門目錄，並非個人化推薦。"))
                            .font(.caption).foregroundStyle(.secondary).padding(.horizontal, 16)
                        if !saved.isEmpty { librarySection }
                    }
                    metadataNotice
                }
                if busy { ProgressView(localized("正在透過 JS 音源解析播放…")).frame(maxWidth: .infinity) }
                if let error = store.loadFailure ?? library.loadFailure {
                    Text(error).font(.footnote).foregroundStyle(.secondary).padding(.horizontal, 20)
                }
            }.padding(.top, isLibrary ? 12 : 0).padding(.bottom, 28)
        }
        .background { (isLibrary ? Color(uiColor: .systemGroupedBackground) : homeCanvas).ignoresSafeArea() }
        .toolbarBackground(isLibrary ? Color(uiColor: .systemGroupedBackground) : homeCanvas, for: .navigationBar)
        .toolbarTitleDisplayMode(.inline)
        .accessibilityIdentifier(isLibrary ? "mediaHub.musicLibrary" : "mediaHub.musicHome")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { settings = true } label: {
                    Label(localized("音樂設定"), systemImage: "slider.horizontal.3")
                        .font(.title2).foregroundStyle(.primary)
                }
                    .accessibilityIdentifier("mediaHub.music.settings")
            }
        }
        .sheet(isPresented: $settings) {
            MusicSourceSettingsView(selectedSourceID: $selectedSourceID, providerID: $providerID, quality: $quality)
        }
        .sheet(item: $playing) { item in MusicPlayerView(item: item, queue: [item], autoPlay: true) }
        .alert(localized("音樂操作失敗"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(localized("關閉"), role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
        .task {
            library.reload()
            normalizeSelection()
        }
        .task(id: refreshID) { if !isLibrary { await catalog.load(platform: metadataPlatform) } }
        .refreshable { if !isLibrary { refreshID = UUID() } }
        .onChange(of: selectedSourceID) { _, _ in selectionChanged() }
        .onChange(of: providerID) { _, _ in selectionChanged() }
        .onChange(of: store.sources) { _, _ in normalizeSelection(); cancelActions() }
        .onChange(of: query) { _, _ in
            cancelSearch(); catalogResults = []; scriptResults = []; searchFailure = nil
            submitted = false
        }
        .onChange(of: metadataPlatform) { _, platform in
            // Discovery selection never writes selectedSourceID / providerID / quality or the queue.
            cancelSearch(); cancelActions(); catalog.reset()
            catalogResults = []; scriptResults = []; searchFailure = nil; submitted = false
            if !platform.searchKinds.contains(searchKind) { searchKind = .song }
            refreshID = UUID()
        }
        .onChange(of: searchKind) { _, _ in if submitted { search() } }
        .onChange(of: searchInScript) { _, _ in if submitted { search() } }
        .onDisappear { cancelSearch(); cancelActions() }
    }

    private var metadataPicker: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker(localized("公開元資料平台"), selection: $metadataPlatform) {
                ForEach(MusicCatalogPlatform.allCases) { platform in
                    Text(localized(platform.title)).tag(platform)
                }
            }.pickerStyle(.segmented)
                .accessibilityIdentifier("mediaHub.music.metadataPlatform")
            Text(localized("只切換目錄資料；播放仍使用設定中的 JS 音源與平台。"))
                .font(.caption).foregroundStyle(.secondary)
            if metadataPlatform == .tx {
                Text(localized("QQ 目錄支援歌曲、專輯與歌單；暫不支援歌手搜尋／詳情。"))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.padding(.horizontal, 16)
    }

    private var searchField: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField(localized(isLibrary ? "搜尋已收藏音樂" : "歌曲、歌手、專輯或歌單"), text: $query)
                    .submitLabel(.search).autocorrectionDisabled().textInputAutocapitalization(.never)
                    .onSubmit { if !isLibrary { search() } }
                    .accessibilityIdentifier("mediaHub.music.sourceSearch")
                if !query.isEmpty {
                    Button { query = ""; submitted = false } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel(localized("清除搜尋"))
                }
                if !isLibrary && !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Button(action: search) { Image(systemName: "arrow.right.circle.fill").font(.title3) }
                        .accessibilityLabel(localized("搜尋"))
                }
            }
            .font(isLibrary ? .body : .callout.weight(.semibold))
            .padding(.horizontal, isLibrary ? 14 : 8)
            .padding(.vertical, isLibrary ? 14 : 6)
            .frame(minHeight: isLibrary ? 48 : 34)
            .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: isLibrary ? 16 : 10))
            if !isLibrary && (!query.isEmpty || submitted) {
                if provider?.canSearch == true {
                    Picker(localized("搜尋目錄"), selection: $searchInScript) {
                        Text(localized(metadataPlatform.title) + localized("目錄")).tag(false)
                        Text(localized("目前 JS 音源")).tag(true)
                    }.pickerStyle(.segmented)
                }
                if !searchInScript {
                    Picker(localized("搜尋類型"), selection: $searchKind) {
                        ForEach(metadataPlatform.searchKinds) { Text(localized($0.title)).tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
        }.padding(.horizontal, isLibrary ? 20 : 16)
    }

    private func continueCard(_ item: MediaHubLibraryItem) -> some View {
        Button {
            if player.errorMessage != nil, let song = MusicJSSong.from(item) { play(song) }
            else {
                if !player.isPlaying { player.resume() }
                playing = item
            }
        } label: {
            HStack(spacing: 14) {
                MusicCatalogArtwork(poster: item.poster, size: 66, cornerRadius: 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(localized(player.isPlaying ? "正在播放" : "繼續播放")).font(.caption2.weight(.semibold))
                    Text(item.title).font(.headline).lineLimit(1)
                    Text([item.remarks ?? "", localized("停在") + " " + MusicHomePresentation.time(player.currentTime)]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                    if let error = player.errorMessage { Text(error).font(.caption).foregroundStyle(.red).lineLimit(2) }
                }
                Spacer(minLength: 0)
                Image(systemName: player.isPlaying ? "waveform.circle.fill" : "play.circle.fill")
                    .font(.system(size: 30)).frame(width: 34, height: 44)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(.primary).padding(14)
            .background(continueSurface, in: RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain).disabled(busy).padding(.horizontal, 16)
        .accessibilityIdentifier("mediaHub.music.continuePlaying")
    }

    private func catalogRail(title: String, entries: [MusicCatalogEntry], loading: Bool, error: String?, showingOrigin: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            NavigationLink {
                MusicCatalogDirectoryView(title: title, entries: entries, showingOrigin: showingOrigin,
                                          onPlay: playTrack, onSave: saveTrack)
            } label: {
                HStack(spacing: 8) {
                    Text(localized(title)).font(.title3.bold()).foregroundStyle(.primary)
                    Image(systemName: "chevron.right").font(.subheadline.bold()).foregroundStyle(.tertiary)
                }.frame(minHeight: 28, alignment: .leading)
            }
            .buttonStyle(.plain).disabled(entries.isEmpty).padding(.horizontal, 16)
            .accessibilityIdentifier(showingOrigin ? "mediaHub.music.charts" : "mediaHub.music.playlists")
            if loading && entries.isEmpty {
                ProgressView(localized("載入公開音樂目錄…")).frame(maxWidth: .infinity, minHeight: 148)
            } else if let error {
                MusicCatalogStatus(message: error, retry: { refreshID = UUID() }).padding(.horizontal, 16)
            } else if entries.isEmpty {
                Text(localized("目錄暫無內容。")) .font(.subheadline).foregroundStyle(.secondary).padding(.horizontal, 16)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: 14) {
                        ForEach(entries) { entry in
                            NavigationLink {
                                MusicCatalogCollectionView(entry: entry, onPlay: playTrack, onSave: saveTrack)
                            } label: {
                                VStack(alignment: .leading, spacing: 7) {
                                    MusicCatalogArtwork(poster: entry.poster, size: 148, cornerRadius: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(entry.title).font(.subheadline.weight(.semibold)).lineLimit(1)
                                        Text(MusicHomePresentation.catalogCaption(for: entry, showingOrigin: showingOrigin))
                                            .font(.caption.weight(.medium)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                }.frame(width: 148, alignment: .leading).foregroundStyle(.primary)
                            }.buttonStyle(.plain)
                                .accessibilityIdentifier("mediaHub.music.catalog.\(entry.id)")
                        }
                    }.padding(.horizontal, 16)
                }
            }
        }.padding(.bottom, 4)
    }

    private var metadataNotice: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(localized(metadataPlatform.providerName), systemImage: "info.circle")
            Text(localized("目錄只提供歌曲資料；播放網址僅由你導入的 JS 音源解析。需具備相應播放權限。"))
            if !MusicHomePresentation.canResolveCatalog(source: source, providerID: providerID, platform: metadataPlatform) {
                Button(localized("選擇支援") + " \(metadataPlatform.rawValue) " + localized("的 JS 音源以播放")) { settings = true }
            }
        }.font(.caption).foregroundStyle(.secondary).padding(.horizontal, 20)
    }

    private var searchResults: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(localized("搜尋結果")).font(.title2.bold())
                Spacer()
                Button(localized("返回發現")) { cancelSearch(); submitted = false }
            }
            Text((searchInScript ? (source?.name ?? localized("JS 音源")) : localized(metadataPlatform.providerName)) + " · " + submittedQuery)
                .font(.caption).foregroundStyle(.secondary)
            if searchLoading { ProgressView(localized("搜尋中…")) }
            else if let searchFailure { MusicCatalogStatus(message: searchFailure, retry: search) }
            else if catalogResults.isEmpty && scriptResults.isEmpty { Text(localized("沒有搜尋結果。")).foregroundStyle(.secondary) }
            if searchInScript {
                ForEach(scriptResults) { song in songRow(song, isSaved: false) }
            } else {
                ForEach(catalogResults) { entry in
                    if let track = entry.track {
                        MusicCatalogSongRow(title: track.title, subtitle: entry.subtitle, poster: track.poster, busy: busy,
                                            onPlay: { playTrack(track) }, onSave: { saveTrack(track) })
                    } else {
                        NavigationLink {
                            MusicCatalogCollectionView(entry: entry, onPlay: playTrack, onSave: saveTrack)
                        } label: {
                            HStack(spacing: 12) {
                                MusicCatalogArtwork(poster: entry.poster, size: 52)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(entry.title).font(.headline).lineLimit(2)
                                    Text(entry.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }.foregroundStyle(.primary)
                        }.buttonStyle(.plain)
                    }
                    Divider()
                }
                if !catalogResults.isEmpty { Text(localized("顯示服務返回的前 30 筆結果。")) .font(.caption).foregroundStyle(.secondary) }
            }
        }.padding(.horizontal, 20)
    }

    private var librarySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("已收藏音樂")).font(.title2.bold())
            if saved.isEmpty { Text(localized("尚無收藏")).foregroundStyle(.secondary) }
            ForEach(saved) { song in songRow(song, isSaved: true); Divider() }
        }.padding(.horizontal, 20)
    }

    private func songRow(_ song: MusicJSSong, isSaved: Bool) -> some View {
        MusicCatalogSongRow(title: song.title, subtitle: [song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · "),
            poster: song.poster, busy: busy, onPlay: { play(song) }, onSave: {
                do {
                    let item = try song.savedItem(sourceName: sourceName(song))
                    if isSaved { try library.remove(item) } else { try library.save(item) }
                } catch { failure = error.localizedDescription }
            }, isSaved: isSaved)
        .accessibilityIdentifier("mediaHub.music.song.\(song.id)")
    }

    private func sourceName(_ song: MusicJSSong) -> String {
        store.sources.first { $0.id == song.sourceID }?.name ?? localized("JS 音源")
    }
    private func normalizeSelection() {
        if source == nil { selectedSourceID = store.sources.first?.id ?? "" }
        if provider == nil {
            providerID = source?.providers.first(where: { $0.id == "wy" })?.id ?? source?.providers.first?.id ?? ""
        }
        if provider?.qualities.contains(quality) != true { quality = provider?.qualities.first ?? "128k" }
        if provider?.canSearch != true { searchInScript = false }
    }
    private func selectionChanged() {
        cancelSearch(); cancelActions(); submitted = false
        catalogResults = []; scriptResults = []
        normalizeSelection()
    }
    private func cancelSearch() {
        searchTask?.cancel(); searchGeneration = UUID(); searchLoading = false
    }
    private func cancelActions() {
        actionTask?.cancel(); actionGeneration = UUID(); busy = false
    }
    private func search() {
        let keyword = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return }
        cancelSearch()
        let token = UUID(); searchGeneration = token
        submitted = true; submittedQuery = keyword; searchLoading = true; searchFailure = nil
        scriptResults = []; catalogResults = []
        let useScript = searchInScript && provider?.canSearch == true
        let sourceID = selectedSourceID, platform = providerID, kind = searchKind
        let catalogPlatform = metadataPlatform
        searchTask = Task { @MainActor in
            defer { if searchGeneration == token { searchLoading = false } }
            do {
                if useScript {
                    let found = try await store.search(sourceID: sourceID, provider: platform, query: keyword)
                    guard !Task.isCancelled, searchGeneration == token else { return }
                    scriptResults = found
                } else {
                    let found = try await MusicPlatformCatalog.search(keyword, kind: kind, platform: catalogPlatform)
                    guard !Task.isCancelled, searchGeneration == token else { return }
                    catalogResults = found
                }
            } catch {
                guard !Task.isCancelled, searchGeneration == token else { return }
                searchFailure = error.localizedDescription
            }
        }
    }
    private func playTrack(_ track: MusicCatalogTrack) {
        do { play(try MusicCatalogResolverMapping.song(track, source: source, providerID: providerID)) }
        catch { failure = error.localizedDescription }
    }
    private func saveTrack(_ track: MusicCatalogTrack) {
        do {
            let song = try MusicCatalogResolverMapping.song(track, source: source, providerID: providerID)
            try library.save(song.savedItem(sourceName: sourceName(song)))
        } catch { failure = error.localizedDescription }
    }
    private func play(_ song: MusicJSSong) {
        guard !busy else { return }
        cancelActions()
        let token = UUID(); actionGeneration = token; busy = true
        let available = store.sources.first { $0.id == song.sourceID }?.providers.first { $0.id == song.provider }
        let chosenQuality = available?.qualities.contains(quality) == true ? quality : available?.qualities.first ?? "128k"
        actionTask = Task { @MainActor in
            defer { if actionGeneration == token { busy = false } }
            do {
                let item = try await store.resolve(song, quality: chosenQuality)
                guard !Task.isCancelled, actionGeneration == token else { return }
                playing = item
            } catch {
                guard !Task.isCancelled, actionGeneration == token else { return }
                failure = error.localizedDescription
            }
        }
    }
}
