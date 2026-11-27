import Foundation

/// Only official standalone products use the official persistent namespace.
/// Tests without a bundle ID use a separate fallback, never release credentials.
enum CodaIdentity {
    static let releaseBundleIdentifier = "wow.caicai.coda"
    static let developmentBundleIdentifier = releaseBundleIdentifier + ".dev"

    /// Official standalone products retain their original identity. An embedded
    /// host must never silently fall back to Coda's release credential domain.
    static func isEmbedded(in bundleIdentifier: String?) -> Bool {
        guard let identifier = bundleIdentifier, !identifier.isEmpty else { return true }
        return identifier != releaseBundleIdentifier && identifier != developmentBundleIdentifier
    }

    static func namespace(for bundleIdentifier: String?) -> String {
        guard let identifier = bundleIdentifier, !identifier.isEmpty else { return "local.coda-music" }
        return isEmbedded(in: identifier) ? identifier + ".coda-music" : identifier
    }

    /// Shared, Foundation-only policy used by all host adapters.
    nonisolated static var isEmbeddedHost: Bool { isEmbedded(in: Bundle.main.bundleIdentifier) }
    static var isEmbedded: Bool { isEmbeddedHost }
    static var namespace: String { namespace(for: Bundle.main.bundleIdentifier) }
    static var syncDirectoryName: String {
        if isEmbedded { return namespace }
        return namespace == developmentBundleIdentifier ? "Coda Dev" : "Coda"
    }
    static func keychainService(_ purpose: String) -> String { namespace + "." + purpose }
    static var releaseRepository: String {
        Bundle.main.object(forInfoDictionaryKey: "CodaReleaseRepository") as? String ?? "Wow-CaiCai/Coda"
    }
}
