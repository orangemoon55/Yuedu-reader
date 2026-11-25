import Foundation
import CoreFoundation
import Testing
@testable import yuedu_app

@Suite("Module media registration and local subtitle import", .serialized)
@MainActor
struct ModuleMediaImportTests {
    private let srt = "1\n00:00:01,250 --> 00:00:03,000\n你好，字幕\n第二行\n\n2\n00:00:03,200 --> 00:00:04,000\n完\n"
    private let source = #"[{"id":"test","name":"Local test","baseUrl":"https://example.invalid/api"}]"#
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ModuleMediaImportTests-\(UUID())", isDirectory: true)
    }
    private func rejects(_ action: () throws -> Void) {
        do { try action(); Issue.record("Expected invalid import to be rejected") } catch {}
    }

    @Test("three unique supported routes and real destination-count semantics")
    func routesAndCounts() {
        #expect(ModuleMediaRoute.allCases == [.danmaku, .subtitles, .catSources])
        #expect(Set(ModuleMediaRoute.allCases.map(\.accessibilityIdentifier)).count == 3)
        #expect(ModuleMediaRoute.catSources.titleKey == "貓源")
        let counts = ModuleLandingCounts(appOfficial: 3, installedOfficial: 7, installedImported: 2, unreadableImported: 1)
        #expect(counts.official == 10)
        #expect(counts.imported == 3)
    }

    @Test("Dandanplay array and explicit SubtitleDB object/array registration")
    func sourceSchemas() throws {
        let data = Data(source.utf8)
        let list = try ModuleMediaImportParser.registry(data, kind: .danmaku)
        #expect(list.count == 1 && list[0].id == "test")
        let object = #"{"id":"sub","name":"SubtitleDB config","baseUrl":"https://example.invalid/subtitles"}"#
        #expect(try ModuleMediaImportParser.registry(Data(object.utf8), kind: .subtitle).first?.id == "sub")
        #expect(try ModuleMediaImportParser.registry(data, kind: .subtitle).count == 1)
        rejects { _ = try ModuleMediaImportParser.registry(Data(object.utf8), kind: .danmaku) }
        rejects { _ = try ModuleMediaImportParser.registry(Data("[]".utf8), kind: .danmaku) }
        rejects { _ = try ModuleMediaImportParser.registry(Data(#"[{"id":"x"}]"#.utf8), kind: .danmaku) }
        rejects { _ = try ModuleMediaImportParser.registry(Data([0xff, 0xfe]), kind: .subtitle) }
        rejects { _ = try ModuleMediaImportParser.registry(Data(repeating: 32, count: 256 * 1024 + 1), kind: .danmaku) }
        let duplicate = "[" + object + "," + object + "]"
        rejects { _ = try ModuleMediaImportParser.registry(Data(duplicate.utf8), kind: .subtitle) }
        for address in ["file:///tmp/a", "javascript:alert(1)", "https://user:password@example.invalid/a", "https://example.invalid/a#secret", "https://"] {
            rejects { try ModuleMediaImportParser.validate(.init(id: "x", name: "x", baseUrl: address)) }
        }
    }

    @Test("SRT BOM/CRLF, multiline, filename containment, millisecond timestamps")
    func utf8SRT() throws {
        let data = Data(("\u{feff}" + srt.replacingOccurrences(of: "\n", with: "\r\n")).utf8)
        let file = try ModuleMediaImportParser.subtitle(data, filename: "../../樣片.SRT")
        #expect(file.filename == "樣片.SRT")
        #expect(file.encoding == "UTF-8")
        #expect(file.cues.count == 2)
        #expect(file.cues[0].start == 1.25 && file.cues[0].end == 3)
        #expect(file.cues[0].text == "你好，字幕\n第二行")
    }

    @Test("GBK Chinese subtitles are decoded by the actual Foundation parser")
    func gbkSRT() throws {
        let encoding = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let data = try #require(srt.data(using: encoding))
        let file = try ModuleMediaImportParser.subtitle(data, filename: "測試.srt")
        #expect(file.encoding == "GBK / GB18030")
        #expect(file.cues[0].text == "你好，字幕\n第二行")
    }

    @Test("WebVTT header, cue id, settings, NOTE and STYLE blocks")
    func vtt() throws {
        let text = "WEBVTT\n\nNOTE ignored\nmetadata\n\nSTYLE\n::cue { color: red }\n\ncue-id\n00:01.000 --> 00:02.250 align:start\nHi\n"
        let file = try ModuleMediaImportParser.subtitle(Data(text.utf8), filename: "sample.vtt")
        #expect(file.cues == [ModuleSubtitleCue(start: 1, end: 2.25, text: "Hi")])
    }

    @Test("Malformed/oversized subtitle input never imports a partial result")
    func invalidSubtitles() {
        for text in ["", "arbitrary text", "1\n00:99:00,000 --> 00:00:01,000\na", "1\n00:00:03,000 --> 00:00:01,000\na", "1\n00:00:01,0 --> 00:00:02,000\na", "1\n00:00:01,000 --> 00:00:02,000\n\0"] {
            rejects { _ = try ModuleMediaImportParser.subtitle(Data(text.utf8), filename: "invalid.srt") }
        }
        rejects { _ = try ModuleMediaImportParser.subtitle(Data(srt.utf8), filename: "wrong.py") }
        rejects { _ = try ModuleMediaImportParser.subtitle(Data(srt.utf8), filename: "missing-header.vtt") }
        rejects { _ = try ModuleMediaImportParser.subtitle(Data(repeating: 32, count: 4 * 1024 * 1024 + 1), filename: "large.srt") }
        let longCue = "1\n00:00:01,000 --> 00:00:02,000\n" + String(repeating: "a", count: 16_385)
        rejects { _ = try ModuleMediaImportParser.subtitle(Data(longCue.utf8), filename: "long.srt") }
        let tooMany = (1...20_001).map { "\($0)\n00:00:01,000 --> 00:00:02,000\na" }.joined(separator: "\n\n")
        rejects { _ = try ModuleMediaImportParser.subtitle(Data(tooMany.utf8), filename: "many.srt") }
    }

    @Test("Registry upserts, kind separation, subtitle persistence and removals")
    func persistence() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ModuleMediaImportStore(directory: folder)
        try store.importRegistry(Data(source.utf8), kind: .danmaku)
        try store.importRegistry(Data(source.replacingOccurrences(of: "Local test", with: "Updated").utf8), kind: .danmaku)
        try store.importRegistry(Data(source.utf8), kind: .subtitle)
        let file = try store.importSubtitle(Data(srt.utf8), filename: "local.srt")
        #expect(store.archive.danmaku.count == 1 && store.archive.danmaku[0].name == "Updated")
        #expect(store.archive.subtitle[0].name == "Local test")
        let reloaded = ModuleMediaImportStore(directory: folder)
        reloaded.loadIfNeeded()
        #expect(reloaded.loadFailure == nil)
        #expect(reloaded.archive == store.archive)
        try reloaded.removeSource(id: "test", kind: .danmaku)
        try reloaded.removeSubtitle(id: file.id)
        let finalStore = ModuleMediaImportStore(directory: folder)
        finalStore.loadIfNeeded()
        #expect(finalStore.archive.danmaku.isEmpty && finalStore.archive.files.isEmpty)
        #expect(finalStore.archive.subtitle.count == 1)
    }

    @Test("Corrupt and future-version archives are retained and block writes")
    func corruptArchive() throws {
        for contents in ["{broken", #"{"version":99,"danmaku":[],"subtitle":[],"files":[]}"#] {
            let folder = directory()
            defer { try? FileManager.default.removeItem(at: folder) }
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent("registry-v1.json")
            let original = Data(contents.utf8)
            try original.write(to: url)
            let store = ModuleMediaImportStore(directory: folder)
            store.loadIfNeeded()
            #expect(store.loadFailure != nil)
            rejects { _ = try store.importRegistry(Data(source.utf8), kind: .danmaku) }
            #expect(try Data(contentsOf: url) == original)
        }
    }

    @Test("Store caps each source kind and subtitle-file count without partial writes")
    func storeLimits() throws {
        let folder = directory()
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = ModuleMediaImportStore(directory: folder)
        let rows = (0..<100).map { ModuleRegisteredMediaSource(id: "id\($0)", name: "Source \($0)", baseUrl: "https://example.invalid/\($0)") }
        try store.importRegistry(JSONEncoder().encode(rows), kind: .danmaku)
        let before = store.archive
        rejects { _ = try store.importRegistry(Data(source.utf8), kind: .danmaku) }
        #expect(store.archive == before)
        let shortSRT = Data("1\n00:00:01,000 --> 00:00:02,000\na".utf8)
        for index in 0..<50 { try store.importSubtitle(shortSRT, filename: "file\(index).srt") }
        rejects { _ = try store.importSubtitle(shortSRT, filename: "overflow.srt") }
        #expect(store.archive.files.count == 50)
        let reloaded = ModuleMediaImportStore(directory: folder)
        reloaded.loadIfNeeded()
        #expect(reloaded.archive == store.archive)
    }

    @Test("Failed disk write never publishes an unpersisted registry")
    func writeFailure() throws {
        let url = directory()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not a directory".utf8).write(to: url)
        let store = ModuleMediaImportStore(directory: url)
        rejects { _ = try store.importRegistry(Data(source.utf8), kind: .danmaku) }
        #expect(store.archive.danmaku.isEmpty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "not a directory")
    }

    @Test("File reader accepts exact limit and rejects limit+1 bytes")
    func boundedFileRead() throws {
        let url = directory()
        defer { try? FileManager.default.removeItem(at: url) }
        try Data(repeating: 65, count: 16).write(to: url)
        #expect(try ModuleMediaImportStore.readBounded(url, limit: 16).count == 16)
        rejects { _ = try ModuleMediaImportStore.readBounded(url, limit: 15) }
    }
}
