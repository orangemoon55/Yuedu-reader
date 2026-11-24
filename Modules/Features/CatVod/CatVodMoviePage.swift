import SwiftUI

struct CatVodMoviePage: View {
    let sourceID: String, siteKey: String, videoID: String, title: String
    @State private var detail: CatVodVideo?
    @State private var failure: String?, playFailure: String?
    @State private var selectedRoute = "", playingTitle = ""
    @State private var retry = 0
    @State private var pending: Task<Void, Never>?
    @State private var player: CatVodPlayTicket?
    @State private var lease: UUID?
    @EnvironmentObject private var store: BookStore
    private var route: CatVodRoute? { detail?.routes.first(where: { $0.id == selectedRoute }) ?? detail?.routes.first }
    var body: some View {
        List {
            if let detail {
                Section {
                    HStack(spacing: DSSpacing.md) {
                        CatVodPoster(sourceID: sourceID, rawURL: detail.poster)
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(detail.title).font(DSFont.headline)
                            Text([detail.year, detail.area, detail.remarks].filter { !$0.isEmpty }.joined(separator: " · ")).font(DSFont.footnote)
                        }
                    }
                    if !detail.actor.isEmpty { Text(detail.actor).foregroundStyle(DSColor.textSecondary).font(DSFont.footnote) }
                    if !detail.summary.isEmpty { Text(detail.summary).font(DSFont.body) }
                }.interfaceSectionSurface()
                Section {
                    if detail.routes.count > 1 {
                        Picker(localized("播放線路"), selection: $selectedRoute) {
                            ForEach(detail.routes) { Text($0.name).tag($0.id) }
                        }
                    }
                    if let route, !route.episodes.isEmpty {
                        ForEach(route.episodes) { episode in
                            Button { play(episode, flag: route.flag) } label: { Label(episode.title, systemImage: "play.circle") }
                              .disabled(pending != nil)
                        }
                    } else { Text(localized("這部影片沒有可播放的集數")) }
                    if pending != nil { ProgressView(localized("載入中")) }
                    if let playFailure { Text(playFailure).foregroundStyle(DSColor.warning) }
                } header: { Text(localized("選集")) }.interfaceSectionSurface()
            } else if let failure {
                Text(failure); Button(localized("重試")) { retry += 1 }
            } else { ProgressView(localized("載入中")) }
        }
        .navigationTitle(detail?.title ?? title).toolbarTitleDisplayMode(.inline)
        .themedAppSurface(for: .explore)
        .task(id: retry) {
            guard detail == nil else { return }; failure = nil
            do {
                let result = try await CatVodCatalog.shared.detail(sourceID: sourceID, siteKey: siteKey, videoID: videoID)
                try Task.checkCancellation(); detail = result; selectedRoute = result.routes.first?.id ?? ""
            } catch { if !Task.isCancelled { failure = CatVodCatalog.message(error) } }
        }
        .fullScreenCover(item: $player, onDismiss: releasePlayer) { ticket in
            VideoPlayerView(content: .link(ticket.stream, title: playingTitle)) { player = nil }.environmentObject(store)
        }
        .onDisappear { pending?.cancel(); pending = nil; if player == nil { releasePlayer() } }
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
