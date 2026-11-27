import Foundation

/// Local checkpoints write one complete session. Pre-session files are read only
/// for migration; their queue is never written alongside the current format.
struct PlaybackState: Codable {
    /// Last confirmed badge, independent of a loaded audio engine or stream URL.
    enum AudioQualityBadge: Codable, Equatable {
        case quality(String)
        case externalSource
    }

    let audioQualityBadge: AudioQualityBadge?
    let session: PlaybackSession?
    let recentContexts: [PlayContext]?
    let legacy: Legacy?

    struct Legacy: Decodable {
        let queue: [Track]
        let currentID: Int?
        let shuffle: Bool
        let queueOrder: String?
    }

    init(session: PlaybackSession?, recentContexts: [PlayContext], audioQualityBadge: AudioQualityBadge? = nil) {
        self.audioQualityBadge = audioQualityBadge
        self.session = session
        self.recentContexts = recentContexts
        legacy = nil
    }

    private enum CodingKeys: String, CodingKey {
        case session, recentContexts, queue, audioQualityBadge
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audioQualityBadge = try container.decodeIfPresent(AudioQualityBadge.self, forKey: .audioQualityBadge)
        session = try container.decodeIfPresent(PlaybackSession.self, forKey: .session)
        recentContexts = try container.decodeIfPresent([PlayContext].self, forKey: .recentContexts)
        legacy = session == nil && container.contains(.queue) ? try Legacy(from: decoder) : nil
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(audioQualityBadge, forKey: .audioQualityBadge)
        try container.encodeIfPresent(session, forKey: .session)
        try container.encodeIfPresent(recentContexts, forKey: .recentContexts)
    }
}
