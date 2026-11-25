import SwiftUI
import UniformTypeIdentifiers

/// Music currently has one import path: user-selected LX JavaScript source files.
/// CatVod sites, direct links, playlists and local audio are not offered as source imports.
struct MusicJSSourceView: View {
    let isLibrary: Bool
    @ObservedObject private var store = MusicJSSourceStore.shared
    @ObservedObject private var library = MediaHubLibrary.shared
    @AppStorage("readcc.musicJS.selectedSource.v1") private var selectedSourceID = ""
    @State private var providerID = ""
    @State private var quality = "128k"
    @State private var query = ""
    @State private var results: [MusicJSSong] = []
    @State private var searching = false
    @State private var busy = false
    @State private var importing = false
    @State private var sourceManagement = false
    @State private var failure: String?
    @State private var playing: MediaHubLibraryItem?
    @State private var task: Task<Void, Never>?
    @State private var generation = UUID()

    private var source: MusicJSSource? { store.sources.first { $0.id == selectedSourceID } }
    private var provider: MusicJSProvider? { source?.providers.first { $0.id == providerID } }
    private var saved: [MusicJSSong] {
        library.items.compactMap(MusicJSSong.from).filter {
            query.isEmpty || ($0.title + $0.artist).localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        List {
            Section {
                Button { importing = true } label: {
                    Label(localized("導入 JS 音源"), systemImage: "square.and.arrow.down")
                }.accessibilityIdentifier("mediaHub.music.importJS")
                if !store.sources.isEmpty {
                    Picker(localized("JS 音源"), selection: $selectedSourceID) {
                        Text(localized("選擇音源")).tag("")
                        ForEach(store.sources) { source in Text(source.name).tag(source.id) }
                    }.accessibilityIdentifier("mediaHub.music.sourcePicker")
                    Button { sourceManagement = true } label: {
                        Label(localized("管理音源"), systemImage: "slider.horizontal.3")
                    }
                }
            } footer: {
                Text(localized("目前只可導入 LX 格式 JS 音源；音源可存取其音樂服務，請只導入可信檔案。"))
            }
            .interfaceSectionSurface()

            if !isLibrary {
                if let source {
                    Section {
                        Picker(localized("平台"), selection: $providerID) {
                            ForEach(source.providers) { Text($0.name).tag($0.id) }
                        }.accessibilityIdentifier("mediaHub.music.providerPicker")
                        if let provider {
                            Picker(localized("音質"), selection: $quality) {
                                ForEach(provider.qualities, id: \.self) { Text($0).tag($0) }
                            }
                            TextField(localized("歌曲或歌手"), text: $query)
                                .submitLabel(.search).autocorrectionDisabled()
                                .onSubmit { search() }
                                .accessibilityIdentifier("mediaHub.music.sourceSearch")
                            Button(action: search) { Label(localized("搜索"), systemImage: "magnifyingglass") }
                                .disabled(busy || !provider.canSearch || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            if !provider.canSearch {
                                Text(localized("此平台只提供播放解析；請選擇支援搜尋的平台。"))
                                    .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                            }
                        }
                        if busy { ProgressView(localized("載入中")) }
                    }.interfaceSectionSurface()
                    if searching {
                        Section(localized("搜尋結果")) {
                            if results.isEmpty && !busy { Text(localized("沒有搜尋結果。")) }
                            ForEach(results) { song in songRow(song, saved: false) }
                        }.interfaceSectionSurface()
                    }
                } else {
                    Section {
                        Label(localized("請先導入或選擇 JS 音源"), systemImage: "music.note")
                    }.interfaceSectionSurface()
                }
            }
            if isLibrary || !saved.isEmpty {
                Section(localized("已收藏音樂")) {
                    if isLibrary {
                        TextField(localized("搜尋已收藏音樂"), text: $query).autocorrectionDisabled()
                    }
                    if saved.isEmpty { Text(localized("尚無收藏")) }
                    ForEach(saved) { song in songRow(song, saved: true) }
                }.interfaceSectionSurface()
            }
            if let error = store.loadFailure ?? library.loadFailure {
                Section { Text(error).foregroundStyle(DSColor.textSecondary) }
            }
        }
        .accessibilityIdentifier(isLibrary ? "mediaHub.musicLibrary" : "mediaHub.musicHome")
        .fileImporter(isPresented: $importing, allowedContentTypes: [UTType(filenameExtension: "js") ?? .javaScript],
                      allowsMultipleSelection: false, onCompletion: importSource)
        .sheet(isPresented: $sourceManagement) { sourceList }
        .sheet(item: $playing) { item in MusicPlayerView(item: item, queue: [item], autoPlay: true) }
        .alert(localized("音樂導入失敗"), isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })) {
            Button(localized("關閉"), role: .cancel) { failure = nil }
        } message: { Text(failure ?? "") }
        .task {
            library.reload()
            if selectedSourceID.isEmpty { selectedSourceID = store.sources.first?.id ?? "" }
            chooseProvider()
        }
        .onChange(of: selectedSourceID) { _, _ in
            task?.cancel(); generation = UUID(); busy = false; searching = false; results = []; chooseProvider()
        }
        .onChange(of: providerID) { _, _ in
            task?.cancel(); generation = UUID(); busy = false; results = []; searching = false
            quality = provider?.qualities.first ?? "128k"
        }
        .onDisappear { task?.cancel() }
    }

    private func chooseProvider() {
        providerID = source?.providers.first(where: \.canSearch)?.id ?? source?.providers.first?.id ?? ""
        quality = provider?.qualities.first ?? "128k"
    }

    private func songRow(_ song: MusicJSSong, saved isSaved: Bool) -> some View {
        Button { play(song) } label: {
            HStack(spacing: DSSpacing.md) {
                Image(systemName: "play.circle.fill").font(DSFont.title).foregroundStyle(DSColor.accent)
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    Text(song.title).foregroundStyle(DSColor.textPrimary).lineLimit(2)
                    Text([song.artist, song.album].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary).lineLimit(1)
                }
            }.frame(minHeight: 44)
        }
        .disabled(busy)
        .accessibilityIdentifier("mediaHub.music.song.\(song.id)")
        .contextMenu {
            if isSaved {
                Button(localized("移除收藏"), role: .destructive) {
                    do { try library.remove(song.savedItem(sourceName: sourceName(song))) }
                    catch { failure = error.localizedDescription }
                }
            } else {
                Button(localized("加入媒體庫")) {
                    do { try library.save(song.savedItem(sourceName: sourceName(song))) }
                    catch { failure = error.localizedDescription }
                }
            }
        }
    }

    private func sourceName(_ song: MusicJSSong) -> String {
        store.sources.first { $0.id == song.sourceID }?.name ?? localized("JS 音源")
    }

    private func importSource(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result, let url = urls.first else {
            if case .failure(let error) = result, (error as NSError).code != CocoaError.userCancelled.rawValue {
                failure = error.localizedDescription
            }
            return
        }
        task?.cancel(); let token = UUID(); generation = token; busy = true
        task = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                let source = try await store.importFile(url)
                try Task.checkCancellation()
                selectedSourceID = source.id; chooseProvider()
            } catch { if !Task.isCancelled && generation == token { failure = error.localizedDescription } }
        }
    }

    private func search() {
        guard provider?.canSearch == true, !busy else { return }
        task?.cancel(); let token = UUID(); generation = token; busy = true; searching = true; results = []
        let sourceID = selectedSourceID, provider = providerID, keyword = query
        task = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                let found = try await store.search(sourceID: sourceID, provider: provider, query: keyword)
                try Task.checkCancellation()
                if generation == token { results = found }
            } catch { if !Task.isCancelled && generation == token { failure = error.localizedDescription } }
        }
    }

    private func play(_ song: MusicJSSong) {
        guard !busy else { return }
        task?.cancel(); let token = UUID(); generation = token; busy = true
        let available = store.sources.first { $0.id == song.sourceID }?.providers.first { $0.id == song.provider }
        let selectedQuality = available?.qualities.contains(quality) == true ? quality : available?.qualities.first ?? "128k"
        task = Task { @MainActor in
            defer { if generation == token { busy = false } }
            do {
                let item = try await store.resolve(song, quality: selectedQuality)
                try Task.checkCancellation()
                if generation == token { playing = item }
            } catch { if !Task.isCancelled && generation == token { failure = error.localizedDescription } }
        }
    }

    private var sourceList: some View {
        NavigationStack {
            List {
                ForEach(store.sources) { source in
                    VStack(alignment: .leading, spacing: DSSpacing.xs) {
                        Text(source.name).font(DSFont.headline)
                        Text(source.version + " · " + source.providers.map(\.name).joined(separator: " / "))
                            .font(DSFont.footnote).foregroundStyle(DSColor.textSecondary)
                    }
                    .swipeActions {
                        Button(localized("移除"), role: .destructive) {
                            do { try store.remove(source) }
                            catch { failure = error.localizedDescription }
                        }
                    }
                }
            }
            .navigationTitle(localized("管理音源"))
            .toolbar { ToolbarItem(placement: .confirmationAction) {
                Button(localized("關閉")) { sourceManagement = false }
            } }
        }
    }
}
