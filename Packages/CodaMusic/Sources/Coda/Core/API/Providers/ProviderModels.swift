// Adapted from XIaodou0416/Beans-Music (MIT); see ThirdPartyNotices/Beans-Music.md.
import Foundation

/// 音质等级。
enum ProviderAudioQuality: String, CaseIterable, Identifiable {
    case standard
    case higher
    case exhigh
    case lossless
    case hires

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .standard: return providerLocalized("标准", "Standard")
        case .higher: return providerLocalized("较高", "Higher")
        case .exhigh: return providerLocalized("极高", "Very High")
        case .lossless: return providerLocalized("无损", "Lossless")
        case .hires: return "Hi-Res"
        }
    }

    /// 网易云 songURL 的 level 参数
    var level: String { rawValue }

    /// 当前官方播放音质（默认 Hi-Res；不可用时由各平台接口自行降级）。
    static var current: ProviderAudioQuality {
        let raw = Self.exhigh.rawValue
        return ProviderAudioQuality(rawValue: raw) ?? .hires
    }
}

/// 歌曲来源（网易云 / QQ音乐 / 酷狗音乐）
enum ProviderSongSource: String, Codable, Sendable {
    case netease
    case qq
    case kugou
    case qishui

    /// 兼容旧版本地收藏：未知或已下线来源统一回退为网易云
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = ProviderSongSource(rawValue: raw) ?? .netease
    }
}

struct KugouCloudReference: Hashable, Codable, Sendable {
    let ownerID: String
    let fileID: String
    let audioID: String
    let name: String
    let byteCount: Int64
}

struct ProviderSong: Identifiable, Hashable, Codable, Sendable {
    let id: Int
    let name: String
    let artists: String
    let album: String
    let coverURL: URL?
    let duration: TimeInterval
    /// 歌曲来源（网易云 / QQ音乐）
    let source: ProviderSongSource
    /// QQ 音乐 songmid（source == .qq 时用于获取播放地址与歌词）
    let qqMid: String?
    /// QQ 音乐音频文件 media_mid；部分歌曲与 songmid 不同，取 vkey 时必须优先使用
    let qqMediaMid: String?
    let qqAlbumMID: String?
    let qqArtistReferences: [ProviderArtist]?
    /// 酷狗音乐文件 hash 与专辑音频 id（source == .kugou 时用于获取播放地址与歌词）
    let kugouHash: String?
    let kugouAlbumAudioId: String?
    /// Account history/CSCC identifier. Search can return AlbumAudioID and
    /// MixSongID together; playback resource handles are not reporting IDs.
    let kugouMixSongID: String?
    let kugouAlbumId: String?
    let kugouQualityHashes: [String: String]?
    let qishui: QishuiTrackReference?
    let kugouCloud: KugouCloudReference?
    /// 付费/VIP 标记（网易云：0 免费、1 VIP、4 付费单曲；QQ：0 免费、非 0 付费）
    let fee: Int

    /// 跨平台唯一标识（避免网易云与 QQ 音乐歌曲 id 撞车）
    var identityKey: String {
        switch source {
        case .qq: return "qq-\(qqMid ?? String(id))"
        case .qishui: return "qishui-\(qishui?.trackID ?? String(id))"
        case .kugou: return "kugou-\(id)"
        case .netease: return "netease-\(id)"
        }
    }

    init(id: Int, name: String, artists: String, album: String, coverURL: URL?, duration: TimeInterval, source: ProviderSongSource = .netease, qqMid: String? = nil, qqMediaMid: String? = nil, qqAlbumMID: String? = nil, qqArtistReferences: [ProviderArtist]? = nil, kugouHash: String? = nil, kugouAlbumAudioId: String? = nil, kugouMixSongID: String? = nil, kugouAlbumId: String? = nil, kugouQualityHashes: [String: String]? = nil, kugouCloud: KugouCloudReference? = nil, qishui: QishuiTrackReference? = nil, fee: Int = 0) {
        self.id = id
        self.name = name
        self.artists = artists
        self.album = album
        self.coverURL = coverURL
        self.duration = duration
        self.source = source
        self.qqMid = qqMid
        self.qqMediaMid = qqMediaMid
        self.qqAlbumMID = qqAlbumMID
        self.qqArtistReferences = qqArtistReferences
        self.kugouHash = kugouHash
        self.kugouAlbumAudioId = kugouAlbumAudioId
        self.kugouMixSongID = kugouMixSongID
        self.kugouAlbumId = kugouAlbumId
        self.kugouQualityHashes = kugouQualityHashes
        self.qishui = qishui
        self.kugouCloud = kugouCloud
        self.fee = fee
    }

    init?(json: [String: Any]) {
        qishui = nil
        kugouCloud = nil
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        let artistsArray = json["artists"] as? [[String: Any]] ?? (json["ar"] as? [[String: Any]]) ?? []
        artists = artistsArray.compactMap { $0["name"] as? String }.joined(separator: " / ")
        if let albumDict = json["album"] as? [String: Any] {
            album = albumDict["name"] as? String ?? ""
            let pic = albumDict["picUrl"] as? String ?? (albumDict["blurPicUrl"] as? String ?? "")
            coverURL = pic.isEmpty ? nil : URL(string: pic)
        } else if let al = json["al"] as? [String: Any] {
            album = al["name"] as? String ?? ""
            let pic = al["picUrl"] as? String ?? ""
            coverURL = pic.isEmpty ? nil : URL(string: pic)
        } else {
            album = ""
            coverURL = nil
        }
        let ms = json["duration"] as? Int ?? (json["dt"] as? Int) ?? 0
        duration = Double(ms) / 1000.0
        source = .netease
        qqMid = nil
        qqMediaMid = nil
        qqAlbumMID = nil
        qqArtistReferences = nil
        kugouHash = nil
        kugouAlbumAudioId = nil
        kugouMixSongID = nil
        kugouAlbumId = nil
        kugouQualityHashes = nil
        fee = json["fee"] as? Int ?? 0
    }

    private enum CodingKeys: String, CodingKey { case id, name, artists, album, coverURL, duration, source, qqMid, qqMediaMid, qqAlbumMID, qqArtistReferences, kugouHash, kugouAlbumAudioId, kugouMixSongID, kugouAlbumId, kugouQualityHashes, kugouCloud, qishui, fee }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        artists = try c.decodeIfPresent(String.self, forKey: .artists) ?? ""
        album = try c.decodeIfPresent(String.self, forKey: .album) ?? ""
        coverURL = try c.decodeIfPresent(URL.self, forKey: .coverURL)
        duration = try c.decodeIfPresent(TimeInterval.self, forKey: .duration) ?? 0
        source = try c.decodeIfPresent(ProviderSongSource.self, forKey: .source) ?? .netease
        qqMid = try c.decodeIfPresent(String.self, forKey: .qqMid)
        qqMediaMid = try c.decodeIfPresent(String.self, forKey: .qqMediaMid)
        qqAlbumMID = try c.decodeIfPresent(String.self, forKey: .qqAlbumMID)
        qqArtistReferences = try c.decodeIfPresent([ProviderArtist].self, forKey: .qqArtistReferences)
        kugouHash = try c.decodeIfPresent(String.self, forKey: .kugouHash)
        kugouAlbumAudioId = try c.decodeIfPresent(String.self, forKey: .kugouAlbumAudioId)
        kugouMixSongID = try c.decodeIfPresent(String.self, forKey: .kugouMixSongID)
        kugouAlbumId = try c.decodeIfPresent(String.self, forKey: .kugouAlbumId)
        kugouQualityHashes = try c.decodeIfPresent([String: String].self, forKey: .kugouQualityHashes)
        qishui = try c.decodeIfPresent(QishuiTrackReference.self, forKey: .qishui)
        kugouCloud = try c.decodeIfPresent(KugouCloudReference.self, forKey: .kugouCloud)
        fee = try c.decodeIfPresent(Int.self, forKey: .fee) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(artists, forKey: .artists)
        try c.encode(album, forKey: .album)
        try c.encodeIfPresent(coverURL, forKey: .coverURL)
        try c.encode(duration, forKey: .duration)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(qqMid, forKey: .qqMid)
        try c.encodeIfPresent(qqMediaMid, forKey: .qqMediaMid)
        try c.encodeIfPresent(qqAlbumMID, forKey: .qqAlbumMID)
        try c.encodeIfPresent(qqArtistReferences, forKey: .qqArtistReferences)
        try c.encodeIfPresent(kugouHash, forKey: .kugouHash)
        try c.encodeIfPresent(kugouAlbumAudioId, forKey: .kugouAlbumAudioId)
        try c.encodeIfPresent(kugouMixSongID, forKey: .kugouMixSongID)
        try c.encodeIfPresent(kugouAlbumId, forKey: .kugouAlbumId)
        try c.encodeIfPresent(kugouQualityHashes, forKey: .kugouQualityHashes)
        try c.encodeIfPresent(qishui, forKey: .qishui)
        try c.encodeIfPresent(kugouCloud, forKey: .kugouCloud)
        try c.encode(fee, forKey: .fee)
    }
}

/// 歌手搜索结果（网易云 / QQ音乐通用）
struct ProviderArtist: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let coverURL: URL?
    let source: ProviderSongSource
}

/// 专辑搜索结果（网易云 / QQ音乐通用）
struct ProviderAlbum: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let name: String
    let artistName: String
    let coverURL: URL?
    let source: ProviderSongSource
    var trackCount: Int?
    var releaseType: String? = nil
    var releaseDateMS: Int? = nil
}

struct ProviderPlaylist: Identifiable, Hashable, Codable, Sendable {
    var qqDirectoryID: Int? = nil
    var isQQRadio: Bool? = nil
    var qishui: QishuiPlaylistReference? = nil
    // Cloud-list IDs belong to an account; public collection IDs identify the source.
    var kugouGlobalCollectionID: String? = nil
    var kugouCreateUserID: String? = nil
    var kugouCreateListID: String? = nil
    var kugouCreateGID: String? = nil
    /// Sent back unchanged by modify_list, which rewrites every listed field.
    var kugouIntro: String? = nil
    var kugouTags: String? = nil
    var kugouSort: Int? = nil
    var ownerID: String? = nil
    var isOwned: Bool? = nil
    var isSubscribed: Bool? = nil
    let id: Int
    var name: String
    var coverURL: URL?
    let trackCount: Int
    let creatorName: String
    let specialType: Int
    /// 歌单来源（网易云 / QQ音乐），非网易云歌单用对应接口加载
    let source: ProviderSongSource

    init(id: Int, name: String, coverURL: URL?, trackCount: Int = 0, source: ProviderSongSource = .netease) {
        self.id = id
        self.name = name
        self.coverURL = coverURL
        self.trackCount = trackCount
        self.creatorName = ""
        self.specialType = 0
        self.source = source
    }

    init?(json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        trackCount = json["trackCount"] as? Int ?? 0
        let pic = json["coverImgUrl"] as? String ?? json["picUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        creatorName = (json["creator"] as? [String: Any])?["nickname"] as? String ?? ""
        specialType = json["specialType"] as? Int ?? 0
        source = .netease
    }

    init?(personalizedJSON json: [String: Any]) {
        guard let id = json["id"] as? Int else { return nil }
        self.id = id
        name = json["name"] as? String ?? ""
        trackCount = 0
        let pic = json["picUrl"] as? String ?? ""
        coverURL = pic.isEmpty ? nil : URL(string: pic)
        creatorName = ""
        specialType = json["specialType"] as? Int ?? 0
        source = .netease
    }

}

/// QQ 峰尖榜总览项
struct QQTopInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let subTitle: String
    let topSongNames: [String]
    let coverURL: URL?
}

/// 酷狗官方排行榜总览项
struct KugouTopInfo: Identifiable, Hashable {
    let id: Int
    let name: String
    let updateFrequency: String
    let coverURL: URL?
}

// MARK: - 歌曲评论

struct ProviderSongComment: Identifiable, Hashable {
    let id: Int
    let content: String
    let nickname: String
    let avatarURL: URL?
    let time: Date
    let likedCount: Int
    let isHot: Bool

    init(id: Int, content: String, nickname: String, avatarURL: URL?, time: Date, likedCount: Int, isHot: Bool = false) {
        self.id = id
        self.content = content
        self.nickname = nickname
        self.avatarURL = avatarURL
        self.time = time
        self.likedCount = likedCount
        self.isHot = isHot
    }

    init?(json: [String: Any], isHot: Bool = false) {
        guard let id = json["commentId"] as? Int else { return nil }
        self.id = id
        content = json["content"] as? String ?? ""
        let user = json["user"] as? [String: Any]
        nickname = user?["nickname"] as? String ?? ""
        let avatar = user?["avatarUrl"] as? String ?? ""
        avatarURL = avatar.isEmpty ? nil : URL(string: avatar)
        let ms = json["time"] as? Int ?? 0
        time = Date(timeIntervalSince1970: Double(ms) / 1000.0)
        likedCount = json["likedCount"] as? Int ?? 0
        self.isHot = isHot
    }
}

struct QQMusicCatalogOption: Identifiable, Hashable {
    let id: Int
    let name: String
}

struct QQMusicRecommendationMode: Identifiable, Hashable {
    let id: String
    let name: String
    let poolID: String?

    /// QQ's own "guess you like" radio, played when no scene pool is chosen.
    static let guessYouLike = Self(id: "guess-you-like", name: String(localized: "猜你喜欢"), poolID: nil)
}
