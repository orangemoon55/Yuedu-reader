import Foundation

/// Long-press destinations are transient UI state, not user preferences.
enum MediaHubSelection {
    static func route(_ selected: MediaHubKind?, isLibrary: Bool) -> MediaHubRoute? {
        guard let kind = selected,
              !isLibrary || MediaHubKind.libraryMenuKinds.contains(kind) else { return nil }
        return MediaHubRoute(kind: kind, isLibrary: isLibrary)
    }
}
