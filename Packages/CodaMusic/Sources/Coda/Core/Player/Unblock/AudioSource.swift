import Foundation

/// Where a gray track's replacement audio can come from: a NetEase mirror,
/// third-party parsing services, or one of the app's own platforms
/// other than the track's own.
enum AudioSourceID: String, CaseIterable, Hashable, Sendable {
    case mirror
    case parser
    case netease
    case qq
    case kugou
    case qishui

    init(platform: MusicProvider) {
        switch platform {
        case .netease: self = .netease
        case .qq: self = .qq
        case .kugou: self = .kugou
        case .qishui: self = .qishui
        }
    }

    var platform: MusicProvider? {
        switch self {
        case .mirror, .parser: return nil
        case .netease: return .netease
        case .qq: return .qq
        case .kugou: return .kugou
        case .qishui: return .qishui
        }
    }

    var displayName: String {
        switch self {
        case .mirror, .parser: return "备用音源"
        default: return platform?.name ?? rawValue
        }
    }

    /// Mirrors and parsing services: no account, tried before the platforms.
    var isMirror: Bool { platform == nil }
}

/// A playable stream and the tier it actually serves, when known.
struct UnblockStream: Sendable, Equatable {
    let url: URL
    let quality: AudioQuality?
    /// Bits per second, when the source reports it.
    var bitrate: Int? = nil
    /// The unified quality title, with the reported or estimated bitrate.
    var title: String? = nil
}

struct ResolvedAudioSource: Sendable {
    let id: AudioSourceID
    let url: URL
    let quality: AudioQuality?
    /// Bits per second, when the source reports it.
    let bitrate: Int?
    /// The unified quality title, with the reported or estimated bitrate.
    let title: String?

    var displayName: String { id.displayName }
}

/// The platform-neutral description of the song being looked for.
struct UnblockQuery: Sendable, Hashable {
    let origin: MusicProvider
    let title: String
    let artists: [String]
    let album: String
    let durationMS: Int
    /// The NetEase song ID when the track itself comes from NetEase.
    let neteaseID: Int?

    init(track: Track) {
        let platform = track.platformSong.map { MusicProvider(rawValue: $0.source.rawValue) ?? .netease } ?? .netease
        origin = platform
        title = track.name
        artists = track.artists.map(\.name).filter { !$0.isEmpty }
        album = track.album.name
        durationMS = track.durationMS
        neteaseID = platform == .netease && track.id > 0 ? track.id : nil
    }

    init(origin: MusicProvider, title: String, artists: [String], album: String, durationMS: Int, neteaseID: Int? = nil) {
        self.origin = origin
        self.title = title
        self.artists = artists
        self.album = album
        self.durationMS = durationMS
        self.neteaseID = neteaseID
    }

    var keyword: String {
        "\(title) \(artists.first ?? "")".trimmingCharacters(in: .whitespaces)
    }
}

/// One search hit on another platform, reduced to what matching needs.
struct UnblockCandidate<Payload> {
    let title: String
    let artist: String
    let album: String
    let durationMS: Int
    let payload: Payload
}

protocol UnblockSource: Sendable {
    var id: AudioSourceID { get }
    /// Whether the source can be tried at all right now (e.g. has an account).
    func isAvailable() async -> Bool
    /// Whether a signed-in account backs this source; signed-in sources go first.
    func isSignedIn() async -> Bool
    /// A full-length stream of the same recording, or nil when there is none.
    func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream?
    /// Every tier this source serves for the recording, titled like the platform menus.
    func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption]
}

enum AudioSourceProviderError: LocalizedError {
    case invalidResponse
    case invalidURL
    case missingBitrate
    case missingStreamURL

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid audio-source response"
        case .invalidURL: return "Invalid audio-source URL"
        case .missingBitrate: return "Audio-source response has no bitrate"
        case .missingStreamURL: return "Audio-source response has no stream URL"
        }
    }
}
