import Foundation
import os

/// Compatibility entry point for the existing UI. Shared operations dispatch to
/// the selected platform and return the original unified models; NetEase-only
/// operations require NetEase. See MusicServiceCatalog for the complete contract.
enum NeteaseAPI {
    private static var client: NeteaseClient { .shared }
    private static let playbackLog = Logger(subsystem: "wow.caicai.coda", category: "netease-playback")

    private static func eapi<T: Decodable>(
        _ type: T.Type, _ path: String, _ payload: [String: Any] = [:]
    ) async throws -> T {
        try MusicProviderContext.shared.requireNetease()
        let ticket = MusicProviderContext.shared.ticket
        let data = try await client.eapi(path, payload)
        try MusicProviderContext.shared.check(ticket)
        return try client.decoded(T.self, from: data)
    }

    struct CodeOnly: Decodable {
        let code: Int
    }

    // MARK: - Auth

    struct QRKeyResponse: Decodable {
        let code: Int
        let unikey: String
    }

    static func qrKey() async throws -> String {
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(QRKeyResponse.self, "/login/qrcode/unikey", ["type": 3]).unikey
    }

    /// QR key on an isolated client, for adding an account without touching the active session.
    static func qrKey(using isolated: NeteaseClient) async throws -> String {
        let data = try await isolated.eapi("/login/qrcode/unikey", ["type": 3])
        return try isolated.decoded(QRKeyResponse.self, from: data).unikey
    }

    static func qrLoginURL(unikey: String) -> String {
        "https://music.163.com/login?codekey=\(unikey)"
    }

    struct QRCheckResponse: Decodable {
        let code: Int
        let message: String?
        let nickname: String?
        let avatarUrl: String?
    }

    /// Codes: 800 expired · 801 waiting · 802 scanned · 803 success.
    /// On 803 the auth cookies arrive via Set-Cookie and are absorbed by the client.
    static func qrCheck(unikey: String) async throws -> QRCheckResponse {
        try MusicProviderContext.shared.requireNetease()
        let data = try await client.eapi("/login/qrcode/client/login", ["key": unikey, "type": 3])
        return try JSONDecoder().decode(QRCheckResponse.self, from: data)
    }

    /// On 803 the new account's cookies land in `isolated`, not the shared client.
    static func qrCheck(unikey: String, using isolated: NeteaseClient) async throws -> QRCheckResponse {
        let data = try await isolated.eapi("/login/qrcode/client/login", ["key": unikey, "type": 3])
        return try JSONDecoder().decode(QRCheckResponse.self, from: data)
    }

    /// Sends an SMS verification code for phone-number login
    /// (upstream: `/api/sms/captcha/sent`).
    static func sendSMSCode(phone: String, countryCode: String = "86") async throws {
        try MusicProviderContext.shared.requireNetease()
        let data = try await client.api("/sms/captcha/sent",
                                          ["ctcode": countryCode, "cellphone": phone,
                                           "secrete": "music_middleuser_pclogin"])
        _ = try client.decoded(CodeOnly.self, from: data)
    }

    /// Phone-number login with an SMS code (upstream: `/api/w/login/cellphone`).
    /// Auth cookies arrive via Set-Cookie.
    static func loginCellphone(phone: String, captcha: String, countryCode: String = "86") async throws {
        try MusicProviderContext.shared.requireNetease()
        let data = try await client.api("/w/login/cellphone",
                                          ["type": "1", "https": "true",
                                           "phone": phone, "countrycode": countryCode,
                                           "captcha": captcha, "remember": "true"])
        _ = try client.decoded(CodeOnly.self, from: data)
        guard client.isLoggedIn else {
            throw NeteaseAPIError.business(code: -1, message: String(localized: "登录失败，请重试"))
        }
    }

    /// An isolated client keeps a late logout response away from a newer login.
    static func logout(
        detachedCookies: [String: String],
        using client: NeteaseClient = NeteaseClient(configuration: .ephemeral, persistsCookies: false)
    ) async throws {
        try MusicProviderContext.shared.requireNetease()
        client.setCookies(detachedCookies)
        let data = try await client.eapi("/logout", absorbResponseCookies: false)
        _ = try client.decoded(CodeOnly.self, from: data)
    }

    static func refreshLogin() async {
        guard MusicProviderContext.shared.current == .netease else { return }
        _ = try? await client.eapi("/login/token/refresh")
    }

    struct AccountResponse: Decodable {
        let code: Int
        let profile: UserProfile?
    }

    static func userAccount(using client: NeteaseClient = .shared) async throws -> UserProfile? {
        try MusicProviderContext.shared.requireNetease()
        let data = try await client.eapi("/nuser/account/get")
        return try client.decoded(AccountResponse.self, from: data).profile
    }

    struct UserDetailResponse: Decodable {
        struct Profile: Decodable {
            let follows: Int?
            let followeds: Int?
            let playlistCount: Int?
        }
        let level: Int?
        let listenSongs: Int?
        let profile: Profile?
    }

    static func userDetail(uid: Int) async throws -> UserDetailResponse {
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(UserDetailResponse.self, "/v1/user/detail/\(uid)")
    }

    // MARK: - User library

    struct UserPlaylistsResponse: Decodable {
        let playlist: [PlaylistSummary]
        let more: Bool?
    }

    static func userPlaylists(uid: Int, limit: Int = 2000, offset: Int = 0) async throws -> [PlaylistSummary] {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.userPlaylists() }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(UserPlaylistsResponse.self, "/user/playlist",
                        ["uid": uid, "limit": limit, "offset": offset, "includeVideo": true]).playlist
    }

    struct LikelistResponse: Decodable {
        let ids: [Int]
    }

    static func likedTrackIDs(uid: Int) async throws -> [Int] {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.favorites().map(\.id) }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(LikelistResponse.self, "/song/like/get", ["uid": uid]).ids
    }

    static func likeTrack(id: Int, like: Bool) async throws {
        if MusicProviderContext.shared.current != .netease { try await PlatformMusicAPI.shared.like(id: id, liked: like); return }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        _ = try await eapi(CodeOnly.self, "/radio/like",
                           ["alg": "itembased", "trackId": String(id), "like": like ? "true" : "false", "time": "3"])
    }

    struct SublistResponse<Item: Decodable>: Decodable {
        let data: [Item]
        let count: Int?
        let hasMore: Bool?
    }

    static func likedAlbums(limit: Int = 500, offset: Int = 0) async throws -> [AlbumSummary] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.likedQQAlbums() }
        if MusicProviderContext.shared.current == .qishui { return try await PlatformMusicAPI.shared.qishuiLikedAlbums() }
        if MusicProviderContext.shared.current != .netease { return [] }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(SublistResponse<AlbumSummary>.self, "/album/sublist",
                        ["limit": limit, "offset": offset, "total": true]).data
    }

    static func likedArtists(limit: Int = 500, offset: Int = 0) async throws -> [ArtistSummary] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.followedQQArtists() }
        if MusicProviderContext.shared.current == .qishui { return try await PlatformMusicAPI.shared.qishuiFollowedArtists() }
        if MusicProviderContext.shared.current == .kugou { return try await PlatformMusicAPI.shared.followedKugouArtists() }
        if MusicProviderContext.shared.current != .netease { return [] }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(SublistResponse<ArtistSummary>.self, "/artist/sublist",
                        ["limit": limit, "offset": offset, "total": true]).data
    }

    struct PlayRecordResponse: Decodable {
        let weekData: [PlayRecordItem]?
        let allData: [PlayRecordItem]?
    }

    static func playRecords(uid: Int, week: Bool) async throws -> [PlayRecordItem] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.qqListeningRank(period: week ? 2 : 4) }
        if MusicProviderContext.shared.current == .kugou { return try await PlatformMusicAPI.shared.playRecords(week: week) }
        try MusicProviderContext.shared.requireNetease()
        let resp = try await eapi(PlayRecordResponse.self, "/v1/play/record",
                                   ["uid": uid, "type": week ? 1 : 0])
        return (week ? resp.weekData : resp.allData) ?? []
    }

    struct RecentSongsResponse: Decodable {
        struct Payload: Decodable {
            let list: [RecentSongPlayRecord]
        }
        let data: Payload
    }

    static func recentSongs(limit: Int = 100, using client: NeteaseClient = .shared) async throws -> [RecentSongPlayRecord] {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.recentSongs(limit: limit) }
        let data = try await client.eapi("/play-record/song/list", ["limit": limit])
        let response = try client.decoded(RecentSongsResponse.self, from: data)
        return response.data.list.sorted { $0.playedAt > $1.playedAt }
    }

    struct CloudResponse: Decodable {
        let data: [CloudSongItem]?
        let hasMore: Bool?
        /// Bytes; served as a number or a numeric string depending on account age.
        let size: Int64?
        let maxSize: Int64?

        private enum CodingKeys: String, CodingKey {
            case data, hasMore, size, maxSize
        }

        init(data: [CloudSongItem], hasMore: Bool, size: Int64?, maxSize: Int64?) {
            self.data = data; self.hasMore = hasMore; self.size = size; self.maxSize = maxSize
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            data = try? c.decode([CloudSongItem].self, forKey: .data)
            hasMore = try? c.decode(Bool.self, forKey: .hasMore)
            size = (try? c.decode(Int64.self, forKey: .size))
                ?? (try? c.decode(String.self, forKey: .size)).flatMap(Int64.init)
            maxSize = (try? c.decode(Int64.self, forKey: .maxSize))
                ?? (try? c.decode(String.self, forKey: .maxSize)).flatMap(Int64.init)
        }
    }

    static func cloudSongs(limit: Int = 1000, offset: Int = 0) async throws -> CloudResponse {
        if [.kugou, .qq].contains(MusicProviderContext.shared.current) { return try await PlatformMusicAPI.shared.cloudSongs() }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(CloudResponse.self, "/v1/cloud/get", ["limit": limit, "offset": offset])
    }

    static func cloudDelete(id: Int) async throws {
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        guard client.isLoggedIn else { throw NeteaseAPIError.needLogin }
        guard id > 0 else { throw NeteaseAPIError.decoding("Invalid cloud song ID") }
        _ = try await eapi(CodeOnly.self, "/cloud/del", ["songIds": "[\(id)]"])
    }

    // MARK: - Playlists

    struct PersonalizedResponse: Decodable {
        let result: [PlaylistSummary]
    }

    static func personalizedPlaylists(limit: Int = 30) async throws -> [PlaylistSummary] {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.recommendedPlaylists(limit: limit) }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(PersonalizedResponse.self, "/personalized/playlist",
                        ["limit": limit, "total": true, "n": 1000]).result
    }

    struct RecommendResourceResponse: Decodable {
        let recommend: [PlaylistSummary]
    }

    /// Logged-in daily recommended playlists.
    static func recommendResource() async throws -> [PlaylistSummary] {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.recommendedPlaylists() }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(RecommendResourceResponse.self, "/v1/discovery/recommend/resource").recommend
    }

    struct RecommendSongsResponse: Decodable {
        struct Body: Decodable {
            let dailySongs: [Track]?
        }

        // New accounts with no listening history get `"data": null`.
        let data: Body?
    }

    static func dailyRecommendSongs(afresh: Bool = false, using client: NeteaseClient = .shared) async throws -> [Track] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.qqDailySongs() }
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.recommendations() }
        try MusicProviderContext.shared.requireNetease()
        let data = try await client.eapi("/v3/discovery/recommend/songs", afresh ? ["afresh": true] : [:])
        let resp = try client.decoded(RecommendSongsResponse.self, from: data)
        return resp.data?.dailySongs ?? []
    }

    struct RecommendDislikeResponse: Decodable {
        let data: Track

        private enum CodingKeys: String, CodingKey {
            case data
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let track = try container.decode(Track.self, forKey: .data)
            guard track.id > 0,
                  !track.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw DecodingError.dataCorruptedError(
                    forKey: .data,
                    in: container,
                    debugDescription: "Recommendation replacement is incomplete"
                )
            }
            data = track
        }
    }

    static func dislikeRecommendedSong(id: Int) async throws -> Track {
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(
            RecommendDislikeResponse.self,
            "/v2/discovery/recommend/dislike",
            ["resId": id, "resType": 4, "sceneType": 1]
        ).data
    }

    struct PlaylistDetailResponse: Decodable {
        let playlist: PlaylistDetail
        let privileges: [TrackPrivilege]?
    }

    static func playlistDetail(id: Int) async throws -> PlaylistDetailResponse {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.playlistDetail(id: id) }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(PlaylistDetailResponse.self, "/v6/playlist/detail",
                        ["id": id, "n": 100_000, "s": 8])
    }

    /// Fetch only the first ten chart entries while preserving chart order.
    static func toplistPreviewTracks(id: Int) async throws -> (tracks: [Track], previousRanks: [Int: Int], growthRatios: [Int: Double]) {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.toplistPreviewTracks(id: id) }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        let response = try await eapi(PlaylistDetailResponse.self, "/v6/playlist/detail",
                                       ["id": id, "n": 10, "s": 0])
        let ids = Array(response.playlist.trackIds.prefix(10).map(\.id))
        let tracks = Array(response.playlist.tracks.prefix(10))
        let previousRanks = Dictionary(response.playlist.trackIds.compactMap { ref in
            ref.lr.map { (ref.id, $0 >= 0 ? $0 + 1 : 0) }
        }, uniquingKeysWith: { first, _ in first })
        let growthRatios = Dictionary(response.playlist.trackIds.compactMap { ref in
            ref.ratio.map { (ref.id, $0) }
        }, uniquingKeysWith: { first, _ in first })
        if ids.isEmpty { return (tracks, previousRanks, growthRatios) }
        let byID = Dictionary(tracks.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if ids.allSatisfy({ byID[$0] != nil }) {
            return (ids.compactMap { byID[$0] }, previousRanks, growthRatios)
        }
        let full = try await songDetails(ids: ids)
        let fullByID = Dictionary(full.songs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return (ids.compactMap { fullByID[$0] }, previousRanks, growthRatios)
    }

    struct PlaylistBrief: Decodable {
        struct Body: Decodable {
            let id: Int
            let name: String?
            let coverImgUrl: String?
            let tracks: [Track]?
            let trackIds: [TrackIDRef]?

            init(id: Int, name: String?, coverImgUrl: String?, tracks: [Track]? = nil,
                 trackIds: [TrackIDRef]? = nil) {
                self.id = id
                self.name = name
                self.coverImgUrl = coverImgUrl
                self.tracks = tracks
                self.trackIds = trackIds
            }
        }

        let playlist: Body
    }

    struct RadarPlaylist: Identifiable, Hashable {
        let id: Int
        let title: String
        let subtitle: String?
        let coverURL: String?

        init(id: Int, title: String, subtitle: String?, coverURL: String?) {
            self.id = id
            self.title = title
            self.subtitle = subtitle
            self.coverURL = coverURL
        }

        init(brief: PlaylistBrief.Body) {
            id = brief.id
            // The last separator separates the radar name from its current seed-song intro.
            let name = (brief.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if let separator = name.lastIndex(of: "|") {
                let label = name[name.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
                let intro = name[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
                let introIsLabel = intro.contains("雷达") || intro.hasSuffix("歌单")
                let labelIsLabel = label.contains("雷达") || label.hasSuffix("歌单")
                if introIsLabel, !labelIsLabel {
                    title = intro
                    subtitle = label.isEmpty ? nil : label
                } else if labelIsLabel {
                    title = label.isEmpty ? String(localized: "雷达歌单") : label
                    subtitle = intro.isEmpty ? nil : intro
                } else {
                    // A pipe inside a seed-song name is part of the source copy.
                    title = name
                    subtitle = nil
                }
            } else {
                title = name.isEmpty ? String(localized: "雷达歌单") : name
                subtitle = nil
            }
            coverURL = brief.coverImgUrl
        }
    }

    /// The desktop client's radar module is authoritative for membership and order.
    /// `newStyle` supplies its current seed-song text and complete generated cover URL.
    struct DesktopRadarResponse: Decodable {
        struct Body: Decodable { let blocks: [Block] }
        struct Block: Decodable {
            let code: String?
            let creatives: [Creative]?
        }
        struct UIElement: Decodable {
            struct Title: Decodable { let title: String? }
            struct Image: Decodable { let imageUrl: String? }
            let mainTitle: Title?
            let images: [Image]?
        }
        struct Creative: Decodable {
            let uiElement: UIElement?
            let resources: [Resource]?
        }
        struct Resource: Decodable {
            let id: Int?
            let resourceType: String?
            let valid: Bool?

            private enum CodingKeys: String, CodingKey { case resourceId, resourceType, valid }
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                id = (try? c.decode(Int.self, forKey: .resourceId))
                    ?? (try? c.decode(String.self, forKey: .resourceId)).flatMap(Int.init)
                resourceType = try? c.decode(String.self, forKey: .resourceType)
                valid = try? c.decode(Bool.self, forKey: .valid)
            }
        }
        let data: Body

        func playlists() throws -> [RadarPlaylist] {
            let blocks = data.blocks.filter { $0.code == "CUSTOMIZE_PLAYLIST_MGC" }
            // Missing/malformed modules must not erase a previously loaded snapshot.
            guard !blocks.isEmpty, blocks.allSatisfy({ $0.creatives != nil }) else {
                throw NeteaseAPIError.decoding("Missing desktop radar module")
            }
            var seen = Set<Int>()
            return blocks.flatMap { $0.creatives ?? [] }.compactMap { creative in
                guard let resource = creative.resources?.first(where: {
                    ($0.resourceType == "playlist" || $0.resourceType == "list")
                        && $0.valid != false && ($0.id ?? 0) > 0
                }), let id = resource.id, seen.insert(id).inserted else { return nil }
                return RadarPlaylist(brief: .init(id: id,
                    name: creative.uiElement?.mainTitle?.title,
                    coverImgUrl: creative.uiElement?.images?.first?.imageUrl))
            }
        }
    }

    static func radarPlaylists(using client: NeteaseClient = .shared) async throws -> [RadarPlaylist] {
        try MusicProviderContext.shared.requireNetease()
        let data = try await client.eapi("/pc/customize/block/page", ["newStyle": true])
        let source = try client.decoded(DesktopRadarResponse.self, from: data).playlists()
        // Keep source membership, order and copy; prefer the playlist artwork.
        // Detail failures never drop a module entry.
        return await withTaskGroup(of: (Int, RadarPlaylist).self) { group in
            for (index, playlist) in source.enumerated() {
                group.addTask {
                    guard let brief = try? await playlistBrief(id: playlist.id, using: client),
                          brief.id == playlist.id
                    else { return (index, playlist) }
                    let hasName = !(brief.name?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                    let label = hasName ? RadarPlaylist(brief: brief) : playlist
                    let intro = playlist.subtitle ?? (playlist.title == label.title ? nil : playlist.title)
                    let ownCover = PlaylistCoverSource.firstValid([brief.coverImgUrl, playlist.coverURL])
                    let cover = ownCover == nil ? await radarFirstSongCover(brief, using: client) : ownCover
                    return (index, RadarPlaylist(id: playlist.id, title: label.title,
                        subtitle: intro ?? label.subtitle, coverURL: cover))
                }
            }
            var ordered: [Int: RadarPlaylist] = [:]
            for await (index, playlist) in group { ordered[index] = playlist }
            return source.indices.compactMap { ordered[$0] }
        }
    }

    private static func radarFirstSongCover(_ brief: PlaylistBrief.Body, using client: NeteaseClient) async -> String? {
        guard let firstID = brief.trackIds?.first?.id ?? brief.tracks?.first?.id else { return nil }
        if let cover = brief.tracks?.first(where: { $0.id == firstID })?.album.picUrl,
           !cover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return cover }
        // Some personalized playlists omit the first track object; resolve its actual ID,
        // rather than accidentally taking the next available song's cover.
        let payload = ["c": "[{\"id\":\(firstID)}]"]
        guard let data = try? await client.eapi("/v3/song/detail", payload),
              let response = try? client.decoded(SongDetailResponse.self, from: data),
              let cover = response.songs.first(where: { $0.id == firstID })?.album.picUrl,
              !cover.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return cover
    }

    /// Fetch metadata and the first song for the personalized radar cards.
    static func playlistBrief(id: Int, using client: NeteaseClient = .shared) async throws -> PlaylistBrief.Body {
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        let data = try await client.eapi("/v6/playlist/detail", ["id": id, "n": 1, "s": 0])
        return try client.decoded(PlaylistBrief.self, from: data).playlist
    }

    struct SongDetailResponse: Decodable {
        let songs: [Track]
        let privileges: [TrackPrivilege]?
    }

    static func songDetails(ids: [Int]) async throws -> SongDetailResponse {
        if MusicProviderContext.shared.current != .netease { return .init(songs: try await MainActor.run { try ids.map { try PlatformMusicAPI.shared.register(PlatformMusicAPI.shared.song($0)) } }, privileges: nil) }
        try MusicProviderContext.shared.requireNetease()
        guard !ids.isEmpty else { return SongDetailResponse(songs: [], privileges: []) }
        let c = "[" + ids.map { "{\"id\":\($0)}" }.joined(separator: ",") + "]"
        return try await eapi(SongDetailResponse.self, "/v3/song/detail", ["c": c])
    }

    struct TopPlaylistResponse: Decodable {
        let playlists: [PlaylistSummary]
        let total: Int?
        let more: Bool?
    }

    static func topPlaylists(category: String, order: String = "hot",
                             limit: Int = 50, offset: Int = 0) async throws -> TopPlaylistResponse {
        if MusicProviderContext.shared.current != .netease {
            guard ["全部", "推荐歌单"].contains(category) else { throw MusicProviderError.unsupported }
            return .init(playlists: offset == 0 ? try await PlatformMusicAPI.shared.recommendedPlaylists(limit: limit) : [], total: nil, more: false)
        }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(TopPlaylistResponse.self, "/playlist/list",
                        ["cat": category, "order": order, "limit": limit, "offset": offset, "total": true])
    }

    struct HighQualityResponse: Decodable {
        let playlists: [PlaylistSummary]
        let lasttime: Int?
        let more: Bool?
    }

    static func highQualityPlaylists(category: String = "全部", limit: Int = 50,
                                     before: Int = 0) async throws -> HighQualityResponse {
        if MusicProviderContext.shared.current != .netease { throw MusicProviderError.unsupported }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(HighQualityResponse.self, "/playlist/highquality/list",
                        ["cat": category, "limit": limit, "lasttime": before, "total": true])
    }

    struct ToplistResponse: Decodable {
        let list: [ToplistItem]
    }

    static func toplists() async throws -> [ToplistItem] {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.topLists() }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(ToplistResponse.self, "/toplist").list
    }

    struct PlaylistCreateResponse: Decodable {
        let code: Int
        let id: Int?
    }

    @discardableResult
    static func createPlaylist(name: String, isPrivate: Bool) async throws -> Int? {
        if MusicProviderContext.shared.current == .kugou { return try await PlatformMusicAPI.shared.createKugouPlaylist(name: name, isPrivate: isPrivate) }
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.createQQPlaylist(name: name, isPrivate: isPrivate) }
        if MusicProviderContext.shared.current == .qishui { return try await PlatformMusicAPI.shared.createQishuiPlaylist(name: name, isPrivate: isPrivate) }
        try MusicProviderContext.shared.requireNetease()
        let result = try await eapi(PlaylistCreateResponse.self, "/playlist/create",
                        ["name": name, "privacy": isPrivate ? 10 : 0, "type": "NORMAL"]).id
        await MainActor.run { SidebarResources.libraryChanged() }
        return result
    }

    static func deletePlaylist(id: Int) async throws {
        if MusicProviderContext.shared.current == .qq { try await PlatformMusicAPI.shared.deleteQQPlaylist(id: id); return }
        if MusicProviderContext.shared.current == .qishui { try await PlatformMusicAPI.shared.deleteQishuiPlaylist(id: id); return }
        if MusicProviderContext.shared.current == .kugou {
            try await PlatformMusicAPI.shared.deleteKugouPlaylist(id: id)
            await MainActor.run { SidebarResources.libraryChanged() }
            return
        }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        _ = try await eapi(CodeOnly.self, "/playlist/remove", ["ids": "[\(id)]"])
        await MainActor.run { SidebarResources.libraryChanged() }
    }

    static func subscribePlaylist(id: Int, subscribe: Bool) async throws {
        if MusicProviderContext.shared.current == .kugou { try await PlatformMusicAPI.shared.subscribeKugouPlaylist(id: id, subscribe: subscribe); return }
        if MusicProviderContext.shared.current == .qq { try await PlatformMusicAPI.shared.subscribeQQPlaylist(id: id, subscribe: subscribe); return }
        if MusicProviderContext.shared.current == .qishui { try await PlatformMusicAPI.shared.setQishuiCollection(.playlist, id: id, saved: subscribe); return }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        _ = try await eapi(CodeOnly.self, "/playlist/\(subscribe ? "subscribe" : "unsubscribe")", ["id": id])
        await MainActor.run { SidebarResources.libraryChanged() }
    }

    static func playlistTracks(op: String, playlistID: Int, trackIDs: [Int]) async throws {
        if MusicProviderContext.shared.current == .qq {
            guard op == "add" || op == "del" else { throw MusicProviderError.unsupported }
            try await PlatformMusicAPI.shared.updateQQPlaylistTracks(id: playlistID, trackIDs: trackIDs, adding: op == "add")
            return
        }
        if MusicProviderContext.shared.current == .qishui {
            guard op == "add" || op == "del" else { throw MusicProviderError.unsupported }
            try await PlatformMusicAPI.shared.updateQishuiPlaylistTracks(id: playlistID, trackIDs: trackIDs, adding: op == "add")
            await MainActor.run { SidebarResources.libraryChanged() }
            return
        }
        if MusicProviderContext.shared.current == .kugou {
            guard op == "add" || op == "del" else { throw MusicProviderError.unsupported }
            if op == "add" {
                try await PlatformMusicAPI.shared.addKugouPlaylistTracks(id: playlistID, trackIDs: trackIDs)
            } else {
                try await PlatformMusicAPI.shared.removeKugouPlaylistTracks(id: playlistID, trackIDs: trackIDs)
            }
            await MainActor.run { SidebarResources.libraryChanged() }
            return
        }
        try MusicProviderContext.shared.requireNetease()
        let ids = "[" + trackIDs.map(String.init).joined(separator: ",") + "]"
        let data = try await client.eapi("/playlist/manipulate/tracks",
                                          ["op": op, "pid": playlistID, "trackIds": ids, "imme": "true"])
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let code = obj["code"] as? Int, code != 200 {
            // 512: already-in-playlist quirk — retry with doubled ids like the reference impl
            if code == 512, op == "add" {
                let doubled = "[" + (trackIDs + trackIDs).map(String.init).joined(separator: ",") + "]"
                _ = try await client.eapi("/playlist/manipulate/tracks",
                                           ["op": op, "pid": playlistID, "trackIds": doubled, "imme": "true"])
                await MainActor.run { SidebarResources.libraryChanged() }
                return
            }
            throw NeteaseAPIError.business(code: code, message: obj["message"] as? String)
        }
        await MainActor.run { SidebarResources.libraryChanged() }
    }

    struct IntelligenceResponse: Decodable {
        struct Item: Decodable {
            let songInfo: Track?
            let id: Int?
        }

        let data: [Item]?
    }

    /// 心动模式 — generates a heartbeat-mode queue from a seed song in a playlist.
    static func intelligenceList(songID: Int, playlistID: Int) async throws -> [Track] {
        try MusicProviderContext.shared.requireNetease()
        let resp = try await eapi(IntelligenceResponse.self, "/playmode/intelligence/list",
                                   ["songId": songID, "type": "fromPlayOne",
                                    "playlistId": playlistID, "startMusicId": songID, "count": 1])
        return (resp.data ?? []).compactMap(\.songInfo)
    }

    // MARK: - Tracks

    /// Per-song source availability, from the same detail payload used by MeloX.
    /// A resource must have actual bytes/bitrate; null and empty objects do not
    /// create selectable tiers. Membership rights are enforced by the URL API.
    private struct SongQualityDetail: Decodable {
        let options: [AudioQualityOption]
        var qualities: [AudioQuality] { options.map(\.quality) }
        private struct Key: CodingKey {
            var stringValue: String
            var intValue: Int? { nil }
            init(_ value: String) { stringValue = value }
            init?(stringValue: String) { self.stringValue = stringValue }
            init?(intValue: Int) { return nil }
        }
        private struct Resource: Decodable { let br: Int?; let size: Int64?; let name: String?; let qualityName: String?; let type: String? }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            let fields: [(AudioQuality, String)] = [(.standard, "l"), (.higher, "m"),
                (.exhigh, "h"), (.lossless, "sq"), (.hires, "hr"),
                (.jyeffect, "je"), (.sky, "sk"), (.jymaster, "jm")]
            let durationMS = (try? container.decode(Double.self, forKey: Key("dt"))) ?? 0
            options = fields.compactMap { quality, field in
                guard let resource = try? container.decode(Resource.self, forKey: Key(field)),
                      (resource.br ?? 0) > 0 || (resource.size ?? 0) > 0 else { return nil }
                return AudioQualityOption(quality: quality, title: AudioQualityOption.unifiedTitle(
                    quality: quality, reportedBitrate: resource.br.map(Double.init),
                    byteCount: resource.size.map(Double.init), durationSeconds: durationMS / 1000))
            }
        }
    }

    static func songAudioQualityOptions(id: Int) async throws -> [AudioQualityOption] {
        if MusicProviderContext.shared.current != .netease {
            return try await PlatformMusicAPI.shared.songAudioQualityOptions(id: id)
        }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        struct Response: Decodable { let songs: [SongQualityDetail] }
        let c = "[{\"id\":\(id)}]"
        let ticket = MusicProviderContext.shared.ticket
        let options = try await eapi(Response.self, "/v3/song/detail", ["c": c]).songs.first?.options ?? []
        var checked = options.filter { ![.lossless, .hires].contains($0.quality) }
        for option in options where [.lossless, .hires].contains(option.quality) {
            let data = try? await songURL(ids: [id], level: option.quality.rawValue).first { $0.id == id }
            try Task.checkCancellation()
            try MusicProviderContext.shared.check(ticket)
            guard let data, data.url?.isEmpty == false, data.freeTrialInfo == nil,
                  data.code == nil || data.code == 200, let tier = data.resolvedAudioQuality else { continue }
            let bitrate = AudioQualityCheck.bitrateBPS(Double(data.br))
            checked.append(.init(quality: tier, title: bitrate == nil && tier == option.quality ? option.title
                : AudioQualityOption.unifiedTitle(quality: tier, bitrate: bitrate)))
        }
        return AudioQualityOption.unified(checked)
    }

    static func songAudioQualities(id: Int) async throws -> [AudioQuality] {
        if MusicProviderContext.shared.current != .netease {
            return try await PlatformMusicAPI.shared.songAudioQualities(id: id)
        }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        struct Response: Decodable { let songs: [SongQualityDetail] }
        let c = "[{\"id\":\(id)}]"
        return try await eapi(Response.self, "/v3/song/detail", ["c": c]).songs.first?.qualities ?? []
    }

    /// The playback endpoint can already return the best available resource for
    /// a higher request. Probe intermediate tiers only if they can improve it.
    static func preferredSongURL(id: Int, quality: AudioQuality, alwaysHighest: Bool,
                                 using client: NeteaseClient = .shared) async throws -> SongURLData? {
        let context = MusicProviderContext.shared
        let ticket = context.ticket
        if context.current != .netease { return try await PlatformMusicAPI.shared.songURLs(ids: [id], level: quality.rawValue).first }
        guard id > 0 else { throw MusicProviderError.missingTrack }
        let authentication = client.authenticationFingerprint
        let ranks = AudioQuality.allCases
        let basic: [AudioQuality] = [.hires, .lossless, .exhigh, .higher, .standard]
        let selectedRank = ranks.firstIndex(of: quality) ?? 0
        let candidates = alwaysHighest ? basic : [quality] + basic.filter { (ranks.firstIndex(of: $0) ?? 0) < selectedRank }
        var best: SongURLData?
        var bestRank = -1
        var lastError: Error?
        for candidate in candidates {
            try context.check(ticket)
            guard client.authenticationFingerprint == authentication else { throw CancellationError() }
            let candidateRank = ranks.firstIndex(of: candidate) ?? 0
            if best?.freeTrialInfo == nil, bestRank >= candidateRank { break }
            do {
                let results = try await songURL(ids: [id], level: candidate.rawValue, using: client)
                try context.check(ticket)
                guard client.authenticationFingerprint == authentication else { throw CancellationError() }
                let result = results.first { $0.id == id }
                let actual = result?.resolvedAudioQuality
                playbackLog.debug("id=\(id, privacy: .public) requested=\(candidate.rawValue, privacy: .public) returned=\(actual?.rawValue ?? "unknown", privacy: .public) code=\(result?.code ?? 0, privacy: .public) trial=\(result?.freeTrialInfo != nil, privacy: .public)")
                guard let result, result.code == nil || result.code == 200,
                      let address = result.url, let url = URL(string: address),
                      let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
                      url.host != nil else { continue }
                if result.freeTrialInfo != nil {
                    if best == nil { best = result }
                    continue
                }
                let rank = actual.flatMap { ranks.firstIndex(of: $0) } ?? -1
                if best == nil || best?.freeTrialInfo != nil || rank > bestRank {
                    best = result
                    bestRank = rank
                }
            } catch is CancellationError { throw CancellationError() }
            catch { lastError = error }
        }
        try context.check(ticket)
        guard client.authenticationFingerprint == authentication else { throw CancellationError() }
        if let best { return best }
        if let lastError { throw lastError }
        return nil
    }

    struct SongURLResponse: Decodable {
        let data: [SongURLData]
    }

    static func songURL(ids: [Int], level: String, using client: NeteaseClient = .shared) async throws -> [SongURLData] {
        let context = MusicProviderContext.shared
        let ticket = context.ticket
        if context.current != .netease { return try await PlatformMusicAPI.shared.songURLs(ids: ids, level: level) }
        let idString = "[" + ids.map(String.init).joined(separator: ",") + "]"
        var payload: [String: Any] = ["ids": idString, "level": level, "encodeType": "flac"]
        if level == "sky" { payload["immerseType"] = "c51" }
        let authentication = client.authenticationFingerprint
        func request(overrides: [String: String]) async throws -> [SongURLData] {
            try context.check(ticket)
            guard client.authenticationFingerprint == authentication else { throw CancellationError() }
            let data = try await client.eapi("/song/enhance/player/url/v1", payload, cookieOverrides: overrides)
            try context.check(ticket)
            guard client.authenticationFingerprint == authentication else { throw CancellationError() }
            let streams = try client.decoded(SongURLResponse.self, from: data).data
            var checked: [SongURLData] = []
            for stream in streams {
                var result = stream
                if let address = stream.url, stream.freeTrialInfo == nil,
                   let reported = stream.resolvedAudioQuality, [.lossless, .hires].contains(reported) {
                    let bitrate = AudioQualityCheck.bitrateBPS(Double(stream.br))
                    let codec = stream.type ?? ""
                    let verified: AudioQuality?
                    if AudioQualityCheck.isLossy(codec) {
                        verified = AudioQualityCheck.lossyTier(bitrate: bitrate) ?? .standard
                    } else {
                        verified = await client.playbackMediaTier(url: address, bitrate: bitrate)
                    }
                    if let verified {
                        result = stream.withQuality(verified)
                    } else if reported == .hires {
                        let fallback: AudioQuality? = AudioQualityCheck.isLossless(codec) ? .lossless : nil
                        result = stream.withQuality(fallback)
                    }
                }
                try Task.checkCancellation()
                try context.check(ticket)
                guard client.authenticationFingerprint == authentication else { throw CancellationError() }
                checked.append(result)
            }
            return checked
        }
        // The desktop profile intermittently returns -460 for playable tiers.
        // Keep the authenticated session and try the same tier on the other
        // profile before the resolver considers a downgrade.
        do {
            return try await request(overrides: ["os": "ios", "appver": "9.0.90",
                                                 "osver": "16.2", "channel": "distribution"])
        } catch NeteaseAPIError.business(code: -460, message: _) {
            playbackLog.notice("Retrying playback tier \(level, privacy: .public) after NetEase code -460")
            return try await request(overrides: [:])
        }
    }

    /// Download eligibility is resolved independently of the playback URL.
    /// An injectable client lets the compatibility probe use an isolated cookie
    /// jar without reading or changing the listener's current login.
    static func songDownloadResource(track: Track, level: String, accountScope: String,
                                     client: NeteaseClient = .shared) async throws -> OfflineAudioResource {
        if MusicProviderContext.shared.current == .kugou { return try await PlatformMusicAPI.shared.downloadResource(track: track, level: level, accountScope: accountScope) }
        try MusicProviderContext.shared.requireNetease()
        let data = try await songDownloadURL(id: track.id, level: level, client: client)
        return try downloadResource(data: data, track: track, accountScope: accountScope)
    }

    static func songDownloadURL(id: Int, level: String, client: NeteaseClient = .shared) async throws -> SongURLData {
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        struct Response: Decodable { let data: SongURLData? }
        let body = try await client.eapi("/song/enhance/download/url/v1",
                                         ["id": id, "level": level, "immerseType": "c51"])
        let response = try client.decoded(Response.self, from: body)
        guard let data = response.data else { throw OfflineAudioError.unavailable }
        return data
    }

    static func downloadResource(data: SongURLData, track: Track, accountScope: String) throws -> OfflineAudioResource {
        guard data.id == track.id, data.code == 200, data.freeTrialInfo == nil,
              let md5 = data.md5?.lowercased(), let quality = data.level,
              let format = data.type.flatMap({ OfflineAudioFormat(rawValue: $0.lowercased()) }),
              let rawURL = data.url, var components = URLComponents(string: rawURL),
              ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil else { throw OfflineAudioError.unavailable }
        components.scheme = "https"
        guard let url = components.url else { throw OfflineAudioError.invalidResource }
        // Some download responses omit time, and some songs (cloud drive,
        // simplified entries) omit dt. Whichever is known supplies the duration;
        // when both are, they must agree, which also rejects a trial URL.
        let responseDuration = data.time > 0 ? Double(data.time) / 1000 : 0
        if responseDuration > 0, track.duration > 0, abs(responseDuration - track.duration) > max(2, track.duration * 0.03) {
            throw OfflineAudioError.invalidAudio
        }
        let duration = track.duration > 0 ? track.duration : responseDuration
        guard duration > 0 else { throw OfflineAudioError.unavailable }
        let identity = OfflineAudioIdentity(accountScope: accountScope, trackID: track.id, source: "netease",
                                            quality: quality, format: format, contentMD5: md5)
        let descriptor = OfflineAudioDescriptor(identity: identity, byteCount: Int64(data.size), duration: duration)
        try descriptor.validate()
        return OfflineAudioResource(descriptor: descriptor, url: url)
    }

    /// Same EAPI route, parameters and fallback contract as MeloX's neteaseLyrics.
    static func lyric(id: Int, using client: NeteaseClient = .shared) async throws -> LyricResponse {
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        do {
            let data = try await client.lyricsEAPI("/song/lyric/v1", [
                "id": id, "cp": false, "tv": 0, "lv": 0, "rv": 0,
                "kv": 0, "yv": 0, "ytv": 0, "yrv": 0
            ])
            return try client.decoded(LyricResponse.self, from: data)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let data = try await client.lyricsEAPI("/song/lyric", [
                "id": id, "tv": -1, "lv": -1, "rv": -1, "kv": -1, "_nmclfl": 1
            ])
            return try client.decoded(LyricResponse.self, from: data)
        }
    }

    struct FMResponse: Decodable {
        let data: [Track]?
    }

    static func personalFM() async throws -> [Track] {
        if MusicProviderContext.shared.current != .netease {
            guard MusicProviderContext.shared.current.supports(.personalFM) else { throw MusicProviderError.unsupported }
            return try await PlatformMusicAPI.shared.recommendations(fm: true)
        }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(FMResponse.self, "/v1/radio/get").data ?? []
    }

    static func fmTrash(id: Int) async throws {
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        _ = try await eapi(CodeOnly.self, "/radio/trash/add",
                            ["alg": "RT", "songId": String(id), "time": "25"])
    }

    struct SimiSongResponse: Decodable {
        let songs: [Track]
    }

    static func similarSongs(id: Int, limit: Int = 30) async throws -> [Track] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.qqSimilarSongs(id: id, limit: limit) }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(SimiSongResponse.self, "/v1/discovery/simiSong",
                        ["songid": id, "limit": limit, "offset": 0]).songs
    }

    // MARK: - Albums

    static func album(id: Int) async throws -> AlbumDetailResponse {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.album(id: id) }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(AlbumDetailResponse.self, "/v1/album/\(id)")
    }

    struct NewAlbumsResponse: Decodable {
        let albums: [AlbumSummary]
    }

    static func newAlbums(area: String = "ALL", limit: Int = 30, offset: Int = 0) async throws -> [AlbumSummary] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.qqNewAlbums(limit: limit, offset: offset) }
        if MusicProviderContext.shared.current == .kugou { return try await PlatformMusicAPI.shared.kugouNewAlbums(limit: limit, offset: offset) }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(NewAlbumsResponse.self, "/album/new",
                        ["area": area, "limit": limit, "offset": offset, "total": true]).albums
    }

    struct AlbumDynamicResponse: Decodable {
        let isSub: Bool?
        let subCount: Int?
    }

    static func albumDynamic(id: Int) async throws -> AlbumDynamicResponse {
        if MusicProviderContext.shared.current == .qq {
            return .init(isSub: try await PlatformMusicAPI.shared.qqAlbumSubscribed(id: id), subCount: nil)
        }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(AlbumDynamicResponse.self, "/album/detail/dynamic", ["id": id])
    }

    static func subscribeAlbum(id: Int, subscribe: Bool) async throws {
        if MusicProviderContext.shared.current == .qq { try await PlatformMusicAPI.shared.subscribeQQAlbum(id: id, subscribe: subscribe); return }
        if MusicProviderContext.shared.current == .qishui { try await PlatformMusicAPI.shared.setQishuiCollection(.album, id: id, saved: subscribe); return }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        _ = try await eapi(CodeOnly.self, "/album/\(subscribe ? "sub" : "unsub")", ["id": id])
        await MainActor.run { SidebarResources.libraryChanged() }
    }

    // MARK: - Artists

    struct ArtistResponse: Decodable {
        let artist: ArtistSummary
        let hotSongs: [Track]
    }

    static func artist(id: Int) async throws -> ArtistResponse {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.artist(id: id) }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(ArtistResponse.self, "/v1/artist/\(id)")
    }

    /// Other names Netease records for an artist: aliases ("Joe Hisaishi")
    /// and the translated name ("久石让"), used by lyric matching.
    static func artistAliases(id: Int) async throws -> [String] {
        struct Response: Decodable {
            struct Artist: Decodable {
                let alias: [String]?
                let trans: String?
                let transNames: [String]?
            }
            let artist: Artist
        }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        let artist = try await eapi(Response.self, "/v1/artist/\(id)").artist
        return (artist.alias ?? []) + [artist.trans].compactMap { $0 } + (artist.transNames ?? [])
    }

    struct ArtistAlbumsResponse: Decodable {
        let hotAlbums: [AlbumSummary]
        let more: Bool?
    }

    static func artistAlbums(id: Int, limit: Int = 100, offset: Int = 0) async throws -> ArtistAlbumsResponse {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.artistAlbums(id: id, limit: limit, offset: offset) }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(ArtistAlbumsResponse.self, "/artist/albums/\(id)",
                        ["limit": limit, "offset": offset, "total": true])
    }

    static func artistSubscriptionParameters(id: Int) -> [String: String] {
        // Match the web client's string-valued form parameters for this endpoint.
        ["artistId": String(id), "artistIds": "[\(id)]"]
    }

    static func subscribeArtist(id: Int, subscribe: Bool, using client: NeteaseClient = .shared) async throws {
        if MusicProviderContext.shared.current == .qq { try await PlatformMusicAPI.shared.followQQArtist(id: id, follow: subscribe); return }
        if MusicProviderContext.shared.current == .qishui { try await PlatformMusicAPI.shared.setQishuiCollection(.artist, id: id, saved: subscribe); return }
        if MusicProviderContext.shared.current == .kugou { try await PlatformMusicAPI.shared.followKugouArtist(id: id, follow: subscribe); return }
        try MusicProviderContext.shared.requireNetease()
        guard client.isLoggedIn else { throw NeteaseAPIError.needLogin }
        guard id > 0 else {
            throw NeteaseAPIError.business(code: -1, message: String(localized: "歌手信息无效，请重新打开页面"))
        }
        // EAPI following is rejected with -460. Keep the web profile for both operations.
        let data = try await client.api("/artist/\(subscribe ? "sub" : "unsub")",
                                          artistSubscriptionParameters(id: id), cookieOverrides: ["os": "web"])
        _ = try client.decoded(CodeOnly.self, from: data)
        if client === NeteaseClient.shared { await MainActor.run { SidebarResources.libraryChanged() } }
    }

    struct ToplistArtistResponse: Decodable {
        struct Body: Decodable {
            let artists: [ArtistSummary]
        }

        let list: Body
    }

    static func topArtists(limit: Int = 100) async throws -> [ArtistSummary] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.qqSingers(limit: limit) }
        if MusicProviderContext.shared.current == .kugou { return try await PlatformMusicAPI.shared.kugouSingers(limit: limit) }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(ToplistArtistResponse.self, "/toplist/artist",
                        ["type": 1, "limit": limit, "offset": 0, "total": true]).list.artists
    }

    struct SimiArtistResponse: Decodable {
        let artists: [ArtistSummary]
    }

    static func similarArtists(id: Int) async throws -> [ArtistSummary] {
        if MusicProviderContext.shared.current == .qq { return try await PlatformMusicAPI.shared.qqSimilarArtists(id: id) }
        try MusicProviderContext.shared.requireNetease()
        guard id > 0 else { throw MusicProviderError.missingTrack }
        return try await eapi(SimiArtistResponse.self, "/discovery/simiArtist", ["artistid": id]).artists
    }

    // MARK: - Search

    enum SearchType: Int {
        case songs = 1
        case albums = 10
        case artists = 100
        case playlists = 1000
    }

    struct SearchResult: Decodable {
        let songs: [Track]?
        let albums: [AlbumSummary]?
        let artists: [ArtistSummary]?
        let playlists: [PlaylistSummary]?
        let songCount: Int?
        let albumCount: Int?
        let artistCount: Int?
        let playlistCount: Int?
    }

    struct SearchResponse: Decodable {
        let result: SearchResult?
    }

    static func search(_ keywords: String, type: SearchType,
                       limit: Int = 30, offset: Int = 0) async throws -> SearchResult {
        if MusicProviderContext.shared.current != .netease { return try await PlatformMusicAPI.shared.search(keywords, type: type, limit: limit, offset: offset) }
        try MusicProviderContext.shared.requireNetease()
        let resp = try await eapi(SearchResponse.self, "/cloudsearch/pc",
                                  ["s": keywords, "type": type.rawValue,
                                   "limit": limit, "offset": offset, "total": true])
        return resp.result ?? SearchResult(songs: nil, albums: nil, artists: nil, playlists: nil,
                                           songCount: nil, albumCount: nil, artistCount: nil, playlistCount: nil)
    }

    struct SearchSuggestResponse: Decodable {
        struct Body: Decodable {
            let songs: [Track]?
            let artists: [ArtistSummary]?
            let albums: [AlbumSummary]?
            let playlists: [PlaylistSummary]?
        }

        let result: Body?
    }

    static func searchSuggest(_ keywords: String) async throws -> SearchSuggestResponse.Body? {
        if MusicProviderContext.shared.current != .netease { return nil }
        try MusicProviderContext.shared.requireNetease()
        return try await eapi(SearchSuggestResponse.self, "/search/suggest/web", ["s": keywords]).result
    }

    struct SearchDefaultResponse: Decodable {
        struct Body: Decodable {
            let showKeyword: String?
            let realkeyword: String?
        }

        let data: Body?
    }

    static func searchDefaultKeyword() async throws -> String? {
        if MusicProviderContext.shared.current != .netease { return nil }
        try MusicProviderContext.shared.requireNetease()
        let body = try await eapi(SearchDefaultResponse.self, "/search/defaultkeyword/get").data
        // showKeyword is decorated hint text ("大家都在搜 …"); realkeyword is the query.
        return [body?.realkeyword, body?.showKeyword]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    // MARK: - Personalized extras

}
