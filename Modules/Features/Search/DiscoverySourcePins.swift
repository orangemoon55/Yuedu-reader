import Foundation
import Observation

/// Pins belong only to the discovery picker. Never reorder BookSourceStore or export them.
@MainActor @Observable
final class DiscoverySourcePins {
    static let preferenceKey = "yd_discovery_picker_pinned_source_ids_v1"

    struct Change: Equatable {
        let sourceID: UUID
        let shouldPin: Bool
    }

    private(set) var pinnedIDs: [UUID]
    private(set) var pendingChange: Change?
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

    /// Showing the native confirmation must not change order or persistence.
    func requestChange(for id: UUID) {
        pendingChange = Change(sourceID: id, shouldPin: !isPinned(id))
    }

    func cancelPendingChange() {
        pendingChange = nil
    }

    /// Called only by the confirmation button, against the full (unfiltered) picker list.
    /// A source removed while the dialog is open cannot acquire a new pin.
    func confirmPendingChange(availableIDs: Set<UUID>) {
        guard let change = pendingChange else { return }
        pendingChange = nil
        guard availableIDs.contains(change.sourceID) else { return }
        pinnedIDs.removeAll { $0 == change.sourceID }
        if change.shouldPin {
            pinnedIDs.insert(change.sourceID, at: 0)
        }
        defaults.set(pinnedIDs.map(\.uuidString), forKey: Self.preferenceKey)
    }

    /// Newest-confirmed pins first; unpinned rows retain the supplied order. Missing IDs
    /// are ignored, so deletion/reimport never pins an unrelated row. Keep hidden pins
    /// across filtering or temporary disabling; names and URLs are never persisted here.
    func ordered(_ sources: [DiscoverableBookSource]) -> [DiscoverableBookSource] {
        let byID = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let pinned = Set(pinnedIDs)
        return pinnedIDs.compactMap { byID[$0] } + sources.filter { !pinned.contains($0.id) }
    }
}
