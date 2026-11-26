import Foundation

/// Media destination identifiers. Menu visibility is controlled separately per root tab.
enum MediaHubKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case video
    case music
    case drama

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .video: return "影视"
        case .music: return "音乐"
        case .drama: return "短剧"
        }
    }

    var libraryTitleKey: String {
        switch self {
        case .video: return "影视库"
        case .music: return "音乐库"
        case .drama: return "短剧库"
        }
    }

    var systemImage: String {
        switch self {
        case .video: return "play.rectangle.fill"
        case .music: return "music.note"
        case .drama: return "rectangle.stack.fill"
        }
    }

    static let discoveryMenuKinds: [MediaHubKind] = [.video, .music]
    static let libraryMenuKinds: [MediaHubKind] = [.video, .music]

    /// Menus exist only for the two requested root tabs. Keeping their contents here
    /// makes ordering and the absence of short dramas in the library independently testable.
    static func quickActionKinds(for tab: RootTabItem) -> [MediaHubKind] {
        switch tab {
        case .explore: return discoveryMenuKinds
        case .bookshelf: return libraryMenuKinds
        default: return []
        }
    }
}

struct MediaHubRoute: Identifiable, Hashable {
    let kind: MediaHubKind
    let isLibrary: Bool

    var id: String { "\(kind.rawValue).\(isLibrary ? "library" : "hub")" }
}
