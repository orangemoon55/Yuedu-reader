// CatVodSiteBrowserView.swift
// 瀏覽單一已安裝 CatVod (MD5) 源站點：分類、搜尋、分頁、詳情、播放。
import SwiftUI

// MARK: - Chips

private struct CatVodChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(.subheadline, design: .rounded))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .foregroundStyle(isSelected ? Color.white : Color.primary)
                .background(isSelected ? Color.accentColor : Color.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Poster

private struct CatVodPoster: View {
    let url: URL?
    var width: CGFloat = 104
    var height: CGFloat = 148

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().aspectRatio(contentMode: .fill)
                    case .empty:
                        Rectangle().fill(Color.secondary.opacity(0.12))
                    case .failure:
                        posterPlaceholder
                    @unknown default:
                        posterPlaceholder
                    }
                }
            } else {
                posterPlaceholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var posterPlaceholder: some View {
        ZStack {
            Color.secondary.opacity(0.1)
            Image(systemName: "film")
                .font(.system(size: 20))
                .foregroundStyle(Color.secondary)
        }
    }
}

// MARK: - Browser

/// 站點瀏覽：分類橫條 + 影片網格 + 搜尋 + 分頁。
struct CatVodSiteBrowserView: View {
    @ObservedObject var session: CatVodSession

    var body: some View {
        NavigationStack {
            content
                .navigationTitle(session.site.name)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        if session.site.searchable {
                            NavigationLink {
                                CatVodSearchView(session: session)
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                        }
                    }
                }
                .navigationDestination(for: CatVodVideo.self) { video in
                    CatVodDetailView(video: video, session: session)
                }
        }
        .task {
            if session.categories.isEmpty && session.videos.isEmpty {
                await session.loadHome()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if session.isLoading && session.videos.isEmpty {
            ProgressView(localized("載入中"))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let message = session.errorMessage, session.videos.isEmpty {
            errorState(message)
        } else if session.videos.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 40))
                    .foregroundStyle(Color.secondary)
                Text(localized("暫无内容"))
                    .font(.system(.headline, design: .rounded))
                Text(localized("換一個分類，或到搜尋試試。"))
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Color.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            grid
        }
    }

    private func errorState(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28))
                .foregroundStyle(Color.secondary)
            Text(message)
                .font(.system(.footnote, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.secondary)
            Button(localized("重試")) {
                Task { await session.loadHome() }
            }
            .buttonStyle(.bordered)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var grid: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                if !session.categories.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            CatVodChip(title: localized("全部"),
                                       isSelected: session.selectedCategoryID.isEmpty) {
                                Task { await session.loadCategory("") }
                            }
                            ForEach(session.categories) { category in
                                CatVodChip(title: category.name,
                                           isSelected: session.selectedCategoryID == category.id) {
                                    Task { await session.loadCategory(category.id) }
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 3),
                          spacing: 14) {
                    ForEach(session.videos) { video in
                        NavigationLink(value: video) {
                            VStack(alignment: .leading, spacing: 4) {
                                CatVodPoster(url: posterURL(video))
                                Text(video.title)
                                    .font(.system(.caption, design: .rounded))
                                    .lineLimit(2)
                                Text(video.remarks)
                                    .font(.system(.caption2, design: .rounded))
                                    .foregroundStyle(Color.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)

                if session.hasMore {
                    Button {
                        Task { await session.loadMore() }
                    } label: {
                        HStack(spacing: 6) {
                            if session.isLoading { ProgressView().controlSize(.small) }
                            Text(localized("載入更多"))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .disabled(session.isLoading)
                }
            }
            .padding(.vertical, 12)
        }
    }

    private func posterURL(_ video: CatVodVideo) -> URL? {
        guard !video.poster.isEmpty else { return nil }
        return URL(string: video.poster)
    }
}

// MARK: - Search

private struct CatVodSearchView: View {
    @ObservedObject var session: CatVodSession
    @State private var keyword = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(session.searchResults) { video in
                    Button {
                        dismiss()
                    } label: {
                        NavigationLink(value: video) {
                            HStack(spacing: 10) {
                                CatVodPoster(url: URL(string: video.poster), width: 40, height: 56)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(video.title).font(.system(.subheadline, design: .rounded))
                                    Text(video.remarks).font(.system(.caption2, design: .rounded)).foregroundStyle(Color.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
                if session.searchHasMore {
                    Button(localized("載入更多")) {
                        Task { await session.searchMore() }
                    }
                }
            }
            .overlay {
                if session.searchResults.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "magnifyingglass").font(.system(size: 40)).foregroundStyle(Color.secondary)
                        Text(localized("搜尋這個站點")).font(.system(.headline, design: .rounded))
                        Text(localized("輸入片名後按鍵盤上的搜尋。")).font(.system(.footnote, design: .rounded)).foregroundStyle(Color.secondary)
                    }
                }
            }
            .navigationTitle(localized("搜尋"))
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $keyword, prompt: Text(localized("片名")))
            .onSubmit(of: .search) {
                Task { await session.search(keyword) }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("關閉")) { dismiss() }
                }
            }
        }
    }
}

// MARK: - Detail

/// 影片詳情：海報、簡介、線路、選集；點選集直接播放。
struct CatVodDetailView: View {
    let video: CatVodVideo
    @ObservedObject var session: CatVodSession
    @State private var detail: CatVodVideo?
    @State private var routeID = ""
    @State private var playback: CatVodPlayback?
    @State private var playingTitle = ""
    @State private var isBusy = false

    private var shown: CatVodVideo { detail ?? video }
    private var routes: [CatVodRoute] { shown.routes }
    private var currentRoute: CatVodRoute? {
        routes.first { $0.id == routeID } ?? routes.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if shown.routes.isEmpty {
                    if session.isLoadingDetail {
                        ProgressView(localized("載入中")).frame(maxWidth: .infinity)
                    } else {
                        Text(localized("這個站點沒有提供線路。"))
                            .font(.system(.footnote, design: .rounded))
                            .foregroundStyle(Color.secondary)
                    }
                } else {
                    if routes.count > 1 {
                        routeRow
                    }
                    episodeGrid
                }
            }
            .padding(16)
        }
        .navigationTitle(shown.title)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if detail == nil && video.routes.isEmpty {
                await session.loadDetail(videoID: video.id)
                detail = session.detail
            }
            if routeID.isEmpty { routeID = currentRoute?.id ?? "" }
        }
        .fullScreenCover(item: .init(
            get: { playback },
            set: { playback = $0 }
        )) { pb in
            CatVodPlayerSheet(playback: pb, title: playingTitle)
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            CatVodPoster(url: URL(string: shown.poster), width: 96, height: 136)
            VStack(alignment: .leading, spacing: 4) {
                Text(shown.title)
                    .font(.system(.headline, design: .rounded))
                if !shown.remarks.isEmpty {
                    Text(shown.remarks)
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(Color.secondary)
                }
                let facts = [shown.year, shown.area, shown.actor]
                    .filter { !$0.isEmpty }
                    .joined(separator: " · ")
                if !facts.isEmpty {
                    Text(facts)
                        .font(.system(.caption2, design: .rounded))
                        .foregroundStyle(Color.secondary)
                        .lineLimit(2)
                }
            }
        }
    }

    private var routeRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(routes) { route in
                    CatVodChip(title: route.name, isSelected: route.id == currentRoute?.id) {
                        routeID = route.id
                    }
                }
            }
        }
    }

    private var episodeGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 3),
                  spacing: 8) {
            ForEach(currentRoute?.episodes ?? []) { episode in
                Button {
                    play(episode)
                } label: {
                    Text(episode.title)
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(isBusy)
            }
        }
    }

    private func play(_ episode: CatVodEpisode) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            await session.loadPlayback(routeID: currentRoute?.id ?? "", episodeID: episode.playID)
            isBusy = false
            if let pb = session.playback {
                playingTitle = "\(shown.title) · \(episode.title)"
                playback = pb
            }
        }
    }
}

// MARK: - Player

private struct CatVodPlayerSheet: View {
    let playback: CatVodPlayback
    let title: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VideoPlayerView(content: .link(stream, title: title), onClose: { dismiss() })
    }

    private var stream: VideoStream {
        let url = URL(string: playback.url) ?? URL(string: "about:blank")!
        return VideoStream(url: url, headers: playback.headers)
    }
}
extension CatVodPlayback: Identifiable {
    public var id: String { url }
}
