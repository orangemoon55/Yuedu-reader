import Foundation

/// Module compatibility belongs to the rule engine, independently of the app's marketing
/// version. A partial port must reject features it does not implement even at this version.
enum RuleModuleRuntimeCompatibility {
    static let version = "3.0.2"

    static func validateCapabilities(_ module: RuleModule) throws(RuleModuleRejection) {
        // Native stores are supported for 3.0.2 manifests. Keep old manifests on the old
        // capability boundary; never whitelist official module ids. Nested volume mapping
        // and entry detail TTL share the implemented 3.0.2 runtime boundary.
        let declared = module.requiredVersion.flatMap(RuleModuleVersion.init)
        let supportsStore = declared.map { $0 >= RuleModuleVersion(RuleModuleFormat.version3_0_2)! } ?? false
        if module.icon != nil { throw .unsupportedCapability("icon") }
        if module.detail != nil { throw .unsupportedCapability("detail") }
        if module.related != nil { throw .unsupportedCapability("related") }
        if module.genre != nil { throw .unsupportedCapability("genre") }
        let entries = module.modules.enumerated().map { ("modules[\($0.offset)]", $0.element) }
            + [("search", module.search), ("lookup", module.lookup)].compactMap { path, entry in
                entry.map { (path, $0) }
            }
        for (path, entry) in entries {
            if entry.store != nil, !supportsStore { throw .unsupportedCapability("\(path).store") }
            if entry.list.volumes != nil, !supportsStore { throw .unsupportedCapability("\(path).list.volumes") }
            if entry.searchesAuthors != nil { throw .unsupportedCapability("\(path).searchesAuthors") }
            if entry.detail?.cacheDuration != nil, !supportsStore { throw .unsupportedCapability("\(path).detail.cacheDuration") }
            // Home section editors have not acquired the conditional/suggestion UI. Global
            // settings have it; reject entry-only fields rather than hide their intended UI.
            for (index, param) in entry.params.enumerated() {
                if param.belongTo != nil { throw .unsupportedCapability("\(path).params[\(index)].belongTo") }
                if param.placeholders != nil { throw .unsupportedCapability("\(path).params[\(index)].placeholders") }
            }
        }
        if module.comments?.chapter.list.rating != nil { throw .unsupportedCapability("comments.chapter.list.rating") }
        if module.comments?.paragraph?.list.rating != nil { throw .unsupportedCapability("comments.paragraph.list.rating") }
    }
}
