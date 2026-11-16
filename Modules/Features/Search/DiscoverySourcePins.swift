import Foundation
import Observation

/// Pins belong only to the discovery picker. Never reorder BookSourceStore or export them.
@MainActor @Observable
final class DiscoverySourcePins {
    static let preferenceKey = "yd_discovery_picker_pinned_source_ids_v1"

    private(set) var pinnedIDs: [UUID]
    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        var seen = Set<UUID>()
        pinnedIDs = (defaults.stringArray(forKey: Self.preferenceKey) ?? []).compactMap { value in
            guard let id = UUID(uuidString: value), seen.insert(id).inserted else { return nil }
            return id
        }
    }

    func isPinned(_ id: UUID) -> Bool {
        pinnedIDs.contains(id)
    }

    /// Apply and persist immediately, checking the full (unfiltered) picker list.
    /// A source that is no longer available cannot change its pin.
    func togglePin(_ id: UUID, availableIDs: Set<UUID>) {
        guard availableIDs.contains(id) else { return }
        if isPinned(id) {
            pinnedIDs.removeAll { $0 == id }
        } else {
            pinnedIDs.insert(id, at: 0)
        }
        defaults.set(pinnedIDs.map(\.uuidString), forKey: Self.preferenceKey)
    }

    /// Newest pins first; unpinned rows retain the supplied order. Missing IDs
    /// are ignored, so deletion/reimport never pins an unrelated row. Keep hidden pins
    /// across filtering or temporary disabling; names and URLs are never persisted here.
    func ordered(_ sources: [DiscoverableBookSource]) -> [DiscoverableBookSource] {
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = Set(pinnedIDs)
        return pinnedIDs.compactMap { byID[$0] } + sources.filter { !pinned.contains($0.id) }
    }
}
