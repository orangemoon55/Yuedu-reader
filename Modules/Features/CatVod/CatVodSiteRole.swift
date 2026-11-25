import Foundation

extension CatVodSite {
    /// These are explicit management destinations, not playable catalogues. Never turn their
    /// localhost website/QR entries into a film or weaken the media proxy management denylist.
    var isConfigurationSite: Bool {
        CatVodSiteRole.isConfiguration(name: name, key: key)
    }
}

enum CatVodSiteRole {
    static func isConfiguration(name: String, key: String) -> Bool {
        let compact = name.components(separatedBy: CharacterSet.alphanumerics.inverted).joined().lowercased()
        let labels: Set<String> = ["配置中心", "設定中心", "设置中心", "configuration", "configurationcenter"]
        // A display label is deliberately narrow; a regular movie site containing “配置”
        // somewhere in its title must not be redirected or have its content hidden.
        return labels.contains(compact) || ["configuration", "config_center"].contains(key.lowercased())
    }
}
