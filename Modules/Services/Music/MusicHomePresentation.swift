import Combine
import Foundation

/// Bookmarks are not listening history. Only the actual player's session can produce this card.
enum MusicHomePresentation {
    static func continuation(currentTrack: MediaHubLibraryItem?) -> MediaHubLibraryItem? {
        guard let currentTrack, currentTrack.kind == .music else { return nil }
        return currentTrack
    }
    static func time(_ value: TimeInterval) -> String {
        guard value.isFinite, value >= 0, value < 86_400_000 else { return "0:00" }
        let seconds = Int(value)
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }
    /// Charts are supplied by the NetEase catalogue, not by the selected JS resolver.
    /// Playlist creators remain the provider's metadata; no screenshot names are seeded.
    static func catalogCaption(for entry: MusicCatalogEntry, showingOrigin: Bool) -> String {
        showingOrigin || entry.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? localized("網易雲音樂") : entry.subtitle
    }
    static func canResolveCatalog(source: MusicJSSource?, providerID: String) -> Bool {
        providerID == "wy" && source?.providers.contains(where: { $0.id == "wy" && $0.actions.contains("musicUrl") }) == true
    }
}

@MainActor
final class MusicHomeCatalogModel: ObservableObject {
    @Published private(set) var charts: [MusicCatalogEntry] = []
    @Published private(set) var playlists: [MusicCatalogEntry] = []
    @Published private(set) var chartsLoading = false
    @Published private(set) var playlistsLoading = false
    @Published private(set) var chartsError: String?
    @Published private(set) var playlistsError: String?
    private var generation = UUID()

    func load() async {
        let token = UUID(); generation = token
        chartsLoading = true; playlistsLoading = true
        chartsError = nil; playlistsError = nil
        async let first: Void = loadCharts(token)
        async let second: Void = loadPlaylists(token)
        _ = await (first, second)
    }
    private func loadCharts(_ token: UUID) async {
        defer { if generation == token { chartsLoading = false } }
        do {
            let values = try await MusicPublicCatalog.shared.charts()
            guard !Task.isCancelled, generation == token else { return }
            charts = values
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            charts = []; chartsError = error.localizedDescription
        }
    }
    private func loadPlaylists(_ token: UUID) async {
        defer { if generation == token { playlistsLoading = false } }
        do {
            let values = try await MusicPublicCatalog.shared.playlists()
            guard !Task.isCancelled, generation == token else { return }
            playlists = values
        } catch {
            guard !Task.isCancelled, generation == token else { return }
            playlists = []; playlistsError = error.localizedDescription
        }
    }
}
