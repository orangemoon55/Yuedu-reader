import Foundation

/// Basic tiers every platform understands; the NetEase-only effects map to Hi-Res.
private func basicQuality(_ quality: AudioQuality) -> AudioQuality {
    switch quality {
    case .standard, .higher, .exhigh, .lossless, .hires: return quality
    case .jyeffect, .sky, .jymaster: return .hires
    }
}

private func providerQuality(_ quality: AudioQuality) -> ProviderAudioQuality {
    ProviderAudioQuality(rawValue: basicQuality(quality).rawValue) ?? .hires
}

private func candidates(_ songs: [ProviderSong]) -> [UnblockCandidate<ProviderSong>] {
    songs.map {
        UnblockCandidate(title: $0.name, artist: $0.artists, album: $0.album,
                         durationMS: Int($0.duration * 1000), payload: $0)
    }
}

/// Asks a source for each tier and keeps the distinct tiers it actually serves.
private func probeTiers(_ source: any UnblockSource, _ query: UnblockQuery,
                        _ tiers: [AudioQuality]) async -> [AudioQualityOption] {
    var options: [AudioQualityOption] = []
    for tier in tiers {
        guard let stream = try? await source.resolve(query, quality: tier), let served = stream.quality,
              !options.contains(where: { $0.quality == served }) else { continue }
        options.append(.init(quality: served, title: stream.title ?? AudioQualityOption.unifiedTitle(quality: served)))
    }
    return options
}

/// The matched song per source, so playback, tier switches and the quality
/// menu search each platform once.
actor UnblockMatchCache {
    static let shared = UnblockMatchCache()
    private static let lifetime: TimeInterval = 10 * 60

    private struct Key: Hashable {
        let source: AudioSourceID
        let query: UnblockQuery
    }

    private var entries: [Key: (expiry: Date, song: ProviderSong?)] = [:]

    func song(_ source: AudioSourceID, _ query: UnblockQuery,
              search: @Sendable () async throws -> [ProviderSong]) async throws -> ProviderSong? {
        let key = Key(source: source, query: query)
        let now = Date()
        if let entry = entries[key], entry.expiry > now { return entry.song }
        let song = AudioSourceTrackMatcher.best(query, in: candidates(try await search()))
        if entries.count > 300 { entries = entries.filter { $0.value.expiry > now } }
        entries[key] = (now.addingTimeInterval(Self.lifetime), song)
        return song
    }
}

// MARK: - NetEase song lookup

/// Finds the NetEase song ID of a track from another platform. Shared by the
/// mirror and NetEase sources so one gray track searches NetEase only once.
actor NeteaseSongLookup {
    static let shared = NeteaseSongLookup()
    private static let lifetime: TimeInterval = 10 * 60

    private var entries: [UnblockQuery: (expiry: Date, task: Task<Int?, Error>)] = [:]

    func songID(for query: UnblockQuery) async throws -> Int? {
        if let id = query.neteaseID { return id }
        let now = Date()
        entries = entries.filter { $0.value.expiry > now }
        let task: Task<Int?, Error>
        if let entry = entries[query] {
            task = entry.task
        } else {
            task = Task { try await Self.search(query) }
            entries[query] = (now.addingTimeInterval(Self.lifetime), task)
        }
        do {
            return try await task.value
        } catch {
            // Errors are transient; only a definite answer is remembered.
            entries[query] = nil
            throw error
        }
    }

    private static func search(_ query: UnblockQuery) async throws -> Int? {
        let client = await UnblockSessionPool.shared.neteaseClient()
        let data = try await client.eapi("/cloudsearch/pc", [
            "s": query.keyword, "type": NeteaseAPI.SearchType.songs.rawValue,
            "limit": 10, "offset": 0, "total": true,
        ])
        let songs = try client.decoded(NeteaseAPI.SearchResponse.self, from: data).result?.songs ?? []
        return AudioSourceTrackMatcher.best(query, in: songs.map {
            UnblockCandidate(title: $0.name, artist: $0.artistNames, album: $0.album.name,
                             durationMS: $0.durationMS, payload: $0.id)
        })
    }
}

// MARK: - Mirror

struct MirrorUnblockSource: UnblockSource {
    let id = AudioSourceID.mirror
    private let httpClient: AudioSourceClient

    init(httpClient: AudioSourceClient = .shared) {
        self.httpClient = httpClient
    }

    func isAvailable() async -> Bool { true }
    func isSignedIn() async -> Bool { false }

    /// The mirror's `br` tiers: 128/192/320 kbps MP3, 740/999 the best FLAC it has.
    static func requestedBitrate(for quality: AudioQuality) -> Int {
        switch basicQuality(quality) {
        case .standard: return 128
        case .higher: return 192
        case .exhigh: return 320
        default: return 999
        }
    }

    func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream? {
        guard let songID = try await NeteaseSongLookup.shared.songID(for: query) else { return nil }
        let data = try await httpClient.data(
            from: "https://music-api.gdstudio.xyz/api.php?types=url&source=netease&id=\(songID)&br=\(Self.requestedBitrate(for: quality))",
            source: id,
            operation: "resolve"
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw AudioSourceProviderError.invalidResponse
        }
        guard let bitrate = object["br"] as? Int, bitrate > 0 else {
            throw AudioSourceProviderError.missingBitrate
        }
        guard let address = object["url"] as? String, !address.isEmpty else {
            throw AudioSourceProviderError.missingStreamURL
        }
        let secureAddress = address.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: secureAddress) else {
            throw AudioSourceProviderError.invalidURL
        }
        let served = await Self.tier(bitrateKbps: bitrate, address: secureAddress)
        let title = served.map {
            AudioQualityOption.unifiedTitle(quality: $0, reportedBitrate: Double(bitrate * 1000),
                                            byteCount: (object["size"] as? NSNumber)?.doubleValue,
                                            durationSeconds: Double(query.durationMS) / 1000)
        }
        return UnblockStream(url: url, quality: served, bitrate: bitrate * 1000, title: title)
    }

    func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption] {
        await probeTiers(self, query, [.standard, .higher, .exhigh, .lossless])
    }

    /// MP3 tiers follow the bitrate; above 320 kbps it is FLAC, whose header
    /// tells lossless from Hi-Res.
    static func tier(bitrateKbps: Int, address: String) async -> AudioQuality? {
        let bitrate = Double(bitrateKbps) * 1000
        guard bitrateKbps > 320 else { return AudioQualityCheck.lossyTier(bitrate: bitrate) }
        let client = await UnblockSessionPool.shared.neteaseClient()
        return await client.playbackMediaTier(url: address, bitrate: bitrate) ?? .lossless
    }
}

// MARK: - NetEase

struct NeteaseUnblockSource: UnblockSource {
    let id = AudioSourceID.netease

    func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption] {
        await probeTiers(self, query, [.standard, .higher, .exhigh, .lossless, .hires])
    }

    func isAvailable() async -> Bool { true }
    func isSignedIn() async -> Bool { await UnblockSessionPool.shared.hasAccount(.netease) }

    func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream? {
        guard let songID = try await NeteaseSongLookup.shared.songID(for: query) else { return nil }
        let client = await UnblockSessionPool.shared.neteaseClient()
        let data = try await client.eapi("/song/enhance/player/url/v1", [
            "ids": "[\(songID)]", "level": basicQuality(quality).rawValue, "encodeType": "flac",
        ])
        let streams = try client.decoded(NeteaseAPI.SongURLResponse.self, from: data).data
        guard let stream = streams.first(where: { $0.id == songID }),
              stream.code == nil || stream.code == 200,
              stream.freeTrialInfo == nil,
              let address = stream.url
        else { return nil }
        let secureAddress = address.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: secureAddress) else { return nil }
        var served = stream.resolvedAudioQuality
        // NetEase sometimes labels CD-class FLAC as Hi-Res; the header decides.
        if let reported = served, [.lossless, .hires].contains(reported) {
            served = await client.playbackMediaTier(
                url: secureAddress, bitrate: AudioQualityCheck.bitrateBPS(Double(stream.br))) ?? reported
        }
        let title = served.map {
            AudioQualityOption.unifiedTitle(quality: $0, reportedBitrate: Double(stream.br),
                                            byteCount: Double(stream.size), durationSeconds: Double(stream.time) / 1000)
        }
        return UnblockStream(url: url, quality: served, bitrate: stream.br > 0 ? stream.br : nil, title: title)
    }
}

// MARK: - QQ Music

struct QQUnblockSource: UnblockSource {
    let id = AudioSourceID.qq

    func isAvailable() async -> Bool { true }
    func isSignedIn() async -> Bool { await UnblockSessionPool.shared.hasAccount(.qq) }

    func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream? {
        let api = await UnblockSessionPool.shared.qqAPI()
        guard let song = try await Self.match(query, api: api),
              let mid = song.qqMid,
              let result = try await api.songURLResult(songmid: mid, mediaMid: song.qqMediaMid,
                                                       quality: providerQuality(quality))
        else { return nil }
        guard let url = URL(string: result.url.replacingOccurrences(of: "http://", with: "https://")) else { return nil }
        // QQ reports file sizes, not bitrates; estimate like its own quality menu.
        let rates = (try? await api.averageBitrates(songmid: mid)) ?? [:]
        let title = result.quality.map {
            AudioQualityOption.unifiedTitle(quality: $0, bitrate: rates[result.br], estimated: true)
        }
        return UnblockStream(url: url, quality: result.quality, title: title)
    }

    /// The same tiers and estimates as QQ's own quality menu.
    func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption] {
        let api = await UnblockSessionPool.shared.qqAPI()
        guard let song = try await Self.match(query, api: api), let mid = song.qqMid else { return [] }
        let rates = (try? await api.averageBitrates(songmid: mid)) ?? [:]
        var options: [AudioQualityOption] = []
        for candidate: ProviderAudioQuality in [.standard, .exhigh, .lossless, .hires] {
            guard let result = try await api.songURLResult(songmid: mid, mediaMid: song.qqMediaMid, quality: candidate),
                  let served = result.quality, !options.contains(where: { $0.quality == served }) else { continue }
            options.append(.init(quality: served, title: AudioQualityOption.unifiedTitle(
                quality: served, bitrate: rates[result.br], estimated: true)))
        }
        return options
    }

    private static func match(_ query: UnblockQuery, api: QQMusicAPI) async throws -> ProviderSong? {
        try await UnblockMatchCache.shared.song(.qq, query) {
            try await api.searchSongs(keyword: query.keyword, limit: 10)
        }
    }
}

// MARK: - KuGou

struct KugouUnblockSource: UnblockSource {
    let id = AudioSourceID.kugou

    func isAvailable() async -> Bool { true }
    func isSignedIn() async -> Bool { await UnblockSessionPool.shared.hasAccount(.kugou) }

    func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream? {
        let api = await UnblockSessionPool.shared.kugouAPI()
        guard let song = try await Self.match(query, api: api),
              let result = try await api.songURLResult(song: song, quality: providerQuality(quality))
        else { return nil }
        // KuGou signs some CDN URLs over HTTP; keep the scheme it gave.
        guard let url = URL(string: result.url) else { return nil }
        let served = result.quality.flatMap { AudioQuality(rawValue: $0.rawValue) }
        return UnblockStream(url: url, quality: served,
                             title: result.title ?? served.map { AudioQualityOption.unifiedTitle(quality: $0) })
    }

    /// KuGou's own quality menu, unchanged.
    func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption] {
        let api = await UnblockSessionPool.shared.kugouAPI()
        guard let song = try await Self.match(query, api: api) else { return [] }
        return try await api.qualityOptions(song: song)
    }

    private static func match(_ query: UnblockQuery, api: KugouMusicAPI) async throws -> ProviderSong? {
        try await UnblockMatchCache.shared.song(.kugou, query) {
            try await api.searchSongs(keyword: query.keyword, limit: 10)
        }
    }
}

// MARK: - Qishui

/// Qishui downloads and decrypts the whole file before it can play, so it is
/// the slowest source and always tried last.
struct QishuiUnblockSource: UnblockSource {
    let id = AudioSourceID.qishui

    func isAvailable() async -> Bool { await UnblockSessionPool.shared.hasAccount(.qishui) }
    func isSignedIn() async -> Bool { await isAvailable() }

    func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream? {
        try await Self.resolve(query, quality: quality)
    }

    @MainActor
    private static func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream? {
        guard let api = UnblockSessionPool.shared.qishuiAPI(),
              let trackID = try await match(query, api: api)?.qishui?.trackID
        else { return nil }
        let resource: QishuiMusicAPI.PlaybackResource
        do {
            resource = try await api.playback(trackID: trackID, quality: basicQuality(quality))
        } catch QishuiError.previewOnly {
            return nil
        } catch QishuiError.unavailable {
            return nil
        }
        guard let url = URL(string: resource.url) else { return nil }
        let title = AudioQualityOption.unifiedTitle(
            quality: resource.level, reportedBitrate: resource.bitrate.map(Double.init),
            byteCount: Double(resource.size), durationSeconds: Double(resource.durationMS) / 1000)
        return UnblockStream(url: url, quality: resource.level, bitrate: resource.bitrate, title: title)
    }

    /// Qishui's stream list, titled like the other platforms.
    func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption] {
        try await Self.qualityOptions(query)
    }

    @MainActor
    private static func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption] {
        guard let api = UnblockSessionPool.shared.qishuiAPI(),
              let trackID = try await match(query, api: api)?.qishui?.trackID
        else { return [] }
        return try await api.playbackQualityOptions(trackID: trackID, unifiedNames: true)
    }

    @MainActor
    private static func match(_ query: UnblockQuery, api: QishuiMusicAPI) async throws -> ProviderSong? {
        try await UnblockMatchCache.shared.song(.qishui, query) {
            try await api.search(keyword: query.keyword, type: .songs, limit: 10, offset: 0).songs
        }
    }
}
