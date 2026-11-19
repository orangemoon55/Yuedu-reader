import Combine
import Foundation

/// Five shortcuts are stored separately per existing home configuration. Original sections
/// remain untouched and can still be edited through the original More menu.
@MainActor
final class DiscoveryCategoryModel: ObservableObject {
    @Published private(set) var slots = DiscoveryCategorySlots([])
    @Published var selection = 0
    @Published private(set) var catalog: [DiscoveryCategoryChoice] = []
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    /// A selected category disappeared under the source's new filters; never substitute another kind.
    @Published private(set) var invalidReferences: Set<ExploreCategoryReference> = []
    @Published private(set) var sourceErrors: [String: String] = [:]

    private let defaults: UserDefaults
    private let key: String
    private var configuration = ""
    private var generation = 0
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
    }

    var current: DiscoveryCategoryChoice? { slots.choices.indices.contains(selection) ? slots.choices[selection] : nil }

    func prepare(configuration: String, page: HomePage?, sources: [BookSource]) async {
        generation += 1
        let request = generation
        let configured = DiscoveryCategorySlots.configured(for: page, sources: sources)
        if self.configuration != configuration {
            self.configuration = configuration
            slots = stored[configuration] ?? DiscoveryCategorySlots(configured.map(Optional.some))
            selection = min(4, max(0, defaults.integer(forKey: key + ".selected." + configuration)))
            catalog = []
            invalidReferences = []
            sourceErrors = [:]
            lists.removeAll()
        }
        isLoadingCatalog = true
        catalogError = nil
        defer { if generation == request { isLoadingCatalog = false } }
        var found = configured
        // Only the active source is inspected. Other slots retain their own cached feed;
        // selecting one mounts its own source controls and reconciles just that source.
        let activeURL = current?.reference.sourceURL
            ?? slots.choices.compactMap { $0?.reference.sourceURL }.first
            ?? configured.first?.reference.sourceURL
        let chosenSource = sources.first { $0.bookSourceUrl == activeURL } ?? sources.first
        for source in chosenSource.map({ [$0] }) ?? [] {
            guard !Task.isCancelled, generation == request else { return }
            let filters = slots.choices.compactMap { $0 }.first { $0.reference.sourceURL == source.bookSourceUrl }?.filters ?? [:]
            let listing = SourceCategoryListing(source: source, filterValues: filters)
            await listing.load()
            guard !Task.isCancelled, generation == request else { return }
            if case .failed(let reason) = listing.state { catalogError = reason }
            for item in listing.groups.flatMap(\.items) {
                if let ref = listing.reference(for: item) {
                    found.append(.init(reference: ref, filters: listing.filterValues))
                }
            }
        }
        guard !Task.isCancelled, generation == request else { return }
        var seen = Set<DiscoveryCategoryChoice.ID>()
        catalog = (found + slots.choices.compactMap { $0 }).filter { seen.insert($0.id).inserted }
        if stored[configuration] == nil {
            slots = DiscoveryCategorySlots.filling(from: configured, catalog: catalog)
            if slots.choices.contains(where: { $0 != nil }) { save() }
        }
        if current == nil, let first = slots.choices.firstIndex(where: { $0 != nil }) { selection = first }
    }

    func select(_ index: Int) {
        guard slots.choices.indices.contains(index), slots.choices[index] != nil else { return }
        selection = index
        defaults.set(index, forKey: key + ".selected." + configuration)
    }

    func choose(_ choice: DiscoveryCategoryChoice, at index: Int) {
        guard choice.reference.cardItem != nil else { return }
        slots.set(choice, at: index)
        invalidReferences.remove(choice.reference)
        sourceErrors[choice.reference.sourceURL] = nil
        selection = index
        if !catalog.contains(where: { $0.id == choice.id }) { catalog.append(choice) }
        save()
        defaults.set(index, forKey: key + ".selected." + configuration)
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
                         refreshBooks: Bool = false) {
        applyFilters(values: values, sourceURL: sourceURL)
        // The controls can report the same resolved categories again after appearing or
        // restoring their filters. ListKey already covers category, filters and source
        // revision: evicting here replaced a paged model with an empty page-1 model under
        // the SAME SwiftUI .id(choice.id), discarding the visible list's scroll identity.
        // A genuinely different category/filter/revision selects a different key itself.
        invalidReferences = invalidReferences.filter { $0.sourceURL != sourceURL }
        sourceErrors[sourceURL] = error
        let references = items.compactMap { item -> ExploreCategoryReference? in
            guard item.isFetchable, let url = item.raw.url else { return nil }
            return ExploreCategoryReference(sourceURL: sourceURL, title: item.title, url: url)
        }
        slots = DiscoveryCategorySlots(slots.choices.map { choice in
            guard let choice, choice.reference.sourceURL == sourceURL else { return choice }
            let sameTitle = references.filter { $0.title == choice.reference.title }
            let resolved = references.first { $0 == choice.reference }
                ?? (sameTitle.count == 1 ? sameTitle.first : nil)
            guard error == nil, let resolved else {
                invalidReferences.insert(choice.reference)
                return choice
            }
            return DiscoveryCategoryChoice(reference: resolved, filters: values, label: choice.label)
        })
        catalog.removeAll { $0.reference.sourceURL == sourceURL }
        catalog.append(contentsOf: references.map { DiscoveryCategoryChoice(reference: $0, filters: values) })
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
        stored[configuration] = slots
        if let encoded = try? JSONEncoder().encode(stored) { defaults.set(encoded, forKey: key) }
    }
}
