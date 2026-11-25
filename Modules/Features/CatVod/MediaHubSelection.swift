import Foundation

/// Independent choices for the two roots. Tab taps/background/relaunch never clear them.
/// Only another menu selection or the explicit return-to-reading action changes a choice.
enum MediaHubSelection {
    static let homeKey = "readcc.mediaHub.homeContent.v1"
    static let libraryKey = "readcc.mediaHub.bookshelfContent.v1"

    static func route(_ stored: String, isLibrary: Bool) -> MediaHubRoute? {
        guard let kind = MediaHubKind(rawValue: stored),
              !isLibrary || MediaHubKind.libraryMenuKinds.contains(kind) else { return nil }
        return MediaHubRoute(kind: kind, isLibrary: isLibrary)
    }
}
