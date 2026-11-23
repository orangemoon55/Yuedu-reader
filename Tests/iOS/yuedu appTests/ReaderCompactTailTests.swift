import CoreText
import Foundation
import Testing
import UIKit
import YueduCoreText
@testable import yuedu_app

@Suite("Chinese short-tail fitting")
struct ReaderCompactTailTests {
    @Test("a screenshot-like quote tail is fitted or balanced by CoreText without changing source offsets",
          arguments: [CGFloat(0), CGFloat(0.25)])
    func screenshotLikeQuoteTailUsesBoundedLocalTracking(letterSpacing: CGFloat) async throws {
        let text = "“这肉咋这么嫩，里头的膏也是满的。”"
        let fontSize: CGFloat = 24
        let original = Self.attributed(text, fontSize: fontSize, letterSpacing: letterSpacing, indent: 48)
        var accepted: (width: CGFloat, value: NSAttributedString, before: [NSRange], after: [NSRange])?

        // Find a real CoreText width at which the quote ends with one or two Han characters.
        // This avoids relying on a guessed device width while exercising the same CT line breaker.
        for width in stride(from: CGFloat(180), through: 560, by: 1) {
            let before = Self.lineRanges(original, width: width)
            guard before.count >= 2,
                  let oldTail = before.last,
                  let oldTailHan = Self.hanCount(oldTail, in: original.string),
                  (1...2).contains(oldTailHan)
            else { continue }

            let candidate = CJKParagraphTailFit.fitting(original, lineWidth: width)
            guard !candidate.isEqual(to: original) else { continue }
            let after = Self.lineRanges(candidate, width: width)
            guard after.count == before.count || after.count < before.count else { continue }
            if after.count == before.count,
               let newTail = after.last,
               (Self.hanCount(newTail, in: candidate.string) ?? 0) <= oldTailHan {
                continue
            }
            accepted = (width, candidate, before, after)
            break
        }

        let result = try #require(accepted, "Expected a bounded CoreText fit or widow-balanced width for the quote fixture")
        #expect(result.value.string == original.string)
        #expect(result.value.length == original.length)
        #expect(result.before.count >= 2)
        #expect(result.after.count <= result.before.count)
        #expect(result.value.attribute(.font, at: 0, effectiveRange: nil) as? UIFont
            == original.attribute(.font, at: 0, effectiveRange: nil) as? UIFont)
        #expect((result.value.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment == .justified)

        let marker = (text as NSString).range(of: "的")
        #expect(marker.location != NSNotFound)
        #expect((result.value.string as NSString).range(of: "的") == marker)
        #expect(result.value.attribute(.kern, at: result.value.length - 1, effectiveRange: nil)
            as? NSNumber == original.attribute(.kern, at: original.length - 1, effectiveRange: nil) as? NSNumber)

        // The edit is a small per-em kern change, not a size change or whole-string rewrite.
        for index in 0..<original.length {
            let old = (original.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)
                .map { CGFloat($0.doubleValue) } ?? 0
            let new = (result.value.attribute(.kern, at: index, effectiveRange: nil) as? NSNumber)
                .map { CGFloat($0.doubleValue) } ?? 0
            #expect(abs(new - old) <= fontSize * CJKParagraphTailFit.maximumTrackingAdjustmentPerEm + 0.01)
        }

        // CTFrame ranges remain UTF-16 source ranges and still cover the unchanged text.
        let frame = Self.frame(result.value, width: result.width)
        let visible = CTFrameGetVisibleStringRange(frame)
        #expect(visible.location == 0)
        #expect(visible.length == original.length)
        let frameLines = CTFrameGetLines(frame) as! [CTLine]
        #expect(frameLines.count == result.after.count)

        let layout = await CoreTextPaginator().paginate(
            spineIndex: 0,
            attrStr: Self.attributed(text, fontSize: fontSize, letterSpacing: letterSpacing, indent: 48),
            renderSize: CGSize(width: result.width, height: 600), fontSize: fontSize
        )
        #expect(layout.attributedString.string == original.string)
        #expect(layout.attributedString.length == original.length)
        #expect(layout.pageRanges.reduce(0) { $0 + $1.length } == original.length)
        #expect(layout.attributedString.isEqual(to: result.value))
        #expect(layout.writingMode == .horizontal)
    }

    @Test("authored breaks, non-Chinese text, and link geometry are not candidates")
    func explicitBreaksAndNonChineseParagraphsRemainUntouched() {
        let hardLine = Self.attributed("这是足够长的一段中文内容，\u{2028}这里保留作者指定的换行位置。", fontSize: 20, letterSpacing: 0.4)
        #expect(CJKParagraphTailFit.fitting(hardLine, lineWidth: 180) === hardLine)

        let english = Self.attributed("A short English line should not be squeezed.", fontSize: 20, letterSpacing: 0.4)
        #expect(CJKParagraphTailFit.fitting(english, lineWidth: 180) === english)

        let japanese = Self.attributed("これは日本語の段落で、短い終わりです。", fontSize: 20, letterSpacing: 0.4)
        #expect(CJKParagraphTailFit.fitting(japanese, lineWidth: 180) === japanese)

        let quote = "“这肉咋这么嫩，里头的膏也是满的。”"
        let linked = NSMutableAttributedString(attributedString: Self.attributed(quote, fontSize: 24, letterSpacing: 0.4, indent: 48))
        linked.addAttribute(.link, value: URL(string: "https://example.com")!, range: NSRange(location: 0, length: linked.length))
        #expect(CJKParagraphTailFit.fitting(linked, lineWidth: 320) === linked)
    }

    @Test("a true paragraph boundary is never joined to its neighbour")
    func paragraphBreaksRemainAuthorialBoundaries() {
        let text = "“这肉咋这么嫩，里头的膏也是满。\n的。”"
        let attributed = Self.attributed(text, fontSize: 22, letterSpacing: 0.35, indent: 36)
        let fitted = CJKParagraphTailFit.fitting(attributed, lineWidth: 190)
        #expect(fitted.string == text)
        #expect(fitted.length == attributed.length)
        #expect(fitted === attributed)
    }

    private static func attributed(
        _ text: String,
        fontSize: CGFloat,
        letterSpacing: CGFloat,
        indent: CGFloat = 0
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .justified
        paragraph.firstLineHeadIndent = indent
        paragraph.lineBreakMode = .byCharWrapping
        let font = UIFont.systemFont(ofSize: fontSize)
        return NSAttributedString(string: text, attributes: [
            .font: font,
            .kern: NSNumber(value: Double(letterSpacing)),
            .paragraphStyle: paragraph,
            .foregroundColor: UIColor.label,
        ])
    }

    private static func frame(_ text: NSAttributedString, width: CGFloat) -> CTFrame {
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        return CTFramesetterCreateFrame(
            framesetter,
            CFRange(location: 0, length: text.length),
            CGPath(rect: CGRect(x: 0, y: 0, width: width, height: 2_000), transform: nil),
            nil
        )
    }

    private static func lineRanges(_ text: NSAttributedString, width: CGFloat) -> [NSRange] {
        let lines = CTFrameGetLines(frame(text, width: width)) as! [CTLine]
        return lines.map { line in
            let range = CTLineGetStringRange(line)
            return NSRange(location: range.location, length: range.length)
        }
    }

    private static func hanCount(_ range: NSRange, in text: String) -> Int? {
        let source = text as NSString
        var index = range.location
        var count = 0
        while index < NSMaxRange(range) {
            let cluster = source.rangeOfComposedCharacterSequence(at: index)
            guard NSMaxRange(cluster) <= NSMaxRange(range) else { return nil }
            let token = source.substring(with: cluster)
            if token.unicodeScalars.first.map({ isHan($0.value) }) == true {
                count += 1
            } else if !CharacterSet.punctuationCharacters.contains(token.unicodeScalars.first!) {
                return nil
            }
            index = NSMaxRange(cluster)
        }
        return count
    }

    private static func isHan(_ scalar: UInt32) -> Bool {
        (0x3400...0x4DBF).contains(scalar)
            || (0x4E00...0x9FFF).contains(scalar)
            || (0x20000...0x3134F).contains(scalar)
    }
}
