import Combine
import Foundation
import Observation

/// The discovery source remembered by the Search tab.
@MainActor @Observable
final class SourceDiscoverySelection {
    static let preferenceKey = "yd_search_discovery_source_url"

    private(set) var sources: [DiscoverableBookSource] = []
    private(set) var selectedSource: BookSource?
    private(set) var isLoaded = false
    @ObservationIgnored private var subscription: AnyCancellable?
    @ObservationIgnored private var discoveryWork: Task<Snapshot, Never>?
    @ObservationIgnored private var applyWork: Task<Void, Never>?
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var started = false

    private struct Snapshot: Sendable {
        let sources: [DiscoverableBookSource]
        let selected: DiscoverableBookSource?
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func start(store: BookSourceStore = .shared) {
        guard !started else { return }
        started = true
        store.whenLoaded { [weak self] _ in
            guard let self else { return }
            self.prepare()
            self.subscription = store.sourcesPublisher.dropFirst()
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.prepare() }
        }
    }

    func select(_ candidate: DiscoverableBookSource) {
        guard selectedSource?.bookSourceUrl != candidate.url,
              let source = BookSourceStore.shared.source(id: candidate.id) else { return }
        selectedSource = source
        defaults.set(candidate.url, forKey: Self.preferenceKey)
    }

    /// A removed or disabled saved source falls back to the first available discovery source.
    nonisolated static func preferredSource(
        in sources: [DiscoverableBookSource], savedURL: String?
    ) -> DiscoverableBookSource? {
        sources.first { $0.url == savedURL } ?? sources.first
    }

    private func prepare() {
        discoveryWork?.cancel()
        applyWork?.cancel()
        let savedURL = selectedSource?.bookSourceUrl ?? defaults.string(forKey: Self.preferenceKey)
        let work = Task.detached(priority: .userInitiated) {
            let sources = BookSourceStore.shared.discoverableSources()
            return Snapshot(
                sources: sources,
                selected: Self.preferredSource(in: sources, savedURL: savedURL)
            )
        }
        discoveryWork = work
        applyWork = Task { [weak self] in
            let snapshot = await work.value
            guard !Task.isCancelled, let self else { return }
            self.sources = snapshot.sources
            self.selectedSource = snapshot.selected.flatMap { BookSourceStore.shared.source(id: $0.id) }
            self.isLoaded = true
            if let selected = snapshot.selected,
               self.defaults.string(forKey: Self.preferenceKey) != selected.url {
                self.defaults.set(selected.url, forKey: Self.preferenceKey)
            }
        }
    }
}
