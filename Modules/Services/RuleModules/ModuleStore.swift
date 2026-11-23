import CryptoKit
import Foundation

// Adapted from Yuedu-reader, MPL-2.0, commit d6cfdb980346c3b82b8e56cb343d00b4fefb5de1.
// Listings come from the original modules' `store`, never from fuzzy source-title matches.
struct ModuleStoreListing: Hashable, Identifiable, Sendable {
    let moduleID: String
    let entryID: String
    let title: String
    var id: String { "\(moduleID)/\(entryID)" }
    var route: ModuleStoreRoute { .init(moduleID: moduleID, entryID: entryID, title: title) }
}

struct ModuleStoreRoute: Hashable, Sendable {
    let moduleID: String
    let entryID: String
    let title: String
}

enum ModuleStores {
    static func listings(in modules: [RuleModule]) -> [ModuleStoreListing] {
        let rank = { (m: RuleModule) in OfficialRuleModules.storeOrder.firstIndex(of: m.id) ?? Int.max }
        return modules.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .flatMap { _, module in
                module.modules.compactMap { entry -> ModuleStoreListing? in
                    guard let id = entry.id, !(entry.store ?? []).isEmpty,
                          let title = entry.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                          !title.isEmpty else { return nil }
                    return .init(moduleID: module.id, entryID: id, title: title)
                }
            }
    }

    @MainActor static func listings(in library: RuleModuleLibrary = .shared) -> [ModuleStoreListing] {
        listings(in: library.modules.map(\.module))
    }

    static func page(of entry: RuleModule.Entry, in module: RuleModule, language: String) -> HomePage {
        guard let entryID = entry.id else { return .init(sections: []) }
        let values = RuleModule.Param.currentValues(of: entry.params, in: [:], language: language)
        let sections = (entry.store ?? []).enumerated().compactMap { index, section -> HomeSection? in
            let id = sectionID(moduleID: module.id, entryID: entryID, index: index)
            if let shelves = section.shelves {
                let cards = shelves.compactMap { shelf -> HomeListCard? in
                    if let condition = shelf.belongTo,
                       !condition.value.contains(values[condition.paramName] ?? "") { return nil }
                    let listID = shelf.list ?? entryID
                    guard let list = module.modules.first(where: { $0.id == listID }) else { return nil }
                    let params = shelf.params ?? [:]
                    return .init(binding: .module(moduleID: module.id, entryID: listID),
                                 parameters: params,
                                 title: shelf.list == nil ? title(of: params, in: list) : (list.title ?? listID))
                }
                guard !cards.isEmpty else { return nil }
                return .init(id: id, layout: HomeSectionLayout(style: .collection),
                             title: String(format: localized("書店：更多%@"), entry.title ?? ""),
                             binding: .lists(cards))
            }
            // Feed parameters are unchanged. Map only the original store's visual layout
            // to this app's existing equivalent, rather than changing the source/query.
            let layout = section.layout == "heroCards"
                ? HomeSectionLayout(style: .featured) : HomeSectionLayout(rawValue: section.layout)
            let params = section.params ?? [:]
            return .init(id: id, layout: layout, title: title(of: params, in: entry),
                         binding: .module(moduleID: module.id, entryID: entryID), parameters: params)
        }
        return HomePage(sections: sections)
    }

    static func title(of values: [String: String], in entry: RuleModule.Entry) -> String {
        for parameter in entry.params where parameter.kind == .enumeration {
            if let value = values[parameter.name],
               let option = parameter.enumOptions?.first(where: { $0.value == value }) { return option.title }
        }
        return entry.title ?? ""
    }

    private static func sectionID(moduleID: String, entryID: String, index: Int) -> UUID {
        let d = Array(SHA256.hash(data: Data("store/\(moduleID)/\(entryID)/\(index)".utf8)))
        return UUID(uuid: (d[0], d[1], d[2], d[3], d[4], d[5], d[6], d[7],
                           d[8], d[9], d[10], d[11], d[12], d[13], d[14], d[15]))
    }
}
