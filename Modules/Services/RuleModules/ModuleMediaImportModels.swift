import Foundation
import CoreFoundation

/// Module-area registration only. These routes do not claim a playback/matching engine.
enum ModuleMediaRoute: String, CaseIterable, Identifiable {
    case danmaku, subtitles, catSources
    var id: String { rawValue }
    var titleKey: String {
        switch self { case .danmaku: "弹幕源"; case .subtitles: "字幕"; case .catSources: "猫源" }
    }
    var systemImage: String {
        switch self { case .danmaku: "bubble.left.and.bubble.right.fill"; case .subtitles: "captions.bubble.fill"; case .catSources: "tv.and.hifispeaker.fill" }
    }
    var accessibilityIdentifier: String {
        switch self { case .danmaku: "modules.danmaku"; case .subtitles: "modules.subtitles"; case .catSources: "modules.md5Sources" }
    }
}

struct ModuleLandingCounts: Equatable {
    let official: Int
    let imported: Int
    init(appOfficial: Int, installedOfficial: Int, installedImported: Int, unreadableImported: Int) {
        official = appOfficial + installedOfficial
        // Unreadable folders are visible in the existing imported destination too.
        imported = installedImported + unreadableImported
    }
}

enum ModuleMediaRegistryKind: String, Codable { case danmaku, subtitle }

struct ModuleRegisteredMediaSource: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let baseUrl: String
}

struct ModuleSubtitleCue: Codable, Equatable {
    let start: Double
    let end: Double
    let text: String
}

struct ModuleLocalSubtitle: Codable, Equatable, Identifiable {
    let id: UUID
    let filename: String
    let encoding: String
    let cues: [ModuleSubtitleCue]
    let importedAt: Date
    var title: String { (filename as NSString).deletingPathExtension }
}

enum ModuleMediaImportError: LocalizedError {
    case invalid(String)
    var errorDescription: String? {
        switch self { case .invalid(let message): message }
    }
}

/// Pure, bounded parsers. No requests, script execution, hosts, or bundled source credentials.
enum ModuleMediaImportParser {
    static let registryByteLimit = 256 * 1024
    static let subtitleByteLimit = 4 * 1024 * 1024
    static let sourceLimit = 100
    static let cueLimit = 20_000
    static let cueTextLimit = 16_384

    static func registry(_ data: Data, kind: ModuleMediaRegistryKind) throws -> [ModuleRegisteredMediaSource] {
        guard !data.isEmpty, data.count <= registryByteLimit else { throw failure("来源 JSON 为空或超过 256 KB。") }
        guard let text = String(data: data, encoding: .utf8) else { throw failure("来源 JSON 必须是 UTF-8。") }
        let clean = text.trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}").union(.whitespacesAndNewlines))
        let decoder = JSONDecoder()
        let normalized = Data(clean.utf8)
        let sources: [ModuleRegisteredMediaSource]
        do {
            if kind == .subtitle, clean.hasPrefix("{") {
                sources = [try decoder.decode(ModuleRegisteredMediaSource.self, from: normalized)]
            } else {
                sources = try decoder.decode([ModuleRegisteredMediaSource].self, from: normalized)
            }
        } catch { throw failure("JSON 格式错误；每项必须包含字串 id、name、baseUrl。弹幕源须为阵列。") }
        guard !sources.isEmpty, sources.count <= sourceLimit else { throw failure("每次需汇入 1–100 个来源。") }
        var ids = Set<String>()
        for source in sources {
            try validate(source)
            guard ids.insert(source.id).inserted else { throw failure("同一份 JSON 的来源 id 不可重复。") }
        }
        return sources
    }

    static func validate(_ source: ModuleRegisteredMediaSource) throws {
        for (value, limit) in [(source.id, 128), (source.name, 128), (source.baseUrl, 2048)] {
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  value.count <= limit, value.rangeOfCharacter(from: .controlCharacters) == nil else {
                throw failure("来源栏位为空、过长或含控制字元。")
            }
        }
        guard let url = URLComponents(string: source.baseUrl),
              ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.fragment == nil, url.url != nil else {
            throw failure("baseUrl 必须是 HTTP(S) 网址，且不可含帐号、密码或 fragment。")
        }
    }

    static func subtitle(_ data: Data, filename: String) throws -> ModuleLocalSubtitle {
        guard !data.isEmpty, data.count <= subtitleByteLimit else { throw failure("字幕为空或超过 4 MB。") }
        let filename = (filename as NSString).lastPathComponent
        let ext = (filename as NSString).pathExtension.lowercased()
        guard ["srt", "vtt"].contains(ext), filename.count <= 255 else { throw failure("请选择 .srt 或 .vtt 字幕档案。") }
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let decoded: String
        let encoding: String
        if let text = String(data: data, encoding: .utf8) { decoded = text; encoding = "UTF-8" }
        else if let text = String(data: data, encoding: gbk) { decoded = text; encoding = "GBK / GB18030" }
        else { throw failure("字幕编码无法辨识；仅支援 UTF-8 或 GBK。") }
        let text = decoded.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .trimmingCharacters(in: CharacterSet(charactersIn: "\u{feff}"))
        guard !text.contains("\0") else { throw failure("字幕含有无效的二进位内容。") }
        var blocks: [[String]] = []
        var block: [String] = []
        for line in text.components(separatedBy: "\n") {
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                if !block.isEmpty { blocks.append(block); block = [] }
            } else { block.append(line) }
        }
        if !block.isEmpty { blocks.append(block) }
        if ext == "vtt" {
            guard let header = blocks.first?.first,
                  header == "WEBVTT" || header.hasPrefix("WEBVTT ") || header.hasPrefix("WEBVTT\t") else {
                throw failure("VTT 缺少 WEBVTT 标头。")
            }
            blocks.removeFirst()
        }
        var cues: [ModuleSubtitleCue] = []
        for lines in blocks {
            if ext == "vtt", let first = lines.first,
               first == "NOTE" || first.hasPrefix("NOTE ") || first == "STYLE" || first == "REGION" { continue }
            guard let index = lines.prefix(2).firstIndex(where: { $0.contains("-->") }) else {
                throw failure("字幕区块缺少有效的时间轴。")
            }
            let timeline = lines[index].components(separatedBy: "-->")
            guard timeline.count == 2,
                  let endPart = timeline[1].split(whereSeparator: { $0.isWhitespace }).first else { throw failure("字幕时间轴格式错误。") }
            let start = try timestamp(timeline[0].trimmingCharacters(in: .whitespaces), allowsShort: ext == "vtt")
            let end = try timestamp(String(endPart), allowsShort: ext == "vtt")
            let cueText = lines.dropFirst(index + 1).joined(separator: "\n")
            guard end > start, end <= 7 * 24 * 3600, !cueText.isEmpty, cueText.utf8.count <= cueTextLimit else {
                throw failure("字幕时间顺序、文字长度或内容无效。")
            }
            cues.append(ModuleSubtitleCue(start: start, end: end, text: cueText))
            guard cues.count <= cueLimit else { throw failure("字幕超过 20,000 个时间轴。") }
        }
        guard !cues.isEmpty else { throw failure("字幕没有可汇入的时间轴。") }
        return ModuleLocalSubtitle(id: UUID(), filename: filename, encoding: encoding, cues: cues, importedAt: Date())
    }

    private static func timestamp(_ value: String, allowsShort: Bool) throws -> Double {
        let parts = value.replacingOccurrences(of: ",", with: ".").split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3 || (allowsShort && parts.count == 2) else { throw failure("字幕时间格式错误。") }
        func integer(_ value: Substring) -> Int? {
            guard !value.isEmpty, value.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) else { return nil }
            return Int(value)
        }
        let secondsParts = parts.last!.split(separator: ".", omittingEmptySubsequences: false)
        guard secondsParts.count == 2, secondsParts[0].count == 2, secondsParts[1].count == 3,
              let seconds = integer(secondsParts[0]), seconds < 60,
              let milliseconds = integer(secondsParts[1]),
              parts[parts.count - 2].count == 2, let minutes = integer(parts[parts.count - 2]), minutes < 60 else {
            throw failure("字幕时间必须使用 时:分:秒,毫秒 或 VTT 分:秒.毫秒。")
        }
        var hours = 0
        if parts.count == 3 {
            guard parts[0].count >= 2, parts[0].count <= 3, let value = integer(parts[0]) else { throw failure("字幕小时格式错误。") }
            hours = value
        }
        return Double(hours * 3600 + minutes * 60 + seconds) + Double(milliseconds) / 1000
    }

    private static func failure(_ message: String) -> ModuleMediaImportError { .invalid(message) }
}
