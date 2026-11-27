import Foundation

/// One timed word (or short run) inside a verbatim (yrc) lyric line.
struct LyricWord: Hashable {
    let text: String
    let start: TimeInterval
    let duration: TimeInterval
    var end: TimeInterval { start + duration }
}

struct LyricLine: Identifiable, Hashable {
    let id: Int
    let time: TimeInterval
    let text: String
    var translation: String?
    var romaji: String?
    /// Base text split so each reading sits over the kanji it belongs to.
    /// Nil when there is nothing to annotate.
    var furigana: [RubySegment]?
    /// Per-word timings for karaoke highlighting; nil when only line-level
    /// (lrc) timing is available.
    var words: [LyricWord]?
}

struct ParsedLyrics: Hashable {
    var lines: [LyricLine] = []
    var isInstrumental = false
    var contributor: String?
    var translationContributor: String?
    var timeline: [TimedLyricLine]?

    var synchronizedLines: [TimedLyricLine] {
        timeline ?? lines.map { line in
            TimedLyricLine(id: "coda:\(line.id)", time: line.time,
                timingKind: line.words == nil ? .lineSynchronized : .precise,
                text: line.text, syllables: (line.words ?? []).map {
                    LyricSyllable(text: $0.text, startTime: $0.start, endTime: $0.end)
                })
        }
    }

    var isEmpty: Bool { lines.isEmpty }

    /// The playback timeline handles lyric lookup, including overlapping vocals.
    func activeIndex(at time: TimeInterval) -> Int? {
        guard time.isFinite else { return nil }
        let native = synchronizedLines
        let position = LyricPlaybackTimeline.position(at: time, in: native)
        return native.firstIndex { $0.id == position.highlightedLyricID }
    }
}

// The timed lyric parser handles parsing and annotation alignment.
// This adapter only retains Coda's API response and Japanese-reading models.
enum LyricsParser {
    static func parseLRC(_ source: String) -> [(time: TimeInterval, text: String)] {
        TimedLyricParser.parseLRC(source).map { ($0.time, $0.text) }
    }

    static func parseYRC(_ source: String) -> [LyricLine] {
        TimedLyricParser.parseYRC(source).enumerated().map { index, line in
            adapt(line, id: index, wordTiming: true)
        }
    }

    private static func adapt(_ line: TimedLyricLine, id: Int, wordTiming: Bool) -> LyricLine {
        LyricLine(id: id, time: line.time, text: line.text,
            translation: line.translation, romaji: line.romanization,
            words: wordTiming && !line.syllables.isEmpty ? line.syllables.map {
                LyricWord(text: $0.text, start: $0.startTime, duration: $0.endTime - $0.startTime)
            } : nil)
    }

    /// Credit and notice lines ("作词：X", "Producer: Y", "Lyrics by Z",
    /// copyright notices) are not sung, so only the lyric body is shown.
    /// A colon line counts only when its label names a credit role: duet
    /// labels such as "男：" or "合：" are sung parts and stay.
    static func isCredit(_ text: String) -> Bool {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if creditNotices.contains(where: line.contains) { return true }
        if line.range(of: #"^(lyrics?|music|words|composed|written|arranged|produced|mixed|mastered|recorded)\s+by\s+\S"#,
                      options: [.regularExpression, .caseInsensitive]) != nil { return true }
        guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let body = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        return !body.isEmpty && isCreditRole(String(line[..<colon]))
    }

    /// Also consulted by the duet parser, so a credit label is never mistaken
    /// for a singer and stripped off, which would leave the bare name behind.
    static func isCreditRole(_ label: String) -> Bool {
        let head = label.lowercased().filter { !$0.isWhitespace }
        guard !head.isEmpty, head.count <= 24 else { return false }
        return exactCreditRoles.contains(head) || creditRoles.contains { head.contains($0) }
    }

    private static let creditNotices = ["未经许可", "未经授权", "未经著作权人", "著作权", "版权所有"]
    private static let exactCreditRoles: Set<String> = ["词", "曲", "鼓", "op", "sp"]
    private static let creditRoles = [
        "作词", "作曲", "填词", "词曲", "编曲", "编配", "编写", "制作", "监制", "出品", "混音", "缩混",
        "母带", "录音", "吉他", "贝斯", "键盘", "弦乐", "钢琴", "演奏", "发行", "宣传", "策划", "统筹",
        "经纪", "文案", "助理", "厂牌", "设计", "版权", "企划", "出版", "工程", "演唱", "歌手", "原唱",
        "配唱", "作者", "lyric", "compos", "writer", "arrang", "produc", "mix", "master", "record",
        "engineer", "publish", "label", "guitar", "bass", "drum", "keyboard", "piano", "string", "vocal", "artist",
    ]

    /// QQ Music and Kugou open with a "歌名 - 歌手" line. Only an opening line
    /// made of the track's own title and primary artist, joined by a dash,
    /// counts, so a sung line that merely mentions the title stays.
    static func isTitleHeader(_ text: String, track: Track) -> Bool {
        guard text.contains(where: { "-—–－".contains($0) }) else { return false }
        let key = LyricsMatching.normalized(text)
        let title = LyricsMatching.normalized(track.name)
        let artists = track.artists.map { LyricsMatching.normalized($0.name) }.filter { !$0.isEmpty }
        guard !title.isEmpty, let primary = artists.first,
              key.count <= title.count + artists.reduce(0, { $0 + $1.count }) + 12 else { return false }
        return (key.hasPrefix(title) && key.dropFirst(title.count).contains(primary))
            || (key.hasPrefix(primary) && key.hasSuffix(title))
    }

    /// Indices of credit lines. Besides lines `isCredit` recognises, a credit
    /// block also carries roles no keyword list can cover ("音乐总监：X",
    /// "爱尔兰风笛 : Y"). Providers write such a block as "label：name" lines a
    /// few seconds apart (Netease 1 s; QQ Music under 3 s, even in QRC), so
    /// every colon line chained to a recognised credit within that gap goes.
    /// Sung lines sit further apart, and duet labels (男, 女, 合…) stay.
    static func creditIndices(_ lines: [(time: TimeInterval, text: String)]) -> Set<Int> {
        let maximumGap: TimeInterval = 5
        func isLabelled(_ text: String) -> Bool {
            guard let colon = text.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
            let label = text[..<colon].trimmingCharacters(in: .whitespaces)
            let body = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            guard !body.isEmpty, (2...24).contains(label.count) || isCreditRole(label) else { return false }
            return !["男", "女", "合", "众", "男声", "女声", "合唱", "全体"].contains(label)
        }
        var drop = Set(lines.indices.filter { isCredit(lines[$0].text) })
        for seed in drop.sorted() {
            for step in [-1, 1] {
                var previous = seed, next = seed + step
                while lines.indices.contains(next), abs(lines[next].time - lines[previous].time) <= maximumGap,
                      drop.contains(next) || isLabelled(lines[next].text) {
                    drop.insert(next)
                    previous = next
                    next += step
                }
            }
        }
        return drop
    }

    /// Credits leave the raw LRC before the duet parser runs; otherwise it
    /// reads an unknown role as a singer and leaves the bare name behind.
    static func removingCredits(fromLRC source: String) -> String {
        let lines = source.components(separatedBy: .newlines)
        let timed = lines.indices.compactMap { index -> (index: Int, time: TimeInterval, text: String)? in
            let line = lines[index]
            guard let stamp = line.range(of: #"^\s*\[\d+:\d+(\.\d+)?\]"#, options: .regularExpression) else { return nil }
            let parts = line[stamp].trimmingCharacters(in: CharacterSet(charactersIn: " []")).split(separator: ":")
            let text = line.replacingOccurrences(of: #"^(\s*\[[^\]]*\])+"#, with: "", options: .regularExpression)
                .trimmingCharacters(in: .whitespaces)
            guard parts.count == 2, let minutes = Double(parts[0]), let seconds = Double(parts[1]), !text.isEmpty else { return nil }
            return (index, minutes * 60 + seconds, text)
        }
        let drop = Set(creditIndices(timed.map { ($0.time, $0.text) }).map { timed[$0].index })
        return lines.indices.filter { !drop.contains($0) }.map { lines[$0] }.joined(separator: "\n")
    }

    static func parse(_ response: LyricResponse, track: Track? = nil) -> ParsedLyrics {
        let lrc = removingCredits(fromLRC: response.lrc?.lyric ?? "")
        // Netease writes only credit lines as JSON inside YRC.
        let yrc = (response.yrc?.lyric ?? "").components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("{") }.joined(separator: "\n")
        var native = TimedLyricParser.parse(
            yrc: yrc, lrc: lrc,
            translatedYRC: response.ytlrc?.lyric ?? "",
            translatedLRC: response.tlyric?.lyric ?? "",
            romanizedYRC: response.yromalrc?.lyric ?? "",
            romanizedLRC: response.romalrc?.lyric ?? "")
        var result = ParsedLyrics()
        result.isInstrumental = response.pureMusic == true
        result.contributor = response.lyricUser?.nickname
        result.translationContributor = response.transUser?.nickname
        // Preserve the provider's instrumental designation, which is outside
        // synchronization and is used by track matching and the empty state.
        let markers = ["纯音乐，请欣赏", "没有填词的纯音乐"]
        if native.count <= 10, native.contains(where: { line in markers.contains(where: line.text.contains) }) {
            result.isInstrumental = true
            native.removeAll { line in markers.contains(where: line.text.contains)
                || line.text.range(of: #"^作(词|曲)\s*[:：]"#, options: .regularExpression) != nil }
        }
        let credits = creditIndices(native.map { ($0.time, $0.text) })
        native = native.indices.filter { !credits.contains($0) }.map { native[$0] }
        if let track, let first = native.first, isTitleHeader(first.text, track: track) {
            native.removeFirst()
        }
        result.timeline = native
        result.lines = native.enumerated().map { adapt($0.element, id: $0.offset, wordTiming: true) }
        if RomajiTranscriber.isJapanese(result.lines.map(\.text)) {
            for index in result.lines.indices {
                if result.lines[index].romaji == nil {
                    result.lines[index].romaji = RomajiTranscriber.transcribe(result.lines[index].text)
                }
                result.lines[index].furigana = Furigana.segments(for: result.lines[index].text)
            }
        } else {
            for index in result.lines.indices { result.lines[index].romaji = nil }
        }
        return result
    }
}
