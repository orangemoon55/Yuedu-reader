import YueduCoreText
import Combine
import SwiftUI

// MARK: - Fixed page reader (SwiftUI entry)
//
// Hosts the UIKit `FixedPageReaderViewController` full-screen and overlays SwiftUI
// controls. Shared state flows through `FixedPageReaderState`.

@MainActor
final class FixedPageReaderState: ObservableObject {
    @Published var chapterTitle: String = ""
    @Published var chapterListItems: [FixedPageChapterListItem] = []
    @Published var currentChapterIndex: Int = 0
    @Published var currentPage: Int = 0
    @Published var totalPages: Int = 0
    @Published var fixedPageReaderConfiguration: FixedPageReaderConfiguration = .recommendedDefault(for: .rtl)
    /// A manga, so the settings sheet offers 漫畫預設模式 (feedback #37).
    @Published var isManga: Bool = false
    /// The book has no reading mode of its own yet: it opened in 漫畫預設模式, and changing
    /// that default here changes it too.
    @Published var followsMangaDefault: Bool = false
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    /// The book opens on the page, as the flowing reader does. The pages are images
    /// with no accessibility element, so under VoiceOver the controls are all there
    /// is to focus: they come up with the book and stay up.
    @Published var showControls: Bool = UIAccessibility.isVoiceOverRunning
    @Published var showChapterList: Bool = false
    @Published var isAutoScrolling: Bool = false
    /// The page is moving: a finger, a glide or auto-scroll. The auto-scroll button dims.
    @Published var isContentScrolling: Bool = false

    // Actions wired by the controller.
    var onJumpToPage: ((Int) -> Void)?
    var onSelectChapter: ((Int) -> Void)?
    var onSetConfiguration: ((FixedPageReaderConfiguration) -> Void)?
    var onNextChapter: (() -> Void)?
    var onPrevChapter: (() -> Void)?
    var onPrepareForExit: (() -> Void)?
    var onReload: (() -> Void)?
    var onToggleAutoScroll: (() -> Void)?
    var onStopAutoScroll: (() -> Void)?
    /// Flush the live page, then fence off the old controller until the switch finishes.
    var onSetSourceChangeSuspended: ((Bool) -> Void)?
}

struct FixedPageChapterListItem: Identifiable, Equatable {
    let id: UUID
    let index: Int
    let title: String

    static func items(from refs: [OnlineChapterRef]) -> [FixedPageChapterListItem] {
        refs.enumerated().map { offset, ref in
            let trimmedTitle = ref.title.trimmingCharacters(in: .whitespacesAndNewlines)
            return FixedPageChapterListItem(
                id: ref.id,
                index: offset,
                title: trimmedTitle.isEmpty
                    ? String(format: localized("第 %d 章"), offset + 1)
                    : trimmedTitle
            )
        }
    }
}

struct FixedPageReaderView: View {
    let bookId: UUID
    @EnvironmentObject var store: BookStore
    // iOS 17 invalidates DismissAction over and over while a reader is pushed above
    // a book detail, and this reader's toolbar feeds every rebuild back into
    // navigation layout. Same stable binding as BookReaderView and ReaderView
    // (Technotes/iOS17ReaderNavigationWatchdog.md).
    @Environment(\.presentationMode) private var presentationMode
    @Environment(\.readerNavigator) private var readerNavigator
    @Environment(\.readerUsesParentNavigationStack) private var usesParentNavigationStack
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.appDependencies) private var dependencies
    @StateObject private var state = FixedPageReaderState()
    @Bindable private var globalSettings = GlobalSettings.shared
    @State private var readingStatsTracker: ReadingStatsSessionTracker?
    @State private var showTouchZoneEditor = false
    @State private var showDownloadOptions = false
    @State private var sourcePickerBook: ReadingBook?
    @State private var sourceSwitchTask: Task<Void, Never>?
    @State private var sourceGeneration = UUID()
    @State private var isSwitchingSource = false

    var body: some View {
        // The shelf's card push hosts this reader in a UIKit controller whose bar
        // carries the toolbar. Every other entry lets ReaderNavigationContainer
        // decide, as the flowing reader does: a modal reader brings its own stack,
        // a reader pushed from a book detail joins the detail's. No card navigator
        // does not mean modal; the detail's destination must never hold a second
        // NavigationStack (DetailReaderStackTests).
        if readerNavigator == nil {
            ReaderNavigationContainer { readerContent }
        } else {
            readerContent
        }
    }

    private var readerContent: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let book = store.readingBook(id: bookId) {
                FixedPageReaderRepresentable(
                    book: book,
                    store: store,
                    state: state,
                    chapterFetcher: dependencies.chapterFetcher
                )
                    // A controller snapshots source headers, decoder, TOC and held pages.
                    // A successful switch must replace it, not call its old onReload.
                    .id(sourceGeneration)
                    .ignoresSafeArea()

                if state.isLoading || isSwitchingSource {
                    ProgressView().tint(.white).controlSize(.large)
                }

                if let message = state.errorMessage {
                    errorView(message)
                }

                if state.showControls {
                    FixedPageReaderControlsOverlay(
                        state: state,
                        isModal: readerNavigator == nil && !usesParentNavigationStack,
                        onClose: {
                            sourceSwitchTask?.cancel()
                            state.onPrepareForExit?()
                            if let readerNavigator {
                                readerNavigator.close()
                            } else {
                                // Pops a detail-origin push, dismisses a modal reader.
                                presentationMode.wrappedValue.dismiss()
                            }
                        },
                        onOpenTouchZoneEditor: {
                            state.showControls = false
                            showTouchZoneEditor = true
                        },
                        onChangeSource: book.isOnline && book.resolvedPipelineKind == .manga
                            && book.bookSourceId != nil ? {
                                guard !isSwitchingSource else { return }
                                state.onStopAutoScroll?()
                                sourcePickerBook = currentBook
                            } : nil,
                        onOfflineCache: offlineCacheSupported(book) ? openDownloadOptions : nil,
                        offlineCacheEnabled: !isSwitchingSource && offlineCacheChapterIndex(for: book) != nil
                    )
                        .transition(.opacity)
                }

                if state.fixedPageReaderConfiguration.layout == .continuousVerticalScroll,
                   globalSettings.fixedPageAutoScrollButton {
                    FixedPageAutoScrollButton(
                        isAutoScrolling: state.isAutoScrolling,
                        isContentScrolling: state.isContentScrolling,
                        position: globalSettings.fixedPageAutoScrollButtonPosition,
                        action: { state.onToggleAutoScroll?() }
                    )
                    .transition(.opacity)
                }

                if showTouchZoneEditor {
                    ReaderTouchZoneEditorView(
                        isRTL: state.fixedPageReaderConfiguration.progression == .rightToLeft,
                        offersChangeSource: false,
                        onCancel: { showTouchZoneEditor = false },
                        onSave: { showTouchZoneEditor = false }
                    )
                    .zIndex(100)
                }
            }
        }
        .animation(DSAnimation.fast, value: state.showControls)
        .hidesRootTabBar()
        .navigationBarBackButtonHidden(true)
        .toolbarTitleDisplayMode(.inline)
        .toolbar(state.showControls ? .visible : .hidden, for: .navigationBar, .bottomBar)
        // The page is black in either appearance, and light-mode bars put a black
        // title and status bar on it. A visible bar background keeps the controls on
        // a backdrop wherever a bar does not take the dark scheme (iOS 27's bottom
        // bar does not, and iOS 17 draws its bars transparent over the page).
        .toolbarBackground(.visible, for: .navigationBar, .bottomBar)
        .toolbarColorScheme(.dark, for: .navigationBar, .bottomBar)
        .statusBarHidden(!state.showControls)
        // Same immersive rule as the flowing reader: the home indicator fades with
        // the controls and comes back with them.
        .persistentSystemOverlays(
            ReaderOverlayPresentationPolicy.hidesHomeIndicator(
                showsReaderChrome: state.showControls,
                isEditing: false
            ) ? .hidden : .automatic
        )
        .onChange(of: state.isLoading) { _, isLoading in
            if !isLoading {
                // The page container or its error state has been installed.
                readerNavigator?.signalReaderContentReady()
            }
        }
        .onChange(of: state.fixedPageReaderConfiguration) { _, configuration in
            readerNavigator?.updateOpeningDirection(
                ReaderBookOpeningDirection.resolve(
                    writingMode: .horizontal,
                    pageProgressionIsRTL: configuration.progression == .rightToLeft
                )
            )
        }
        .onAppear {
            beginReadingStatsSession()
        }
        .onDisappear {
            // Leaving the reader while a TOC is pending must not rebind its source later.
            sourceSwitchTask?.cancel()
            finishReadingStatsSession()
        }
        .onChanged(of: scenePhase) { phase in
            if phase == .background || phase == .inactive {
                finishReadingStatsSession()
            } else if phase == .active {
                beginReadingStatsSession()
            }
        }
        .onChange(of: state.showChapterList) { _, isPresented in
            if isPresented { state.onStopAutoScroll?() }
        }
        // Switched off in settings: its button goes, so nothing would be left to stop it.
        .onChange(of: globalSettings.fixedPageAutoScrollButton) { _, isOn in
            if !isOn { state.onStopAutoScroll?() }
        }
        // VoiceOver turned on while the controls were away: they are its only way out.
        .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
            if UIAccessibility.isVoiceOverRunning { state.showControls = true }
        }
        .sheet(isPresented: $state.showChapterList) {
            FixedPageChapterListView(state: state, bookID: bookId) { state.showChapterList = false }
        }
        .sheet(isPresented: $showDownloadOptions) {
            if let book = currentBook {
                downloadOptions(for: book)
            }
        }
        .sheet(item: $sourcePickerBook) { book in
            if let sourceID = book.bookSourceId {
                SourceSearchSheet(
                    query: book.title, author: book.author,
                    currentSourceId: sourceID, currentBookURL: book.bookInfoURL ?? "",
                    kind: .manga, restrictToKind: true,
                    onSelectOrigin: { switchSource(to: $0) }
                )
            }
        }
    }

    private func switchSource(to origin: BookOrigin) {
        guard !isSwitchingSource,
              let before = currentBook, before.isOnline,
              before.resolvedPipelineKind == .manga else { return }
        guard let source = BookSourceStore.shared.source(id: origin.sourceId), source.enabled,
              origin.inferredContentKind() == .manga else {
            state.errorMessage = localized("找不到來源配置")
            return
        }
        guard before.bookSourceId != origin.sourceId || before.bookInfoURL != origin.bookUrl else { return }
        state.onSetSourceChangeSuspended?(true)
        isSwitchingSource = true
        sourceSwitchTask = Task { @MainActor in
            defer {
                if !Task.isCancelled {
                    isSwitchingSource = false
                    sourceSwitchTask = nil
                }
            }
            do {
                let search = ChangeSourceSearch(fetcher: dependencies.bookSourceFetcher)
                let toc = try await search.prepareTOCPackage(for: origin)
                try Task.checkCancellation()
                // A candidate may be removed/disabled while its TOC is loading. Also never
                // rebind a removed book or overwrite another switch that won the race.
                guard let live = currentBook, live.isOnline,
                      live.bookSourceId == before.bookSourceId,
                      live.bookInfoURL == before.bookInfoURL,
                      let selected = BookSourceStore.shared.source(id: origin.sourceId), selected.enabled,
                      origin.inferredContentKind() == .manga else {
                    throw NSError(domain: "FixedPageSourceChange", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: localized("找不到來源配置")])
                }
                await dependencies.chapterFetcher.cancelAll(for: bookId, includingDownloads: true)
                try Task.checkCancellation()
                try await OnlineBookSourceSwitch(store: store, dependencies: dependencies)
                    .commit(bookId: bookId, origin: origin, toc: toc)
                // Finish the source/position commit even if exit cancelled its caller.
                // Only the now-stale presentation work is suppressed.
                guard !Task.isCancelled else { return }
                // The old controller stays suspended: its disappearance must not save its
                // old chapter over the mapped position. The new one reads the same book ID.
                state.errorMessage = nil
                state.isLoading = true
                sourceGeneration = UUID()
            } catch {
                // Cancellation on exit must not resume the departing controller.
                guard !Task.isCancelled else { return }
                state.onSetSourceChangeSuspended?(false)
                if !(error is CancellationError) { state.errorMessage = error.localizedDescription }
            }
        }
    }

    private var currentBook: ReadingBook? {
        store.readingBook(id: bookId)
    }

    private func offlineCacheSupported(_ book: ReadingBook) -> Bool {
        guard book.isInBookshelf, book.isOnline, book.remoteSource == nil,
              book.resolvedPipelineKind == .manga, let sourceID = book.bookSourceId else { return false }
        return BookSourceStore.shared.source(id: sourceID)?.enabled == true
    }

    private func offlineCacheChapterIndex(for book: ReadingBook) -> Int? {
        let index = state.currentChapterIndex
        guard state.chapterListItems.indices.contains(index), let chapters = book.onlineChapters,
              !chapters.isEmpty else { return nil }
        let chapterID = state.chapterListItems[index].id
        // The reader holds its TOC snapshot. Resolve its row against the shelf TOC the queue uses.
        if chapters.indices.contains(index), chapters[index].id == chapterID { return index }
        return chapters.firstIndex { $0.id == chapterID }
    }

    private func openDownloadOptions() {
        guard !isSwitchingSource, let book = currentBook, offlineCacheSupported(book),
              offlineCacheChapterIndex(for: book) != nil else { return }
        state.onStopAutoScroll?()
        showDownloadOptions = true
    }

    private func downloadOptions(for book: ReadingBook) -> some View {
        let manager = dependencies.offlineDownloadManager
        let chapters = book.onlineChapters ?? []
        return ReaderDownloadOptionsView(
            bookId: book.id,
            bookTitle: book.title,
            currentChapterIndex: offlineCacheChapterIndex(for: book) ?? 0,
            totalChapters: chapters.count,
            onStart: { start, count in
                guard !isSwitchingSource, let latest = currentBook, offlineCacheSupported(latest),
                      latest.bookSourceId == book.bookSourceId, latest.bookInfoURL == book.bookInfoURL,
                      chapters.indices.contains(start), count > 0 else { return }
                let end = start + min(count, chapters.count - start) - 1
                guard let latestChapters = latest.onlineChapters, latestChapters.indices.contains(end),
                      (start...end).allSatisfy({ latestChapters[$0].id == chapters[$0].id }) else {
                    showDownloadOptions = false
                    return
                }
                Task { await manager.start(book: latest, selection: .range(start...end), store: store) }
            },
            onPause: { Task { await manager.pause(bookId: book.id, store: store) } },
            onResume: {
                guard let latest = currentBook, offlineCacheSupported(latest) else { return }
                Task {
                    if latest.offlineDownloadState == .partial || latest.offlineDownloadState == .failed {
                        await manager.retryFailed(book: latest, store: store)
                    } else {
                        await manager.resume(book: latest, store: store)
                    }
                }
            },
            onSkipFailed: { Task { await manager.skipFailed(bookId: book.id, store: store) } },
            onRemove: {
                Task {
                    do { try await manager.remove(bookId: book.id, store: store) }
                    catch { AppLogger.error("Failed to remove offline download", error: error) }
                }
            },
            onClose: { showDownloadOptions = false }
        )
    }

    private func beginReadingStatsSession() {
        guard readingStatsTracker == nil, let currentBook else { return }
        readingStatsTracker = ReadingStatsSessionTracker(
            bookId: currentBook.id.uuidString,
            bookTitle: currentBook.title
        )
    }

    private func finishReadingStatsSession() {
        guard let tracker = readingStatsTracker else { return }
        if let session = tracker.finish() {
            ReadingStatsStore.shared.recordSession(session)
        }
        readingStatsTracker = nil
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: DSSpacing.md) {
            Text(message)
                .foregroundColor(.white)
                .font(DSFont.body)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button(localized("重試")) { state.onReload?() }
                .foregroundColor(DSColor.accent)
                .font(DSFont.bodyBold)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - UIKit bridge

private struct FixedPageReaderRepresentable: UIViewControllerRepresentable {
    let book: ReadingBook
    let store: BookStore
    let state: FixedPageReaderState
    let chapterFetcher: any ChapterFetching

    func makeUIViewController(context: Context) -> FixedPageReaderViewController {
        FixedPageReaderViewController(
            book: book,
            store: store,
            state: state,
            chapterFetcher: chapterFetcher
        )
    }

    func updateUIViewController(_ uiViewController: FixedPageReaderViewController, context: Context) {}

    static func dismantleUIViewController(_ controller: FixedPageReaderViewController, coordinator: ()) {
        controller.prepareForExit()
    }
}

// MARK: - Controls overlay

struct FixedPageReaderControlsOverlay: View {
    @ObservedObject var state: FixedPageReaderState
    var isModal = true
    var onClose: () -> Void
    var onOpenTouchZoneEditor: () -> Void
    var onChangeSource: (() -> Void)? = nil
    var onOfflineCache: (() -> Void)? = nil
    var offlineCacheEnabled = false
    @State private var showSettings = false
    @State private var pendingTouchZoneEditor = false
    /// iOS 17: the paywall a locked setting asked for, presented once settings is gone.
    @State private var pendingPaywall: PremiumFeature?
    @State private var paywallFeature: PremiumFeature?

    var body: some View {
        GeometryReader { geometry in
            Color.clear
                .allowsHitTesting(false)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: onClose) {
                            Label(localized(isModal ? "關閉" : "返回"), systemImage: isModal ? "xmark" : "chevron.left")
                                .labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if !state.chapterListItems.isEmpty {
                            Button {
                                state.onStopAutoScroll?()
                                state.showChapterList = true
                            } label: {
                                Label(localized("目錄"), systemImage: "list.bullet")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarLeading) {
                        if let onOfflineCache, !state.chapterListItems.isEmpty {
                            Button(action: onOfflineCache) {
                                Label(localized("离线缓存"), systemImage: "arrow.down.circle")
                                    .labelStyle(.iconOnly)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityIdentifier("manga.offlineCache")
                            .disabled(!offlineCacheEnabled)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let onChangeSource {
                            Button(action: onChangeSource) {
                                Label(localized("換源"), systemImage: "arrow.left.and.right")
                                    .labelStyle(.iconOnly)
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            state.onStopAutoScroll?()
                            showSettings = true
                        } label: {
                            Label(localized("閱讀設定"), systemImage: "slider.horizontal.3")
                                .labelStyle(.iconOnly)
                        }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        // Like Aidoku, the progress control lives in the native toolbar.
                        // Measure this window, including Split View, rather than the screen.
                        bottomBar
                            .frame(width: max(0, geometry.size.width - DSSpacing.xl * 2))
                    }
                }
        }
        .navigationTitle(state.chapterTitle)
        .sheet(isPresented: $showSettings, onDismiss: {
            if pendingTouchZoneEditor {
                pendingTouchZoneEditor = false
                onOpenTouchZoneEditor()
            }
            if let feature = pendingPaywall {
                pendingPaywall = nil
                paywallFeature = feature
            }
        }) {
            FixedPageReaderSettingsView(
                state: state,
                onClose: { showSettings = false },
                onOpenTouchZoneEditor: {
                    pendingTouchZoneEditor = true
                    showSettings = false
                },
                onOpenPaywall: ReaderSettingsPresentationPolicy.requiresFirstLevelImporter
                    ? { feature in
                        pendingPaywall = feature
                        showSettings = false
                    }
                    : nil
            )
        }
        .sheet(item: $paywallFeature) { feature in
            PaywallView(highlightedFeature: feature)
                .environmentObject(SubscriptionStore.shared)
        }
    }

    private var isRTL: Bool {
        state.fixedPageReaderConfiguration.progression == .rightToLeft
    }

    private var pageIndicatorText: String {
        String(format: localized("第 %d / %d 頁"), state.currentPage + 1,
               max(state.totalPages, state.currentPage + 1))
    }

    private var bottomBar: some View {
        HStack(spacing: DSSpacing.sm) {
            chapterButton(forward: false)
            // Aidoku's ReaderToolbarView anchors the slider to the top of the
            // bar and pins the page labels to its bottom edge, so the label
            // never takes part in the slider's own layout. Stacking the two in
            // a VStack instead centres them as a pair and leaves the slider
            // about 6pt above the bar's centre line.
            ZStack {
                Slider(
                    value: Binding(
                        get: { Double(state.currentPage) },
                        set: { state.onJumpToPage?(Int($0.rounded())) }
                    ),
                    in: 0...Double(max(1, state.totalPages - 1)),
                    step: 1
                )
                .disabled(state.totalPages <= 1)
                // The value is always plain forward progress; a right-to-left
                // book mirrors the *track* instead, which is what Aidoku's
                // ReaderSliderView does for `direction == .backward` by
                // re-anchoring its thumb and filled track to the trailing edge.
                // Inverting the value here instead filled the whole bar on page
                // one of a manga, so a freshly opened book read as finished.
                .environment(\.layoutDirection, isRTL ? .rightToLeft : .leftToRight)
                .tint(DSColor.textPrimary)
                .accessibilityLabel(localized("閱讀進度"))
                .accessibilityValue(pageIndicatorText)
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    Text(pageIndicatorText)
                        .font(DSFont.caption2)
                        .foregroundStyle(DSColor.textSecondary)
                        .accessibilityHidden(true)
                }
            }
            chapterButton(forward: true)
        }
        // The bar itself never mirrors with the app's UI language; only the
        // slider above follows the book. This is what Aidoku gets from
        // `semanticContentAttribute = .playback` on its slider view.
        .environment(\.layoutDirection, .leftToRight)
        // The toolbar's capsule keeps its own height whatever this frame asks for,
        // so anything laid out past minimumTapTarget spills outside it — that is
        // what pushed the page number half out of the bar.
        .frame(height: DSLayout.minimumTapTarget)
    }

    private func chapterButton(forward: Bool) -> some View {
        let nextChapter = forward != isRTL
        return Button {
            if nextChapter { state.onNextChapter?() } else { state.onPrevChapter?() }
        } label: {
            Image(systemName: forward ? "forward.end" : "backward.end")
                .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(DSColor.textPrimary)
        .accessibilityLabel(nextChapter ? localized("下一章") : localized("上一章"))
    }
}

struct FixedPageReaderSettingsView: View {
    @ObservedObject var state: FixedPageReaderState
    /// Closes this sheet. Not `@Environment(\.dismiss)`: under the detail → reader push
    /// iOS 17 replaces that DismissAction on every update of the pages below — 搜索
    /// publishing its later pages re-ran this body each time, the open 閱讀模式 menu
    /// included. Feedback #132 (iOS 17.0) reported picks made then that did not take.
    /// `Technotes/iOS17ReaderNavigationWatchdog.md`.
    var onClose: () -> Void
    var onOpenTouchZoneEditor: () -> Void
    /// iOS 17: hands the paywall to the controls overlay, which presents it once this
    /// sheet is gone — a sheet asked for from inside this one can be dropped there
    /// (`ReaderSettingsPresentationPolicy`). Nil where this view presents it itself.
    var onOpenPaywall: ((PremiumFeature) -> Void)? = nil
    @ObservedObject private var subscriptionStore = SubscriptionStore.shared
    @Bindable private var globalSettings = GlobalSettings.shared
    @State private var paywallFeature: PremiumFeature?

    private var configuration: FixedPageReaderConfiguration { state.fixedPageReaderConfiguration }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker(localized("閱讀模式"), selection: Binding(
                        get: { configuration.mode },
                        set: { selectMode($0) }
                    )) {
                        ForEach(FixedPageReadingMode.allCases, id: \.rawValue) { mode in
                            Text(mode.localizedName).tag(mode)
                        }
                    }
                }
                if state.isManga {
                    Section {
                        Picker(localized("漫畫預設模式"), selection: Binding(
                            get: { globalSettings.fixedPageMangaDefaultMode },
                            set: { mode in
                                globalSettings.fixedPageMangaDefaultMode = mode
                                // Still in the old default: this book had no mode of its own.
                                if state.followsMangaDefault { selectMode(mode) }
                            }
                        )) {
                            ForEach(FixedPageReadingMode.allCases, id: \.rawValue) { mode in
                                Text(mode.localizedName).tag(mode)
                            }
                        }
                    } footer: {
                        Text(localized("只套用到還沒自己選過閱讀模式的漫畫。"))
                            .dsSectionFooter()
                    }
                }
                Section {
                    if configuration.layout == .paged {
                        Picker(localized("頁面顯示"), selection: binding(\.pageSpreadLayout)) {
                            ForEach(FixedPageReaderConfiguration.PageSpreadLayout.allCases, id: \.rawValue) { layout in
                                Text(spreadTitle(layout)).tag(layout)
                            }
                        }
                        Toggle(localized("封面單頁偏移"), isOn: binding(\.pageOffset))
                        Toggle(localized("自動切分雙頁大圖"), isOn: binding(\.splitWideImages))
                    } else {
                        Toggle(localized("寬屏黑邊限制"), isOn: binding(\.pillarbox))
                    }
                    Toggle(localized("自動裁切留白邊框"), isOn: binding(\.cropBorders))
                    Toggle(localized("原文字選取與識別"), isOn: binding(\.isLiveTextEnabled))
                }
                Section {
                    Toggle(localized("雙擊放大"), isOn: $globalSettings.fixedPageDoubleTapToZoom)
                } footer: {
                    Text(localized("關閉後，點一下會立即翻頁或呼出選單；雙指縮放照常可用。所有書共用這個設定。"))
                        .dsSectionFooter()
                }
                if configuration.layout == .continuousVerticalScroll {
                    Section {
                        Toggle(localized("自動捲動"), isOn: $globalSettings.fixedPageAutoScrollButton)
                        if globalSettings.fixedPageAutoScrollButton {
                            Picker(localized("按鈕位置"), selection: $globalSettings.fixedPageAutoScrollButtonPosition) {
                                Text(localized("左側")).tag(FixedPageAutoScrollButtonPosition.left)
                                Text(localized("右側")).tag(FixedPageAutoScrollButtonPosition.right)
                            }
                            autoScrollSpeedRow
                        }
                    } footer: {
                        Text(localized("開啟後，畫面角落會出現播放按鈕，點一下開始或暫停自動捲動。"))
                            .dsSectionFooter()
                    }
                }
                if configuration.layout == .paged {
                    Section {
                        if ReaderPremiumVisibilityPolicy(isProActive: subscriptionStore.isProActive).showsTouchZoneEditor {
                            Button(action: onOpenTouchZoneEditor) {
                                Label(localized("翻頁區塊編輯"), systemImage: "hand.tap")
                            }
                        } else {
                            // Seen without Pro too, locked (2026-09-27): the paywall, not the editor.
                            Button {
                                requestPaywall(.touchZoneEditor)
                            } label: {
                                HStack {
                                    Label(localized("翻頁區塊編輯"), systemImage: "hand.tap")
                                        .foregroundStyle(DSColor.textPrimary)
                                    Spacer(minLength: DSSpacing.md)
                                    Text(localized("需要 Pro"))
                                        .foregroundStyle(DSColor.textSecondary)
                                    Image(systemName: "lock.fill")
                                        .font(DSFont.caption)
                                        .foregroundStyle(DSColor.textSecondary)
                                        .accessibilityHidden(true)
                                }
                            }
                        }
                    }
                }
            }
            .softScrollEdges()
            .navigationTitle(localized("閱讀設定"))
            .toolbarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: onClose) {
                        Label(localized("關閉"), systemImage: "xmark").labelStyle(.iconOnly)
                    }
                }
            }
            .sheet(item: $paywallFeature) { feature in
                PaywallView(highlightedFeature: feature)
                    .environmentObject(subscriptionStore)
            }
        }
        // Search/detail and shelf readers have different navigation hosts. This
        // sheet owns its control tint rather than inheriting the reader bar's white.
        .tint(DSColor.accent)
    }

    /// A locked control's paywall: from this sheet on iOS 18, from the controls overlay on
    /// iOS 17 (`onOpenPaywall`) — the same split as the flowing reader's settings.
    private func requestPaywall(_ feature: PremiumFeature) {
        if let onOpenPaywall {
            onOpenPaywall(feature)
        } else {
            paywallFeature = feature
        }
    }

    /// Switches this book to `mode`, keeping the toggles it has.
    private func selectMode(_ mode: FixedPageReadingMode) {
        var updated = FixedPageReaderConfiguration.recommendedDefault(for: mode)
        updated.cropBorders = configuration.cropBorders
        updated.isLiveTextEnabled = configuration.isLiveTextEnabled
        updated.pageSpreadLayout = configuration.pageSpreadLayout
        updated.pageOffset = configuration.pageOffset
        updated.splitWideImages = configuration.splitWideImages
        updated.pillarbox = configuration.pillarbox
        state.onSetConfiguration?(updated)
    }

    /// Spoken and shown alike, so VoiceOver never reads a different number.
    private var autoScrollSpeedText: String {
        configuration.autoScrollSpeed.formatted()
    }

    /// The rows around it carry no symbol, so this one doesn't either; otherwise the
    /// same shape as `SettingsSliderRow`.
    private var autoScrollSpeedRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            LabeledContent(localized("速度")) {
                Text(autoScrollSpeedText)
                    .monospacedDigit()
                    .foregroundStyle(DSColor.textSecondary)
            }
            // The slider below carries both; read once, not twice.
            .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { Double(configuration.autoScrollSpeed) },
                    set: { binding(\.autoScrollSpeed).wrappedValue = Int($0.rounded()) }
                ),
                in: Double(FixedPageReaderConfiguration.autoScrollSpeedRange.lowerBound)
                    ... Double(FixedPageReaderConfiguration.autoScrollSpeedRange.upperBound),
                step: 1
            )
            .accessibilityLabel(localized("速度"))
            .accessibilityValue(autoScrollSpeedText)
        }
    }

    private func binding<Value>(_ keyPath: WritableKeyPath<FixedPageReaderConfiguration, Value>) -> Binding<Value> {
        Binding(get: { configuration[keyPath: keyPath] }, set: { value in
            var updated = configuration
            updated[keyPath: keyPath] = value
            state.onSetConfiguration?(updated)
        })
    }

    private func spreadTitle(_ layout: FixedPageReaderConfiguration.PageSpreadLayout) -> String {
        switch layout {
        case .single: return localized("單頁")
        case .double: return localized("雙頁")
        case .auto: return localized("自動雙頁")
        }
    }
}

struct FixedPageChapterListView: View {
    @ObservedObject var state: FixedPageReaderState
    @Environment(\.colorScheme) private var colorScheme
    // Retained call-site identity only; manga TOC no longer reads/writes sort preferences.
    let bookID: UUID?
    /// Stable owner closure, matching the existing fixed-page sheet lifecycle.
    var onClose: () -> Void
    @State private var edgeRequest: ReaderTOCEdgeRequest?
    @State private var latestRowFrame: CGRect?
    @State private var viewportFrame: CGRect = .zero

    private var isAtLatest: Bool {
        ReaderTOCEdgeVisibility.isAtLatest(row: latestRowFrame, viewport: viewportFrame,
                                         verticalColumns: false)
    }

    private var edgeActionTitle: String { localized(isAtLatest ? "回頂部" : "去底部") }

    private func jumpToOtherEdge() {
        guard !state.chapterListItems.isEmpty else { return }
        edgeRequest = ReaderTOCEdgeRequest(destination: isAtLatest ? .first : .latest)
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { proxy in
                List {
                    let first = ReaderTOCEdge.first.target(in: state.chapterListItems, index: \.index, title: \.title)
                    let latest = ReaderTOCEdge.latest.target(in: state.chapterListItems, index: \.index, title: \.title)
                    ForEach(state.chapterListItems) { item in
                        Button {
                            state.onSelectChapter?(item.index)
                        } label: {
                            HStack {
                                Text(item.title)
                                    .foregroundColor(.primary)
                                    .font(DSFont.subheadline)
                                Spacer()
                                if item.index == state.currentChapterIndex {
                                    Image(systemName: "checkmark")
                                        .foregroundColor(.accentColor)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                        .interfaceSectionSurface()
                        .id(item.index)
                        .reportTOCEdges(index: item.index, first: first, latest: latest)
                    }
                }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { viewportFrame = $0 }
                .onPreferenceChange(ReaderTOCEdgeFramesKey.self) { latestRowFrame = $0[.latest] }
                .softScrollEdges()
                .scrollContentBackground(.hidden)
                .contentMargins(.top, 0, for: .scrollContent)
                .accessibilityIdentifier("manga.toc.list")
                .onAppear {
                    // Open at the current chapter, just as the novel TOC does.
                    guard state.chapterListItems.contains(where: { $0.index == state.currentChapterIndex }) else { return }
                    proxy.scrollTo(state.currentChapterIndex, anchor: .center)
                }
                .onChange(of: edgeRequest, initial: true) { _, request in
                    guard let request,
                          let row = request.destination.target(in: state.chapterListItems, index: \.index, title: \.title)
                    else { return }
                    proxy.scrollTo(row, anchor: request.destination.anchor(verticalColumns: false))
                }
            }
            .background(PageBackgroundView(scope: .settings).ignoresSafeArea())
            .pageBackgroundToolbar(for: .settings)
            .navigationTitle(localized("目錄"))
            .toolbarTitleDisplayMode(.inline)
            // The black reader supplies white chrome. Its light TOC sheet needs its
            // own adaptive tint/bar scheme instead of inheriting white-on-white buttons.
            .toolbarColorScheme(colorScheme, for: .navigationBar)
            .tint(DSColor.textPrimary)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onClose) {
                        Label(localized("關閉"), systemImage: "xmark").labelStyle(.iconOnly)
                            .foregroundStyle(DSColor.textPrimary)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: jumpToOtherEdge) {
                        Text(edgeActionTitle).foregroundStyle(DSColor.textPrimary)
                    }
                        .disabled(state.chapterListItems.isEmpty)
                        .accessibilityLabel(edgeActionTitle)
                        .accessibilityIdentifier("toc.latest")
                }
            }
        }
    }
}

#Preview {
    FixedPageReaderView(bookId: UUID())
        .environmentObject(BookStore())
}

#Preview("Controls overlay") {
    let state = FixedPageReaderState()
    state.chapterTitle = "第 1 話"
    state.chapterListItems = FixedPageChapterListItem.items(
        from: [OnlineChapterRef(index: 0, title: "第 1 話", url: "")]
    )
    state.totalPages = 24
    return NavigationStack {
        ZStack {
            Color.black.ignoresSafeArea()
            FixedPageReaderControlsOverlay(state: state, onClose: {}, onOpenTouchZoneEditor: {})
        }
        .toolbarTitleDisplayMode(.inline)
    }
}

#Preview("目錄・首尾跳轉") {
    let state = FixedPageReaderState()
    state.chapterListItems = FixedPageChapterListItem.items(
        from: (0..<12).map { OnlineChapterRef(index: $0, title: "第 \($0 + 1) 話", url: "") }
    )
    state.currentChapterIndex = 4
    let bookID = UUID()
    return FixedPageChapterListView(state: state, bookID: bookID, onClose: {})
}

#Preview("Settings") {
    // Paged by default, so 翻頁區塊編輯 shows — locked unless Pro is active.
    FixedPageReaderSettingsView(state: FixedPageReaderState(), onClose: {}, onOpenTouchZoneEditor: {})
        .environmentObject(SubscriptionStore.shared)
}

#Preview("Settings — webtoon auto-scroll") {
    // Webtoon layout with the auto-scroll button on, so the speed slider shows.
    let state = FixedPageReaderState()
    state.fixedPageReaderConfiguration = .recommendedDefault(for: .webtoon)
    GlobalSettings.shared.fixedPageAutoScrollButton = true
    return FixedPageReaderSettingsView(state: state, onClose: {}, onOpenTouchZoneEditor: {})
        .environmentObject(SubscriptionStore.shared)
}

#Preview("Settings — manga") {
    // A manga offers 漫畫預設模式 under its own reading mode.
    let state = FixedPageReaderState()
    state.isManga = true
    state.followsMangaDefault = true
    return FixedPageReaderSettingsView(state: state, onClose: {}, onOpenTouchZoneEditor: {})
        .environmentObject(SubscriptionStore.shared)
}
