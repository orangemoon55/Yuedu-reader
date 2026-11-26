import Foundation

// Derived from Yingxia / TVBox-Silicon Sources/TVCore/MusicLyrics.swift
// at jo32/tvbox-silicon commit a6bcc00bbbdbd7c6af7b7223ca2fa6018d6d685c.
// GPL-3.0-only; see LICENSES/Yingxia-GPL-3.0-only.txt and NOTICE.
// Readcc adaptation: parse user-imported local LRC and expose playback-time lookup;
// deliberately excludes upstream catalog/network lyric providers.
struct YingxiaLyricLine: Hashable, Sendable {
    /// Seconds from the beginning of the track; zero for unsynced text.
    var time: Double
    /// Empty text represents an instrumental gap in timed LRC.
    var text: String
    var translation: String?
}

struct YingxiaMusicLyrics: Hashable, Sendable {
    var lines: [YingxiaLyricLine]
    var synced: Bool

    /// Returns the last timed lyric whose start is at or before `time`.
    func index(at time: Double) -> Int? {
        guard time.isFinite, synced, let first = lines.first, time >= first.time else { return nil }
        var low = 0, high = lines.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if lines[mid].time <= time { low = mid } else { high = mid - 1 }
        }
        return low
    }

    private static let stamp = try! NSRegularExpression(pattern: "\\[(\\d{1,3}):(\\d{1,2})(?:[.:](\\d{1,3}))?\\]")
    private static let tag = try! NSRegularExpression(pattern: "^\\[([a-zA-Z#]+):([^\\]]*)\\]\\s*$")

    /// Parses timed or plain LRC, repeated timestamps, offset tags and optional translations.
    /// Metadata-only/empty input returns nil.
    static let maximumLines = 6_000
    static let maximumTextBytes = 2 * 1024 * 1024

    static func parse(_ lrc: String, translation: String? = nil) -> YingxiaMusicLyrics? {
        guard lrc.utf8.count <= maximumTextBytes,
              let (timed, plain, offset) = lines(of: lrc) else { return nil }
        if timed.isEmpty {
            let text = plain.filter { !$0.isEmpty }
            return text.isEmpty ? nil : YingxiaMusicLyrics(
                lines: text.map { YingxiaLyricLine(time: 0, text: $0, translation: nil) }, synced: false)
        }

        var result = timed.map {
            YingxiaLyricLine(time: max(0, $0.time - offset), text: $0.text, translation: nil)
        }
        result = result.enumerated()
            .sorted { $0.element.time == $1.element.time ? $0.offset < $1.offset : $0.element.time < $1.element.time }
            .map(\.element)
        guard result.contains(where: { !$0.text.isEmpty }) else { return nil }

        if let translation {
            guard translation.utf8.count <= maximumTextBytes,
                  let (translated, _, translatedOffset) = lines(of: translation) else { return nil }
            let usable = translated.filter { !$0.text.isEmpty && $0.text != "//" }
                .map { (time: max(0, $0.time - translatedOffset), text: $0.text) }
                .sorted { $0.time < $1.time }
            for index in result.indices where !result[index].text.isEmpty {
                guard !Task.isCancelled else { return nil }
                // Both sides are already offset-corrected. Bound matching to O(N log M),
                // not a full translation scan for every original line.
                let time = result[index].time
                var low = 0, high = usable.count
                while low < high {
                    let mid = (low + high) / 2
                    if usable[mid].time < time { low = mid + 1 } else { high = mid }
                }
                var match: (time: Double, text: String)? = low < usable.count ? usable[low] : nil
                if low > 0 {
                    let earlier = usable[low - 1]
                    if match == nil || abs(earlier.time - time) <= abs(match!.time - time) { match = earlier }
                }
                if let match, abs(match.time - time) < 0.35, match.text != result[index].text {
                    result[index].translation = match.text
                }
            }
        }

        // Ignore only an explicitly labelled opening metadata/credit prefix; keep lyric punctuation intact.
        if let firstSung = result.firstIndex(where: { !isCredit($0.text) }), firstSung > 0 {
            result.removeFirst(firstSung)
        }
        result = result.enumerated()
            .filter { $0.offset == 0 || !($0.element.text.isEmpty && result[$0.offset - 1].text.isEmpty) }
            .map(\.element)
        return YingxiaMusicLyrics(lines: result, synced: true)
    }

    /// Reads a caller-selected local `.lrc` only; no URLSession or source lookup is involved.
    static func load(from url: URL) throws -> YingxiaMusicLyrics {
        guard url.pathExtension.lowercased() == "lrc" else { throw MusicLyricsImportError.unsupportedFile }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size > 0 else { throw MusicLyricsImportError.emptyFile }
        guard size <= 2 * 1024 * 1024 else { throw MusicLyricsImportError.fileTooLarge }
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw MusicLyricsImportError.invalidText
        }
        guard let lyrics = parse(text) else { throw MusicLyricsImportError.noLyrics }
        return lyrics
    }

    private static let creditLabels: Set<String> = [
        "title", "artist", "album", "by", "lyrics", "lyricist", "composer", "arranger", "producer",
        "lyrics by", "words by", "music by", "composed by", "arranged by", "produced by",
        "mixed by", "recorded by", "mastered by",
        "歌名", "歌曲", "歌手", "专辑", "專輯", "演唱", "原唱",
        "词", "詞", "曲", "作词", "作詞", "作曲", "词曲", "詞曲", "编曲", "編曲",
        "制作人", "製作人", "制作", "製作", "监制", "監製", "录音", "錄音", "混音", "母带", "母帶",
        "和声", "和聲", "出品", "发行", "發行"
    ]

    private static func isCredit(_ text: String) -> Bool {
        let line = text.trimmingCharacters(in: .whitespaces)
        if line.isEmpty { return true }
        guard let colon = line.firstIndex(where: { $0 == ":" || $0 == "：" }) else { return false }
        let label = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
        return creditLabels.contains(label)
    }

    private static func lines(of lrc: String) -> (timed: [(time: Double, text: String)], plain: [String], offset: Double)? {
        var timed: [(time: Double, text: String)] = [], plain: [String] = [], offset = 0.0
        let normalized = lrc.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let rawLines = normalized.components(separatedBy: "\n")
        guard rawLines.count <= maximumLines else { return nil }
        for (index, raw) in rawLines.enumerated() {
            guard !Task.isCancelled, raw.utf8.count <= 16_384 else { return nil }
            // A leading BOM is an encoding signature, not part of the first timestamp/tag.
            let content = index == 0 && raw.hasPrefix("\u{FEFF}") ? String(raw.dropFirst()) : raw
            let line = content.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            if let match = tag.firstMatch(in: line, range: range),
               let name = Range(match.range(at: 1), in: line), let value = Range(match.range(at: 2), in: line) {
                if line[name].lowercased() == "offset",
                   let milliseconds = Double(line[value].trimmingCharacters(in: .whitespaces)),
                   milliseconds.isFinite, abs(milliseconds) <= 86_400_000 {
                    offset = milliseconds / 1000
                }
                continue
            }
            var times: [Double] = [], end = line.startIndex
            for match in stamp.matches(in: line, range: range) {
                guard let whole = Range(match.range, in: line), whole.lowerBound == end,
                      let minutes = Range(match.range(at: 1), in: line).flatMap({ Double(line[$0]) }),
                      let seconds = Range(match.range(at: 2), in: line).flatMap({ Double(line[$0]) }) else { break }
                var fraction = 0.0
                if let digits = Range(match.range(at: 3), in: line).map({ String(line[$0]) }),
                   let value = Double(digits) {
                    fraction = value / pow(10, Double(digits.count))
                }
                times.append(minutes * 60 + seconds + fraction)
                guard timed.count + times.count <= maximumLines else { return nil }
                end = whole.upperBound
            }
            let text = String(line[end...]).trimmingCharacters(in: .whitespaces)
            if times.isEmpty { plain.append(text) }
            else { timed += times.map { (time: $0, text: text) } }
        }
        return (timed, plain, offset)
    }
}

enum MusicLyricsImportError: LocalizedError {
    case unsupportedFile
    case emptyFile
    case fileTooLarge
    case invalidText
    case noLyrics

    var errorDescription: String? {
        switch self {
        case .unsupportedFile: return localized("请选择 .lrc 歌词档。")
        case .emptyFile: return localized("歌词档是空的。")
        case .fileTooLarge: return localized("歌词档超过 2 MB 限制。")
        case .invalidText: return localized("无法以 UTF-8 或 UTF-16 读取歌词档。")
        case .noLyrics: return localized("档案中没有可显示的歌词。")
        }
    }
}
