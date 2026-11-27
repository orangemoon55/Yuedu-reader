import CryptoKit
import Foundation

/// Converts vendor models at the API boundary. Stable negative IDs keep all
/// existing queues, caches and offline files separate from NetEase's IDs.
@MainActor
final class PlatformMusicAPI {
    static let shared = PlatformMusicAPI()
    struct Catalog: Codable, Sendable {
        var songs: [Int: ProviderSong] = [:]
        var playlists: [Int: ProviderPlaylist] = [:]
        var artists: [Int: ProviderArtist] = [:]
        var albums: [Int: ProviderAlbum] = [:]
        var charts: Set<Int> = []
        var pendingCreated: [Int: ProviderPlaylist]? = nil
        var pendingDeleted: [String: Set<Int>]? = nil
    }
    private let url = CodaPaths.applicationSupport.appendingPathComponent("platform-catalog.json")
    private var loadedCatalog: Catalog?
    private var catalogLoad: Task<Catalog, Never>?
    private let catalogWriter = DispatchQueue(label: "wow.caicai.coda.platform-catalog", qos: .utility)
    private var saveTask: Task<Void, Never>?
    private var saveAfter: ContinuousClock.Instant = .now
    private var qqFMAccount: String?
    private var qqFMPage = 1
    private var qqFMRequest: UUID?
    private var qqFMScene: QQMusicRecommendationMode?
    private var qqFMRecentIDs: [Int] = []
    private init() {}

    /// `scene` switches FM from the radar feed to one of QQ's listening modes.
    func resetQQFM(scene: QQMusicRecommendationMode? = nil) {
        qqFMPage = 1
        qqFMRequest = nil
        qqFMScene = scene
        qqFMRecentIDs = []
    }

    private nonisolated static func readCatalog(at url: URL) -> Catalog {
        guard let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode(Catalog.self, from: data) else { return Catalog() }
        return saved
    }

    private func prepareCatalog() async {
        guard loadedCatalog == nil else { return }
        let load = catalogLoad ?? Task.detached(priority: .utility) { [url] in Self.readCatalog(at: url) }
        catalogLoad = load
        let saved = await load.value
        // Synchronous playback restoration may already have loaded and updated it.
        if loadedCatalog == nil { loadedCatalog = saved }
        catalogLoad = nil
    }

    private var catalog: Catalog {
        get {
            if loadedCatalog == nil { loadedCatalog = Self.readCatalog(at: url) }
            return loadedCatalog!
        }
        _modify {
            if loadedCatalog == nil { loadedCatalog = Self.readCatalog(at: url) }
            yield &loadedCatalog!
        }
    }
    nonisolated static func identifier(provider: MusicProvider, kind: String, value: String) -> Int {
        let digest = SHA256.hash(data: Data("\(provider.rawValue):\(kind):\(value)".utf8))
        let number = digest.prefix(7).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        return -Int(number + 1)
    }
    var provider: MusicProvider { MusicProviderContext.shared.current }
    private func source(_ source: ProviderSongSource) -> MusicProvider { MusicProvider(rawValue: source.rawValue) ?? .netease }
    private func persist() {
        saveAfter = .now + .milliseconds(500)
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            guard let self else { return }
            repeat {
                do { try await Task.sleep(until: self.saveAfter, clock: .continuous) }
                catch { self.saveTask = nil; return }
            } while ContinuousClock.now < self.saveAfter
            self.saveTask = nil
            // Capture the value on the main actor and write snapshots in order.
            self.catalogWriter.async { [url = self.url, snapshot = self.catalog] in
                do {
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
                } catch { /* Metadata can be rehydrated from a Track or the next service response. */ }
            }
        }
    }
    static func decode<T: Decodable>(_ type: T.Type = T.self, _ object: [String: Any]) throws -> T {
        try JSONDecoder().decode(type, from: JSONSerialization.data(withJSONObject: object))
    }
    func register(_ song: ProviderSong) throws -> Track {
        let provider = source(song.source)
        let handles = provider == .qq ? [song.qqMid] : [song.kugouHash?.lowercased(), song.kugouAlbumAudioId]
        let value = song.qishui?.trackID ?? handles.compactMap { $0 }.first(where: { !$0.isEmpty }) ?? String(song.id)
        let cloud = song.kugouCloud
        let id = Self.identifier(provider: provider, kind: cloud == nil ? "song" : "cloud", value: cloud.map { "\($0.ownerID):\($0.fileID):\(value)" } ?? value)
        registerKugouReferences(song)
        registerQishuiReferences(song)
        catalog.songs[id] = Self.preferredPlaybackMetadata(cached: catalog.songs[id], incoming: song)
        persist()
        var artists = [ArtistRef(id: 0, name: song.artists)]
        var album = AlbumRef(id: 0, name: song.album, picUrl: song.coverURL?.absoluteString ?? "")
        if provider == .kugou {
            (artists, album) = Self.kugouReferences(song)
        } else if provider == .qq {
            if let credits = song.qqArtistReferences, !credits.isEmpty {
                artists = credits.map { artist in
                    let id = Self.identifier(provider: .qq, kind: "artist", value: artist.id)
                    if catalog.artists[id] == nil { catalog.artists[id] = artist }
                    return ArtistRef(id: id, name: artist.name)
                }
            }
            if let mid = song.qqAlbumMID, !mid.isEmpty {
                let id = Self.identifier(provider: .qq, kind: "album", value: mid)
                if catalog.albums[id] == nil {
                    catalog.albums[id] = .init(id: mid, name: song.album, artistName: song.artists,
                                               coverURL: song.coverURL, source: .qq)
                }
                album = AlbumRef(id: id, name: song.album, picUrl: album.picUrl)
            }
            persist()
        } else if let reference = song.qishui {
            if let credits = reference.artists, !credits.isEmpty {
                artists = credits.map {
                    ArtistRef(id: Self.identifier(provider: .qishui, kind: "artist", value: $0.id), name: $0.name)
                }
            }
            if let albumID = reference.albumID, !albumID.isEmpty {
                album = AlbumRef(id: Self.identifier(provider: .qishui, kind: "album", value: albumID),
                                 name: song.album, picUrl: album.picUrl)
            }
        }
        return Track(id: id, song: song, artists: artists, album: album)
    }
    nonisolated static func kugouReferences(_ song: ProviderSong) -> ([ArtistRef], AlbumRef) {
        let artists = song.artists.split(separator: "/").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.map {
            ArtistRef(id: identifier(provider: .kugou, kind: "artist", value: $0), name: $0)
        }
        let value = song.kugouAlbumId.flatMap { $0.isEmpty || $0 == "0" ? nil : $0 } ?? "name:\(song.artists):\(song.album)"
        let album = AlbumRef(id: song.album.isEmpty ? 0 : identifier(provider: .kugou, kind: "album", value: value), name: song.album, picUrl: song.coverURL?.absoluteString)
        return (artists, album)
    }

    private func registerKugouReferences(_ song: ProviderSong) {
        guard song.source == .kugou else { return }
        let (artists, album) = Self.kugouReferences(song)
        for artist in artists where catalog.artists[artist.id] == nil {
            catalog.artists[artist.id] = ProviderArtist(id: artist.name, name: artist.name, coverURL: nil, source: .kugou)
        }
        if album.id != 0, catalog.albums[album.id] == nil {
            catalog.albums[album.id] = ProviderAlbum(id: song.kugouAlbumId ?? "", name: album.name, artistName: song.artists, coverURL: song.coverURL, source: .kugou)
        }
    }

    private func registerQishuiReferences(_ song: ProviderSong) {
        guard let reference = song.qishui else { return }
        for artist in reference.artists ?? [] {
            let id = Self.identifier(provider: .qishui, kind: "artist", value: artist.id)
            if catalog.artists[id]?.coverURL == nil { catalog.artists[id] = artist }
        }
        if let albumID = reference.albumID, !albumID.isEmpty {
            let id = Self.identifier(provider: .qishui, kind: "album", value: albumID)
            if catalog.albums[id]?.coverURL == nil {
                catalog.albums[id] = ProviderAlbum(id: albumID, name: song.album, artistName: song.artists,
                    coverURL: song.coverURL, source: .qishui, trackCount: nil)
            }
        }
    }

    func restore(_ track: Track) {
        guard let song = track.platformSong else { return }
        registerKugouReferences(song)
        registerQishuiReferences(song)
        catalog.songs[track.id] = Self.preferredPlaybackMetadata(cached: catalog.songs[track.id], incoming: song)
    }

    static func preferredPlaybackMetadata(cached: ProviderSong?, incoming: ProviderSong) -> ProviderSong {
        guard let cached, incoming.source == .kugou, cached.source == incoming.source,
              cached.kugouCloud == incoming.kugouCloud,
              cached.kugouHash?.lowercased() == incoming.kugouHash?.lowercased(),
              cached.kugouHash?.isEmpty == false,
              cached.name == incoming.name, cached.artists == incoming.artists,
              cached.kugouAlbumId == incoming.kugouAlbumId else { return incoming }
        let cachedCount = KugouMusicAPI.metadataQualities(cached).count
        let incomingCount = KugouMusicAPI.metadataQualities(incoming).count
        return cachedCount > incomingCount ? cached : incoming
    }

    func song(_ id: Int) throws -> ProviderSong {
        guard let song = catalog.songs[id], source(song.source) == provider else { throw MusicProviderError.missingTrack }
        return song
    }
    func tracks(_ songs: [ProviderSong]) throws -> [Track] { try songs.map(register) }
    func playlist(_ item: ProviderPlaylist, owned: Bool = false, liked: Bool = false, chart: Bool = false) throws -> PlaylistSummary {
        let kind = item.qishui?.radio != nil || item.isQQRadio == true ? "radio" : (chart ? "chart" : "playlist")
        let id = Self.identifier(provider: source(item.source), kind: kind, value: item.qishui?.playlistID ?? String(item.id))
        var metadata = item
        // The catalog is shared across accounts. Subscription state belongs to
        // the active library and must never be restored from this metadata.
        if item.source == .qishui { metadata.isSubscribed = nil }
        catalog.playlists[id] = metadata
        if chart { catalog.charts.insert(id) }
        persist()
        var object: [String: Any] = ["id": id, "name": item.name, "coverImgUrl": item.coverURL?.absoluteString ?? "",
            "trackCount": item.trackCount, "specialType": liked ? 5 : 0]
        object["subscribed"] = item.isSubscribed ?? false
        if (item.isOwned ?? owned), let profile = AccountStore.shared.profile {
            object["creator"] = ["userId": profile.userId, "nickname": profile.nickname]
        }
        return try Self.decode(PlaylistSummary.self, object)
    }
    func recommendedPlaylists(limit: Int = 30) async throws -> [PlaylistSummary] {
        let ticket = MusicProviderContext.shared.ticket
        let items: [ProviderPlaylist]
        if provider == .qishui { items = try await QishuiMusicAPI.shared.recommendedPlaylists(limit: limit) }
        else if provider == .qq { items = try await qqRecommendedPlaylists(limit: limit) }
        else { items = try await KugouMusicAPI.shared.recommendPlaylists(limit: limit) }
        try MusicProviderContext.shared.check(ticket)
        return try items.map { try playlist($0) }
    }

    func kugouSortedPlaylists(_ sort: KugouMusicAPI.PlaylistSort) async throws -> [PlaylistSummary] {
        let ticket = MusicProviderContext.shared.ticket
        let items = try await KugouMusicAPI.shared.sortedPlaylists(sort)
        try MusicProviderContext.shared.check(ticket)
        return try items.map { try playlist($0) }
    }

    func qishuiFeaturedPlaylists(excluding exposureIDs: [UInt64]) async throws
        -> (playlists: [PlaylistSummary], exposureIDs: [UInt64], hasMore: Bool) {
        let ticket = MusicProviderContext.shared.ticket
        let page = try await QishuiMusicAPI.shared.discoveryPlaylists(excluding: exposureIDs)
        await prepareCatalog()
        try MusicProviderContext.shared.check(ticket)
        return (try page.items.map { try playlist($0) }, page.exposureIDs, page.hasMore)
    }
    func topLists() async throws -> [ToplistItem] {
        guard provider.supports(.toplists) else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let items: [ProviderPlaylist]
        if provider == .qishui {
            items = try await QishuiMusicAPI.shared.charts()
        } else if provider == .qq {
            items = try await QQMusicAPI.shared.topLists().map { .init(id: $0.id, name: $0.name, coverURL: $0.coverURL, source: .qq) }
        } else {
            items = try await KugouMusicAPI.shared.topLists().map { .init(id: $0.id, name: $0.name, coverURL: $0.coverURL, source: .kugou) }
        }
        await prepareCatalog()
        try MusicProviderContext.shared.check(ticket)
        return try items.map { item in
            let mapped = try playlist(item, chart: true)
            return try Self.decode(ToplistItem.self, ["id": mapped.id, "name": mapped.name, "coverImgUrl": mapped.coverURL ?? ""])
        }
    }
    func userPlaylists() async throws -> [PlaylistSummary] {
        let ticket = MusicProviderContext.shared.ticket
        var items: [ProviderPlaylist]
        if provider == .qishui {
            let api = QishuiMusicAPI.shared
            async let created = api.userPlaylists()
            async let collected = api.collectionItems(.playlist)
            let (own, rows) = try await (created, collected)
            await prepareCatalog()
            try MusicProviderContext.shared.check(ticket)
            let createdItems = reconcileCreatedPlaylists(remote: own, ownerID: api.userID)
            let ownIDs = Set(createdItems.map(\.id))
            items = createdItems + rows.compactMap(QishuiMusicAPI.playlist).filter { !ownIDs.contains($0.id) }.map {
                var item = $0
                item.isSubscribed = true
                return item
            }
        } else {
            items = try await (provider == .qq ? QQMusicAPI.shared.userPlaylists(uin: QQMusicAuth.shared.playlistUin) : KugouMusicAPI.shared.userPlaylists())
        }
        try MusicProviderContext.shared.check(ticket)
        if provider == .qq || provider == .kugou {
            let ownerID = provider == .qq ? QQMusicAuth.shared.uin : KugouMusicAuth.shared.userId
            items = reconcileCreatedPlaylists(remote: items, ownerID: ownerID)
        }
        if provider == .kugou {
            let key = "kugou:\(KugouMusicAuth.shared.userId)"
            let pending = catalog.pendingDeleted?[key] ?? []
            let reconciled = Self.reconcileDeletedPlaylists(remote: items, pending: pending)
            items = reconciled.visible
            var deleted = catalog.pendingDeleted ?? [:]; deleted[key] = reconciled.remaining; catalog.pendingDeleted = deleted
        }
        return try items.map {
            try playlist($0, owned: provider != .qishui || $0.isSubscribed != true, liked: isFavoritesPlaylist($0))
        }
    }
    private func reconcileCreatedPlaylists(remote: [ProviderPlaylist], ownerID: String) -> [ProviderPlaylist] {
        let pending = catalog.pendingCreated ?? [:]
        let merged = Self.mergePendingPlaylists(remote: remote,
            pending: pending.filter { source($0.value.source) == provider }, ownerID: ownerID)
        catalog.pendingCreated = pending.filter { source($0.value.source) != provider }.merging(merged.remaining) { _, new in new }
        return merged.visible
    }

    private func isFavoritesPlaylist(_ item: ProviderPlaylist) -> Bool {
        if item.source == .qishui { return item.qishui?.type == 1 }
        if item.source == .qq { return item.id == QQMusicAPI.qqLikedPlaylistID }
        return ["我喜欢", "我的喜欢", "我喜欢的音乐", "喜欢的音乐"].contains(item.name)
    }
    func playlistDetail(id: Int) async throws -> NeteaseAPI.PlaylistDetailResponse {
        let ticket = MusicProviderContext.shared.ticket
        await prepareCatalog()
        try MusicProviderContext.shared.check(ticket)
        guard var item = catalog.playlists[id], source(item.source) == provider else { throw MusicProviderError.missingTrack }
        // Recover collections completed by the server even if an older client
        // reported a failure afterwards. Public and account list IDs differ.
        if provider == .kugou, !catalog.charts.contains(id),
           item.ownerID != KugouMusicAuth.shared.userId,
           catalog.playlists.values.contains(where: { $0.source == .kugou && $0.isSubscribed == true && $0.ownerID == KugouMusicAuth.shared.userId }),
           let resolved = try? await KugouMusicAPI.shared.collectionSource(item) {
            try MusicProviderContext.shared.check(ticket)
            item = resolved
            item.isSubscribed = collectedKugouPlaylist(for: resolved) != nil
        }
        let songs: [ProviderSong]
        var feed: QishuiFeedState?
        if item.isQQRadio == true {
            songs = try await QQMusicAPI.shared.radioSongs(id: item.id)
        } else if isQishuiChart(id) {
            songs = try await QishuiMusicAPI.shared.chartEntries(id: item.id).map(\.song)
        } else if provider == .qishui {
            guard let reference = item.qishui else { throw MusicProviderError.missingTrack }
            if let radio = reference.radio {
                let api = QishuiMusicAPI.shared
                let page = try await api.feedPage(api.feedState(.radio(id: reference.playlistID, radio)))
                songs = page.songs
                feed = page.state
            } else {
                let response = try await QishuiMusicAPI.shared.playlistDetail(reference)
                songs = response.songs
                if var metadata = response.playlist, !metadata.name.isEmpty {
                    metadata.coverURL = metadata.coverURL ?? item.coverURL
                    metadata.ownerID = metadata.ownerID ?? item.ownerID
                    if metadata.qishui?.type == 0 { metadata.qishui = reference }
                    item = metadata
                }
                item.isSubscribed = AccountStore.shared.subscribedPlaylists.contains { $0.id == id }
            }
        } else if catalog.charts.contains(id) {
            songs = try await (provider == .qq ? QQMusicAPI.shared.topListSongs(topid: item.id, limit: 100) : KugouMusicAPI.shared.rankSongs(rankID: item.id))
        } else {
            songs = try await (provider == .qq ? QQMusicAPI.shared.playlistSongs(listID: item.id,
                ownedDirectoryID: item.ownerID == QQMusicAuth.shared.uin ? item.qqDirectoryID : nil) : KugouMusicAPI.shared.playlistSongs(playlist: item))
        }
        if provider == .qq, QQMusicAuth.shared.isLoggedIn, !catalog.charts.contains(id), item.isQQRadio != true, item.id > 0, item.isOwned != true,
           let subscribed = try? await QQMusicAPI.shared.playlistSubscribed(id: item.id) {
            item.isSubscribed = subscribed
        }
        try MusicProviderContext.shared.check(ticket)
        let mapped = try tracks(songs)
        let liked = provider == .qishui ? isFavoritesPlaylist(item) : item.id == QQMusicAPI.qqLikedPlaylistID
        let owned = provider == .qishui
            ? QishuiMusicAPI.shared.isLoggedIn && (liked || item.ownerID == QishuiMusicAPI.shared.userID)
            : item.id == QQMusicAPI.qqLikedPlaylistID
        var detail = PlaylistDetail(summary: try playlist(item, owned: owned, liked: liked, chart: isQishuiChart(id)))
        detail.qishuiFeed = feed
        detail.tracks = mapped
        detail.trackIds = mapped.map { TrackIDRef(id: $0.id) }
        detail.trackCount = mapped.count
        return .init(playlist: detail, privileges: nil)
    }

    func restoredPlaySource(_ source: PlaySource) -> PlaySource {
        guard provider == .qishui, case .playlist(let id) = source,
              let reference = catalog.playlists[id]?.qishui, let radio = reference.radio else { return source }
        return .qishuiFeed(QishuiMusicAPI.shared.feedState(.radio(id: reference.playlistID, radio)), playlistID: id)
    }

    func isQQRadio(_ id: Int) -> Bool { catalog.playlists[id]?.isQQRadio == true }

    func isQishuiChart(_ id: Int) -> Bool {
        catalog.charts.contains(id) && catalog.playlists[id]?.source == .qishui
    }

    func toplistPreviewTracks(id: Int) async throws -> (tracks: [Track], previousRanks: [Int: Int], growthRatios: [Int: Double]) {
        if provider == .qishui {
            guard isQishuiChart(id), let item = catalog.playlists[id] else { throw MusicProviderError.missingTrack }
            let ticket = MusicProviderContext.shared.ticket
            let entries = try await QishuiMusicAPI.shared.chartEntries(id: item.id)
            try MusicProviderContext.shared.check(ticket)
            var tracks: [Track] = []
            var previousRanks: [Int: Int] = [:]
            for entry in entries.prefix(10) {
                let track = try register(entry.song)
                tracks.append(track)
                previousRanks[track.id] = entry.previousRank
            }
            return (tracks, previousRanks, [:])
        }
        guard provider == .qq else {
            return (Array(try await playlistDetail(id: id).playlist.tracks.prefix(10)), [:], [:])
        }
        let ticket = MusicProviderContext.shared.ticket
        guard let item = catalog.playlists[id], item.source == .qq, catalog.charts.contains(id) else {
            throw MusicProviderError.missingTrack
        }
        let entries = try await QQMusicAPI.shared.topListEntries(topid: item.id, limit: 10)
        try MusicProviderContext.shared.check(ticket)
        var tracks: [Track] = []
        var previousRanks: [Int: Int] = [:]
        var growthRatios: [Int: Double] = [:]
        for entry in entries {
            let track = try register(entry.song)
            tracks.append(track)
            previousRanks[track.id] = entry.previousRank
            growthRatios[track.id] = entry.growthRatio
        }
        return (tracks, previousRanks, growthRatios)
    }

    func recommendations(fm: Bool = false) async throws -> [Track] {
        guard provider.supports(fm ? .personalFM : .recommendedSongs) else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let songs: [ProviderSong]
        if provider == .qq {
            if fm {
                let account = MusicProviderContext.shared.authenticationKey
                if qqFMAccount != account { resetQQFM(); qqFMAccount = account }
                guard qqFMRequest == nil, qqFMPage <= 100 else { return [] }
                let request = UUID()
                qqFMRequest = request
                defer { if qqFMRequest == request { qqFMRequest = nil } }
                if let scene = qqFMScene {
                    let batch = try await QQMusicAPI.shared.guessYouLike(poolID: scene.poolID)
                    try MusicProviderContext.shared.check(ticket)
                    guard qqFMRequest == request else { throw CancellationError() }
                    // Scene radios return small random batches; skip songs heard recently.
                    let recent = Set(qqFMRecentIDs)
                    let fresh = try tracks(batch).filter { !recent.contains($0.id) }
                    qqFMRecentIDs = Array((qqFMRecentIDs + fresh.map(\.id)).suffix(200))
                    return fresh
                }
                let page = try await QQMusicAPI.shared.radioRadar(page: qqFMPage)
                try MusicProviderContext.shared.check(ticket)
                guard qqFMRequest == request else { throw CancellationError() }
                qqFMPage = page.more ? qqFMPage + 1 : 101
                songs = page.songs
            } else if QQMusicAuth.shared.isLoggedIn {
                songs = try await QQMusicAPI.shared.guessYouLike()
            } else {
                songs = try await QQMusicAPI.shared.recommendSongs()
            }
        } else { songs = try await (fm ? KugouMusicAPI.shared.personalFM() : KugouMusicAPI.shared.everydayRecommend()) }
        try MusicProviderContext.shared.check(ticket)
        return try tracks(songs)
    }
    func qqDailySongs() async throws -> [Track] {
        let ticket = MusicProviderContext.shared.ticket
        let songs = try await QQMusicAPI.shared.dailySongs()
        try MusicProviderContext.shared.check(ticket)
        return try tracks(songs)
    }

    func qqSimilarSongs(id: Int, limit: Int) async throws -> [Track] {
        let ticket = MusicProviderContext.shared.ticket
        let track = try song(id)
        guard track.id > 0 else { throw MusicProviderError.missingTrack }
        let songs = try await QQMusicAPI.shared.similarSongs(songID: track.id, limit: limit)
        try MusicProviderContext.shared.check(ticket)
        return try tracks(songs)
    }

    func qqSongExtras(id: Int) async throws -> (versions: [Track], labels: [String], count: Int?) {
        let ticket = MusicProviderContext.shared.ticket
        let track = try song(id)
        guard track.source == .qq, track.id > 0 else { throw MusicProviderError.missingTrack }
        let api = QQMusicAPI.shared
        async let versions = try? api.songVersions(songID: track.id)
        async let labels = try? api.songLabels(songID: track.id)
        async let count = try? api.songFavoriteCount(songID: track.id)
        let result = await (versions, labels, count)
        try MusicProviderContext.shared.check(ticket)
        return (try tracks(result.0 ?? []), result.1 ?? [], result.2)
    }

    func qqListeningRank(period: Int) async throws -> [PlayRecordItem] {
        let ticket = MusicProviderContext.shared.ticket
        let rows = try await QQMusicAPI.shared.listeningRank(period: period)
        try MusicProviderContext.shared.check(ticket)
        return try rows.map { .init(song: try register($0.song), playCount: $0.count) }
    }

    func qqRelatedPlaylists(id: Int) async throws -> [PlaylistSummary] {
        let ticket = MusicProviderContext.shared.ticket
        let track = try song(id)
        guard track.id > 0 else { throw MusicProviderError.missingTrack }
        let items = try await QQMusicAPI.shared.relatedPlaylists(songID: track.id)
        try MusicProviderContext.shared.check(ticket)
        return try items.map { try playlist($0) }
    }

    /// Prefer QQ's personalized playlist feed; the y.qq.com shelf is the same for everyone.
    private func qqRecommendedPlaylists(limit: Int) async throws -> [ProviderPlaylist] {
        if let feed = try? await QQMusicAPI.shared.discoveryPlaylists(limit: limit), !feed.isEmpty {
            return feed
        }
        return try await QQMusicAPI.shared.hotPlaylists(limit: limit)
    }

    func qqNewAlbums(limit: Int, offset: Int) async throws -> [AlbumSummary] {
        let ticket = MusicProviderContext.shared.ticket
        let items = try await QQMusicAPI.shared.newAlbums(limit: limit, offset: offset)
        try MusicProviderContext.shared.check(ticket)
        return try registerProviderAlbums(items)
    }

    private func registerProviderAlbums(_ items: [ProviderAlbum], provider: MusicProvider = .qq) throws -> [AlbumSummary] {
        let result = try items.map { item in
            let id = Self.identifier(provider: provider, kind: "album", value: item.id)
            catalog.albums[id] = item
            return try Self.decode(AlbumSummary.self, ["id": id, "name": item.name, "artist": ["name": item.artistName],
                "picUrl": item.coverURL?.absoluteString ?? "", "size": item.trackCount ?? 0, "publishTime": item.releaseDateMS ?? 0])
        }
        persist()
        return result
    }

    func qqSingers(limit: Int) async throws -> [ArtistSummary] {
        let ticket = MusicProviderContext.shared.ticket
        let items = try await QQMusicAPI.shared.singers(limit: limit)
        try MusicProviderContext.shared.check(ticket)
        return try registerProviderArtists(items)
    }

    private func registerProviderArtists(_ items: [ProviderArtist], provider: MusicProvider = .qq) throws -> [ArtistSummary] {
        let result = try items.map { item in
            let id = Self.identifier(provider: provider, kind: "artist", value: item.id)
            catalog.artists[id] = item
            return try Self.decode(ArtistSummary.self, ["id": id, "name": item.name, "picUrl": item.coverURL?.absoluteString ?? ""])
        }
        persist()
        return result
    }

    /// 酷狗新碟不支持翻页，后续页返回空列表。
    func kugouNewAlbums(limit: Int, offset: Int) async throws -> [AlbumSummary] {
        guard offset == 0 else { return [] }
        let ticket = MusicProviderContext.shared.ticket
        let items = try await KugouMusicAPI.shared.newAlbums(limit: limit)
        try MusicProviderContext.shared.check(ticket)
        return try registerProviderAlbums(items, provider: .kugou)
    }

    func kugouSingers(limit: Int) async throws -> [ArtistSummary] {
        let ticket = MusicProviderContext.shared.ticket
        let items = try await KugouMusicAPI.shared.hotSingers(limit: limit)
        try MusicProviderContext.shared.check(ticket)
        return try registerProviderArtists(items, provider: .kugou)
    }

    func qqCategoryPlaylists(id: Int, page: Int) async throws -> (items: [PlaylistSummary], more: Bool) {
        let ticket = MusicProviderContext.shared.ticket
        let result = try await QQMusicAPI.shared.categoryPlaylists(id: id, page: page)
        try MusicProviderContext.shared.check(ticket)
        return (try result.items.map { try playlist($0) }, result.more)
    }

    func qqSimilarArtists(id: Int) async throws -> [ArtistSummary] {
        guard let item = catalog.artists[id], item.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let items = try await QQMusicAPI.shared.similarArtists(mid: item.id, name: item.name)
        try MusicProviderContext.shared.check(ticket)
        return try registerProviderArtists(items)
    }

    func favorites() async throws -> [Track] {
        guard provider.supports(.likedSongs) else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let songs: [ProviderSong]
        if provider == .qq { songs = try await QQMusicAPI.shared.favoriteSongs() }
        else {
            let lists = try await userPlaylists()
            guard let liked = lists.first(where: \.isLikedSongsList) else { return [] }
            return try await playlistDetail(id: liked.id).playlist.tracks
        }
        try MusicProviderContext.shared.check(ticket)
        return try tracks(songs)
    }
    func like(id: Int, liked: Bool) async throws {
        guard provider.supportsFavoriteChanges else { throw MusicProviderError.unsupported }
        let item = try song(id)
        let ticket = MusicProviderContext.shared.ticket
        switch provider {
        case .qishui:
            guard let trackID = item.qishui?.trackID else { throw MusicProviderError.missingTrack }
            try await QishuiMusicAPI.shared.setLiked(trackID: trackID, liked: liked)
        case .qq:
            guard let mid = item.qqMid else { throw MusicProviderError.missingTrack }
            try await QQMusicAPI.shared.like(songID: item.id, songmid: mid, liked: liked)
        case .kugou:
            let list = try await kugouLikedList()
            if liked { try await KugouMusicAPI.shared.addSongs(listID: list.id, songs: [item]) }
            else { try await KugouMusicAPI.shared.deleteSongs(listID: list.id, songs: [item]) }
        default: throw MusicProviderError.unsupported
        }
        try MusicProviderContext.shared.check(ticket)
    }
    func search(_ keyword: String, type: NeteaseAPI.SearchType, limit: Int, offset: Int) async throws -> NeteaseAPI.SearchResult {
        let ticket = MusicProviderContext.shared.ticket
        if provider == .qishui {
            let page = try await QishuiMusicAPI.shared.search(keyword: keyword, type: type, limit: limit, offset: offset)
            try MusicProviderContext.shared.check(ticket)
            let albums = try page.albums.map { item in
                let id = Self.identifier(provider: .qishui, kind: "album", value: item.id)
                catalog.albums[id] = item
                return try Self.decode(AlbumSummary.self, ["id": id, "name": item.name, "artist": ["name": item.artistName],
                    "picUrl": item.coverURL?.absoluteString ?? "", "size": item.trackCount ?? 0])
            }
            let artists = try page.artists.map { item in
                let id = Self.identifier(provider: .qishui, kind: "artist", value: item.id)
                catalog.artists[id] = item
                return try Self.decode(ArtistSummary.self, ["id": id, "name": item.name, "picUrl": item.coverURL?.absoluteString ?? ""])
            }
            persist()
            return .init(songs: type == .songs ? try tracks(page.songs) : nil,
                albums: type == .albums ? albums : nil, artists: type == .artists ? artists : nil,
                playlists: type == .playlists ? try page.playlists.map { try playlist($0) } : nil,
                songCount: type == .songs ? page.total : nil, albumCount: type == .albums ? page.total : nil,
                artistCount: type == .artists ? page.total : nil, playlistCount: type == .playlists ? page.total : nil)
        }
        if provider == .qq {
            let response: QQMusicAPI.CatalogSearchPage?
            do {
                response = try await QQMusicAPI.shared.catalogSearch(keyword: keyword, type: type, limit: limit, offset: offset)
            } catch is CancellationError { throw CancellationError() }
            catch {
                if type == .playlists { throw error }
                response = nil
            }
            try MusicProviderContext.shared.check(ticket)
            if let response {
                let albums = try registerProviderAlbums(response.albums)
                let artists = try registerProviderArtists(response.artists)
                return .init(songs: type == .songs ? try tracks(response.songs) : nil,
                    albums: type == .albums ? albums : nil, artists: type == .artists ? artists : nil,
                    playlists: type == .playlists ? try response.playlists.map { try playlist($0) } : nil,
                    songCount: type == .songs ? response.total : nil, albumCount: type == .albums ? response.total : nil,
                    artistCount: type == .artists ? response.total : nil, playlistCount: type == .playlists ? response.total : nil)
            }
        }
        var songs: [Track]?, artists: [ArtistSummary]?, albums: [AlbumSummary]?
        switch type {
        case .songs:
            let items = try await (provider == .qq ? QQMusicAPI.shared.searchSongs(keyword: keyword, limit: limit, offset: offset) : KugouMusicAPI.shared.searchSongs(keyword: keyword, limit: limit + offset))
            try MusicProviderContext.shared.check(ticket)
            songs = try tracks(provider == .qq ? items : Array(items.dropFirst(offset).prefix(limit)))
        case .artists:
            let items = try await (provider == .qq ? QQMusicAPI.shared.searchArtists(keyword: keyword, limit: limit + offset) : KugouMusicAPI.shared.searchArtists(keyword: keyword, limit: limit + offset))
            try MusicProviderContext.shared.check(ticket)
            artists = try items.dropFirst(offset).prefix(limit).map { item in
                let id = Self.identifier(provider: provider, kind: "artist", value: item.id)
                catalog.artists[id] = item
                return try Self.decode(ArtistSummary.self, ["id": id, "name": item.name, "picUrl": item.coverURL?.absoluteString ?? ""])
            }
        case .albums:
            let items = try await (provider == .qq ? QQMusicAPI.shared.searchAlbums(keyword: keyword, limit: limit + offset) : KugouMusicAPI.shared.searchAlbums(keyword: keyword, limit: limit + offset))
            try MusicProviderContext.shared.check(ticket)
            albums = try items.dropFirst(offset).prefix(limit).map { item in
                let id = Self.identifier(provider: provider, kind: "album", value: item.id)
                catalog.albums[id] = item
                return try Self.decode(AlbumSummary.self, ["id": id, "name": item.name, "artist": ["name": item.artistName], "picUrl": item.coverURL?.absoluteString ?? "", "size": item.trackCount ?? 0, "subType": item.releaseType ?? ""])
            }
        case .playlists:
            guard provider == .kugou else { break }
            let pageSize = min(max(limit, 1), 30)
            let items = try await KugouMusicAPI.shared.searchPlaylists(keyword: keyword, page: offset / pageSize + 1, limit: pageSize)
            try MusicProviderContext.shared.check(ticket)
            persist()
            return .init(songs: nil, albums: nil, artists: nil, playlists: try items.map { try playlist($0) },
                         songCount: nil, albumCount: nil, artistCount: nil, playlistCount: nil)
        }
        persist()
        return .init(songs: songs, albums: albums, artists: artists, playlists: nil, songCount: nil, albumCount: nil, artistCount: nil, playlistCount: nil)
    }
    func artist(id: Int) async throws -> NeteaseAPI.ArtistResponse {
        guard provider.supports(.artistDetail) else { throw MusicProviderError.unsupported }
        for song in Array(catalog.songs.values) { registerKugouReferences(song) }
        guard var item = catalog.artists[id], source(item.source) == provider else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        if provider == .qishui {
            let (metadata, songs) = try await QishuiMusicAPI.shared.artistDetail(item.id)
            try MusicProviderContext.shared.check(ticket)
            let summary = try Self.decode(ArtistSummary.self, ["id": id, "name": metadata?.name ?? item.name,
                "picUrl": (metadata?.coverURL ?? item.coverURL)?.absoluteString ?? ""])
            return .init(artist: summary, hotSongs: try tracks(songs))
        }
        if provider == .kugou, Int(item.id) == nil || item.coverURL == nil {
            let candidates = try await KugouMusicAPI.shared.searchArtists(keyword: item.name)
            try MusicProviderContext.shared.check(ticket)
            if let resolved = candidates.first(where: { ($0.id == item.id || $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame) && Int($0.id) != nil && $0.coverURL != nil }) {
                item = resolved
                catalog.artists[id] = resolved
                persist()
            }
        }
        if provider == .qq {
            async let profile = try? QQMusicAPI.shared.singerProfile(mid: item.id, name: item.name)
            async let songs = QQMusicAPI.shared.artistHotSongs(mid: item.id, name: item.name)
            let (details, fetched) = try await (profile, songs)
            try MusicProviderContext.shared.check(ticket)
            let summary = try Self.decode(ArtistSummary.self, ["id": id, "name": details?.name ?? item.name,
                "picUrl": (details?.cover ?? item.coverURL)?.absoluteString ?? "", "briefDesc": details?.description ?? ""])
            return .init(artist: summary, hotSongs: try tracks(fetched))
        }
        var songs: [ProviderSong]
        if provider == .kugou, Int(item.id) == nil {
            songs = try await KugouMusicAPI.shared.searchSongs(keyword: item.name, limit: 100).filter {
                Self.kugouReferences($0).0.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
            }
        } else {
            songs = try await KugouMusicAPI.shared.artistSongs(authorID: item.id)
        }
        // Numeric artist IDs can also yield an empty author response. Resolve songs
        // through search in that case, retaining only exact artist credits.
        if provider == .kugou, songs.isEmpty {
            songs = try await KugouMusicAPI.shared.searchSongs(keyword: item.name, limit: 100).filter {
                Self.kugouReferences($0).0.contains { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame }
            }
        }
        try MusicProviderContext.shared.check(ticket)
        let summary = try Self.decode(ArtistSummary.self, ["id": id, "name": item.name, "picUrl": item.coverURL?.absoluteString ?? ""])
        return .init(artist: summary, hotSongs: try tracks(songs))
    }
    func songAudioQualityOptions(id: Int) async throws -> [AudioQualityOption] {
        let item = try song(id)
        if item.kugouCloud != nil { return [] }
        let ticket = MusicProviderContext.shared.ticket
        if item.source == .qishui, let trackID = item.qishui?.trackID {
            let options = try await QishuiMusicAPI.shared.playbackQualityOptions(trackID: trackID)
            try MusicProviderContext.shared.check(ticket)
            return options
        }
        if item.source == .kugou {
            let metadata = await KugouMusicAPI.shared.playbackMetadata(for: item)
            try MusicProviderContext.shared.check(ticket)
            catalog.songs[id] = metadata
            persist()
            let options = try await KugouMusicAPI.shared.qualityOptions(song: metadata)
            try MusicProviderContext.shared.check(ticket)
            return options
        }
        guard let mid = item.qqMid else { return [] }
        let bitrates = (try? await QQMusicAPI.shared.averageBitrates(songmid: mid)) ?? [:]
        try MusicProviderContext.shared.check(ticket)
        var options: [AudioQualityOption] = []
        for candidate: ProviderAudioQuality in [.standard, .exhigh, .lossless, .hires] {
            guard let result = try await QQMusicAPI.shared.songURLResult(songmid: mid, mediaMid: item.qqMediaMid, quality: candidate) else { continue }
            try MusicProviderContext.shared.check(ticket)
            guard let quality = result.quality, !options.contains(where: { $0.quality == quality }) else { continue }
            let title = AudioQualityOption.unifiedTitle(quality: quality, bitrate: bitrates[result.br], estimated: true)
            options.append(.init(quality: quality, title: title))
        }
        return options.sorted { (AudioQuality.allCases.firstIndex(of: $0.quality) ?? 0) < (AudioQuality.allCases.firstIndex(of: $1.quality) ?? 0) }
    }

    func songAudioQualities(id: Int) async throws -> [AudioQuality] {
        let item = try song(id)
        guard item.source == .kugou, item.kugouCloud == nil else { return [] }
        let ticket = MusicProviderContext.shared.ticket
        let metadata = await KugouMusicAPI.shared.playbackMetadata(for: item)
        try MusicProviderContext.shared.check(ticket)
        catalog.songs[id] = metadata
        persist()
        return KugouMusicAPI.metadataQualities(metadata).compactMap { AudioQuality(rawValue: $0.rawValue) }
    }

    func songURLs(ids: [Int], level: String) async throws -> [SongURLData] {
        let ticket = MusicProviderContext.shared.ticket
        var result: [SongURLData] = []
        let quality = ProviderAudioQuality(rawValue: level) ?? .hires
        for id in ids {
            let item = try song(id)
            let url: String?
            var actualLevel: String?
            if provider == .qishui {
                guard let trackID = item.qishui?.trackID else { throw MusicProviderError.missingTrack }
                let resource = try await QishuiMusicAPI.shared.playback(trackID: trackID, quality: AudioQuality(rawValue: level))
                try MusicProviderContext.shared.check(ticket)
                result.append(try Self.decode(SongURLData.self, [
                    "id": id, "url": resource.url, "time": resource.durationMS, "code": 200,
                    "br": resource.bitrate ?? 0, "size": resource.size, "type": resource.format, "level": resource.level.rawValue
                ]))
                continue
            } else if provider == .qq {
                guard let mid = item.qqMid else { throw MusicProviderError.missingTrack }
                let resolved = try await QQMusicAPI.shared.songURLResult(songmid: mid, mediaMid: item.qqMediaMid, quality: quality)
                url = resolved?.url
                actualLevel = resolved?.quality?.rawValue
            } else {
                if item.kugouCloud != nil {
                    url = try await KugouMusicAPI.shared.userCloudURL(song: item)
                } else {
                    let resolved = try await KugouMusicAPI.shared.songURLResult(song: item, quality: quality)
                    url = resolved?.url
                    actualLevel = resolved?.quality?.rawValue
                }
            }
            try MusicProviderContext.shared.check(ticket)
            var object: [String: Any] = ["id": id, "time": Int(item.duration * 1000), "code": url == nil ? 404 : 200]
            object["url"] = url
            object["level"] = actualLevel
            result.append(try Self.decode(SongURLData.self, object))
        }
        return result
    }
    func recentSongs(limit: Int = 500) async throws -> [RecentSongPlayRecord] {
        let ticket = MusicProviderContext.shared.ticket
        switch provider {
        case .kugou:
            let entries = try await KugouMusicAPI.shared.recentSongPlays(limit: limit)
            try MusicProviderContext.shared.check(ticket)
            return try entries.map { .init(song: try register($0.song), playedAt: $0.playedAt) }
        case .qishui:
            let entries = try await QishuiMusicAPI.shared.recentSongPlays(limit: limit)
            try MusicProviderContext.shared.check(ticket)
            return try entries.map { .init(song: try register($0.song), playedAt: $0.playedAt) }
        default:
            throw MusicProviderError.unsupported
        }
    }

    func playRecords(week: Bool) async throws -> [PlayRecordItem] {
        guard provider == .kugou else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let entries = try await KugouMusicAPI.shared.listeningRanking(week: week)
        try MusicProviderContext.shared.check(ticket)
        return try entries.map { .init(song: try register($0.song), playCount: $0.count) }
    }

    func cloudSongs() async throws -> NeteaseAPI.CloudResponse {
        if provider == .qq {
            let ticket = MusicProviderContext.shared.ticket
            let entries = try await QQMusicAPI.shared.cloudEntries()
            try MusicProviderContext.shared.check(ticket)
            let items = try entries.map { entry -> CloudSongItem in
                if let song = entry.song { return .init(track: try register(song), fileSize: 0) }
                let id = Self.identifier(provider: .qq, kind: "cloudFile", value: entry.fileID)
                return try Self.decode(CloudSongItem.self, ["songId": id, "songName": entry.fileName])
            }
            return .init(data: items, hasMore: false, size: nil, maxSize: nil)
        }
        guard provider == .kugou else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let library = try await KugouMusicAPI.shared.cloudLibrary()
        try MusicProviderContext.shared.check(ticket)
        let items = try library.songs.map { CloudSongItem(track: try register($0), fileSize: Int($0.kugouCloud?.byteCount ?? 0)) }
        return .init(data: items, hasMore: false, size: library.usedBytes, maxSize: library.maxBytes)
    }

    func cloudUpload(fileAt url: URL) async throws {
        guard provider == .kugou else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let file = try await CloudUploadFile.prepare(url)
        defer { try? FileManager.default.removeItem(at: file.url.deletingLastPathComponent()) }
        try MusicProviderContext.shared.check(ticket)
        try await KugouMusicAPI.shared.uploadCloudFile(.init(url: file.url, md5: file.md5, size: file.size,
            ext: file.ext.isEmpty ? "mp3" : file.ext, title: file.title, artist: file.taggedArtist, durationMS: file.durationMS))
        try MusicProviderContext.shared.check(ticket)
    }

    func cloudDelete(track: Track) async throws {
        guard provider == .kugou else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        restore(track)
        let item = try song(track.id)
        guard item.kugouCloud != nil else { throw MusicProviderError.missingTrack }
        try await KugouMusicAPI.shared.deleteCloudSongs([item])
        try MusicProviderContext.shared.check(ticket)
    }

    func downloadResource(track: Track, level: String, accountScope: String) async throws -> OfflineAudioResource {
        guard provider == .kugou, accountScope == AccountStore.shared.offlineScope else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        restore(track)
        let item = try song(track.id)
        let result = try await KugouMusicAPI.shared.downloadResource(song: item, track: track, level: level, accountScope: accountScope)
        try MusicProviderContext.shared.check(ticket)
        guard accountScope == AccountStore.shared.offlineScope else { throw CancellationError() }
        return result
    }

    func lyric(id: Int) async throws -> LyricResponse {
        let ticket = MusicProviderContext.shared.ticket
        let item = try song(id)
        if provider == .qishui {
            guard let trackID = item.qishui?.trackID else { throw MusicProviderError.missingTrack }
            let response = try await QishuiMusicAPI.shared.lyric(trackID: trackID)
            try MusicProviderContext.shared.check(ticket)
            return response
        }
        if provider == .qq {
            guard let mid = item.qqMid else { throw MusicProviderError.missingTrack }
            let lyrics = try await QQMusicAPI.shared.lyric(songmid: mid)
            try MusicProviderContext.shared.check(ticket)
            let original = lyrics.original ?? ""
            var object: [String: Any] = ["lrc": ["lyric": original], "nolyric": original.isEmpty]
            if let translated = lyrics.translation { object["tlyric"] = ["lyric": translated] }
            return try Self.decode(LyricResponse.self, object)
        }
        let raw = await KugouMusicAPI.shared.lyric(song: item)
        try MusicProviderContext.shared.check(ticket)
        return try Self.decode(LyricResponse.self, ["lrc": ["lyric": raw], "nolyric": raw.isEmpty])
    }
}

extension PlatformMusicAPI {
    func qishuiArtistTracks(id: Int, limit: Int, offset: Int) async throws -> (name: String, tracks: [Track], hasMore: Bool) {
        guard provider == .qishui, let artist = catalog.artists[id], artist.source == .qishui else {
            throw MusicProviderError.missingTrack
        }
        let ticket = MusicProviderContext.shared.ticket
        let page = try await QishuiMusicAPI.shared.artistContent(artist.id, kind: .tracks, limit: limit, offset: offset)
        try MusicProviderContext.shared.check(ticket)
        return (artist.name, try tracks(page.items.compactMap(QishuiMusicAPI.song)), page.hasMore)
    }

    func artistAlbums(id: Int, limit: Int, offset: Int) async throws -> NeteaseAPI.ArtistAlbumsResponse {
        guard provider.supports(.artistAlbums) else { throw MusicProviderError.unsupported }
        guard let artist = catalog.artists[id], source(artist.source) == provider else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let items: [ProviderAlbum]
        let hasMore: Bool
        if provider == .qishui {
            let page = try await QishuiMusicAPI.shared.artistContent(artist.id, kind: .albums, limit: limit, offset: offset)
            items = page.items.compactMap(QishuiMusicAPI.albumMetadata)
            hasMore = page.hasMore
        } else {
            let fetched: [ProviderAlbum]
            if provider == .qq {
                fetched = try await QQMusicAPI.shared.artistAlbums(mid: artist.id, name: artist.name, limit: offset + limit + 1)
            } else {
                fetched = try await KugouMusicAPI.shared.searchAlbums(keyword: artist.name, limit: offset + limit)
                    .filter { $0.artistName.localizedCaseInsensitiveContains(artist.name) }
            }
            items = Array(fetched.dropFirst(offset).prefix(limit))
            hasMore = fetched.count > offset + limit
        }
        try MusicProviderContext.shared.check(ticket)
        let albums = try items.map { item in
            let key = Self.identifier(provider: provider, kind: "album", value: item.id)
            catalog.albums[key] = item
            return try Self.decode(AlbumSummary.self, ["id": key, "name": item.name,
                "picUrl": item.coverURL?.absoluteString ?? "", "artist": ["name": item.artistName],
                "size": item.trackCount ?? 0, "subType": item.releaseType ?? "", "publishTime": item.releaseDateMS ?? 0])
        }
        persist()
        return .init(hotAlbums: albums, more: hasMore)
    }
    /// Album contents are scoped to the service album ID, never its title alone.
    func album(id: Int) async throws -> AlbumDetailResponse {
        guard provider.supports(.albumDetail) else { throw MusicProviderError.unsupported }
        for song in Array(catalog.songs.values) { registerKugouReferences(song) }
        guard let item = catalog.albums[id], source(item.source) == provider else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        if provider == .qishui {
            let (metadata, artist, songs) = try await QishuiMusicAPI.shared.albumDetail(item.id)
            try MusicProviderContext.shared.check(ticket)
            var object: [String: Any] = ["id": id, "name": metadata?.name ?? item.name, "size": songs.count,
                "picUrl": (metadata?.coverURL ?? item.coverURL)?.absoluteString ?? ""]
            if let artist {
                let artistID = Self.identifier(provider: .qishui, kind: "artist", value: artist.id)
                catalog.artists[artistID] = artist
                object["artist"] = ["id": artistID, "name": artist.name, "picUrl": artist.coverURL?.absoluteString ?? ""]
            }
            let detail = try Self.decode(AlbumDetail.self, object)
            return .init(album: detail, songs: try tracks(songs))
        }
        if provider == .qq {
            let songs = try await QQMusicAPI.shared.albumSongs(mid: item.id)
            try MusicProviderContext.shared.check(ticket)
            let detail = try Self.decode(AlbumDetail.self, ["id": id, "name": item.name, "picUrl": item.coverURL?.absoluteString ?? "", "size": songs.count])
            return .init(album: detail, songs: try tracks(songs))
        }
        let songs = try await KugouMusicAPI.shared.albumSongs(album: item)
        try MusicProviderContext.shared.check(ticket)
        let detail = try Self.decode(AlbumDetail.self, ["id": id, "name": item.name, "picUrl": item.coverURL?.absoluteString ?? "", "size": songs.count,
            "artist": ["id": Self.identifier(provider: .kugou, kind: "artist", value: item.artistName), "name": item.artistName]])
        return .init(album: detail, songs: try tracks(songs))
    }
    func comments(id: Int, sort: SongCommentSort, offset: Int, limit: Int) async throws -> SongCommentsPage {
        let ticket = MusicProviderContext.shared.ticket
        let item = try song(id)
        if provider == .qishui {
            guard let trackID = item.qishui?.trackID else { throw MusicProviderError.missingTrack }
            let page = try await QishuiMusicAPI.shared.comments(trackID: trackID, sort: sort, offset: offset, limit: limit)
            try MusicProviderContext.shared.check(ticket)
            return page
        }
        let comments: [ProviderSongComment], total: Int
        if provider == .qq {
            let page = try await QQMusicAPI.shared.comments(songID: item.id, limit: limit, pagenum: offset / max(1, limit))
            comments = page.comments; total = page.total
        } else {
            let page = try await KugouMusicAPI.shared.comments(mixSongID: item.kugouAlbumAudioId ?? "", hash: item.kugouHash, page: offset / max(1, limit) + 1, limit: limit)
            comments = page.comments; total = page.total
        }
        try MusicProviderContext.shared.check(ticket)
        let mapped: [[String: Any]] = comments.map { comment in
            ["commentId": comment.id, "content": comment.content, "time": comment.time.timeIntervalSince1970 * 1000,
             "likedCount": comment.likedCount, "user": ["userId": 0, "nickname": comment.nickname, "avatarUrl": comment.avatarURL?.absoluteString ?? ""]]
        }
        return try Self.decode(SongCommentsPage.self, ["comments": mapped, "hotComments": mapped, "total": total, "more": !mapped.isEmpty && offset + mapped.count < total])
    }
}

extension PlatformMusicAPI {
    /// Supplies the existing home shelves without inventing another page or
    /// passing external accounts into NetEase's homepage transport.
    func homeDiscovery() async throws -> [HomeDiscoverySlot: HomeDiscoveryContent] {
        let ticket = MusicProviderContext.shared.ticket
        if provider == .qishui {
            let radios = try await QishuiMusicAPI.shared.discoveryRadios()
            await prepareCatalog()
            try MusicProviderContext.shared.check(ticket)
            return [.radios: .playlists(try radios.map { try playlist($0) })]
        }
        if provider == .kugou { return try await kugouHomeDiscovery(ticket: ticket) }
        async let playlists = try? recommendedPlaylists(limit: 30)
        async let songs = try? recommendations()
        async let radios = try? qqHomeRadios()
        async let newSongs = try? qqHomeNewSongs()
        let result = await (playlists, songs, radios, newSongs)
        try MusicProviderContext.shared.check(ticket)
        guard result.0 != nil || result.1 != nil else { throw URLError(.cannotLoadFromNetwork) }
        var content: [HomeDiscoverySlot: HomeDiscoveryContent] = [:]
        if let playlists = result.0 { content[.playlists] = .playlists(playlists) }
        if let songs = result.1 { content[.trending] = .songs(songs) }
        if let radios = result.2 { content[.radios] = .playlists(radios) }
        if let newSongs = result.3 { content[.newSongs] = .songs(newSongs) }
        return content
    }

    /// 酷狗首页：近期热播用“热门好歌精选”卡片，不再与每日推荐重复。
    private func kugouHomeDiscovery(ticket: UUID) async throws -> [HomeDiscoverySlot: HomeDiscoveryContent] {
        let api = KugouMusicAPI.shared
        async let playlists = try? recommendedPlaylists(limit: 30)
        async let hot = try? api.cardSongs(.hot)
        async let forYou = try? api.cardSongs(.forYou)
        async let gems = try? api.cardSongs(.hiddenGems)
        async let fresh = try? api.newSongs()
        let (lists, hotSongs, forYouSongs, gemSongs, newSongs) = await (playlists, hot, forYou, gems, fresh)
        try MusicProviderContext.shared.check(ticket)
        var content: [HomeDiscoverySlot: HomeDiscoveryContent] = [:]
        if let lists { content[.playlists] = .playlists(lists) }
        // 缺失的栏位交给首页各自的兜底或失败重试。
        if let hotSongs, !hotSongs.isEmpty { content[.trending] = .songs(try tracks(hotSongs)) }
        if let forYouSongs, !forYouSongs.isEmpty { content[.forYou] = .songs(try tracks(forYouSongs)) }
        if let newSongs, !newSongs.isEmpty { content[.newSongs] = .songs(try tracks(newSongs)) }
        if let gemSongs, !gemSongs.isEmpty { content[.hiddenGems] = .songs(try tracks(gemSongs)) }
        guard !content.isEmpty else { throw URLError(.cannotLoadFromNetwork) }
        return content
    }

    private func qqHomeNewSongs() async throws -> [Track] {
        guard provider == .qq else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let songs = try await QQMusicAPI.shared.newSongs()
        try MusicProviderContext.shared.check(ticket)
        return try tracks(songs)
    }

    private func qqHomeRadios() async throws -> [PlaylistSummary] {
        guard provider == .qq else { throw MusicProviderError.unsupported }
        guard QQMusicAuth.shared.isLoggedIn else { return [] }
        let ticket = MusicProviderContext.shared.ticket
        let items = try await QQMusicAPI.shared.radios()
        try MusicProviderContext.shared.check(ticket)
        return try items.map { try playlist($0) }
    }
}

extension PlatformMusicAPI {
    func createKugouPlaylist(name: String, isPrivate: Bool) async throws -> Int {
        guard provider == .kugou else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let item = try await KugouMusicAPI.shared.createPlaylist(name: name, isPrivate: isPrivate)
        try MusicProviderContext.shared.check(ticket)
        var pending = catalog.pendingCreated ?? [:]
        pending[Self.identifier(provider: .kugou, kind: "playlist", value: String(item.id))] = item
        catalog.pendingCreated = pending
        return try playlist(item).id
    }

    func deleteKugouPlaylist(id: Int) async throws {
        guard provider == .kugou, let item = catalog.playlists[id], item.source == .kugou,
              item.isOwned == true, item.ownerID == KugouMusicAuth.shared.userId,
              !catalog.charts.contains(id) else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        try await KugouMusicAPI.shared.unsubscribePlaylist(listID: item.id)
        try MusicProviderContext.shared.check(ticket)
        let key = "kugou:\(item.ownerID ?? "")"
        var deleted = catalog.pendingDeleted ?? [:]; deleted[key, default: []].insert(item.id); catalog.pendingDeleted = deleted
        catalog.pendingCreated = catalog.pendingCreated?.filter { !($0.value.source == .kugou && $0.value.ownerID == item.ownerID && $0.value.id == item.id) }
        catalog.playlists[id] = nil
        persist()
    }

    func addKugouPlaylistTracks(id: Int, trackIDs: [Int]) async throws {
        guard provider == .kugou, let item = catalog.playlists[id], item.source == .kugou,
              item.isOwned == true, item.ownerID == KugouMusicAuth.shared.userId,
              !catalog.charts.contains(id) else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let songs = try trackIDs.map(song)
        try await KugouMusicAPI.shared.addSongs(listID: item.id, songs: songs)
        try MusicProviderContext.shared.check(ticket)
    }

    private func ownedKugouPlaylist(_ id: Int) throws -> ProviderPlaylist {
        guard provider == .kugou, let item = catalog.playlists[id], item.source == .kugou,
              item.isOwned == true, item.ownerID == KugouMusicAuth.shared.userId,
              !catalog.charts.contains(id) else { throw MusicProviderError.missingTrack }
        return item
    }

    func removeKugouPlaylistTracks(id: Int, trackIDs: [Int]) async throws {
        let item = try ownedKugouPlaylist(id)
        let ticket = MusicProviderContext.shared.ticket
        try await KugouMusicAPI.shared.deleteSongs(listID: item.id, songs: try trackIDs.map(song))
        try MusicProviderContext.shared.check(ticket)
        AccountStore.shared.invalidateLibrary()
    }

    func renameKugouPlaylist(id: Int, name: String) async throws -> String {
        var item = try ownedKugouPlaylist(id)
        guard !isFavoritesPlaylist(item) else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let verified = try await KugouMusicAPI.shared.renamePlaylist(item, name: name)
        try MusicProviderContext.shared.check(ticket)
        item.name = verified
        catalog.playlists[id] = item
        persist()
        AccountStore.shared.renameCreatedPlaylist(id: id, name: verified)
        return verified
    }

    /// KuGou's 「我喜欢」 is an account list; liking edits that list.
    private func kugouLikedList() async throws -> ProviderPlaylist {
        let owner = KugouMusicAuth.shared.userId
        if let item = catalog.playlists.values.first(where: { $0.source == .kugou && $0.ownerID == owner && $0.isOwned == true && isFavoritesPlaylist($0) }) {
            return item
        }
        _ = try await userPlaylists()
        guard let item = catalog.playlists.values.first(where: { $0.source == .kugou && $0.ownerID == owner && $0.isOwned == true && isFavoritesPlaylist($0) }) else {
            throw ProviderRequestError.unknown("未找到酷狗「我喜欢」歌单，请刷新音乐库后重试")
        }
        return item
    }

    func followKugouArtist(id: Int, follow: Bool) async throws {
        guard provider == .kugou, var item = catalog.artists[id], item.source == .kugou else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        if Int(item.id) == nil {
            let candidates = try await KugouMusicAPI.shared.searchArtists(keyword: item.name)
            guard let resolved = candidates.first(where: { $0.name.localizedCaseInsensitiveCompare(item.name) == .orderedSame && Int($0.id) != nil }) else {
                throw ProviderRequestError.unknown("未能确定酷狗歌手编号，请从搜索结果打开歌手页")
            }
            item = resolved
            catalog.artists[id] = resolved
            persist()
        }
        try await KugouMusicAPI.shared.setFollowed(singerID: Int(item.id) ?? 0, follow: follow)
        try MusicProviderContext.shared.check(ticket)
    }

    func followedKugouArtists() async throws -> [ArtistSummary] {
        let ticket = MusicProviderContext.shared.ticket
        let items = try await KugouMusicAPI.shared.followedSingers()
        try MusicProviderContext.shared.check(ticket)
        return try registerProviderArtists(items, provider: .kugou)
    }

    func subscribeKugouPlaylist(id: Int, subscribe: Bool) async throws {
        guard provider == .kugou, let item = catalog.playlists[id], item.source == .kugou,
              !catalog.charts.contains(id), item.isOwned != true else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let api = KugouMusicAPI.shared
        var updated = item
        if subscribe {
            let source = try await api.collectionSource(item)
            updated = source
            try MusicProviderContext.shared.check(ticket)
            // type=1 creates a server-managed collection with its tracks. It
            // must not be followed by add_song, which rejects collected lists.
            let library = try await userPlaylists()
            try MusicProviderContext.shared.check(ticket)
            if Self.matchingKugouCollection(source: source, lists: library.compactMap { catalog.playlists[$0.id] },
                ownerID: KugouMusicAuth.shared.userId) == nil {
                let saved = try await api.createPlaylist(name: item.name, isPrivate: false, source: source)
                try MusicProviderContext.shared.check(ticket)
                let mapped = try playlist(saved)
                var pending = catalog.pendingCreated ?? [:]; pending[mapped.id] = saved; catalog.pendingCreated = pending
            }
        } else {
            let saved: ProviderPlaylist
            if item.ownerID == KugouMusicAuth.shared.userId { saved = item }
            else {
                let lists = try await api.userPlaylists()
                try MusicProviderContext.shared.check(ticket)
                let source = try await api.collectionSource(item)
                try MusicProviderContext.shared.check(ticket)
                guard let match = Self.matchingKugouCollection(source: source, lists: lists, ownerID: KugouMusicAuth.shared.userId) else {
                    throw ProviderRequestError.unknown("未找到已收藏的酷狗歌单，请刷新歌单列表")
                }
                saved = match
            }
            try await api.unsubscribePlaylist(listID: saved.id)
            try MusicProviderContext.shared.check(ticket)
            catalog.pendingCreated = catalog.pendingCreated?.filter { !($0.value.source == .kugou && $0.value.id == saved.id) }
            catalog.playlists = catalog.playlists.filter { !($0.value.source == .kugou && $0.value.ownerID == saved.ownerID && $0.value.id == saved.id) }
            let key = "kugou:\(KugouMusicAuth.shared.userId)"
            var deleted = catalog.pendingDeleted ?? [:]; deleted[key, default: []].insert(saved.id); catalog.pendingDeleted = deleted
        }
        try MusicProviderContext.shared.check(ticket)
        updated.isSubscribed = subscribe
        catalog.playlists[id] = updated; persist()
    }

    private func collectedKugouPlaylist(for source: ProviderPlaylist) -> ProviderPlaylist? {
        let ownerID = KugouMusicAuth.shared.userId
        let deleted = catalog.pendingDeleted?["kugou:\(ownerID)"] ?? []
        return Self.matchingKugouCollection(source: source,
            lists: catalog.playlists.values.filter { !deleted.contains($0.id) }, ownerID: ownerID)
    }

    static func matchingKugouCollection(source: ProviderPlaylist, lists: [ProviderPlaylist], ownerID: String) -> ProviderPlaylist? {
        guard source.source == .kugou, !ownerID.isEmpty else { return nil }
        return lists.first { saved in
            guard saved.source == .kugou, saved.ownerID == ownerID, saved.isSubscribed == true else { return false }
            let globalID = source.kugouGlobalCollectionID ?? ""
            let sameGlobalID = !globalID.isEmpty && !globalID.hasPrefix("gcid_") &&
                (saved.kugouGlobalCollectionID == globalID || saved.kugouCreateGID == globalID)
            let sameCreator = source.kugouCreateUserID?.isEmpty == false && source.kugouCreateListID?.isEmpty == false &&
                saved.kugouCreateUserID == source.kugouCreateUserID && saved.kugouCreateListID == source.kugouCreateListID
            return sameGlobalID || sameCreator
        }
    }

    func createQQPlaylist(name: String, isPrivate: Bool) async throws -> Int {
        guard provider == .qq else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let item = try await QQMusicAPI.shared.createPlaylist(name: name, isPrivate: isPrivate)
        try MusicProviderContext.shared.check(ticket)
        var pending = catalog.pendingCreated ?? [:]; pending[item.id] = item; catalog.pendingCreated = pending
        let summary = try playlist(item, owned: true)
        AccountStore.shared.insertCreatedPlaylist(summary)
        return summary.id
    }
    func deleteQQPlaylist(id: Int) async throws {
        guard provider == .qq, let item = catalog.playlists[id], item.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        try await QQMusicAPI.shared.deletePlaylist(tid: item.id)
        try MusicProviderContext.shared.check(ticket)
        catalog.pendingCreated?[item.id] = nil
        catalog.playlists[id] = nil
        persist()
        AccountStore.shared.removeCreatedPlaylist(id: id)
    }

    func renamePlaylist(id: Int, name: String) async throws -> String {
        switch provider {
        case .qq: return try await renameQQPlaylist(id: id, name: name)
        case .qishui: return try await renameQishuiPlaylist(id: id, name: name)
        case .kugou: return try await renameKugouPlaylist(id: id, name: name)
        case .netease: throw MusicProviderError.unsupported
        }
    }

    func renameQQPlaylist(id: Int, name: String) async throws -> String {
        guard provider == .qq, var item = catalog.playlists[id], item.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let verified = try await QQMusicAPI.shared.renamePlaylist(tid: item.id, name: name)
        try MusicProviderContext.shared.check(ticket)
        item.name = verified
        catalog.playlists[id] = item
        catalog.pendingCreated?[item.id]?.name = verified
        persist()
        AccountStore.shared.renameCreatedPlaylist(id: id, name: verified)
        return verified
    }

    func updateQQPlaylistTracks(id: Int, trackIDs: [Int], adding: Bool) async throws {
        guard provider == .qq, let item = catalog.playlists[id], item.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let songs = try trackIDs.map(song)
        if item.id == QQMusicAPI.qqLikedPlaylistID, !adding, let song = songs.first, songs.count == 1, let mid = song.qqMid {
            try await QQMusicAPI.shared.like(songID: song.id, songmid: mid, liked: false)
        } else {
            try await QQMusicAPI.shared.updatePlaylistTracks(tid: item.id, songIDs: songs.map(\.id), adding: adding)
        }
        try MusicProviderContext.shared.check(ticket)
        AccountStore.shared.invalidateLibrary()
    }

    func subscribeQQPlaylist(id: Int, subscribe: Bool) async throws {
        guard provider == .qq, let item = catalog.playlists[id], item.source == .qq, item.isQQRadio != true, !catalog.charts.contains(id), item.id > 0 else { throw MusicProviderError.missingTrack }
        guard item.isOwned != true else { throw ProviderRequestError.unknown("不能收藏自己创建的歌单") }
        let ticket = MusicProviderContext.shared.ticket
        try await QQMusicAPI.shared.subscribePlaylist(id: item.id, subscribe: subscribe)
        try MusicProviderContext.shared.check(ticket)
        var updated = item; updated.isSubscribed = subscribe
        catalog.playlists[id] = updated; persist()
    }
    func qqAlbumSubscribed(id: Int) async throws -> Bool {
        guard provider == .qq, let album = catalog.albums[id], album.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let subscribed = try await QQMusicAPI.shared.albumSubscribed(mid: album.id)
        try MusicProviderContext.shared.check(ticket)
        return subscribed
    }

    func subscribeQQAlbum(id: Int, subscribe: Bool) async throws {
        guard provider == .qq, let album = catalog.albums[id], album.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        try await QQMusicAPI.shared.subscribeAlbum(mid: album.id, subscribe: subscribe)
        try MusicProviderContext.shared.check(ticket)
    }

    func qqArtistFollowed(id: Int) async throws -> Bool {
        guard provider == .qq, let artist = catalog.artists[id], artist.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        let followed = try await QQMusicAPI.shared.artistFollowed(mid: artist.id, name: artist.name)
        try MusicProviderContext.shared.check(ticket)
        return followed
    }

    func followQQArtist(id: Int, follow: Bool) async throws {
        guard provider == .qq, let artist = catalog.artists[id], artist.source == .qq else { throw MusicProviderError.missingTrack }
        let ticket = MusicProviderContext.shared.ticket
        try await QQMusicAPI.shared.followArtist(mid: artist.id, follow: follow, name: artist.name)
        try MusicProviderContext.shared.check(ticket)
    }

    func createQishuiPlaylist(name: String, isPrivate: Bool) async throws -> Int {
        guard provider == .qishui else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let item = try await QishuiMusicAPI.shared.createPlaylist(name: name, isPrivate: isPrivate)
        try MusicProviderContext.shared.check(ticket)
        var pending = catalog.pendingCreated ?? [:]
        pending[item.id] = item
        catalog.pendingCreated = pending
        let summary = try playlist(item)
        AccountStore.shared.insertCreatedPlaylist(summary)
        return summary.id
    }

    /// Only the account's own, non-favorites playlists accept edits.
    private func ownedQishuiPlaylist(_ id: Int) throws -> ProviderPlaylist {
        guard provider == .qishui, let item = catalog.playlists[id], item.source == .qishui,
              let reference = item.qishui, reference.radio == nil, !isQishuiChart(id), !isFavoritesPlaylist(item),
              item.ownerID == QishuiMusicAPI.shared.userID || AccountStore.shared.createdPlaylists.contains(where: { $0.id == id })
        else { throw MusicProviderError.unsupported }
        return item
    }

    func deleteQishuiPlaylist(id: Int) async throws {
        let item = try ownedQishuiPlaylist(id)
        let ticket = MusicProviderContext.shared.ticket
        try await QishuiMusicAPI.shared.deletePlaylist(id: item.qishui?.playlistID ?? "")
        try MusicProviderContext.shared.check(ticket)
        catalog.pendingCreated?[item.id] = nil
        catalog.playlists[id] = nil
        persist()
        AccountStore.shared.removeCreatedPlaylist(id: id)
    }

    func renameQishuiPlaylist(id: Int, name: String) async throws -> String {
        var item = try ownedQishuiPlaylist(id)
        let ticket = MusicProviderContext.shared.ticket
        let verified = try await QishuiMusicAPI.shared.renamePlaylist(id: item.qishui?.playlistID ?? "", name: name)
        try MusicProviderContext.shared.check(ticket)
        item.name = verified
        catalog.playlists[id] = item
        catalog.pendingCreated?[item.id]?.name = verified
        persist()
        AccountStore.shared.renameCreatedPlaylist(id: id, name: verified)
        return verified
    }

    func updateQishuiPlaylistTracks(id: Int, trackIDs: [Int], adding: Bool) async throws {
        let item = try ownedQishuiPlaylist(id)
        let remoteIDs = try trackIDs.map { trackID -> String in
            let song = try song(trackID)
            guard song.source == .qishui, let remote = song.qishui?.trackID, !remote.isEmpty else { throw MusicProviderError.missingTrack }
            return remote
        }
        let ticket = MusicProviderContext.shared.ticket
        let playlistID = item.qishui?.playlistID ?? ""
        if adding {
            try await QishuiMusicAPI.shared.appendPlaylistTracks(playlistID: playlistID, trackIDs: remoteIDs)
        } else {
            try await QishuiMusicAPI.shared.deletePlaylistTracks(playlistID: playlistID, trackIDs: remoteIDs)
        }
        try MusicProviderContext.shared.check(ticket)
        AccountStore.shared.invalidateLibrary()
    }

    func setQishuiCollection(_ kind: QishuiMusicAPI.CollectionKind, id: Int, saved: Bool) async throws {
        guard provider == .qishui else { throw MusicProviderError.unsupported }
        let remoteID: String
        switch kind {
        case .playlist:
            guard let item = catalog.playlists[id], item.source == .qishui,
                  !isQishuiChart(id),
                  let reference = item.qishui, reference.radio == nil,
                  !isFavoritesPlaylist(item), item.ownerID != QishuiMusicAPI.shared.userID,
                  !AccountStore.shared.createdPlaylists.contains(where: { $0.id == id }) else {
                throw MusicProviderError.unsupported
            }
            remoteID = reference.playlistID
        case .album:
            guard let item = catalog.albums[id], item.source == .qishui else { throw MusicProviderError.missingTrack }
            remoteID = item.id
        case .artist:
            guard let item = catalog.artists[id], item.source == .qishui else { throw MusicProviderError.missingTrack }
            remoteID = item.id
        }
        let ticket = MusicProviderContext.shared.ticket
        try await QishuiMusicAPI.shared.setCollection(kind, id: remoteID, saved: saved)
        try MusicProviderContext.shared.check(ticket)
        SidebarResources.libraryChanged()
    }

    func qishuiLikedAlbums() async throws -> [AlbumSummary] {
        guard provider == .qishui else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let rows = try await QishuiMusicAPI.shared.collectionItems(.album)
        try MusicProviderContext.shared.check(ticket)
        let albums = try rows.compactMap(QishuiMusicAPI.albumMetadata).map { item in
            let id = Self.identifier(provider: .qishui, kind: "album", value: item.id)
            catalog.albums[id] = item
            return try Self.decode(AlbumSummary.self, ["id": id, "name": item.name,
                "picUrl": item.coverURL?.absoluteString ?? "", "artist": ["name": item.artistName],
                "size": item.trackCount ?? 0, "publishTime": item.releaseDateMS ?? 0])
        }
        persist()
        return albums
    }

    func qishuiFollowedArtists() async throws -> [ArtistSummary] {
        guard provider == .qishui else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let rows = try await QishuiMusicAPI.shared.collectionItems(.artist)
        try MusicProviderContext.shared.check(ticket)
        let artists = try rows.compactMap(QishuiMusicAPI.artistMetadata).map { item in
            let id = Self.identifier(provider: .qishui, kind: "artist", value: item.id)
            catalog.artists[id] = item
            return try Self.decode(ArtistSummary.self, ["id": id, "name": item.name,
                "picUrl": item.coverURL?.absoluteString ?? "", "followed": true])
        }
        persist()
        return artists
    }

    func likedQQAlbums() async throws -> [AlbumSummary] {
        guard provider == .qq else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let albums = try await QQMusicAPI.shared.favoriteAlbums()
        try MusicProviderContext.shared.check(ticket)
        let result = try albums.map { item in
            let id = Self.identifier(provider: .qq, kind: "album", value: item.id)
            catalog.albums[id] = item
            return try Self.decode(AlbumSummary.self, ["id": id, "name": item.name, "artist": ["name": item.artistName],
                "picUrl": item.coverURL?.absoluteString ?? "", "size": item.trackCount ?? 0])
        }
        persist()
        return result
    }

    func followedQQArtists() async throws -> [ArtistSummary] {
        guard provider == .qq else { throw MusicProviderError.unsupported }
        let ticket = MusicProviderContext.shared.ticket
        let artists = try await QQMusicAPI.shared.followedArtists()
        try MusicProviderContext.shared.check(ticket)
        let result = try artists.map { item in
            let id = Self.identifier(provider: .qq, kind: "artist", value: item.id)
            catalog.artists[id] = item
            return try Self.decode(ArtistSummary.self, ["id": id, "name": item.name, "picUrl": item.coverURL?.absoluteString ?? "", "followed": true])
        }
        persist(); return result
    }
}


extension PlatformMusicAPI {
    static func reconcileDeletedPlaylists(remote: [ProviderPlaylist], pending: Set<Int>)
        -> (visible: [ProviderPlaylist], remaining: Set<Int>) {
        (remote.filter { !pending.contains($0.id) }, pending.intersection(Set(remote.map(\.id))))
    }

    static func mergePendingPlaylists(remote: [ProviderPlaylist], pending: [Int: ProviderPlaylist], ownerID: String)
        -> (visible: [ProviderPlaylist], remaining: [Int: ProviderPlaylist]) {
        let ids = Set(remote.map(\.id))
        var remaining = pending
        for (id, item) in pending where item.ownerID == ownerID && ids.contains(item.id) { remaining[id] = nil }
        return (remote + remaining.values.filter { $0.ownerID == ownerID }.sorted { $0.id < $1.id }, remaining)
    }
}
