import Foundation

/// Third-party parsing services, called directly over HTTP.
/// Each endpoint takes one platform's song ID and answers with a stream that
/// may come from another platform, so the returned song is checked again.
struct ParserEndpoint: Sendable {
    enum Platform: String, Sendable {
        /// NetEase song ID.
        case wy
        /// KuGou file hash.
        case kg
    }

    let name: String
    let platform: Platform
    /// Mirrors serving the same API, tried in order.
    let hosts: [String]
    let path: String

    func url(host: String, id: String, level: String) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        components.queryItems = [
            URLQueryItem(name: "type", value: "json"),
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "level", value: level),
        ]
        return components.url
    }

    /// Endpoints confirmed to return full-length streams; add a row to add one.
    static let all: [ParserEndpoint] = [
        ParserEndpoint(name: "wy", platform: .wy,
                       hosts: ["musicapi.haitangw.net", "music.haitangw.cc"], path: "/music/wy_song_kw.php"),
        ParserEndpoint(name: "kg", platform: .kg,
                       hosts: ["musicapi.haitangw.net", "music.haitangw.cc"], path: "/music/kg_song_kw.php"),
    ]
}

struct ParserUnblockSource: UnblockSource {
    let id = AudioSourceID.parser
    private let httpClient: AudioSourceClient
    private let endpoints: [ParserEndpoint]

    init(httpClient: AudioSourceClient = .shared, endpoints: [ParserEndpoint] = ParserEndpoint.all) {
        self.httpClient = httpClient
        self.endpoints = endpoints
    }

    func isAvailable() async -> Bool { true }
    func isSignedIn() async -> Bool { false }

    /// The services' NetEase-style levels. Their Hi-Res answer is a low-rate
    /// AAC preview, so everything above CD class asks for lossless.
    static func level(for quality: AudioQuality) -> String {
        switch quality {
        case .standard: return "standard"
        case .higher, .exhigh: return "exhigh"
        case .lossless, .hires, .jyeffect, .sky, .jymaster: return "lossless"
        }
    }

    func resolve(_ query: UnblockQuery, quality: AudioQuality) async throws -> UnblockStream? {
        let level = Self.level(for: quality)
        var lastError: Error?
        for endpoint in endpoints {
            do {
                guard let songID = try await songID(for: endpoint.platform, query: query) else { continue }
                if let stream = try await resolve(endpoint, songID: songID, level: level, query: query) {
                    return stream
                }
            } catch {
                lastError = error
            }
        }
        if let lastError { throw lastError }
        return nil
    }

    func qualityOptions(_ query: UnblockQuery) async throws -> [AudioQualityOption] {
        var options: [AudioQualityOption] = []
        for tier: AudioQuality in [.standard, .exhigh, .lossless] {
            guard let stream = try? await resolve(query, quality: tier), let served = stream.quality,
                  !options.contains(where: { $0.quality == served }) else { continue }
            options.append(.init(quality: served, title: stream.title ?? AudioQualityOption.unifiedTitle(quality: served)))
        }
        return options
    }

    private func songID(for platform: ParserEndpoint.Platform, query: UnblockQuery) async throws -> String? {
        switch platform {
        case .wy:
            return try await NeteaseSongLookup.shared.songID(for: query).map(String.init)
        case .kg:
            let api = await UnblockSessionPool.shared.kugouAPI()
            let song = try await UnblockMatchCache.shared.song(.kugou, query) {
                try await api.searchSongs(keyword: query.keyword, limit: 10)
            }
            return song?.kugouHash?.uppercased()
        }
    }

    private func resolve(_ endpoint: ParserEndpoint, songID: String, level: String,
                         query: UnblockQuery) async throws -> UnblockStream? {
        var lastError: Error?
        for host in endpoint.hosts {
            guard let url = endpoint.url(host: host, id: songID, level: level) else { continue }
            let data: Data
            do {
                data = try await httpClient.data(from: url, source: id, operation: "resolve-\(endpoint.name)")
            } catch {
                // A dead mirror falls through to the next one.
                lastError = error
                continue
            }
            guard let answer = Self.Answer(data) else { throw AudioSourceProviderError.invalidResponse }
            // The service answered; a miss here is a miss on every mirror.
            guard let candidate = answer.candidate(for: query) else { return nil }
            return await Self.stream(candidate, query: query)
        }
        if let lastError { throw lastError }
        return nil
    }

    /// A verified stream from one answer.
    struct Candidate: Equatable {
        let url: String
        let durationMS: Int
        let byteCount: Double?
    }

    /// One parsed service answer.
    struct Answer: Equatable {
        let code: Int
        let name: String
        let artist: String
        let album: String
        let durationMS: Int?
        let byteCount: Double?
        let url: String?

        init?(_ data: Data) {
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let code = (object["code"] as? NSNumber)?.intValue else { return nil }
            let payload = object["data"] as? [String: Any] ?? [:]
            self.code = code
            name = payload["name"] as? String ?? ""
            artist = payload["artist"] as? String ?? ""
            album = payload["album"] as? String ?? ""
            durationMS = (payload["duration"] as? String).flatMap(Self.durationMS)
            byteCount = (payload["size"] as? String).flatMap(Self.byteCount)
            url = (payload["url"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        }

        /// The stream when it is the same recording as the query. A missing
        /// duration (the KuGou endpoint omits it) is checked by size instead.
        func candidate(for query: UnblockQuery) -> Candidate? {
            guard code == 200, let url else { return nil }
            let duration = durationMS ?? query.durationMS
            let candidate = UnblockCandidate(title: name, artist: artist, album: album,
                                             durationMS: duration, payload: ())
            guard AudioSourceTrackMatcher.score(query, candidate) != nil else { return nil }
            return Candidate(url: url, durationMS: duration, byteCount: byteCount)
        }

        /// "4分29秒" → 269000.
        static func durationMS(_ text: String) -> Int? {
            let scanner = Scanner(string: text)
            var seconds = 0
            var found = false
            while !scanner.isAtEnd {
                guard let value = scanner.scanInt() else {
                    _ = scanner.scanCharacter()
                    continue
                }
                let unit = scanner.scanCharacter()
                switch unit {
                case "时": seconds += value * 3600
                case "分": seconds += value * 60
                case "秒", nil: seconds += value
                default: continue
                }
                found = true
            }
            return found && seconds > 0 ? seconds * 1000 : nil
        }

        /// "52.83 MB" → bytes.
        static func byteCount(_ text: String) -> Double? {
            let parts = text.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard let number = parts.first.flatMap({ Double($0) }), number > 0 else { return nil }
            switch parts.dropFirst().first?.uppercased() ?? "B" {
            case "KB": return number * 1024
            case "MB": return number * 1024 * 1024
            case "GB": return number * 1024 * 1024 * 1024
            default: return number
            }
        }
    }

    /// Streams below this are previews or placeholders, not the track.
    static let minimumBitrate: Double = 96_000

    private static func stream(_ candidate: Candidate, query: UnblockQuery) async -> UnblockStream? {
        let address = candidate.url.replacingOccurrences(of: "http://", with: "https://")
        guard let url = URL(string: address) else { return nil }
        let seconds = Double(candidate.durationMS) / 1000
        let bitrate = candidate.byteCount.flatMap { seconds > 0 ? $0 * 8 / seconds : nil }
        if let bitrate, bitrate < minimumBitrate { return nil }
        let served: AudioQuality?
        if url.pathExtension.lowercased() == "flac" {
            let client = await UnblockSessionPool.shared.neteaseClient()
            served = await client.playbackMediaTier(url: address, bitrate: bitrate) ?? .lossless
        } else {
            // Sizes are rounded, so 4.12 MB of 128 kbps reads as 128.5 kbps.
            served = AudioQualityCheck.lossyTier(bitrate: bitrate.map { $0 * 0.95 })
        }
        let title = served.map {
            AudioQualityOption.unifiedTitle(quality: $0, reportedBitrate: nil,
                                            byteCount: candidate.byteCount, durationSeconds: seconds)
        }
        return UnblockStream(url: url, quality: served, bitrate: bitrate.map { Int($0) }, title: title)
    }
}
