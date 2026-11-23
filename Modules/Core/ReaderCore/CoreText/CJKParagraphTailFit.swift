import CoreText
import Foundation
import UIKit
import YueduCoreTextTypography

/// Prevents a one- or two-character Chinese paragraph tail where a tiny, bounded
/// tracking adjustment can recover it or modestly balance it against the line above.
/// No text, UTF-16 offsets, fonts, paragraph styles, or authored breaks are changed.
enum CJKParagraphTailFit {
    /// Cap each tracking change at this fraction of its glyph's em.
    static let maximumTrackingAdjustmentPerEm: CGFloat = 0.04
    private static let minimumBalancedLineHanCount = 6
    private static let shortTailHanLimit = 2

    private static let closingPunctuation: Set<Character> = [
        "，", "。", "、", "；", "：", "！", "？", "…", "—", "·", "～",
        "”", "’", "」", "』", "）", "】", "》", "〉", "〕", "］", "｝",
        "\"", "'", ")", "]", "}", "!", "?", ".", ",", ";", ":",
    ]

    private static let openingPunctuation: Set<Character> = [
        "“", "‘", "「", "『", "（", "【", "《", "〈", "〔", "［", "｛",
    ]

    private struct KerningEdit {
        let index: Int
        let original: CGFloat
        let maximumDelta: CGFloat
    }

    /// Returns the same attributed string unless a short Chinese tail can be recovered
    /// completely, or safely balanced by moving one Han character onto the tail line.
    /// The caller must restrict this to horizontal text without float-shaped frame paths.
    static func fitting(_ string: NSAttributedString, lineWidth: CGFloat) -> NSAttributedString {
        guard string.length > 0, lineWidth.isFinite, lineWidth > 1 else { return string }
        let source = string.string as NSString
        var edits: [KerningEdit] = []
        var paragraphStart = 0

        while paragraphStart < source.length {
            let paragraph = source.paragraphRange(
                for: NSRange(location: paragraphStart, length: 0)
            )
            guard paragraph.length > 0 else { break }
            if let paragraphEdits = fitParagraph(
                paragraph,
                source: source,
                attributed: string,
                lineWidth: lineWidth
            ) {
                edits.append(contentsOf: paragraphEdits)
            }
            paragraphStart = NSMaxRange(paragraph)
        }

        guard !edits.isEmpty else { return string }
        let fitted = NSMutableAttributedString(attributedString: string)
        for edit in edits {
            fitted.addAttribute(
                .kern,
                value: NSNumber(value: Double(edit.original + edit.maximumDelta)),
                range: NSRange(location: edit.index, length: 1)
            )
        }
        return fitted
    }

    private static func fitParagraph(
        _ rawParagraph: NSRange,
        source: NSString,
        attributed: NSAttributedString,
        lineWidth: CGFloat
    ) -> [KerningEdit]? {
        var end = NSMaxRange(rawParagraph)
        // Foundation may treat a Unicode Line Separator as a paragraph boundary. Treat
        // both sides as authorial hard-break material rather than fitting either fragment.
        if (end > 0 && source.character(at: end - 1) == 0x2028)
            || (rawParagraph.location > 0 && source.character(at: rawParagraph.location - 1) == 0x2028) {
            return nil
        }
        while end > rawParagraph.location, isParagraphTerminator(source.character(at: end - 1)) {
            end -= 1
        }
        let paragraph = NSRange(location: rawParagraph.location, length: end - rawParagraph.location)
        guard paragraph.length > 1 else { return nil }
        let text = source.substring(with: paragraph)
        // U+2028 is an explicit authorial line break (poetry/dialogue formatting).
        guard !text.contains("\u{2028}"), !text.contains("\u{000C}"),
              let script = CJKTypographyStyle.detect(in: text),
              script == .simplified || script == .traditional,
              let style = attributed.attribute(.paragraphStyle, at: paragraph.location, effectiveRange: nil)
                as? NSParagraphStyle,
              [.left, .natural, .justified].contains(style.alignment),
              style.baseWritingDirection != .rightToLeft,
              isHanDominantWithoutLatinOrDigits(text)
        else { return nil }

        let lines = lineRanges(in: paragraph, attributed: attributed, style: style, lineWidth: lineWidth)
        guard lines.count >= 2,
              let tail = lines.last,
              let previous = lines.dropLast().last,
              let tailHan = hanCount(in: tail, source: source),
              (1...shortTailHanLimit).contains(tailHan),
              hasNoLinkOrInlineAttachment(
                NSRange(location: previous.location, length: NSMaxRange(tail) - previous.location),
                attributed: attributed
              )
        else { return nil }

        let joined = NSRange(location: previous.location, length: NSMaxRange(tail) - previous.location)
        let width = availableWidth(
            lineStart: previous.location,
            paragraph: paragraph,
            style: style,
            lineWidth: lineWidth
        )

        // Prefer pulling the entire tail onto the preceding line. Only existing positive
        // reader tracking is removed; no glyph advances below their untracked width.
        let compression = trackingEdits(
            in: joined,
            source: source,
            attributed: attributed,
            direction: -1
        )
        if let recovered = minimalEditsThatFit(joined, width: width, edits: compression, attributed: attributed) {
            return recovered
        }

        // If a whole-line recovery exceeds the compression budget, rebalance gently instead:
        // add at most 0.04em per inter-Han gap on the preceding line, and keep the paragraph's
        // line count stable. CoreText must actually move a Han glyph to the short final line;
        // otherwise no edit is made. This is a bounded orphan reduction, not forced reflow.
        guard let oldPreviousHan = hanCount(in: previous, source: source, allowOpening: true) else { return nil }
        let desiredTailHan = min(3, tailHan + 1)
        let balancing = trackingEdits(
            in: previous,
            source: source,
            attributed: attributed,
            direction: 1
        )
        guard !balancing.isEmpty else { return nil }
        return minimalEditsThatBalance(
            paragraph: paragraph,
            originalLines: lines,
            previousLine: previous,
            oldPreviousHan: oldPreviousHan,
            desiredTailHan: desiredTailHan,
            width: lineWidth,
            style: style,
            edits: balancing,
            source: source,
            attributed: attributed
        )
    }

    private static func lineRanges(
        in paragraph: NSRange,
        attributed: NSAttributedString,
        style: NSParagraphStyle,
        lineWidth: CGFloat
    ) -> [NSRange] {
        let typesetter = CTTypesetterCreateWithAttributedString(
            attributed.attributedSubstring(from: paragraph) as CFAttributedString
        )
        var lines: [NSRange] = []
        var start = 0
        while start < paragraph.length {
            let width = availableWidth(
                lineStart: paragraph.location + start,
                paragraph: paragraph,
                style: style,
                lineWidth: lineWidth
            )
            guard width > 1 else { return [] }
            let count = CTTypesetterSuggestLineBreak(typesetter, start, Double(width))
            guard count > 0 else { return [] }
            lines.append(NSRange(location: paragraph.location + start, length: count))
            start += count
        }
        return lines
    }

    private static func availableWidth(
        lineStart: Int,
        paragraph: NSRange,
        style: NSParagraphStyle,
        lineWidth: CGFloat
    ) -> CGFloat {
        let head = lineStart == paragraph.location ? style.firstLineHeadIndent : style.headIndent
        let trailing = style.tailIndent > 0 ? style.tailIndent : lineWidth + style.tailIndent
        return trailing - head
    }

    private static func minimalEditsThatFit(
        _ range: NSRange,
        width: CGFloat,
        edits: [KerningEdit],
        attributed: NSAttributedString
    ) -> [KerningEdit]? {
        guard !edits.isEmpty,
              fitsOnOneLine(range, width: width, edits: edits, factor: 1, attributed: attributed)
        else { return nil }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<12 {
            let middle = (low + high) / 2
            if fitsOnOneLine(range, width: width, edits: edits, factor: middle, attributed: attributed) {
                high = middle
            } else {
                low = middle
            }
        }
        let factor = min(1, high + 0.01)
        guard fitsOnOneLine(range, width: width, edits: edits, factor: factor, attributed: attributed) else {
            return nil
        }
        return edits.compactMap { edit in
            let delta = edit.maximumDelta * factor
            return abs(delta) > 0.001
                ? KerningEdit(index: edit.index, original: edit.original, maximumDelta: delta)
                : nil
        }
    }

    private static func fitsOnOneLine(
        _ range: NSRange,
        width: CGFloat,
        edits: [KerningEdit],
        factor: CGFloat,
        attributed: NSAttributedString
    ) -> Bool {
        let adjusted = NSMutableAttributedString(attributedString: attributed.attributedSubstring(from: range))
        for edit in edits {
            let localIndex = edit.index - range.location
            guard localIndex >= 0, localIndex < adjusted.length else { return false }
            adjusted.addAttribute(
                .kern,
                value: NSNumber(value: Double(edit.original + edit.maximumDelta * factor)),
                range: NSRange(location: localIndex, length: 1)
            )
        }
        let typesetter = CTTypesetterCreateWithAttributedString(adjusted as CFAttributedString)
        return CTTypesetterSuggestLineBreak(typesetter, 0, Double(width)) >= range.length
    }

    private static func minimalEditsThatBalance(
        paragraph: NSRange,
        originalLines: [NSRange],
        previousLine: NSRange,
        oldPreviousHan: Int,
        desiredTailHan: Int,
        width: CGFloat,
        style: NSParagraphStyle,
        edits: [KerningEdit],
        source: NSString,
        attributed: NSAttributedString
    ) -> [KerningEdit]? {
        // Bisection copies only this paragraph, never the whole chapter.
        let local = attributed.attributedSubstring(from: paragraph)
        let localSource = local.string as NSString
        let localRange = NSRange(location: 0, length: local.length)
        func acceptable(_ factor: CGFloat) -> Bool {
            let adjusted = NSMutableAttributedString(attributedString: local)
            for edit in edits {
                adjusted.addAttribute(
                    .kern,
                    value: NSNumber(value: Double(edit.original + edit.maximumDelta * factor)),
                    range: NSRange(location: edit.index - paragraph.location, length: 1)
                )
            }
            let lines = lineRanges(in: localRange, attributed: adjusted, style: style, lineWidth: width)
            guard lines.count == originalLines.count,
                  let tail = lines.last,
                  let previous = lines.dropLast().last,
                  let tailHan = hanCount(in: tail, source: localSource),
                  let previousHan = hanCount(in: previous, source: localSource, allowOpening: true)
            else { return false }
            return tailHan >= desiredTailHan
                && previousHan >= max(minimumBalancedLineHanCount, oldPreviousHan / 2)
        }

        guard acceptable(1) else { return nil }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<12 {
            let middle = (low + high) / 2
            if acceptable(middle) { high = middle } else { low = middle }
        }
        let factor = min(1, high + 0.01)
        guard acceptable(factor) else { return nil }
        return edits.compactMap { edit in
            let delta = edit.maximumDelta * factor
            return delta > 0.001
                ? KerningEdit(index: edit.index, original: edit.original, maximumDelta: delta)
                : nil
        }
    }

    private static func trackingEdits(
        in range: NSRange,
        source: NSString,
        attributed: NSAttributedString,
        direction: CGFloat
    ) -> [KerningEdit] {
        var edits: [KerningEdit] = []
        var index = range.location
        while index < NSMaxRange(range) {
            let cluster = source.rangeOfComposedCharacterSequence(at: index)
            let token = source.substring(with: cluster)
            let kernIndex = NSMaxRange(cluster) - 1
            // Kern advances after each glyph. Never edit the final advance of a candidate line.
            if kernIndex < NSMaxRange(range) - 1, isHanGrapheme(token),
               let font = attributed.attribute(.font, at: cluster.location, effectiveRange: nil) as? UIFont {
                let original = (attributed.attribute(.kern, at: kernIndex, effectiveRange: nil) as? NSNumber)
                    .map { CGFloat($0.doubleValue) } ?? 0
                let em = max(1, font.pointSize)
                let cap = maximumTrackingAdjustmentPerEm * em
                if direction < 0, original > 0.001 {
                    edits.append(KerningEdit(
                        index: kernIndex,
                        original: original,
                        maximumDelta: -min(cap, original)
                    ))
                } else if direction > 0, original >= -0.001 {
                    edits.append(KerningEdit(index: kernIndex, original: original, maximumDelta: cap))
                }
            }
            index = NSMaxRange(cluster)
        }
        return edits
    }

    private static func hanCount(in range: NSRange, source: NSString, allowOpening: Bool = false) -> Int? {
        var count = 0
        var index = range.location
        while index < NSMaxRange(range) {
            let cluster = source.rangeOfComposedCharacterSequence(at: index)
            guard NSMaxRange(cluster) <= NSMaxRange(range) else { return nil }
            let value = source.substring(with: cluster)
            guard isHanGrapheme(value) || closingPunctuation.contains(Character(value))
                || (allowOpening && openingPunctuation.contains(Character(value))) else { return nil }
            if isHanGrapheme(value) { count += 1 }
            index = NSMaxRange(cluster)
        }
        return count
    }

    private static func isHanDominantWithoutLatinOrDigits(_ text: String) -> Bool {
        var han = 0
        var otherLettersOrDigits = 0
        for scalar in text.unicodeScalars {
            if isHanScalar(scalar.value) {
                han += 1
            } else if CharacterSet.letters.contains(scalar) || CharacterSet.decimalDigits.contains(scalar) {
                otherLettersOrDigits += 1
            }
        }
        return han >= 12 && otherLettersOrDigits == 0
    }

    private static func isHanGrapheme(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        return isHanScalar(scalar.value)
    }

    private static func isHanScalar(_ scalar: UInt32) -> Bool {
        switch scalar {
        case 0x3400...0x4DBF, 0x4E00...0x9FFF, 0x20000...0x3134F:
            return true
        default:
            return false
        }
    }

    private static func hasNoLinkOrInlineAttachment(_ range: NSRange, attributed: NSAttributedString) -> Bool {
        var safe = true
        let keys: [NSAttributedString.Key] = [
            .link, .attachment, NSAttributedString.Key(kCTRunDelegateAttributeName as String),
        ]
        for key in keys {
            attributed.enumerateAttribute(key, in: range, options: []) { value, _, stop in
                if value != nil {
                    safe = false
                    stop.pointee = true
                }
            }
            if !safe { return false }
        }
        return true
    }

    private static func isParagraphTerminator(_ codeUnit: unichar) -> Bool {
        codeUnit == 0x000A || codeUnit == 0x000D || codeUnit == 0x2029
    }
}
