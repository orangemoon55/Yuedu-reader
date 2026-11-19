import Combine
import Foundation

/// Search owns one active book source. The five shortcuts and selected index are remembered
/// independently for each source and home configuration, without changing the home page.
@MainActor
final class DiscoveryCategoryModel: ObservableObject {
    @Published private(set) var slots = DiscoveryCategorySlots([])
    @Published private(set) var selection = 0
    @Published private(set) var catalog: [DiscoveryCategoryChoice] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    /// A selected category disappeared under the source's new filters; never substitute another kind.
    @Published private(set) var invalidReferences: Set<ExploreCategoryReference> = []
    @Published private(set) var sourceErrors: [String: String] = [:]

    private let defaults: UserDefaults
    private let key: String
    private var configuration = ""

    /// Identity for one mount of the source controls. An A → B → A switch, or a source
    /// revision change, must not allow the first A's delayed reply into the new screen.
    struct Activation: Hashable {
        let sourceURL: String
        let sourceID: UUID
        let revision: Int64
        let epoch = UUID()

        init(_ source: BookSource) {
            sourceURL = source.bookSourceUrl
            sourceID = source.id
            revision = source.lastUpdateTime
        }

        func matches(_ source: BookSource) -> Bool {
            sourceURL == source.bookSourceUrl && sourceID == source.id && revision == source.lastUpdateTime
        }
    }

    @Published private(set) var activeSource: Activation?

    private struct SourceSession: Codable {
        let slots: DiscoveryCategorySlots
        let selection: Int
    }

    private var sessions: [String: [String: SourceSession]]
    private var stored: [String: DiscoveryCategorySlots]
    private var lists: [ListKey: DiscoveryBookListModel] = [:]

    private struct ListKey: Hashable {
        let choice: DiscoveryCategoryChoice.ID
        let sourceID: UUID
        let revision: Int64
    }

    init(defaults: UserDefaults = .standard, key: String = "yd_discovery_five_categories.v1") {
        self.defaults = defaults
        self.key = key
        self.stored = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: DiscoveryCategorySlots].self, from: $0) } ?? [:]
        self.sessions = defaults.data(forKey: key + ".source-sessions")
            .flatMap { try? JSONDecoder().decode([String: [String: SourceSession]].self, from: $0) } ?? [:]
    }

    var current: DiscoveryCategoryChoice? { slots.choices.indices.contains(selection) ? slots.choices[selection] : nil }

    private var sourceKey: String { key + ".source." + configuration }
    private var legacySelectionKey: String { key + ".selected." + configuration }

    func prepare(configuration: String, page: HomePage?, sources: [BookSource]) {
        let changed = configuration != self.configuration
        self.configuration = configuration
        let configured = DiscoveryCategorySlots.configured(for: page, sources: sources)
        let legacy = stored[configuration]
        let legacyIndex = min(4, max(0, defaults.integer(forKey: legacySelectionKey)))
        let preferredURLs = [changed ? nil : activeSource?.sourceURL, defaults.string(forKey: sourceKey),
                             legacy?.choices[legacyIndex]?.reference.sourceURL,
                             configured.first?.reference.sourceURL]
        let source = preferredURLs.compactMap { $0 }.lazy.compactMap { url in
            sources.first { $0.bookSourceUrl == url }
        }.first ?? sources.first
        if let source {
            if changed || activeSource?.matches(source) != true {
                activate(source, configured: configured)
            }
        } else if changed || activeSource != nil {
            // A source may be removed or disabled. Never leave its cached books onscreen.
            activeSource = nil
            slots = legacy ?? DiscoveryCategorySlots([])
            selection = legacyIndex
            catalog = []
            isLoadingCatalog = false
            catalogError = nil
            invalidReferences = []
            sourceErrors = [:]
        }
    }

    func switchSource(to source: BookSource, page: HomePage?) {
        guard DiscoverViewModel.isExploreSource(source), activeSource?.matches(source) != true else { return }
        activate(source, configured: DiscoveryCategorySlots.configured(for: page, sources: [source]))
    }

    /// Commit the source and its own shortcuts synchronously, before the view starts loading.
    /// DiscoverySourceControls is the single authority for the real category response and filters.
    private func activate(_ source: BookSource, configured: [DiscoveryCategoryChoice]) {
        let url = source.bookSourceUrl
        let previous = sessions[configuration]?[url]
        let legacy = stored[configuration]?.choices.map { $0?.reference.sourceURL == url ? $0 : nil } ?? []
        let saved = previous?.slots ?? DiscoveryCategorySlots(legacy)
        slots = saved.choices.contains { $0 != nil } ? saved : DiscoveryCategorySlots.filling(
            from: configured.filter { $0.reference.sourceURL == url }, catalog: [])
        selection = previous?.selection ?? min(4, max(0, defaults.integer(forKey: legacySelectionKey)))
        normalizeSelection()
        catalog = slots.choices.compactMap { $0 }
        isLoadingCatalog = true
        catalogError = nil
        invalidReferences = []
        sourceErrors = [:]
        activeSource = Activation(source)
        defaults.set(url, forKey: sourceKey)
        save()
    }

    private func normalizeSelection() {
        if current == nil { selection = slots.choices.firstIndex { $0 != nil } ?? 0 }
    }

    func select(_ index: Int) {
        guard slots.choices.indices.contains(index), slots.choices[index] != nil else { return }
        selection = index
        if activeSource != nil { save() } else { defaults.set(index, forKey: legacySelectionKey) }
    }

    func choose(_ choice: DiscoveryCategoryChoice, at index: Int) {
        guard slots.choices.indices.contains(index), choice.reference.cardItem != nil,
              activeSource == nil || activeSource?.sourceURL == choice.reference.sourceURL else { return }
        slots.set(choice, at: index)
        invalidReferences.remove(choice.reference)
        sourceErrors[choice.reference.sourceURL] = nil
        selection = index
        if !catalog.contains(where: { $0.id == choice.id }) { catalog.append(choice) }
        save()
        if activeSource == nil { defaults.set(index, forKey: legacySelectionKey) }
    }

    func list(for choice: DiscoveryCategoryChoice, source: BookSource) -> DiscoveryBookListModel {
        let key = ListKey(choice: choice.id, sourceID: source.id, revision: source.lastUpdateTime)
        if let found = lists[key] { return found }
        let made = DiscoveryBookListModel(choice: choice, source: source)
        lists[key] = made
        return made
    }

    /// Re-key every slot of this source. Choice identity includes the complete filter map,
    /// so a changed menu requests fresh books rather than just changing its highlight.
    func applyFilters(values: [String: String], sourceURL: String) {
        guard activeSource == nil || activeSource?.sourceURL == sourceURL else { return }
        slots = DiscoveryCategorySlots(slots.choices.map { choice in
            guard let choice, choice.reference.sourceURL == sourceURL else { return choice }
            return DiscoveryCategoryChoice(reference: choice.reference, filters: values, label: choice.label)
        })
        catalog = catalog.map { choice in
            guard choice.reference.sourceURL == sourceURL else { return choice }
            return DiscoveryCategoryChoice(reference: choice.reference, filters: values, label: choice.label)
        }
        save()
    }

    /// Called only after the selected source's asynchronous reload has completed. Resolve
    /// each slot by its actual source/title, never by a five-slot index or a guessed genre.
    func reconcileSource(sourceURL: String, values: [String: String], items: [DiscoverCardItem], error: String?,
                         refreshBooks: Bool = false, activation: Activation? = nil) {
        guard activation == activeSource, activeSource == nil || activeSource?.sourceURL == sourceURL else { return }
        isLoadingCatalog = false
        catalogError = error
        if error == nil { applyFilters(values: values, sourceURL: sourceURL) }
        // The controls can report the same resolved categories again after appearing or
        // restoring their filters. ListKey already covers category, filters and source
        // revision: evicting here replaced a paged model with an empty page-1 model under
        // the SAME SwiftUI .id(choice.id), discarding the visible list's scroll identity.
        // A genuinely different category/filter/revision selects a different key itself.
        invalidReferences = invalidReferences.filter { $0.sourceURL != sourceURL }
        sourceErrors[sourceURL] = error
        var seen = Set<ExploreCategoryReference>()
        let references = items.compactMap { item -> ExploreCategoryReference? in
            guard item.isFetchable, let url = item.raw.url else { return nil }
            let reference = ExploreCategoryReference(sourceURL: sourceURL, title: item.title, url: url)
            return seen.insert(reference).inserted ? reference : nil
        }
        var used = Set<ExploreCategoryReference>()
        slots = DiscoveryCategorySlots(slots.choices.map { choice in
            guard let choice, choice.reference.sourceURL == sourceURL else { return choice }
            let sameTitle = references.filter { $0.title == choice.reference.title }
            let resolved = references.first { $0 == choice.reference }
                ?? (sameTitle.count == 1 ? sameTitle.first : nil)
            guard error == nil, let resolved, activeSource == nil || used.insert(resolved).inserted else {
                // A successful reload is authoritative for the active source. On failure
                // keep that source's choices for retry; never fill from another source.
                if activeSource != nil, error == nil { return nil }
                invalidReferences.insert(choice.reference)
                return choice
            }
            return DiscoveryCategoryChoice(reference: resolved, filters: values, label: choice.label)
        })
        let actual = references.map { DiscoveryCategoryChoice(reference: $0, filters: values) }
        if activeSource != nil, error == nil {
            var choices = slots.choices
            for choice in actual where !used.contains(choice.reference) {
                guard let empty = choices.firstIndex(where: { $0 == nil }) else { break }
                choices[empty] = choice
                used.insert(choice.reference)
            }
            slots = DiscoveryCategorySlots(choices)
            normalizeSelection()
        }
        if error == nil {
            catalog.removeAll { $0.reference.sourceURL == sourceURL }
            catalog.append(contentsOf: actual)
        }
        save()
        // Login/user-variable changes may alter books without changing the menu identity.
        // The caller must distinguish those explicit invalidations from catalog restoration.
        // Refresh existing instances rather than remounting the ScrollView with empty data.
        if refreshBooks, error == nil {
            let matching = lists.filter {
                $0.key.choice.reference.sourceURL == sourceURL && $0.key.choice.filters == values
            }.map(\.value)
            Task { for list in matching { await list.loadFirst(force: true) } }
        }
    }

    func refreshCurrent() async {
        for (key, value) in lists where key.choice == current?.id { await value.loadFirst(force: true) }
    }

    private func save() {
        if let activeSource {
            sessions[configuration, default: [:]][activeSource.sourceURL] = SourceSession(slots: slots, selection: selection)
            if let data = try? JSONEncoder().encode(sessions) { defaults.set(data, forKey: key + ".source-sessions") }
        } else {
            stored[configuration] = slots
            if let data = try? JSONEncoder().encode(stored) { defaults.set(data, forKey: key) }
        }
    }
}
