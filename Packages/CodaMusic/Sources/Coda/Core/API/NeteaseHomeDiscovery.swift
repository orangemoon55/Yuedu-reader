import Foundation

/// Homepage resource contracts cross-checked against MeloX's Home API/models.
/// Keep the resource type: editorial shelves may contain playlists or songs.
enum HomeDiscoveryContent {
    case playlists([PlaylistSummary])
    case songs([Track])

    var isEmpty: Bool {
        switch self {
        case .playlists(let values): return values.isEmpty
        case .songs(let values): return values.isEmpty
        }
    }
}

enum HomeDiscoverySlot: String, CaseIterable {
    case playlists, trending, newSongs, regional, radios
    /// 酷狗推荐卡片：专属好歌、小众宝藏。
    case forYou, hiddenGems

    var title: String {
        switch self {
        case .playlists: return String(localized: "推荐歌单")
        case .trending: return String(localized: "近期热播")
        case .newSongs: return String(localized: "新歌速递")
        case .regional: return String(localized: "分地区热门")
        case .radios: return String(localized: "电台")
        case .forYou: return String(localized: "专属好歌")
        case .hiddenGems: return String(localized: "小众宝藏")
        }
    }

    var showsSongRows: Bool { self != .playlists && self != .radios }

    /// Slots the platform only fills for signed-in accounts.
    /// QQ radios are personal stations; Qishui radios and the rest are public.
    func requiresLogin(on provider: MusicProvider) -> Bool {
        provider == .qq && self == .radios
    }
}

extension NeteaseAPI {
    /// Only extract the requested discovery modules; unrelated homepage resources
    /// (ads, videos, podcasts, etc.) must never become playable song cards.
    static func decodeHomeDiscovery(_ data: Data) throws -> [HomeDiscoverySlot: HomeDiscoveryContent] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let payload = root["data"] as? [String: Any],
              let blocks = payload["blocks"] as? [[String: Any]] else {
            throw NeteaseAPIError.decoding("Missing homepage blocks")
        }
        if let code = root["code"] as? Int, code != 200 {
            if code == 301 { throw NeteaseAPIError.needLogin }
            throw NeteaseAPIError.business(code: code, message: root["message"] as? String)
        }
        func decode<T: Decodable>(_ type: T.Type, _ object: [String: Any]) -> T? {
            guard let data = try? JSONSerialization.data(withJSONObject: object) else { return nil }
            return try? JSONDecoder().decode(type, from: data)
        }
        func title(_ ui: [String: Any]?, _ key: String) -> String? {
            (ui?[key] as? [String: Any])?["title"] as? String
        }
        var result: [HomeDiscoverySlot: HomeDiscoveryContent] = [:]
        for block in blocks {
            let ui = block["uiElement"] as? [String: Any]
            let creatives = block["creatives"] as? [[String: Any]] ?? []
            let creativeUI = creatives.first?["uiElement"] as? [String: Any]
            let label = (title(ui, "subTitle") ?? title(ui, "mainTitle") ?? title(creativeUI, "mainTitle") ?? "")
                .filter { !$0.isWhitespace }
            let code = (block["blockCode"] as? String ?? "").uppercased()
            let slot: HomeDiscoverySlot
            if code == "HOMEPAGE_BLOCK_PLAYLIST_RCMD" || label == "推荐歌单" {
                slot = .playlists
            } else if label.contains("最近的热门歌曲") || label.contains("分地区热门") {
                slot = .regional
            } else if label.contains("近期云村热播") || label.contains("近期热播") || code == "HOMEPAGE_BLOCK_STYLE_RCMD" {
                slot = .trending
            } else { continue }
            // Aggregate regional modules; keep the first nonempty source for other slots.
            guard slot == .regional || result[slot] == nil else { continue }
            var playlists: [PlaylistSummary] = []
            var songs: [Track] = []
            var playlistIDs = Set<Int>()
            var songIDs = Set<Int>()
            for resource in creatives.flatMap({ $0["resources"] as? [[String: Any]] ?? [] }) {
                guard resource["valid"] as? Bool != false else { continue }
                let type = (resource["resourceType"] as? String ?? "").lowercased()
                let id = (resource["resourceId"] as? Int)
                    ?? (resource["resourceId"] as? String).flatMap(Int.init) ?? 0
                let resourceUI = resource["uiElement"] as? [String: Any]
                let ext = resource["resourceExtInfo"] as? [String: Any] ?? [:]
                if ["list", "playlist"].contains(type), id > 0 {
                    var object: [String: Any] = ["id": id, "name": title(resourceUI, "mainTitle") ?? ""]
                    object["picUrl"] = (resourceUI?["image"] as? [String: Any])?["imageUrl"]
                    object["copywriter"] = title(resourceUI, "subTitle")
                    object["playCount"] = ext["playCount"]
                    if let playlist = decode(PlaylistSummary.self, object), !playlist.name.isEmpty,
                       playlistIDs.insert(id).inserted { playlists.append(playlist) }
                } else if type == "song" {
                    // Full song objects retain duration, privileges and album metadata.
                    guard let object = (ext["songData"] ?? ext["song"]) as? [String: Any],
                          let song = decode(Track.self, object), song.id > 0, !song.name.isEmpty,
                          songIDs.insert(song.id).inserted else { continue }
                    songs.append(song)
                }
            }
            if !playlists.isEmpty {
                if case .playlists(let previous) = result[slot] {
                    let seen = Set(previous.map(\.id))
                    playlists = previous + playlists.filter { !seen.contains($0.id) }
                }
                result[slot] = .playlists(playlists)
            } else if !songs.isEmpty {
                if case .songs(let previous) = result[slot] {
                    let seen = Set(previous.map(\.id))
                    songs = previous + songs.filter { !seen.contains($0.id) }
                }
                // A mixed-type module keeps the first source's presentation.
                if case .playlists = result[slot] {} else { result[slot] = .songs(songs) }
            }
        }
        return result
    }

    static func homeDiscovery(refresh: Bool = false, using client: NeteaseClient = .shared) async throws
        -> [HomeDiscoverySlot: HomeDiscoveryContent] {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.homeDiscovery() }
        try MusicProviderContext.shared.requireNetease()
        let ticket = MusicProviderContext.shared.ticket
        let data = try await client.eapi("/homepage/block/page", ["refresh": refresh])
        try MusicProviderContext.shared.check(ticket)
        return try decodeHomeDiscovery(data)
    }

    struct HomeTopSongsResponse: Decodable { let data: [Track] }

    /// Same discovery/new/songs source as MeloX's regional fallback.
    /// areaId: 0 all, 7 Chinese, 96 Western, 8 Japanese, 16 Korean.
    static func homeTopSongs(areaID: Int, using client: NeteaseClient = .shared) async throws -> [Track] {
        if MusicProviderContext.shared.current != .netease {
            guard areaID == 0 else { throw MusicProviderError.unsupported }
            return try await PlatformMusicAPI.shared.recommendations()
        }
        try MusicProviderContext.shared.requireNetease()
        let ticket = MusicProviderContext.shared.ticket
        let data = try await client.eapi("/v1/discovery/new/songs", ["areaId": areaID, "total": true])
        try MusicProviderContext.shared.check(ticket)
        return try client.decoded(HomeTopSongsResponse.self, from: data).data.filter { $0.id > 0 }
    }
}
