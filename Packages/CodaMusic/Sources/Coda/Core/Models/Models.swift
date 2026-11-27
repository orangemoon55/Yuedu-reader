import Foundation

// MARK: - User

struct UserProfile: Codable, Hashable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?
    let backgroundUrl: String?
    let signature: String?
    let vipType: Int

    private enum CodingKeys: String, CodingKey {
        case userId, nickname, avatarUrl, backgroundUrl, signature, vipType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = try c.decode(Int.self, forKey: .userId)
        nickname = (try? c.decode(String.self, forKey: .nickname)) ?? ""
        avatarUrl = try? c.decode(String.self, forKey: .avatarUrl)
        backgroundUrl = try? c.decode(String.self, forKey: .backgroundUrl)
        signature = try? c.decode(String.self, forKey: .signature)
        vipType = (try? c.decode(Int.self, forKey: .vipType)) ?? 0
    }
}

// MARK: - Playlist

struct PlaylistCreator: Codable, Hashable {
    let userId: Int
    let nickname: String
    let avatarUrl: String?

    private enum CodingKeys: String, CodingKey {
        case userId, nickname, avatarUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        userId = (try? c.decode(Int.self, forKey: .userId)) ?? 0
        nickname = (try? c.decode(String.self, forKey: .nickname)) ?? ""
        avatarUrl = try? c.decode(String.self, forKey: .avatarUrl)
    }
}

/// A playlist as it appears in grids and sidebars. Tolerates the several cover
/// field names and numeric types NetEase uses across endpoints.
struct PlaylistSummary: Codable, Hashable, Identifiable {
    let id: Int
    var name: String
    let coverURL: String?
    let playCount: Int
    let trackCount: Int
    let updateTime: Int?
    let copywriter: String?
    let creator: PlaylistCreator?
    let specialType: Int
    let privacy: Int
    let subscribed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, coverImgUrl, playCount, playcount, trackCount
        case copywriter, creator, specialType, privacy, subscribed, updateTime, tracks
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        coverURL = PlaylistCoverSource.firstValid([
            try? c.decode(String.self, forKey: .coverImgUrl),
            try? c.decode(String.self, forKey: .picUrl),
            (try? c.decode([Track].self, forKey: .tracks))?.first?.album.picUrl
        ])
        let count = (try? c.decode(Double.self, forKey: .playCount))
            ?? (try? c.decode(Double.self, forKey: .playcount)) ?? 0
        playCount = Int(count)
        trackCount = (try? c.decode(Int.self, forKey: .trackCount)) ?? 0
        updateTime = try? c.decode(Int.self, forKey: .updateTime)
        copywriter = try? c.decode(String.self, forKey: .copywriter)
        creator = try? c.decode(PlaylistCreator.self, forKey: .creator)
        specialType = (try? c.decode(Int.self, forKey: .specialType)) ?? 0
        privacy = (try? c.decode(Int.self, forKey: .privacy)) ?? 0
        subscribed = (try? c.decode(Bool.self, forKey: .subscribed)) ?? false
    }

    /// The auto-created "我喜欢的音乐" playlist.
    var isLikedSongsList: Bool { specialType == 5 }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(coverURL, forKey: .coverImgUrl)
        try c.encode(playCount, forKey: .playCount)
        try c.encode(trackCount, forKey: .trackCount)
        try c.encodeIfPresent(updateTime, forKey: .updateTime)
        try c.encodeIfPresent(copywriter, forKey: .copywriter)
        try c.encodeIfPresent(creator, forKey: .creator)
        try c.encode(specialType, forKey: .specialType)
        try c.encode(privacy, forKey: .privacy)
        try c.encode(subscribed, forKey: .subscribed)
    }
}

struct TrackIDRef: Codable, Hashable {
    let id: Int
    var lr: Int? = nil
    var ratio: Double? = nil
}

struct PlaylistDetail: Codable, Hashable {
    let id: Int
    var name: String
    let coverImgUrl: String?
    let creator: PlaylistCreator?
    let description: String?
    var trackCount: Int
    let playCount: Int
    let subscribedCount: Int
    var subscribed: Bool
    var trackIds: [TrackIDRef]
    var tracks: [Track]
    let specialType: Int
    let updateTime: Int
    var qishuiFeed: QishuiFeedState?

    private enum CodingKeys: String, CodingKey {
        case id, name, coverImgUrl, creator, description, trackCount, playCount
        case subscribedCount, subscribed, trackIds, tracks, specialType, updateTime, qishuiFeed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        coverImgUrl = try? c.decode(String.self, forKey: .coverImgUrl)
        creator = try? c.decode(PlaylistCreator.self, forKey: .creator)
        description = try? c.decode(String.self, forKey: .description)
        trackCount = (try? c.decode(Int.self, forKey: .trackCount)) ?? 0
        playCount = Int((try? c.decode(Double.self, forKey: .playCount)) ?? 0)
        subscribedCount = (try? c.decode(Int.self, forKey: .subscribedCount)) ?? 0
        subscribed = (try? c.decode(Bool.self, forKey: .subscribed)) ?? false
        trackIds = (try? c.decode([TrackIDRef].self, forKey: .trackIds)) ?? []
        tracks = (try? c.decode([Track].self, forKey: .tracks)) ?? []
        specialType = (try? c.decode(Int.self, forKey: .specialType)) ?? 0
        updateTime = (try? c.decode(Int.self, forKey: .updateTime)) ?? 0
        qishuiFeed = try c.decodeIfPresent(QishuiFeedState.self, forKey: .qishuiFeed)
    }

    var playSource: PlaySource {
        if let qishuiFeed { return .qishuiFeed(qishuiFeed, playlistID: id) }
        return .playlist(id)
    }

    /// Preserve playlist order even when hydrated song details arrive out of order.
    var firstTrack: Track? {
        if let firstID = trackIds.first?.id { return tracks.first { $0.id == firstID } }
        return tracks.first
    }

    var coverURL: String? {
        PlaylistCoverSource.firstValid([coverImgUrl, firstTrack?.album.picUrl])
    }

    init(summary: PlaylistSummary) {
        id = summary.id
        name = summary.name
        coverImgUrl = summary.coverURL
        creator = summary.creator
        description = summary.copywriter
        trackCount = summary.trackCount
        playCount = summary.playCount
        subscribedCount = 0
        subscribed = summary.subscribed
        trackIds = []
        tracks = []
        specialType = summary.specialType
        updateTime = 0
    }
}

// MARK: - Album / Artist

struct AlbumSummary: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let artistName: String
    let publishTime: Int
    let size: Int
    let subType: String?
    let alias: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, cover, artist, artists, publishTime, size, subType, alia, alias
    }

    private struct ArtistName: Codable {
        let name: String?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = (try? c.decode(String.self, forKey: .picUrl))
            ?? (try? c.decode(String.self, forKey: .cover))
        if let artist = try? c.decode(ArtistName.self, forKey: .artist), let n = artist.name {
            artistName = n
        } else if let list = try? c.decode([ArtistName].self, forKey: .artists) {
            artistName = list.compactMap(\.name).joined(separator: " / ")
        } else {
            artistName = ""
        }
        publishTime = (try? c.decode(Int.self, forKey: .publishTime)) ?? 0
        size = (try? c.decode(Int.self, forKey: .size)) ?? 0
        subType = try? c.decode(String.self, forKey: .subType)
        alias = (try? c.decode([String].self, forKey: .alia))
            ?? (try? c.decode([String].self, forKey: .alias)) ?? []
    }

    var publishYear: String {
        guard publishTime > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(publishTime) / 1000)
        return String(Calendar.current.component(.year, from: date))
    }
}

struct AlbumDetailResponse: Decodable {
    let album: AlbumDetail
    let songs: [Track]
}

struct AlbumDetail: Decodable, Hashable {
    let id: Int
    let name: String
    let picUrl: String?
    let artist: ArtistSummary?
    let publishTime: Int
    let description: String?
    let company: String?
    let size: Int
    let subType: String?

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, artist, publishTime, description, company, size, subType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = try? c.decode(String.self, forKey: .picUrl)
        artist = try? c.decode(ArtistSummary.self, forKey: .artist)
        publishTime = (try? c.decode(Int.self, forKey: .publishTime)) ?? 0
        description = try? c.decode(String.self, forKey: .description)
        company = try? c.decode(String.self, forKey: .company)
        size = (try? c.decode(Int.self, forKey: .size)) ?? 0
        subType = try? c.decode(String.self, forKey: .subType)
    }
}

struct ArtistSummary: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let picUrl: String?
    let albumSize: Int
    let musicSize: Int
    let briefDesc: String?
    let alias: [String]
    let followed: Bool

    private enum CodingKeys: String, CodingKey {
        case id, name, picUrl, img1v1Url, cover, avatar, albumSize, musicSize, briefDesc, alias, followed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        picUrl = (try? c.decode(String.self, forKey: .picUrl))
            ?? (try? c.decode(String.self, forKey: .cover))
            ?? (try? c.decode(String.self, forKey: .avatar))
            ?? (try? c.decode(String.self, forKey: .img1v1Url))
        albumSize = (try? c.decode(Int.self, forKey: .albumSize)) ?? 0
        musicSize = (try? c.decode(Int.self, forKey: .musicSize)) ?? 0
        briefDesc = try? c.decode(String.self, forKey: .briefDesc)
        alias = (try? c.decode([String].self, forKey: .alias)) ?? []
        followed = (try? c.decode(Bool.self, forKey: .followed)) ?? false
    }
}

// MARK: - Toplist

struct ToplistItem: Decodable, Hashable, Identifiable {
    let id: Int
    let name: String
    let coverImgUrl: String?
    let updateFrequency: String?
    let tracks: [ToplistTrackPreview]
    let playCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, name, coverImgUrl, updateFrequency, tracks, playCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        coverImgUrl = try? c.decode(String.self, forKey: .coverImgUrl)
        updateFrequency = try? c.decode(String.self, forKey: .updateFrequency)
        tracks = (try? c.decode([ToplistTrackPreview].self, forKey: .tracks)) ?? []
        playCount = Int((try? c.decode(Double.self, forKey: .playCount)) ?? 0)
    }
}

struct ToplistTrackPreview: Codable, Hashable {
    let first: String
    let second: String
}

// MARK: - Lyrics

struct LyricResponse: Codable {
    struct LyricBody: Codable {
        let lyric: String?
    }

    let lrc: LyricBody?
    var tlyric: LyricBody?
    let romalrc: LyricBody?
    /// Word timing for karaoke: native YRC or normalized third-party QRC/KRC.
    /// Only present when the source provides word-by-word lyrics.
    let yrc: LyricBody?
    let ytlrc: LyricBody?
    let yromalrc: LyricBody?
    let lyricUser: LyricContributor?
    let transUser: LyricContributor?
    let nolyric: Bool?
    let uncollected: Bool?
    var pureMusic: Bool? = nil
}

struct LyricContributor: Codable {
    let nickname: String?
}

// MARK: - Song URL

struct SongURLData: Decodable, Hashable {
    let id: Int
    let url: String?
    let br: Int
    let size: Int
    let type: String?
    private(set) var level: String?
    let fee: Int
    let freeTrialInfo: FreeTrialInfo?
    let time: Int
    let code: Int?
    let md5: String?

    /// Some URL responses omit `level`; use the returned encoding/bitrate,
    /// never the requested preference, to label the stream in that case.
    var resolvedAudioQuality: AudioQuality? {
        if let level, let quality = AudioQuality(rawValue: level) { return quality }
        if let level, !level.isEmpty { return nil }
        if ["flac", "alac", "wav", "ape"].contains(type?.lowercased() ?? "") { return .lossless }
        guard br > 0 else { return nil }
        if br <= 128_000 { return .standard }
        if br <= 192_000 { return .higher }
        if br <= 320_000 { return .exhigh }
        return nil
    }

    func withQuality(_ quality: AudioQuality?) -> Self {
        var result = self
        result.level = quality?.rawValue
        return result
    }

    var qishuiQualityOption: AudioQualityOption? {
        guard let quality = resolvedAudioQuality else { return nil }
        return .qishui(quality: quality, bitrate: br, byteCount: size, durationMS: time)
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, br, size, type, level, fee, freeTrialInfo, time, code, md5
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(Int.self, forKey: .id)
        url = try? c.decode(String.self, forKey: .url)
        br = (try? c.decode(Int.self, forKey: .br)) ?? 0
        size = (try? c.decode(Int.self, forKey: .size)) ?? 0
        type = try? c.decode(String.self, forKey: .type)
        level = try? c.decode(String.self, forKey: .level)
        fee = (try? c.decode(Int.self, forKey: .fee)) ?? 0
        freeTrialInfo = try? c.decode(FreeTrialInfo.self, forKey: .freeTrialInfo)
        time = (try? c.decode(Int.self, forKey: .time)) ?? 0
        code = try? c.decode(Int.self, forKey: .code)
        md5 = try? c.decode(String.self, forKey: .md5)
    }
}

struct FreeTrialInfo: Codable, Hashable {
    let start: Int?
    let end: Int?
}

// MARK: - Cloud disk

/// A cloud-disk entry. The real payload nests metadata under `privateCloud`
/// and the playable track under `simpleSong`; older docs show flat fields,
/// so both shapes are tolerated.
struct CloudSongItem: Decodable, Hashable, Identifiable {
    let songId: Int
    let songName: String?
    let artist: String?
    let fileSize: Int
    let simpleSong: Track?

    var id: Int { songId }

    init(track: Track, fileSize: Int) {
        songId = track.id; songName = track.name; artist = track.artistNames
        self.fileSize = fileSize; simpleSong = track
    }

    private enum CodingKeys: String, CodingKey {
        case songId, songName, artist, fileSize, simpleSong, privateCloud
    }

    private struct PrivateCloud: Decodable {
        let songId: Int?
        let song: String?
        let artist: String?
        let fileSize: Int?
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try? c.decode(PrivateCloud.self, forKey: .privateCloud)
        simpleSong = try? c.decode(Track.self, forKey: .simpleSong)
        songId = (try? c.decode(Int.self, forKey: .songId))
            ?? nested?.songId ?? simpleSong?.id ?? 0
        songName = (try? c.decode(String.self, forKey: .songName))
            ?? nested?.song ?? simpleSong?.name
        artist = (try? c.decode(String.self, forKey: .artist)) ?? nested?.artist
        fileSize = (try? c.decode(Int.self, forKey: .fileSize)) ?? nested?.fileSize ?? 0
    }
}

// MARK: - Play record

struct PlayRecordItem: Decodable, Hashable {
    let playCount: Int
    let score: Int
    let song: Track

    init(song: Track, playCount: Int) {
        self.song = song; self.playCount = playCount; score = 0
    }

    private enum CodingKeys: String, CodingKey {
        case playCount, score, song
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        playCount = (try? c.decode(Int.self, forKey: .playCount)) ?? 0
        score = (try? c.decode(Int.self, forKey: .score)) ?? 0
        song = try c.decode(Track.self, forKey: .song)
    }
}

/// A song in the user's chronological recently-played history.
struct RecentSongPlayRecord: Decodable, Hashable, Identifiable {
    let song: Track
    let playedAt: Date

    init(song: Track, playedAt: Date) { self.song = song; self.playedAt = playedAt }

    var id: String { "\(song.id)-\(Int64(playedAt.timeIntervalSince1970 * 1_000))" }

    private enum CodingKeys: String, CodingKey {
        case data, playTime, resourceType
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        song = try c.decode(Track.self, forKey: .data)

        let rawTime = (try? c.decode(Double.self, forKey: .playTime))
            ?? Double((try? c.decode(String.self, forKey: .playTime)) ?? "")
            ?? 0
        // The API returns milliseconds, while tolerating seconds for older responses.
        playedAt = Date(timeIntervalSince1970: rawTime > 10_000_000_000 ? rawTime / 1_000 : rawTime)
    }
}

// MARK: - Formatting helpers

enum Formatters {
    private static var usesChineseUnits: Bool {
        Locale.current.language.languageCode?.identifier == "zh"
    }

    static func playCount(_ count: Int) -> String {
        if usesChineseUnits {
            switch count {
            case 100_000_000...:
                return String(format: "%.1f亿", Double(count) / 100_000_000)
            case 10_000...:
                return String(format: "%.1f万", Double(count) / 10_000)
            default:
                return String(count)
            }
        }
        switch count {
        case 1_000_000_000...:
            return String(format: "%.1fB", Double(count) / 1_000_000_000)
        case 1_000_000...:
            return String(format: "%.1fM", Double(count) / 1_000_000)
        case 10_000...:
            return String(format: "%.1fK", Double(count) / 1_000)
        default:
            return String(count)
        }
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }

    static func longDuration(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        if total >= 3600 {
            return String(localized: "\(total / 3600) 小时 \((total % 3600) / 60) 分钟")
        }
        return String(localized: "\(total / 60) 分钟")
    }

    static func date(fromMS ms: Int) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        return fmt.string(from: date)
    }
}

extension String {
    /// Resize the source CDN resource as well as bounding its local decode.
    /// Qishui covers and account avatars come from signed ByteDance CDNs;
    /// changing their query (NetEase's `param=`) invalidates the signature.
    static func isByteDanceImageHost(_ host: String) -> Bool {
        ["douyinpic.com", "byteimg.com", "byteacctimg.com", "douyincdn.com", "bytecdn.cn", "pstatp.com"]
            .contains { host == $0 || host.hasSuffix("." + $0) }
    }
    func resizedImageURL(_ size: Int) -> URL? {
        guard size > 0, var components = URLComponents(string: self) else { return nil }
        if components.scheme == "http" { components.scheme = "https" }
        let host = components.host?.lowercased() ?? ""
        if host == "kugou.com" || host.hasSuffix(".kugou.com") {
            var segments = components.path.components(separatedBy: "/")
            if segments.count > 3, ["stdmusic", "softhead", "custom"].contains(segments[1]), Int(segments[2]) != nil {
                segments[2] = String(size)
                components.path = segments.joined(separator: "/")
            }
            components.path = components.path.replacingOccurrences(of: "{size}", with: String(size))
        } else if host == "y.gtimg.cn" || host.hasSuffix(".qpic.cn") {
            // QQ CDN supports the original T00xM000 resource; bound the local
            // decode rather than asking for unsupported arbitrary R sizes.
            components.path = components.path.replacingOccurrences(
                of: #"(T00[12])R\d+x\d+(M000)"#, with: "$1$2", options: .regularExpression)
        }
        if Self.isByteDanceImageHost(host) {
            #if os(macOS)
            // Keep the CDN path and query intact; ImageCache uses the local
            // fragment to distinguish decoded sizes of the same response.
            components.fragment = "coda-image-pixels=\(size)"
            #endif
            return components.url
        }
        // NetEase's imageView pipeline embeds '=' inside query values.
        // Rebuilding queryItems escapes those separators and some covers
        // then return HTTP 400. Preserve the CDN pipeline byte for byte.
        var items = components.percentEncodedQuery?.components(separatedBy: "&").filter {
            $0.components(separatedBy: "=").first?.removingPercentEncoding != "param"
        } ?? []
        items.append("param=\(size)y\(size)")
        components.percentEncodedQuery = items.joined(separator: "&")
        return components.url
    }
}

extension URL {
    var localImagePixelLimit: Int? {
        let prefix = "coda-image-pixels="
        guard String.isByteDanceImageHost(host?.lowercased() ?? ""),
              let fragment, fragment.hasPrefix(prefix),
              let limit = Int(fragment.dropFirst(prefix.count)), limit > 0 else { return nil }
        return limit
    }

    var imageSourceURL: URL {
        guard localImagePixelLimit != nil,
              var components = URLComponents(url: self, resolvingAgainstBaseURL: false) else { return self }
        components.fragment = nil
        return components.url ?? self
    }
}


extension AlbumSummary {
    var isEPOrSingle: Bool {
        let type = subType?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if type.contains("ep") || type.contains("single") || type.contains("单曲") { return true }
        if type.contains("专辑") || type.contains("album") { return false }
        return size == 1
    }
}

/// Keep service wording separate from the internal cross-service quality key.
struct AudioQualityOption: Identifiable, Equatable {
    let quality: AudioQuality
    let title: String
    var id: String { quality.rawValue }

    static func qishuiLocal(url: URL, level: String?, duration: TimeInterval) -> Self? {
        guard let level, let quality = AudioQuality(rawValue: level),
              let measured = localBitrate(url: url, duration: duration) else { return nil }
        return .init(quality: quality, title: titled(quality.displayName, bitrate: measured.value, estimated: measured.estimated))
    }

    static func qishui(quality: AudioQuality, bitrate: Int?, byteCount: Int, durationMS: Int) -> Self {
        let measured = Self.bitrate(reported: bitrate.map(Double.init), byteCount: Double(byteCount),
                                    durationSeconds: Double(durationMS) / 1000)
        return .init(quality: quality, title: titled(quality.displayName, bitrate: measured?.value,
                                                     estimated: measured?.estimated ?? false))
    }

    /// A downloaded or cached file: the container's bitrate, else size ÷ duration.
    static func unifiedLocal(url: URL, quality: AudioQuality, duration: TimeInterval) -> Self {
        let measured = localBitrate(url: url, duration: duration)
        return .init(quality: quality, title: unifiedTitle(quality: quality, bitrate: measured?.value,
                                                           estimated: measured?.estimated ?? false))
    }

    private static func localBitrate(url: URL, duration: TimeInterval) -> (value: Double, estimated: Bool)? {
        guard url.isFileURL else { return nil }
        if let bitrate = AudioQualityCheck.localBitrate(url: url) { return (Double(bitrate), false) }
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Double.init)
        return bitrate(reported: nil, byteCount: bytes, durationSeconds: duration)
    }

    /// The reported bitrate when there is one, else an estimate from size and length.
    static func bitrate(reported: Double?, byteCount: Double?, durationSeconds: Double?) -> (value: Double, estimated: Bool)? {
        if let reported, reported.isFinite, reported > 0 { return (reported, false) }
        return estimatedBitrate(byteCount: byteCount, durationSeconds: durationSeconds).map { ($0, true) }
    }

    static func estimatedBitrate(byteCount: Double?, durationSeconds: Double?) -> Double? {
        guard let byteCount, let durationSeconds, byteCount.isFinite, durationSeconds.isFinite,
              byteCount > 0, durationSeconds > 0 else { return nil }
        let bitrate = byteCount * 8 / durationSeconds
        return bitrate.isFinite && bitrate > 0 ? bitrate : nil
    }

    /// The unified title from a reported bitrate, or one estimated from size and length.
    static func unifiedTitle(quality: AudioQuality, reportedBitrate: Double?,
                             byteCount: Double?, durationSeconds: Double?) -> String {
        let measured = bitrate(reported: reportedBitrate, byteCount: byteCount, durationSeconds: durationSeconds)
        return unifiedTitle(quality: quality, bitrate: measured?.value, estimated: measured?.estimated ?? false)
    }

    static func unifiedTitle(quality: AudioQuality, bitrate: Double? = nil, estimated: Bool = false) -> String {
        let name: String
        switch quality {
        case .standard: name = "标准"
        case .higher, .exhigh: name = "高品质"
        case .lossless: name = "无损"
        case .hires: name = "高解析度无损"
        default: return "音质"
        }
        return titled(name, bitrate: bitrate, estimated: estimated)
    }

    /// "名称 · 320 kbps"; an estimate reads "名称 · 约937.7 kbps".
    static func titled(_ name: String, bitrate: Double?, estimated: Bool) -> String {
        guard let bitrate, bitrate.isFinite, bitrate > 0 else { return name }
        let kbps = bitrate / 1000
        let rounded = String(format: "%.1f", kbps)
        let text = rounded.hasSuffix(".0") ? String(rounded.dropLast(2)) : rounded
        return "\(name) · \(estimated ? "约" : "")\(text) kbps"
    }

    static func unified(_ options: [AudioQualityOption]) -> [AudioQualityOption] {
        var result: [AudioQualityOption] = []
        for option in options.sorted(by: { (AudioQuality.allCases.firstIndex(of: $0.quality) ?? 0) < (AudioQuality.allCases.firstIndex(of: $1.quality) ?? 0) }) {
            guard [.standard, .higher, .exhigh, .lossless, .hires].contains(option.quality) else { continue }
            if option.quality == .exhigh { result.removeAll { $0.quality == .higher } }
            if !result.contains(where: { $0.quality == option.quality }) { result.append(option) }
        }
        return result
    }

    static func responseTitle(name: String?, format: String? = nil, bitrate: Int? = nil, fallback: String) -> String {
        if let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return name }
        var parts: [String] = []
        if let format, !format.isEmpty { parts.append(format) }
        if let bitrate, bitrate > 0 { parts.append("\(bitrate >= 1000 ? bitrate / 1000 : bitrate) kbps") }
        return parts.isEmpty ? fallback : parts.joined(separator: " · ")
    }
}
