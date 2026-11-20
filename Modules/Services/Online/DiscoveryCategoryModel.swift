import Combine
import Foundation

/// Search's bar is the active source's current catalogue. Persist a reference, not a
/// position, a filtered list of books, or a copy of the catalogue.
@MainActor
final class DiscoveryCategoryModel: ObservableObject {
    @Published private(set) var catalog: [DiscoveryCategoryChoice] = []
    @Published private(set) var current: DiscoveryCategoryChoice?
    @Published private(set) var isLoadingCatalog = false
    @Published private(set) var catalogError: String?
    @Published private(set) var activeSource: Activation?

    /// A → B → A must not admit replies from the first A, even at the same source revision.
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

    private struct ListKey: Hashable {
        let choice: DiscoveryCategoryChoice.ID
        let sourceID: UUID
        let revision: Int64
    }

    // Read the previously selected shortcut on upgrade, but never use its slot/label/filter
    // to build the new bar. The live catalogue has to confirm the reference exists.
    private struct LegacySession: Decodable {
        let slots: [DiscoveryCategoryChoice?]
        let selection: Int

        var selected: DiscoveryCategoryChoice? {
            slots.indices.contains(selection) ? slots[selection] : nil
        }
    }

    private let defaults: UserDefaults
    private let key: String
    private var configuration = ""
    private var selections: [String: [String: ExploreCategoryReference]]
    private let legacySessions: [String: [String: LegacySession]]
    private let legacySlots: [String: [DiscoveryCategoryChoice?]]
    private var lists: [ListKey: DiscoveryBookListModel] = [:]

    init(defaults: UserDefaults = .standard, key: String = "yd_discovery_five_categories.v1") {
        self.defaults = defaults
        self.key = key
        selections = defaults.data(forKey: key + ".catalog-selection")
            .flatMap { try? JSONDecoder().decode([String: [String: ExploreCategoryReference]].self, from: $0) } ?? [:]
        legacySessions = defaults.data(forKey: key + ".source-sessions")
            .flatMap { try? JSONDecoder().decode([String: [String: LegacySession]].self, from: $0) } ?? [:]
        legacySlots = defaults.data(forKey: key)
            .flatMap { try? JSONDecoder().decode([String: [DiscoveryCategoryChoice?]].self, from: $0) } ?? [:]
    }

    private var sourceKey: String { key + ".source." + configuration }

    private var legacyChoice: DiscoveryCategoryChoice? {
        let index = defaults.integer(forKey: key + ".selected." + configuration)
        guard let slots = legacySlots[configuration], slots.indices.contains(index) else { return nil }
        return slots[index]
    }

    func prepare(configuration: String, page: HomePage?, sources: [BookSource]) {
        let changed = configuration != self.configuration
        self.configuration = configuration
        let preferred = [changed ? nil : activeSource?.sourceURL, defaults.string(forKey: sourceKey),
                         legacyChoice?.reference.sourceURL].compactMap { $0 }
        let source = preferred.lazy.compactMap { url in sources.first { $0.bookSourceUrl == url } }.first
            ?? configuredSource(in: page, sources: sources) ?? sources.first
        if let source {
            if changed || activeSource?.matches(source) != true { activate(source) }
        } else if changed || activeSource != nil {
            clearCatalog()
            activeSource = nil
            isLoadingCatalog = false
        }
    }

    /// The home page may supply the initial source, but never any Search category buttons.
    private func configuredSource(in page: HomePage?, sources: [BookSource]) -> BookSource? {
        for section in page?.sections ?? [] where section.isEnabled {
            let bindings: [HomeSectionBinding]
            if case .lists(let lists) = section.binding { bindings = lists.map(\.binding) }
            else { bindings = [section.binding] }
            for case .sourceCategories(let references) in bindings {
                for ref in references where ref.cardItem != nil {
                    if let source = sources.first(where: { $0.bookSourceUrl == ref.sourceURL }) { return source }
                }
            }
        }
        return nil
    }

    func switchSource(to source: BookSource) {
        guard DiscoverViewModel.isExploreSource(source), activeSource?.matches(source) != true else { return }
        activate(source)
    }

    private func activate(_ source: BookSource) {
        clearCatalog()
        isLoadingCatalog = true
        activeSource = Activation(source)
        defaults.set(source.bookSourceUrl, forKey: sourceKey)
    }

    private func clearCatalog() {
        catalog = []
        current = nil
        catalogError = nil
    }

    func select(_ reference: ExploreCategoryReference, activation: Activation) {
        guard activation == activeSource, let choice = catalog.first(where: { $0.reference == reference }) else { return }
        commitSelection(choice)
    }

    func reconcileSource(values: [String: String], items: [DiscoverCardItem], error: String?,
                         refreshBooks: Bool = false, activation: Activation) {
        guard activation == activeSource else { return }
        isLoadingCatalog = false
        catalogError = error
        guard error == nil else {
            catalog = []
            current = nil
            return
        }

        let url = activation.sourceURL
        var seen = Set<ExploreCategoryReference>()
        let actual: [DiscoveryCategoryChoice] = items.compactMap { item in
            guard item.isFetchable, let urlRule = item.raw.url else { return nil }
            let reference = ExploreCategoryReference(sourceURL: url, title: item.title, url: urlRule)
            guard seen.insert(reference).inserted else { return nil }
            return DiscoveryCategoryChoice(reference: reference, filters: values)
        }
        let remembered = selections[configuration]?[url]
            ?? legacySessions[configuration]?[url]?.selected?.reference
            ?? legacyChoice?.reference
        catalog = actual
        commitSelection(actual.first { $0.reference == remembered } ?? actual.first)

        if refreshBooks {
            let live = Set(actual.map(\.id))
            let matching = lists.filter {
                $0.key.sourceID == activation.sourceID && $0.key.revision == activation.revision
                    && live.contains($0.key.choice)
            }.map(\.value)
            Task { [weak self] in
                for list in matching {
                    guard self?.activeSource == activation else { return }
                    await list.loadFirst(force: true)
                }
            }
        }
    }

    private func commitSelection(_ choice: DiscoveryCategoryChoice?) {
        current = choice
        guard let reference = choice?.reference,
              selections[configuration]?[reference.sourceURL] != reference else { return }
        selections[configuration, default: [:]][reference.sourceURL] = reference
        if let data = try? JSONEncoder().encode(selections) { defaults.set(data, forKey: key + ".catalog-selection") }
    }

    func list(for choice: DiscoveryCategoryChoice, source: BookSource) -> DiscoveryBookListModel {
        let key = ListKey(choice: choice.id, sourceID: source.id, revision: source.lastUpdateTime)
        if let found = lists[key] { return found }
        let made = DiscoveryBookListModel(choice: choice, source: source)
        lists[key] = made
        return made
    }
}
