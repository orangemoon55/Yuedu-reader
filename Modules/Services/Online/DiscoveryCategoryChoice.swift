import Foundation

/// A shortcut names a real section from an installed source, including the source filters that
/// were active when the section was chosen. Its ID is not the transient ID of a displayed book.
struct DiscoveryCategoryChoice: Codable, Hashable, Identifiable, Sendable {
    let reference: ExploreCategoryReference
    let filters: [String: String]
    var label: String? = nil

    struct ID: Hashable, Sendable {
        let reference: ExploreCategoryReference
        let filters: [String: String]
    }

    var title: String { label ?? reference.title }
    var id: ID { ID(reference: reference, filters: filters) }
}

struct DiscoveryCategorySlots: Codable, Equatable, Sendable {
    static let count = 5
    private(set) var choices: [DiscoveryCategoryChoice?]

    init(_ choices: [DiscoveryCategoryChoice?]) {
        self.choices = Array(choices.prefix(Self.count))
        self.choices += Array(repeating: nil, count: Self.count - self.choices.count)
    }

    init(from decoder: any Decoder) throws {
        self.init(try decoder.singleValueContainer().decode([DiscoveryCategoryChoice?].self))
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(choices)
    }

    mutating func set(_ choice: DiscoveryCategoryChoice, at index: Int) {
        guard choices.indices.contains(index) else { return }
        // Moving an existing shortcut swaps the slots instead of leaving two buttons for it.
        if let other = choices.firstIndex(where: { $0?.id == choice.id }), other != index {
            choices[other] = choices[index]
        }
        choices[index] = choice
    }

    /// The complete directory can use all configured categories; the shortcut bar takes five.
    static func configured(for page: HomePage?, sources: [BookSource]) -> [DiscoveryCategoryChoice] {
        let available = Set(sources.map(\.bookSourceUrl))
        var result: [DiscoveryCategoryChoice] = []
        var used = Set<DiscoveryCategoryChoice.ID>()
        func append(_ binding: HomeSectionBinding, parameters: [String: String], title: String) {
            guard case .sourceCategories(let refs) = binding else { return }
            let label = title.trimmingCharacters(in: .whitespacesAndNewlines)
            for ref in refs where available.contains(ref.sourceURL) && ref.cardItem != nil {
                let choice = DiscoveryCategoryChoice(reference: ref,
                    filters: HomeSection.filterValues(in: parameters, sourceURL: ref.sourceURL),
                    label: refs.count == 1 && !label.isEmpty ? label : nil)
                if used.insert(choice.id).inserted { result.append(choice) }
            }
        }
        for section in page?.sections ?? [] where section.isEnabled {
            if case .lists(let lists) = section.binding {
                for list in lists { append(list.binding, parameters: list.parameters, title: list.title) }
            } else {
                append(section.binding, parameters: section.parameters, title: section.title)
            }
        }
        return result
    }

    static func filling(from configured: [DiscoveryCategoryChoice], catalog: [DiscoveryCategoryChoice]) -> Self {
        var seen = Set<DiscoveryCategoryChoice.ID>()
        return Self((configured + catalog).filter { seen.insert($0.id).inserted }.map(Optional.some))
    }
}
