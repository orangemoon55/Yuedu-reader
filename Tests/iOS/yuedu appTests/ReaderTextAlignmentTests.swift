@testable import YueduCoreText
import CoreText
import Foundation
import Testing
import UIKit
@testable import yuedu_app

private final class AlignmentChapterProvider: BookContentProvider {
    let payload: ChapterContentPayload
    init(_ body: String) {
        payload = ChapterContentPayload(index: 0, title: "Alignment fixture", plainText: body,
            body: .plainText(body), sourceHref: "https://example.invalid/alignment")
    }
    var totalChapters: Int { 1 }
    func chapterTitle(at index: Int) -> String { payload.title }
    func contentForChapter(index: Int) async throws -> ChapterContentPayload {
        guard index == 0 else { throw BookContentProviderError.chapterIndexOutOfRange(index) }
        return payload
    }
}

/// Complements PlainTextParagraphFormattingTests, ReadingSettingsScopeTests,
/// ReaderRenderSettingsSnapshotTests and BrowserLayoutJustificationTests.
/// Keep construction, await, CoreText measurement and assertions on the same actor.
/// In particular, do not return NSMutableAttributedString from MainActor.run/Task.
@Suite("Reader paragraph alignment", .serialized)
@MainActor
struct ReaderTextAlignmentTests {
    private static func settings(_ alignment: ReaderTextAlignment = .justified) -> ReaderRenderSettings {
        var value = ReaderRenderSettings(theme: "alignment-test", textColor: .black,
            backgroundColor: .white, fontSize: 18, lineHeightMultiple: 1.4,
            lineSpacing: 0, paragraphSpacing: 12.6, letterSpacing: 0,
            marginH: 0, marginV: 0, footerHeight: 0, contentInsets: .zero,
            writingMode: .horizontal)
        value.chapterTitleStyle.visible = false
        value.textAlignment = alignment
        return value
    }

    @Test("enum values and existing settings retain the justified default")
    func defaultsAndEnumRoundTrip() throws {
        let implicit = ReaderRenderSettings(theme: "test", textColor: .black,
            backgroundColor: .white, fontSize: 18, lineHeightMultiple: 1.4,
            lineSpacing: 0, paragraphSpacing: 12.6, letterSpacing: 0,
            marginH: 0, marginV: 0, footerHeight: 0, contentInsets: .zero)
        #expect(implicit.textAlignment == .justified)
        #expect(ReaderTextAlignment.allCases == [.natural, .justified])
        #expect(ReaderTextAlignment.natural.nsTextAlignment == .natural)
        #expect(ReaderTextAlignment.justified.nsTextAlignment == .justified)
        for value in ReaderTextAlignment.allCases {
            let data = try JSONEncoder().encode(value)
            #expect(try JSONDecoder().decode(ReaderTextAlignment.self, from: data) == value)
        }
    }

    @Test("TXT and online text keep strings, UTF16 positions, 2em indent and paragraph gaps",
          arguments: ReaderTextAlignment.allCases)
    func plainTextRendersWithoutRewriting(_ alignment: ReaderTextAlignment) async throws {
        let first = "😀e\u{301} " + String(repeating: "The quiet garden opens to the morning light. ", count: 5) + "End."
        let second = "尾段🚀e\u{301}。"
        let body = first + "\n" + second
        let value = Self.settings(alignment)
        let txt = TXTLazyAttributedStringBuilder(text: body, chapterIndexes: [
            TXTChapterIndex(index: 0, title: "Alignment fixture",
                contentRange: NSRange(location: 0, length: (body as NSString).length))
        ])
        let local = try await txt.buildChapter(at: 0, settings: value,
            themeTextColor: .black, themeBackgroundColor: .white)
        let online = OnlineProviderAttributedStringBuilder(provider: AlignmentChapterProvider(body),
            renderSize: CGSize(width: 320, height: 1200))
        let remote = try await online.buildChapter(at: 0, settings: value,
            themeTextColor: .black, themeBackgroundColor: .white)

        // Both builders canonically terminate each source paragraph with one newline.
        for attributed in [local.attributedString, remote.attributedString] {
            #expect(attributed.string == body + "\n")
            #expect(attributed.length == (body as NSString).length + 1)
            #expect(!attributed.string.contains("\u{3000}\u{3000}"))
            let ns = attributed.string as NSString
            let secondStart = (first as NSString).length + 1
            #expect(ns.range(of: second).location == secondStart)
            #expect(ns.range(of: "😀").length == 2)
            #expect(ns.range(of: "e\u{301}").length == 2)
            for start in [0, secondStart] {
                let style = try #require(attributed.attribute(.paragraphStyle,
                    at: start, effectiveRange: nil) as? NSParagraphStyle)
                #expect(style.alignment == alignment.nsTextAlignment)
                #expect(abs(style.firstLineHeadIndent - 2 * value.fontSize) < 0.1)
                #expect(abs(style.paragraphSpacing - value.paragraphSpacing) < 0.1)
            }
            let frame = CTFramesetterCreateFrame(CTFramesetterCreateWithAttributedString(attributed),
                CFRange(location: 0, length: attributed.length),
                CGPath(rect: CGRect(x: 0, y: 0, width: 320, height: 1200), transform: nil), nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            #expect(visible.location == 0 && visible.length == attributed.length)
            let lines = CTFrameGetLines(frame) as! [CTLine]
            var origins = [CGPoint](repeating: .zero, count: lines.count)
            CTFrameGetLineOrigins(frame, CFRange(location: 0, length: lines.count), &origins)
            let secondLine = try #require(lines.firstIndex {
                let range = CTLineGetStringRange($0)
                return range.location <= secondStart && secondStart < range.location + range.length
            })
            #expect(secondLine > 1, "The first paragraph must actually wrap")
            #expect(abs(origins[0].x - 36) < 0.5)
            #expect(abs(origins[secondLine].x - 36) < 0.5)
            if secondLine > 1 {
                let normalGap = origins[0].y - origins[1].y
                let paragraphGap = origins[secondLine - 1].y - origins[secondLine].y
                #expect(abs(paragraphGap - normalGap - value.paragraphSpacing) < 1)
            }
            let tail = lines[secondLine]
            let tailWidth = CTLineGetTypographicBounds(tail, nil, nil, nil)
                - CTLineGetTrailingWhitespaceWidth(tail)
            #expect(origins[secondLine].x + tailWidth < 300,
                "A short final line must never be force-stretched, even when justified")
            #expect(CTLineGetStringRange(tail).location == secondStart)
        }
        #expect(local.attributedString.string == remote.attributedString.string)
    }

    @Test("Node config applies the reader default but preserves authored center and right",
          arguments: ReaderTextAlignment.allCases)
    func nodeRendererHonorsAuthoredAlignment(_ alignment: ReaderTextAlignment) async throws {
        let value = Self.settings(alignment)
        var centered = RenderStyle.body
        centered.textAlign = .center
        var right = RenderStyle.body
        right.textAlign = .right
        let renderer = NodeAttributedStringRenderer(config: .init(from: value,
            textColor: .black, renderWidth: 320))
        let rendered = await renderer.render([
            .paragraph([.text("Default😀e\u{301}")], style: .body),
            .paragraph([.text("Centered")], style: centered),
            .paragraph([.text("Right")], style: right)
        ])
        for (text, expected) in [("Default😀e\u{301}", alignment.nsTextAlignment),
                                 ("Centered", .center), ("Right", .right)] {
            let range = (rendered.string as NSString).range(of: text)
            try #require(range.location != NSNotFound)
            let style = try #require(rendered.attribute(.paragraphStyle,
                at: range.location, effectiveRange: nil) as? NSParagraphStyle)
            #expect(style.alignment == expected)
        }
        #expect(rendered.string.split(separator: "\n").map(String.init)
            == ["Default😀e\u{301}", "Centered", "Right"])
    }

    private static func browserConfig(_ settings: ReaderRenderSettings) -> BrowserLayoutConfig {
        BrowserLayoutConfigInputs(settings: settings, writingMode: .horizontal,
            fontScalePolicy: .readerAdjustable, contentWidth: 213, contentHeight: 800,
            textColor: .black, backgroundColor: .white, contentInsets: .zero,
            cjkTypographyStyle: nil, publicationFontResolver: nil).makeConfiguration()
    }

    @Test("browser settings reach real line geometry, raster and UTF16 selection",
          arguments: ReaderTextAlignment.allCases)
    func browserRendersBothDefaults(_ alignment: ReaderTextAlignment) throws {
        let text = String(repeating: "春眠不覺曉處處聞啼鳥夜來風雨聲花落知多少", count: 4) + "🚀e\u{301}"
        for bottom in [false, true] {
            var value = Self.settings(alignment)
            value.bottomJustify = bottom
            var config = Self.browserConfig(value)
            #expect(config.defaultTextAlignment == alignment.nsTextAlignment)
            #expect(config.bottomJustify == bottom)
            config.fontResolver = { _, _, _, size in UIFont.systemFont(ofSize: size) }
            let document = BrowserLayoutDocument(html: "<p>\(text)</p>",
                cssTexts: ["body,p { margin:0; font-size:20px; line-height:28px; }"], config: config)
            let pipeline = try document.makeLayout(containerSize: CGSize(width: 213, height: 800))
            let pages = PageFragmentation.fragment(box: pipeline.rootBox,
                pageSize: CGSize(width: 213, height: 800))
            #expect(pipeline.sourceText == text)
            #expect(BrowserLayoutTestSupport.visibleText(pages, sourceText: pipeline.sourceText) == text)
            let fragments = BrowserLayoutTestSupport.allTextFragments(pages)
            #expect(fragments.count > 3)
            let first = try #require(fragments.first)
            let line = try #require(first.ctLine)
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
                - CTLineGetTrailingWhitespaceWidth(line)
            if alignment == .justified {
                #expect(abs(width - 213) < 0.2)
                #expect(abs(first.rect.maxX - 213) < 0.2)
            } else {
                #expect(width < 212)
                #expect(abs(first.rect.minX) < 0.2)
            }
            let tail = try #require(fragments.last)
            #expect(CTLineGetTypographicBounds(try #require(tail.ctLine), nil, nil, nil) < 212)
            let list = DisplayListBuilder.build(for: try #require(pages.first), sourceText: pipeline.sourceText)
            let marker = (text as NSString).range(of: "🚀e\u{301}")
            #expect(marker.length == 4)
            #expect(!BrowserTextGeometry.rects(in: list, range: marker).isEmpty)
            #expect(BrowserTextGeometry.caret(at: NSMaxRange(marker), isEnd: true, in: list) != nil)
            let image = DisplayListRenderer.render(list, size: CGSize(width: 213, height: 800))
            #expect(try #require(image.cgImage).width > 0)
        }
    }

    @Test("authored HTML center, right and justify override either reader default",
          arguments: ReaderTextAlignment.allCases)
    func browserHonorsExplicitCSS(_ alignment: ReaderTextAlignment) throws {
        for (css, expected) in [("center", NSTextAlignment.center), ("right", .right)] {
            let config = Self.browserConfig(Self.settings(alignment))
            let doc = BrowserLayoutDocument(
                html: "<section style='text-align:\(css)'><p>Short😀</p></section>",
                cssTexts: ["body,p { margin:0; font-size:20px; line-height:28px; }"], config: config)
            let result = try doc.makeLayout(containerSize: CGSize(width: 213, height: 800))
            let pages = PageFragmentation.fragment(box: result.rootBox,
                pageSize: CGSize(width: 213, height: 800))
            let fragment = try #require(BrowserLayoutTestSupport.allTextFragments(pages).first)
            let width = CTLineGetTypographicBounds(try #require(fragment.ctLine), nil, nil, nil)
            let expectedX = expected == .center ? (213 - width) / 2 : 213 - width
            #expect(abs(fragment.rect.minX - expectedX) < 0.5)
            #expect(result.sourceText == "Short😀")
        }
        // The reverse override matters too: natural is a default, not a blanket ban on justify.
        let config = Self.browserConfig(Self.settings(alignment))
        let text = String(repeating: "春眠不覺曉處處聞啼鳥", count: 5)
        let doc = BrowserLayoutDocument(html: "<p style='text-align:justify'>\(text)</p>",
            cssTexts: ["body,p { margin:0; font-size:20px; line-height:28px; }"], config: config)
        let result = try doc.makeLayout(containerSize: CGSize(width: 213, height: 800))
        let pages = PageFragmentation.fragment(box: result.rootBox,
            pageSize: CGSize(width: 213, height: 800))
        let first = try #require(BrowserLayoutTestSupport.allTextFragments(pages).first)
        #expect(abs(first.rect.width - 213) < 0.2)
    }

    @Test("sparse theme Codable, scope restriction and clearing do not touch bottomJustify")
    func themeCodableAndScopeAreIndependent() throws {
        let legacy = try JSONDecoder().decode(AppearanceThemeReadingSettings.self,
            from: Data(#"{"bottomJustify":true,"fontSize":21}"#.utf8))
        #expect(legacy.textAlignment == nil)
        for alignment in ReaderTextAlignment.allCases {
            var reading = legacy
            reading.textAlignment = alignment.rawValue
            let decoded = try JSONDecoder().decode(AppearanceThemeReadingSettings.self,
                from: JSONEncoder().encode(reading))
            #expect(decoded == reading)
            #expect(decoded.items == [.fontSize, .bottomJustify, .textAlignment])
            let only = decoded.restricted(to: [.textAlignment])
            #expect(only.textAlignment == alignment.rawValue)
            #expect(only.bottomJustify == nil && only.fontSize == nil)
            #expect(only.items == [.textAlignment])
            var cleared = decoded
            cleared.clear(.textAlignment)
            #expect(cleared == legacy)
            cleared = decoded
            cleared.clear(.bottomJustify)
            #expect(cleared.textAlignment == alignment.rawValue)
            #expect(cleared.bottomJustify == nil && cleared.fontSize == 21)
        }
        var scope = ReadingSettingsScopeConfiguration.default
        #expect(scope.scope(of: .textAlignment) == .theme)
        scope.setScope(.global, for: .textAlignment)
        #expect(scope.scope(of: .textAlignment) == .global)
        #expect(scope.scope(of: .bottomJustify) == .theme)
        let decodedScope = try JSONDecoder().decode(ReadingSettingsScopeConfiguration.self,
            from: JSONEncoder().encode(scope))
        #expect(decodedScope == scope)
    }

    private static func snapshotInput() -> ReaderRenderSettingsSnapshotInput {
        ReaderRenderSettingsSnapshotInput(theme: "test", textColor: .black,
            backgroundColor: .white, fontSize: 18, lineHeightMultiple: 1.4,
            lineSpacing: 0, paragraphSpacing: 12.6, letterSpacing: 0, marginH: 0,
            writingMode: .horizontal, fontPostScriptName: nil, isBold: false,
            chapterTitleStyle: .default, readerBackgroundImageURL: nil,
            regexHighlightConfiguration: .disabled, readerStyleAppearance: .light,
            readerStyleAssetRevision: 0, dialogueBubbleStyle: .default, displayScale: 2)
    }

    @Test("alignment survives paged and scroll snapshots and invalidates layout, not paint")
    func snapshotAndRefreshIntent() {
        #expect(Self.snapshotInput().textAlignment == .justified)
        for bottom in [false, true] {
            for surface in [ReaderRenderSurface.paged(contentInsets: .zero, marginV: 0, footerHeight: 0),
                            .scroll(contentInsets: .zero, marginV: 0, footerHeight: 0)] {
                var input = Self.snapshotInput()
                input.bottomJustify = bottom
                let justified = ReaderRenderSettingsSnapshotBuilder.make(input: input, surface: surface)
                input.textAlignment = .natural
                let natural = ReaderRenderSettingsSnapshotBuilder.make(input: input, surface: surface)
                #expect(justified.textAlignment == .justified)
                #expect(natural.textAlignment == .natural)
                #expect(justified != natural)
                #expect(natural.bottomJustify == justified.bottomJustify)
                #expect(natural.refreshIntent(comparedTo: justified) == .layout)
                #expect(justified.refreshIntent(comparedTo: natural) == .layout)
                #expect(natural.refreshIntent(comparedTo: natural) == nil)
                var recolored = natural
                recolored.textColor = .red
                #expect(recolored.refreshIntent(comparedTo: natural) == .appearance)
                recolored.textAlignment = .justified
                #expect(recolored.refreshIntent(comparedTo: natural) == .layout)
                switch surface {
                case .paged: #expect(natural.bottomJustify == bottom)
                case .scroll: #expect(!natural.bottomJustify)
                }
            }
        }
    }
}
