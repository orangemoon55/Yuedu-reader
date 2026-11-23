import Combine
import SwiftUI

/// Keeps the first result for each normalized cover URL, in source completion order.
struct OnlineCoverCandidateAccumulator {
    private(set) var candidates: [CoverCandidate] = []
    private var seenURLs = Set<String>()

    mutating func append(_ origins: [BookOrigin]) {
        for origin in origins {
            let url = origin.coverUrl.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !url.isEmpty, let key = Self.normalizedURLKey(url), seenURLs.insert(key).inserted else {
                continue
            }
            candidates.append(CoverCandidate(
                coverUrl: url,
                sourceId: origin.sourceId,
                providerName: origin.sourceName
            ))
        }
    }

    static func normalizedURLKey(_ rawURL: String) -> String? {
        guard var components = URLComponents(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        components.scheme = scheme
        components.host = host
        if (scheme == "http" && components.port == 80) || (scheme == "https" && components.port == 443) {
            components.port = nil
        }
        if components.path.isEmpty { components.path = "/" }
        components.fragment = nil
        return components.string
    }
}

/// 搜索已启用、配置了书籍搜索地址的来源，并把同书结果里的封面实时汇总。
@MainActor
final class OnlineCoverSearchViewModel: ObservableObject {
    @Published private(set) var candidates: [CoverCandidate] = []
    @Published private(set) var isSearching = false
    @Published private(set) var hasSearched = false
    @Published private(set) var completedSources = 0
    @Published private(set) var totalSources = 0

    private var searchTask: Task<Void, Never>?
    private var accumulator = OnlineCoverCandidateAccumulator()

    /// Page one only; this ignores search-tab scope, discovery pins and auto-pause.
    /// Keep sources without a cover rule: scripts can still return cover URLs.
    static func searchableSources(in sources: [BookSource]) -> [BookSource] {
        sources.filter { $0.enabled && !$0.searchUrl.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    func start(
        title: String,
        author: String,
        sources: [BookSource]? = nil,
        fetcher: any BookSourceFetching = LiveBookSourceFetcher(bookSourceFetcher: .shared),
        secondsPerSource: UInt64 = 20
    ) {
        guard !isSearching else { return }
        searchTask?.cancel()
        candidates = []
        accumulator = OnlineCoverCandidateAccumulator()
        completedSources = 0
        hasSearched = true

        let sources = Self.searchableSources(in: sources ?? BookSourceStore.shared.sources)
        totalSources = sources.count
        isSearching = !sources.isEmpty
        guard !sources.isEmpty else { return }

        let concurrency = NetworkSearchSettings.clampedConcurrency(GlobalSettings.shared.searchConcurrency)
        searchTask = Task { [weak self] in
            guard let self else { return }
            await BookOriginSearchService.stream(
                title: title,
                author: author,
                sources: sources,
                concurrency: concurrency,
                fetcher: fetcher,
                matchesAuthor: true,
                secondsPerSource: secondsPerSource,
                onSourceFinished: {
                    guard !Task.isCancelled else { return }
                    self.completedSources += 1
                },
                onBatch: { origins in
                    guard !Task.isCancelled else { return }
                    self.accumulator.append(origins)
                    self.candidates = self.accumulator.candidates
                }
            )
            guard !Task.isCancelled else { return }
            self.isSearching = false
        }
    }

    func stop() {
        searchTask?.cancel()
        searchTask = nil
        isSearching = false
    }
}

/// The 封面搜索 screen. Picking a cover hands it back to 書籍資訊.
struct OnlineCoverSearchView: View {
    let title: String
    let author: String
    let onSelect: (CoverCandidate) -> Void

    @StateObject private var model = OnlineCoverSearchViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        AdaptiveSheetContainer(maxWidth: DSLayout.readableListWidth) {
            CoverCandidateGrid(
                bookTitle: title,
                candidates: model.candidates,
                isSearching: model.isSearching,
                hasSearched: model.hasSearched,
                emptyHint: model.totalSources == 0
                    ? localized("請先安裝並啟用支援搜索的書源，或從相簿選一張圖片。")
                    : localized("可以從相簿選一張圖片，或更換書源後重試。"),
                searchProgress: String(
                    format: localized("已完成 %1$d / %2$d 個書源 · %3$d 張封面"),
                    model.completedSources, model.totalSources, model.candidates.count
                )
            ) { candidate in
                model.stop()
                onSelect(candidate)
                dismiss()
            }
        }
        .navigationTitle(localized("封面搜索"))
        .toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .bookshelf)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if model.isSearching {
                        model.stop()
                    } else {
                        model.start(title: title, author: author)
                    }
                } label: {
                    Image(systemName: model.isSearching ? "stop.circle" : "arrow.clockwise")
                }
                .accessibilityLabel(
                    model.isSearching ? localized("停止搜索") : localized("重新搜尋")
                )
            }
        }
        .onAppear { model.start(title: title, author: author) }
        .onDisappear { model.stop() }
    }
}

#Preview {
    NavigationStack {
        OnlineCoverSearchView(
            title: "紅樓夢",
            author: "曹雪芹",
            onSelect: { _ in }
        )
    }
}
