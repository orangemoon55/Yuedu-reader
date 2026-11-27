// Adapted from WXRIW/Lyricify-Lyrics-Helper (Apache-2.0).
// Swift port of QQMusic/LRCLIB/Kugou providers and KRC decoding; see ThirdPartyNotices.
import Foundation
import zlib

enum LyricsSource: String, CaseIterable, Identifiable {
    case automatic, netease, qqMusic, kugou, qishui, lrclib
    static let providers: [Self] = [.netease, .qqMusic, .kugou, .qishui, .lrclib]
    var id: String { rawValue }
    var title: String {
        switch self {
        case .automatic: return "自动优选"
        case .netease: return "网易云音乐"
        case .qqMusic: return "QQ 音乐"
        case .kugou: return "酷狗音乐"
        case .qishui: return "汽水音乐"
        case .lrclib: return "LRCLIB"
        }
    }
    static func saved(for trackID: Int, defaults: UserDefaults = .standard) -> Self {
        let sources = defaults.dictionary(forKey: "lyrics.trackSources") as? [String: String] ?? [:]
        return sources[String(trackID)].flatMap(Self.init(rawValue:)) ?? .automatic
    }
    func save(for trackID: Int, defaults: UserDefaults = .standard) {
        var sources = defaults.dictionary(forKey: "lyrics.trackSources") as? [String: String] ?? [:]
        sources[String(trackID)] = self == .automatic ? nil : rawValue
        defaults.set(sources, forKey: "lyrics.trackSources")
    }
}

extension LyricsSource {
    /// The toast for a failed lyrics load. A source with no lyrics for the
    /// song is only worth saying when the user picked that source; automatic
    /// loads on every track change stay quiet about it.
    func failureToast(for error: Error, userInitiated: Bool, keptLyrics: Bool) -> String? {
        guard (error as? AlternativeLyricsAPI.Failure) == .noMatch else {
            return String(localized: "\(title)：\(error.localizedDescription)")
        }
        guard userInitiated else { return nil }
        if self == .automatic { return String(localized: "未找到这首歌的同步歌词") }
        return keptLyrics
            ? String(localized: "\(title)没有这首歌的歌词，已保留当前歌词")
            : String(localized: "\(title)没有这首歌的歌词，可尝试其他来源")
    }
}

enum AlternativeLyricsAPI {
    enum Failure: LocalizedError {
        case noMatch, invalidResponse
        var errorDescription: String? {
            switch self {
            case .noMatch: return "此来源没有找到匹配的同步歌词，请尝试其他来源。"
            case .invalidResponse: return "歌词来源暂时不可用，请稍后重试或切换来源。"
            }
        }
    }

    static func resolve(track: Track, source: LyricsSource,
                        onUpdate: (@Sendable (LyricsSelection) async -> Void)? = nil) async throws -> LyricsSelection {
        try Task.checkCancellation()
        if source == .automatic {
            if let cached = await LyricsSelectionCache.shared.value(for: track) { return cached }
            let selection = try await automatic(track: track, onUpdate: onUpdate) { source in
                try await candidates(track: track, source: source)
            }
            try Task.checkCancellation()
            await LyricsSelectionCache.shared.store(selection, for: track)
            return selection
        }
        let results = try await candidates(track: track, source: source)
        try Task.checkCancellation()
        guard let selection = LyricsMatching.best(results, for: track) else { throw Failure.noMatch }
        return selection
    }

    /// Each provider runs independently with a deadline. Arrival order does not
    /// affect ranking, and a missing or broken provider cannot discard good hits.
    static func automatic(track: Track, timeout: TimeInterval = 12,
                          onUpdate: (@Sendable (LyricsSelection) async -> Void)? = nil,
                          loader: @escaping @Sendable (LyricsSource) async throws -> [LyricsCandidate]) async throws -> LyricsSelection {
        let results = await withTaskGroup(of: [LyricsCandidate].self) { group in
            for source in LyricsSource.providers {
                group.addTask {
                    await withTaskGroup(of: [LyricsCandidate].self) { race in
                        race.addTask { (try? await loader(source)) ?? [] }
                        race.addTask {
                            try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                            return []
                        }
                        let first = await race.next() ?? []
                        race.cancelAll()
                        return first
                    }
                }
            }
            var all: [LyricsCandidate] = []
            var previousSource: LyricsSource?
            for await candidates in group {
                all.append(contentsOf: candidates)
                if !Task.isCancelled, let best = LyricsMatching.best(all, for: track), best.source != previousSource {
                    previousSource = best.source
                    await onUpdate?(best)
                }
            }
            return all
        }
        try Task.checkCancellation()
        guard let selection = LyricsMatching.best(results, for: track) else { throw Failure.noMatch }
        return selection
    }

    private static func candidates(track: Track, source: LyricsSource) async throws -> [LyricsCandidate] {
        try Task.checkCancellation()
        switch source {
        case .automatic: return []
        case .netease:
            // A QQ, Kugou or Qishui track's id is a local handle, not a Netease id.
            guard track.platformSong == nil else { return [] }
            let response = try await NeteaseAPI.lyric(id: track.id)
            return [LyricsCandidate(source: .netease, id: String(track.id), title: track.name,
                artists: track.artists.map(\.name), album: track.album.name, duration: track.duration,
                response: response, matchedByID: true)]
        case .qqMusic: return try await qqMusic(track)
        case .kugou: return try await kugou(track)
        case .qishui: return try await qishui(track)
        case .lrclib: return try await lrclib(track)
        }
    }

    private static func qishui(_ track: Track) async throws -> [LyricsCandidate] {
        let api = await QishuiMusicAPI.shared
        if let id = track.platformSong?.qishui?.trackID, !id.isEmpty {
            let response = try await api.lyric(trackID: id)
            return [LyricsCandidate(source: .qishui, id: id, title: track.name,
                artists: track.artists.map(\.name), album: track.album.name, duration: track.duration,
                response: response, matchedByID: true)]
        }

        let keyword = ([track.name] + track.artists.prefix(1).map(\.name)).joined(separator: " ")
        let page = try await api.search(keyword: keyword, playlists: false, limit: 15, offset: 0)
        let matches = await rankedHits(page.songs.filter { $0.qishui?.trackID.isEmpty == false }, track: track) {
            ($0.name, [$0.artists], $0.album, $0.duration)
        }
        var results: [LyricsCandidate] = []
        for song in matches.prefix(3) {
            try Task.checkCancellation()
            guard let id = song.qishui?.trackID else { continue }
            if let response = try? await api.lyric(trackID: id) {
                results.append(LyricsCandidate(source: .qishui, id: id, title: song.name,
                    artists: [song.artists], album: song.album, duration: song.duration, response: response))
            }
        }
        return results
    }

    private static func request(_ base: String, query: [String: String] = [:], body: [String: Any]? = nil,
                                referer: String? = nil) async throws -> [String: Any] {
        var components = URLComponents(string: base)!
        if !query.isEmpty { components.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) } }
        var request = URLRequest(url: components.url!, timeoutInterval: 18)
        // Third-party requests never share the music account's cookies.
        request.httpShouldHandleCookies = false
        request.setValue("Coda/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue(referer, forHTTPHeaderField: "Referer")
        if let body {
            request.httpMethod = "POST"
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard let http = response as? HTTPURLResponse else { throw Failure.invalidResponse }
        if http.statusCode == 404 { throw Failure.noMatch }
        guard (200..<300).contains(http.statusCode) else { throw Failure.invalidResponse }
        let json = try JSONSerialization.jsonObject(with: data)
        if let object = json as? [String: Any] { return object }
        if let list = json as? [[String: Any]] { return ["results": list] }
        throw Failure.invalidResponse
    }

    static func response(lrc: String, translation: String? = nil, yrc: String? = nil) throws -> LyricResponse {
        guard !LyricsParser.parseLRC(lrc).isEmpty else { throw Failure.noMatch }
        return LyricResponse(lrc: .init(lyric: lrc), tlyric: translation.map { .init(lyric: $0) },
                             romalrc: nil, yrc: yrc.map { .init(lyric: $0) }, ytlrc: nil, yromalrc: nil,
                             lyricUser: nil, transUser: nil, nolyric: nil, uncollected: nil)
    }

    /// The shared instrumental marker, for platforms that flag instrumentals
    /// outside the lyric text (Kugou's language, Qishui's vocal, LRCLIB's
    /// instrumental) or in their own wording (QQ Music).
    static func instrumentalResponse() -> LyricResponse {
        var response = LyricResponse(lrc: .init(lyric: "[00:00.00]纯音乐，请欣赏"), tlyric: nil, romalrc: nil, yrc: nil,
                                     ytlrc: nil, yromalrc: nil, lyricUser: nil, transUser: nil, nolyric: nil, uncollected: nil)
        response.pureMusic = true
        return response
    }

    /// Ranks search hits by metadata. When some hit names the song but none
    /// is accepted, the track's catalog aliases are loaded once (cached per
    /// artist) and the hits ranked again: "李闰珉" may be "Yiruma".
    static func rankedHits<Hit>(_ hits: [Hit], track: Track,
                                metadata: (Hit) -> (title: String, artists: [String], album: String?, duration: Double?)) async -> [Hit] {
        func ranked() -> [Hit] {
            hits.compactMap { hit -> (Hit, Double)? in
                let item = metadata(hit)
                return LyricsMatching.metadataScore(title: item.title, artists: item.artists, album: item.album,
                                                    duration: item.duration, track: track).map { (hit, $0) }
            }.sorted { $0.1 > $1.1 }.map(\.0)
        }
        let first = ranked()
        guard first.isEmpty, hits.contains(where: { LyricsMatching.titleMatch(metadata($0).title, track: track) != nil }) else {
            return first
        }
        await LyricsArtistAliases.shared.load(for: track)
        return ranked()
    }

    static func matchScore(title: String, artist: String, duration: Double, track: Track) -> Double? {
        guard LyricsMatching.metadataScore(title: title, artists: [artist], album: nil, duration: duration,
                                          track: track, instrumental: false) != nil else { return nil }
        return abs(duration - track.duration)
    }

    private static func makeCandidate(source: LyricsSource, id: String, title: String, artists: [String],
                                      album: String?, duration: Double?, response: LyricResponse, track: Track,
                                      matchedByID: Bool = false) -> LyricsCandidate? {
        let candidate = LyricsCandidate(source: source, id: id, title: title, artists: artists,
                                        album: album, duration: duration, response: response, matchedByID: matchedByID)
        return LyricsMatching.score(candidate, for: track) == nil ? nil : candidate
    }

    private static func lrclib(_ track: Track) async throws -> [LyricsCandidate] {
        // Search exposes album and duration for every recording. The exact get
        // endpoint can hide a better album match behind its single result.
        let search = try await request("https://lrclib.net/api/search", query: ["track_name": track.name,
            "artist_name": track.artists.first?.name ?? track.artistNames])
        return (search["results"] as? [[String: Any]] ?? []).compactMap { item in
            let instrumental = item["instrumental"] as? Bool == true
            guard let response = instrumental ? instrumentalResponse()
                    : try? response(lrc: item["syncedLyrics"] as? String ?? "") else { return nil }
            return makeCandidate(source: .lrclib, id: String(describing: item["id"] ?? ""),
                title: item["trackName"] as? String ?? "", artists: [item["artistName"] as? String ?? ""],
                album: item["albumName"] as? String, duration: (item["duration"] as? NSNumber)?.doubleValue,
                response: response, track: track)
        }
    }

    private static func qqMusic(_ track: Track) async throws -> [LyricsCandidate] {
        // A QQ Music track names its own recording; no search can do better.
        // If that fetch fails, searching remains possible.
        if let song = track.platformSong, song.source == .qq, let mid = song.qqMid, !mid.isEmpty {
            do {
                let response = try await qqLyrics(songID: song.id > 0 ? song.id : nil, mid: mid)
                return [LyricsCandidate(source: .qqMusic, id: mid, title: track.name, artists: track.artists.map(\.name),
                    album: track.album.name, duration: track.duration, response: response, matchedByID: true)]
            } catch { try Task.checkCancellation() }
        }
        let body: [String: Any] = ["req_1": ["method": "DoSearchForQQMusicDesktop", "module": "music.search.SearchCgiService",
            "param": ["num_per_page": 20, "page_num": 1, "query": "\(track.name) \(track.artistNames)", "search_type": 0]]]
        let json = try await request("https://u6.y.qq.com/cgi-bin/musicu.fcg", body: body, referer: "https://c.y.qq.com/")
        let req = json["req_1"] as? [String: Any]
        let data = req?["data"] as? [String: Any]
        let bodyData = data?["body"] as? [String: Any]
        let songs = ((bodyData?["song"] as? [String: Any])?["list"] as? [[String: Any]] ?? []).filter { $0["mid"] is String }
        func artists(_ song: [String: Any]) -> [String] {
            (song["singer"] as? [[String: Any]] ?? []).compactMap { $0["name"] as? String }
        }
        func album(_ song: [String: Any]) -> String? { (song["album"] as? [String: Any])?["name"] as? String }
        let matches = await rankedHits(songs, track: track) {
            ($0["title"] as? String ?? "", artists($0), album($0), ($0["interval"] as? NSNumber)?.doubleValue)
        }
        var results: [LyricsCandidate] = []
        for song in matches.prefix(3) {
            try Task.checkCancellation()
            let mid = song["mid"] as! String
            do {
                let response = try await qqLyrics(songID: (song["id"] as? NSNumber)?.intValue, mid: mid)
                if let candidate = makeCandidate(source: .qqMusic, id: mid, title: song["title"] as? String ?? "",
                    artists: artists(song), album: album(song),
                    duration: (song["interval"] as? NSNumber)?.doubleValue, response: response, track: track) {
                    results.append(candidate)
                }
            } catch { try Task.checkCancellation() }
        }
        return results
    }

    private static func qqLyrics(songID: Int?, mid: String) async throws -> LyricResponse {
        if let songID {
            for requestsQRC in [true, false] {
                do {
                    let payload = try await qqPlayLyricInfo(songID: songID, mid: mid, requestsQRC: requestsQRC)
                    let response = try qqLyricsResponse(payload, base64Encoded: true)
                    guard response.yrc != nil else { return response }
                    // QQ's line timeline may differ from its QRC timeline.
                    // Preserve both so the shared parser can align translations.
                    var fallbackLRC: String?
                    do {
                        let fallback = try await qqPlayLyricInfo(songID: songID, mid: mid, requestsQRC: false)
                        fallbackLRC = try qqLyricsResponse(fallback, base64Encoded: true).lrc?.lyric
                    } catch { try Task.checkCancellation() }
                    return try qqLyricsResponse(payload, base64Encoded: true, fallbackLRC: fallbackLRC)
                } catch { try Task.checkCancellation() }
            }
        }
        let json = try await request("https://c.y.qq.com/lyric/fcgi-bin/fcg_query_lyric_new.fcg",
            query: ["songmid": mid, "format": "json", "nobase64": "1", "g_tk": "5381", "platform": "yqq"],
            referer: "https://c.y.qq.com/")
        return try qqLyricsResponse(json, base64Encoded: false)
    }

    private static func qqPlayLyricInfo(songID: Int, mid: String, requestsQRC: Bool) async throws -> [String: Any] {
        // Request QRC first, following MeloX's QQ Music client profile.
        let body: [String: Any] = ["comm": ["ct": 11, "cv": "1003006", "uin": 0, "tmeAppID": "qqmusiclight"],
            "req_0": ["module": "music.musichallSong.PlayLyricInfo", "method": "GetPlayLyricInfo",
                      "param": ["songID": songID, "songMID": mid, "crypt": 1, "ct": 19, "cv": 2111,
                                "trans": 1, "roma": 0, "qrc": requestsQRC ? 1 : 0,
                                "qrc_t": 0, "lrc_t": 0, "trans_t": 0, "type": 0]]]
        let data = try JSONSerialization.data(withJSONObject: body)
        let json = try await request("https://u.y.qq.com/cgi-bin/musicu.fcg",
            query: ["data": String(decoding: data, as: UTF8.self)], referer: "https://y.qq.com/")
        guard (json["code"] as? Int) == 0,
              let result = json["req_0"] as? [String: Any], (result["code"] as? Int) == 0,
              let lyrics = result["data"] as? [String: Any] else { throw Failure.invalidResponse }
        return lyrics
    }

    static func qqLyricsResponse(_ json: [String: Any], base64Encoded: Bool,
                                 fallbackLRC: String? = nil) throws -> LyricResponse {
        guard let original = json["lyric"] as? String else { throw Failure.invalidResponse }
        func decoded(_ text: String) -> String? {
            if !base64Encoded { return decodeEntities(text) }
            // QRC remains encrypted hex even when the response says crypt=0.
            if let decoded = QQMusicLyricDecoder.decode(text) { return decoded }
            guard let data = Data(base64Encoded: text), let value = String(data: data, encoding: .utf8) else { return nil }
            return decodeEntities(value)
        }
        guard let lrc = decoded(original) else { throw Failure.invalidResponse }
        // QQ Music marks instrumentals with its own sentence, at "[00:00:00]".
        if isQQInstrumental(lrc) { return instrumentalResponse() }
        let translation = (json["trans"] as? String).flatMap(decoded).map { text in
            text.components(separatedBy: .newlines).filter { line in
                line.replacingOccurrences(of: #"\[[^\]]*\]"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespacesAndNewlines) != "//"
            }.joined(separator: "\n")
        }
        let yrc = QRCLyricNormalizer.normalize(lrc)
        if !yrc.isEmpty {
            let lines = LyricsParser.parseYRC(yrc)
            guard lines.contains(where: { $0.words?.isEmpty == false }) else { throw Failure.invalidResponse }
            let generatedLRC = lines.map { line in
                let milliseconds = Int((line.time * 1000).rounded())
                return String(format: "[%02d:%02d.%03d]%@", milliseconds / 60000,
                              milliseconds / 1000 % 60, milliseconds % 1000, line.text)
            }.joined(separator: "\n")
            return try response(lrc: fallbackLRC ?? generatedLRC, translation: translation, yrc: yrc)
        }
        return try response(lrc: lrc, translation: translation)
    }

    private static func decodeEntities(_ text: String) -> String {
        var value = text
        for (entity, replacement) in [("&#39;", "'"), ("&apos;", "'"), ("&quot;", "\""), ("&lt;", "<"), ("&gt;", ">"), ("&amp;", "&")] {
            value = value.replacingOccurrences(of: entity, with: replacement)
        }
        return value
    }

    static func isQQInstrumental(_ lyric: String) -> Bool {
        let lines = lyric.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lines.count <= 10 && lines.contains { $0.contains("没有填词的纯音乐") || $0.contains("纯音乐，请欣赏") }
    }

    private static func kugou(_ track: Track) async throws -> [LyricsCandidate] {
        // A Kugou track's hash names its recording; those hits need no metadata
        // match (they are often titled without the "(Live)" the track carries).
        var hashed: [[String: Any]] = []
        if let hash = track.platformSong?.kugouHash, !hash.isEmpty {
            let json = try? await request("https://lyrics.kugou.com/search", query: ["ver": "1", "man": "yes", "client": "pc",
                "hash": hash, "duration": String(track.durationMS)])
            hashed = json?["candidates"] as? [[String: Any]] ?? []
        }
        var matches = hashed.map { ($0, true) }
        if matches.isEmpty {
            let json = try await request("https://lyrics.kugou.com/search", query: ["ver": "1", "man": "yes", "client": "pc",
                "keyword": LyricsTitle.searchKeyword(for: track), "duration": String(track.durationMS)])
            // This endpoint has no album field; leave it unknown in the shared score.
            matches = await rankedHits(json["candidates"] as? [[String: Any]] ?? [], track: track) {
                ($0["song"] as? String ?? "", [$0["singer"] as? String ?? ""], nil,
                 ((($0["duration"] as? NSNumber)?.doubleValue).map { $0 / 1000 }))
            }.map { ($0, false) }
        }
        var results: [LyricsCandidate] = []
        for (item, byHash) in matches.prefix(3) {
            try Task.checkCancellation()
            guard let id = item["id"] as? String, let key = item["accesskey"] as? String else { continue }
            let title = byHash ? track.name : item["song"] as? String ?? ""
            let artists = byHash ? track.artists.map(\.name) : [item["singer"] as? String ?? ""]
            let duration = ((item["duration"] as? NSNumber)?.doubleValue).map { $0 / 1000 }
            do {
                // Kugou flags instrumentals on the candidate; their lyric files
                // are often user uploads of unrelated prose, so never read them.
                let response: LyricResponse
                if item["language"] as? String == "纯音乐" {
                    response = instrumentalResponse()
                } else {
                    let download = try await request("https://lyrics.kugou.com/download", query: ["ver": "1", "client": "pc", "id": id,
                        "accesskey": key, "fmt": "krc", "charset": "utf8"])
                    guard let content = download["content"] as? String else { continue }
                    response = try decodeKRC(content)
                }
                if let candidate = makeCandidate(source: .kugou, id: id, title: title, artists: artists, album: nil,
                    duration: duration, response: response, track: track, matchedByID: byHash) {
                    results.append(candidate)
                }
            } catch { try Task.checkCancellation() }
        }
        return results
    }

    static func decodeKRC(_ content: String) throws -> LyricResponse {
        guard let data = Data(base64Encoded: content), data.starts(with: [0x6b, 0x72, 0x63, 0x31]) else { throw Failure.invalidResponse }
        let key: [UInt8] = [0x40, 0x47, 0x61, 0x77, 0x5e, 0x32, 0x74, 0x47, 0x51, 0x36, 0x31, 0x2d, 0xce, 0xd2, 0x6e, 0x69]
        let compressed = data.dropFirst(4).enumerated().map { $0.element ^ key[$0.offset % key.count] }
        var output = [UInt8](repeating: 0, count: 4 * 1024 * 1024)
        var size = uLongf(output.count)
        let status = compressed.withUnsafeBufferPointer { input in
            output.withUnsafeMutableBufferPointer { out in uncompress(out.baseAddress!, &size, input.baseAddress!, uLong(compressed.count)) }
        }
        guard status == Z_OK, let text = String(bytes: output.prefix(Int(size)), encoding: .utf8) else { throw Failure.invalidResponse }
        return try parseKRC(text)
    }

    static func parseKRC(_ text: String) throws -> LyricResponse {
        let translations = krcTranslations(text)
        var lrc: [String] = [], yrc: [String] = [], translatedLRC: [String] = []
        for raw in text.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\u{feff}", with: "")
            guard let head = line.firstMatch(of: #/^\[(\d+),(\d+)\]/#), let start = Int(head.output.1) else { continue }
            let words = line.matches(of: #/<(\d+),(\d+),\d+>(.*?)(?=<\d+,\d+,\d+>|$)/#)
            guard !words.isEmpty else { continue }
            let plain = words.map { String($0.output.3) }.joined()
            let timestamp = String(format: "[%02d:%02d.%03d]", start / 60000, start / 1000 % 60, start % 1000)
            // KRC translations align by lyric-line index, including empty or
            // “//” placeholders. Never compact them before matching timestamps.
            let lineIndex = lrc.count
            if lineIndex < translations.count,
               let translation = translations[lineIndex], !translation.isEmpty, translation != "//" {
                translatedLRC.append(timestamp + translation)
            }
            lrc.append(timestamp + plain)
            let timed = words.compactMap { word -> String? in
                guard let offset = Int(word.output.1), offset <= Int.max - start else { return nil }
                return "(\(start + offset),\(word.output.2),0)\(word.output.3)"
            }
            guard timed.count == words.count else { continue }
            yrc.append("[\(start),\(head.output.2)]\(timed.joined())")
        }
        return try response(lrc: lrc.joined(separator: "\n"),
                            translation: translatedLRC.isEmpty ? nil : translatedLRC.joined(separator: "\n"),
                            yrc: yrc.joined(separator: "\n"))
    }

    private static func krcTranslations(_ text: String) -> [String?] {
        guard let tag = text.range(of: "[language:"),
              let end = text[tag.upperBound...].firstIndex(of: "]"),
              let data = Data(base64Encoded: String(text[tag.upperBound..<end])),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              // Type 0 contains pronunciation; type 1 contains translations.
              let translation = content.first(where: { ($0["type"] as? Int) == 1 }),
              let rows = translation["lyricContent"] as? [Any] else { return [] }
        return rows.map { row in
            ((row as? [Any])?.first as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }
}
