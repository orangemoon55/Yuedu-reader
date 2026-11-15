import Foundation

/// Runtime features selected by the app's generated Info.plist.
/// A missing key keeps the regular build's account and cloud behavior.
enum PersonalBuildFeatures {
    // Immutable and nonisolated for Swift 6 callers, including notification callbacks.
    nonisolated static let isStandalone: Bool =
        Bundle.main.object(forInfoDictionaryKey: "ReaderStandalone") as? Bool ?? false

    /// The app name used by the welcome and About screens follows its installed identity.
    nonisolated static var appDisplayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "轻云出岫"
    }

    /// This build grants local capabilities, without asserting a purchase or
    /// granting credentials, paid cloud services, or access to source sites.
    nonisolated static let grantsLocalPremiumAccess: Bool = isStandalone
}
