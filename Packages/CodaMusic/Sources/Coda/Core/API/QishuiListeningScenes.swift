// Feed protocol reference: SodaM f43a22b and libresoda 5edd2ff.
import Foundation

struct QishuiListeningScene: Identifiable, Codable, Hashable {
    let title: String
    let mode: String
    let sceneID: Int?

    var id: String { mode }

    static let defaultRecommendation = Self(title: String(localized: "默认推荐"), mode: "default", sceneID: nil)

    static let preferences = [
        defaultRecommendation,
        Self(title: String(localized: "熟悉模式"), mode: "familiar", sceneID: nil),
        Self(title: String(localized: "新鲜模式"), mode: "fresh", sceneID: nil)
    ]
}

struct QishuiFeedState: Codable, Hashable {
    enum Kind: Codable, Hashable {
        case scene(QishuiListeningScene)
        case radio(id: String, QishuiRadioReference)
    }

    let kind: Kind
    let startedAt: Int64
    var requestCount = 0
    var cursor = ""
    var hasMore = true
}

struct QishuiFeedPage {
    let songs: [ProviderSong]
    let state: QishuiFeedState
}

struct QishuiPlayedMedia {
    let id: String
    let duration: Int
    let milliseconds: Int

    init?(track: Track?, position: TimeInterval) {
        guard let track, let id = track.platformSong?.qishui?.trackID,
              !id.isEmpty, track.duration.isFinite, position.isFinite, position > 0 else { return nil }
        self.id = id
        duration = Int(max(0, track.duration))
        milliseconds = Int(min(position, max(0, track.duration)) * 1000)
    }

    var payload: [String: Any] {
        ["media_id": id, "type": "track", "duration": duration, "played_mills": milliseconds]
    }
}

@MainActor
final class QishuiQueueContinuation {
    private var task: Task<Void, Never>?
    private var history: [QishuiPlayedMedia] = []

    func cancel() {
        task?.cancel()
        task = nil
    }

    func reset() {
        cancel()
        history.removeAll()
    }

    func record(_ track: Track?, position: TimeInterval) {
        guard let media = QishuiPlayedMedia(track: track, position: position) else { return }
        history.removeAll { $0.id == media.id }
        history.insert(media, at: 0)
        if history.count > 20 { history.removeLast() }
    }

    func load(_ state: QishuiFeedState, excluding tracks: [Track], played: [QishuiPlayedMedia]? = nil,
              completion: @escaping (Result<(tracks: [Track], state: QishuiFeedState), Error>) -> Void) {
        let context = MusicProviderContext.shared
        guard task == nil, context.current == .qishui else { return }
        let ticket = context.ticket
        let ids = Set(tracks.compactMap { $0.platformSong?.qishui?.trackID })
        let played = played ?? history
        task = Task {
            defer { if !Task.isCancelled { task = nil } }
            do {
                let page = try await QishuiMusicAPI.shared.continueFeed(state, excluding: ids, played: played)
                try context.check(ticket)
                completion(.success((try PlatformMusicAPI.shared.tracks(page.songs), page.state)))
            } catch {
                guard !Task.isCancelled, context.ticket == ticket else { return }
                completion(.failure(error))
            }
        }
    }
}

extension QishuiMusicAPI {
    func listeningScenes() async throws -> [QishuiListeningScene] {
        let body = try await signedPCPost(path: "/luna/pc/feed/mode", payload: [:])
        guard let blocks = body["feed_mode_block"] as? [[String: Any]] else {
            throw QishuiError.invalidResponse
        }
        var seen = Set(QishuiListeningScene.preferences.map(\.id))
        let scenes = blocks.flatMap { $0["feed_mode"] as? [[String: Any]] ?? [] }.compactMap { entry -> QishuiListeningScene? in
            let entity = entry["entity"] as? [String: Any]
            let scene = entity?["feed_scene_mode"] as? [String: Any]
            let mode = Self.string(scene?["sub_queue_type"])
            let title = Self.string(entry["text"])
            guard let id = Int(Self.string(scene?["scene_mode_id"])), id >= 0,
                  !mode.isEmpty, !title.isEmpty, seen.insert(mode).inserted else { return nil }
            return .init(title: title, mode: mode, sceneID: id)
        }
        return QishuiListeningScene.preferences + scenes
    }

    func feedState(_ kind: QishuiFeedState.Kind) -> QishuiFeedState {
        .init(kind: kind, startedAt: Int64(now().timeIntervalSince1970))
    }

    func feedPage(_ state: QishuiFeedState, played: [QishuiPlayedMedia] = []) async throws -> QishuiFeedPage {
        var payload: [String: Any] = ["played_media": played.map(\.payload)]
        let path: String
        let first = state.requestCount == 0
        var next = state
        next.requestCount += 1
        switch state.kind {
        case .scene(let scene):
            path = "/luna/pc/feed/song-tab"
            payload["did_first_use_time"] = state.startedAt
            payload["is_first_request"] = first
            payload["is_did_first_request"] = first
            payload["feed_counts"] = ["mix_session_count": next.requestCount]
            if let id = scene.sceneID {
                payload["feed_preference"] = ["scene_mode_id": id]
            } else if scene.id != QishuiListeningScene.defaultRecommendation.id {
                payload["feed_preference"] = ["preference_mode": scene.mode]
            }
        case .radio(let id, let radio):
            path = "/luna/pc/feed/radio/tracks"
            payload["radio_id"] = id
            payload["cursor"] = state.cursor
            payload["flow_type"] = radio.flowType
            payload["trigger_info"] = radio.triggerInfo
        }
        let body = try await signedPCPost(path: path, payload: payload)
        next.hasMore = body["has_more"].map(Self.boolean) ?? true
        next.cursor = Self.string(body["next_cursor"] ?? body["cursor"])
        return .init(songs: try Self.feedSongs(body), state: next)
    }

    // A response may contain only tracks the listener already has. Move through
    // a few such pages, then leave the next request to an explicit retry.
    func continueFeed(_ state: QishuiFeedState, excluding ids: Set<String>,
                      played: [QishuiPlayedMedia]) async throws -> QishuiFeedPage {
        var next = state
        for _ in 0..<3 where next.hasMore {
            try Task.checkCancellation()
            let page = try await feedPage(next, played: played)
            next = page.state
            let fresh = page.songs.filter { $0.qishui.map { !ids.contains($0.trackID) } ?? false }
            if !fresh.isEmpty { return .init(songs: fresh, state: next) }
        }
        return .init(songs: [], state: next)
    }

    static func feedSongs(_ body: [String: Any]) throws -> [ProviderSong] {
        guard let items = body["items"] as? [[String: Any]] else { throw QishuiError.invalidResponse }
        var seen = Set<Int>()
        return items.compactMap { Self.song(Self.trackEntity($0)) }.filter { seen.insert($0.id).inserted }
    }

    static func radioCard(_ resource: [String: Any]?) -> ProviderPlaylist? {
        guard let resource, string(resource["type"]) == "radio",
              let style = resource["style"] as? [String: Any] else { return nil }
        let query = URLComponents(string: string(style["link"]))?.queryItems ?? []
        let resourceID = string(resource["resource_id"])
        let id = resourceID.isEmpty ? query.first { $0.name == "queue_id" }?.value ?? "" : resourceID
        let title = string(style["title"])
        guard !id.isEmpty, !title.isEmpty else { return nil }
        let flowType = (query.first { $0.name == "flow_type" }?.value).flatMap(Int.init) ?? 2
        let triggerInfo = query.first { $0.name == "trigger_info" }?.value ?? ""
        let cover = (style["cover_url_list"] as? [[String: Any]])?.first
        var playlist = ProviderPlaylist(
            id: PlatformMusicAPI.identifier(provider: .qishui, kind: "radio", value: id),
            name: title, coverURL: URL(string: imageURL(cover)), source: .qishui
        )
        playlist.qishui = .init(playlistID: id, type: 0, radio: .init(flowType: flowType, triggerInfo: triggerInfo))
        return playlist
    }
}
