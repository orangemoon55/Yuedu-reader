import Foundation

/// Media destination identifiers. Menu visibility is controlled separately per root tab.
enum MediaHubKind: String, CaseIterable, Codable, Hashable, Identifiable, Sendable {
    case music

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .music: return "音乐"
        }
    }

    var libraryTitleKey: String {
        switch self {
        case .music: return "音乐库"
        }
    }

    var systemImage: String {
        switch self {
        case .music: return "music.note"
        }
    }

    static let discoveryMenuKinds: [MediaHubKind] = [.music]
    static let libraryMenuKinds: [MediaHubKind] = [.music]

    /// Menus exist only for the two requested root tabs. Keeping their contents here
    /// makes ordering and the absence of retired media destinations independently testable.
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
