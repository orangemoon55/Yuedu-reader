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
        guard synced, let first = lines.first, time >= first.time else { return nil }
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
    static func parse(_ lrc: String, translation: String? = nil) -> YingxiaMusicLyrics? {
        let (timed, plain, offset) = lines(of: lrc)
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
            let (translated, _, translatedOffset) = lines(of: translation)
            let usable = translated.filter { !$0.text.isEmpty && $0.text != "//" }
                .map { (time: max(0, $0.time - translatedOffset), text: $0.text) }
            for index in result.indices where !result[index].text.isEmpty {
                let time = result[index].time + offset
                if let match = usable.min(by: { abs($0.time - time) < abs($1.time - time) }),
                   abs(match.time - time) < 0.35, match.text != result[index].text {
                    result[index].translation = match.text
                }
            }
        }

        // Ignore the catalog-style title/credit prefix; keep the timed lyric body intact.
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

    private static let creditLine = try! NSRegularExpression(pattern: "^[^：:]{1,16}\\s*[：:]")

    private static func isCredit(_ text: String) -> Bool {
        let line = text.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.contains(" - ") { return true }
        return creditLine.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    private static func lines(of lrc: String) -> (timed: [(time: Double, text: String)], plain: [String], offset: Double) {
        var timed: [(time: Double, text: String)] = [], plain: [String] = [], offset = 0.0
        let normalized = lrc.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        for raw in normalized.components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let range = NSRange(line.startIndex..., in: line)
            if let match = tag.firstMatch(in: line, range: range),
               let name = Range(match.range(at: 1), in: line), let value = Range(match.range(at: 2), in: line) {
                if line[name].lowercased() == "offset",
                   let milliseconds = Double(line[value].trimmingCharacters(in: .whitespaces)) {
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
        case .unsupportedFile: return localized("請選擇 .lrc 歌詞檔。")
        case .emptyFile: return localized("歌詞檔是空的。")
        case .fileTooLarge: return localized("歌詞檔超過 2 MB 限制。")
        case .invalidText: return localized("無法以 UTF-8 或 UTF-16 讀取歌詞檔。")
        case .noLyrics: return localized("檔案中沒有可顯示的歌詞。")
        }
    }
}
