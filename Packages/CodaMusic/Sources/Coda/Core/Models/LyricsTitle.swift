import Foundation

/// A song title as catalogs write it, split into what names the song, what
/// names the recording, and what merely annotates it.
///
/// "River Flows in You (你的心河)", "Summer (映画「菊次郎の夏」より)" and
/// "晴天 - 电影《X》插曲" name the same recordings as their bare titles, while
/// "晴天 (Live)" or "晴天 (伴奏)" do not. Only recognised version tags take
/// part in identity; every other bracket or dash suffix is an annotation.
struct LyricsTitle: Equatable {
    /// Normalized title with brackets, dash suffixes and featured artists removed.
    let base: String
    /// Canonical recording tags such as "live", "inst", "remix".
    let versions: Set<String>
    /// Normalized annotation segments: translations, sources, featured artists.
    let annotations: [String]

    init(_ raw: String) {
        var outside = ""
        var segments: [String] = []
        var depth = 0
        var current = ""
        for character in raw {
            if Self.openers.contains(character) {
                if depth == 0 { current = "" } else { current.append(character) }
                depth += 1
            } else if Self.closers.contains(character), depth > 0 {
                depth -= 1
                if depth == 0 { segments.append(current) } else { current.append(character) }
            } else if depth > 0 {
                current.append(character)
            } else {
                outside.append(character)
            }
        }
        if depth > 0 { outside += current }
        // "Title - Live", "Title – 电影《X》插曲": a spaced dash starts a suffix.
        if let dash = outside.range(of: #"\s+[-–—－]\s+"#, options: .regularExpression) {
            segments.append(String(outside[dash.upperBound...]))
            outside = String(outside[..<dash.lowerBound])
        }
        if let feat = outside.range(of: #"\s+(feat\.?|ft\.?|featuring)\s+"#,
                                    options: [.regularExpression, .caseInsensitive]) {
            segments.append(String(outside[feat.lowerBound...]))
            outside = String(outside[..<feat.lowerBound])
        }
        base = LyricsMatching.normalized(outside)
        var versions = Set<String>()
        var annotations: [String] = []
        for segment in segments {
            let tags = Self.versionTags(in: segment)
            if tags.isEmpty {
                let key = LyricsMatching.normalized(segment)
                if !key.isEmpty { annotations.append(key) }
            } else {
                versions.formUnion(tags)
            }
        }
        self.versions = versions
        self.annotations = annotations
    }

    private static let openers: Set<Character> = ["(", "（", "[", "【", "〔"]
    private static let closers: Set<Character> = [")", "）", "]", "】", "〕"]

    /// Tags that name a different recording or arrangement, and so different
    /// lyric timing or none at all. Remaster and similar labels are absent on
    /// purpose: the recording and its lyrics stay the same.
    private static let tagPatterns: [(tag: String, pattern: String)] = [
        ("live", #"\blive\b|现场|現場|演唱会|演唱會|音乐会|ライブ"#),
        ("inst", #"伴奏|\binst\b|\binst\.|instrumental|karaoke|off\s*vocal|オフボーカル|纯音乐版|純音樂版|消音"#),
        ("remix", #"remix|\brmx\b|\bmix\b"#),
        ("dj", #"\bdj\b|dj版|慢摇|慢搖"#),
        ("acoustic", #"acoustic|不插电|不插電|unplugged"#),
        ("piano", #"钢琴|鋼琴|piano"#),
        ("guitar", #"吉他|guitar"#),
        ("orchestra", #"交响|交響|orchestra|symphon"#),
        ("female", #"女声|女聲|女生版|female"#),
        ("male", #"男声|男聲|男生版|(?<!fe)\bmale\b"#),
        ("chorus", #"合唱版|对唱版|對唱版|duet"#),
        ("demo", #"\bdemo\b|小样|小樣"#),
        ("cover", #"\bcover\b|翻唱|翻自"#),
        ("speed", #"加速|降速|减速|慢速|倍速|sped\s*up|slowed|nightcore|\d(\.\d+)?\s*x\b"#),
        ("extended", #"extended|加长|加長"#),
        ("edit", #"radio\s*edit|\bedit\b|剪辑版|剪輯版"#),
        ("short", #"tv\s*size|tv版|short\s*ver|片段"#),
        ("lang:yue", #"粤语|粵語"#),
        ("lang:zh", #"国语|國語|普通话|普通話"#),
        ("lang:ja", #"日语版|日語版|日文版|japanese\s*ver"#),
        ("lang:en", #"英文版|英语版|英語版|english\s*ver"#),
        ("lang:ko", #"韩语版|韓語版|韩文版|korean\s*ver"#),
    ]

    static func versionTags(in segment: String) -> Set<String> {
        let text = segment.lowercased()
        return Set(tagPatterns.compactMap { item in
            text.range(of: item.pattern, options: .regularExpression) == nil ? nil : item.tag
        })
    }

    /// A search query for catalogs that match keywords literally (Kugou finds
    /// "Summer 久石让" but nothing for "Summer 久石譲"): the title without
    /// brackets and the artists in Chinese script.
    static func searchKeyword(for track: Track) -> String {
        var title = track.name.replacingOccurrences(of: #"[(（\[【〔][^)）\]】〕]*[)）\]】〕]"#, with: " ",
                                                    options: .regularExpression)
        if let dash = title.range(of: #"\s+[-–—－]\s+"#, options: .regularExpression) {
            title = String(title[..<dash.lowerBound])
        }
        title = title.trimmingCharacters(in: .whitespaces)
        let artists = track.artists.map { LyricsArtistName.chineseScript($0.name) }.joined(separator: " ")
        return [title.isEmpty ? track.name : title, artists].filter { !$0.isEmpty }.joined(separator: " ")
    }

    /// Every normalized name this title answers to: its base, its
    /// annotations (often a translation) and the catalog's own aliases.
    func names(aliases: [String] = []) -> Set<String> {
        Set([base] + annotations + aliases.map { LyricsTitle($0).base }).subtracting([""])
    }
}

/// Artist names differ by script across catalogs: Japanese shinjitai
/// ("久石譲" on Netease, "久石让" on QQ Music) is not traditional Chinese, so
/// the Traditional-Simplified transform leaves it alone.
enum LyricsArtistName {
    static func key(_ name: String) -> String {
        String(LyricsMatching.normalized(name).map { shinjitai[$0] ?? $0 })
    }

    /// The name as written, with Japanese forms replaced by Chinese ones.
    static func chineseScript(_ name: String) -> String {
        String(name.map { shinjitai[$0] ?? $0 })
    }

    private static let shinjitai: [Character: Character] = [
        "譲": "让", "沢": "泽", "浜": "滨", "広": "广", "歩": "步", "竜": "龙", "桜": "樱",
        "恵": "惠", "斎": "斋", "斉": "齐", "辺": "边", "邉": "边", "渕": "渊", "栄": "荣",
        "亜": "亚", "円": "圆", "駅": "驿", "嶋": "岛", "嶌": "岛", "徳": "德", "瀬": "濑",
        "滝": "泷", "鉄": "铁", "塚": "冢", "剣": "剑", "薫": "薰", "黒": "黑", "涼": "凉",
        "霊": "灵", "聡": "聪", "伝": "传", "継": "继", "続": "续", "対": "对", "単": "单",
        "戦": "战", "鶴": "鹤", "亀": "龟", "髙": "高", "﨑": "崎", "実": "实", "穂": "穗",
        "県": "县", "険": "险", "検": "检", "験": "验", "楽": "乐", "気": "气", "帰": "归",
        "団": "团", "様": "样", "経": "经", "総": "总", "読": "读", "顕": "显", "芸": "艺",
    ]
}

/// Artist aliases from the track's own catalog ("久石譲" → "Joe Hisaishi",
/// "久石让"). Fetched only when a provider's results match on everything but
/// the artist, then kept for the session. Reads are synchronous so scoring
/// stays a pure function of what has been loaded.
final class LyricsArtistAliases: @unchecked Sendable {
    static let shared = LyricsArtistAliases()
    private let lock = NSLock()
    private var names: [Int: Set<String>] = [:]
    private var pending: [Int: Task<Void, Never>] = [:]

    /// Normalized aliases for every artist of `track`, the names included.
    func keys(for track: Track) -> [Set<String>] {
        lock.lock(); defer { lock.unlock() }
        return track.artists.map { artist in
            Set([LyricsArtistName.key(artist.name)]).union(names[artist.id] ?? []).subtracting([""])
        }
    }

    func store(_ aliases: [String], for artistID: Int) {
        lock.lock(); defer { lock.unlock() }
        names[artistID, default: []].formUnion(aliases.map(LyricsArtistName.key).filter { !$0.isEmpty })
    }

    /// Loads aliases for a Netease catalog track; other catalogs' artist ids
    /// are local handles with no alias endpoint. Failures are not retried
    /// within the session.
    func load(for track: Track, loader: @escaping @Sendable (Int) async throws -> [String] = NeteaseAPI.artistAliases) async {
        guard track.platformSong == nil else { return }
        let tasks: [Task<Void, Never>] = track.artists.filter { $0.id > 0 }.map { artist in
            lock.lock(); defer { lock.unlock() }
            if let task = pending[artist.id] { return task }
            let task = Task { [weak self] in
                guard let aliases = try? await loader(artist.id) else { return }
                self?.store(aliases, for: artist.id)
            }
            pending[artist.id] = task
            return task
        }
        for task in tasks { await task.value }
    }
}
