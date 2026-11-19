import CoreText
import YueduCoreText
import Foundation
import Testing
import UIKit
@testable import yuedu_app

/// Exercises the actual native pagination path: comments are rendered as inline attachments,
/// spliced into source coordinates, and limited using CoreText's final page ranges.
@MainActor
@Suite("Hot comment cards per actual reader page", .serialized)
struct ReaderHotCommentPageLimitTests {
    private static let paragraphCount = 14
    private static let sharedHotHref = "ydreview://r?d=page-limit-shared-hot"
    private static let authorHref = "ydreview://r?d=page-limit-author"
    private static let chapterHref = "ydreview://r?d=page-limit-chapter"
    private static let insets = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 16)

    private struct Fixture {
        let source: NSAttributedString
        let display: NSAttributedString
        let mapping: ReaderTranslationLayout
        let decorations: ReaderTranslationLayout.Decorations
        let settings: ReaderRenderSettings
        let bubbleHrefs: [String]
    }

    private func fixture(size: CGSize, fontSize: CGFloat, vertical: Bool,
                         limited: Bool = true, bilingual: Bool = false) async throws -> Fixture {
        let settings = ReaderRenderSettings(
            theme: "test", textColor: .black, backgroundColor: .white, fontSize: fontSize,
            lineHeightMultiple: 1.4, lineSpacing: 0, paragraphSpacing: 4, letterSpacing: 0,
            marginH: 16, marginV: 16, footerHeight: 0, contentInsets: Self.insets,
            writingMode: vertical ? .verticalRTL : .horizontal)
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = settings.lineHeightMultiple
        style.paragraphSpacing = settings.paragraphSpacing
        // Enough SOURCE text to span pages even after hot cards disappear; otherwise a
        // short chapter could legitimately collapse to one page and make >= 2 cards invalid.
        // Two cards per paragraph still create dense competing runs. Include surrogate pairs.
        let prose = String(repeating: "他推开窗，看见远山与灯火。", count: 5)
        let text = (0..<Self.paragraphCount).map { "第\($0 + 1)段，风起了🌿。\(prose)" }.joined(separator: "\n")
        let source = NSAttributedString(string: text, attributes: [
            .font: UIFont.systemFont(ofSize: fontSize), .foregroundColor: UIColor.black,
            .paragraphStyle: style,
        ])
        let paragraphs = ReaderTranslationText.paragraphs(in: text)
        #expect(paragraphs.count == Self.paragraphCount)
        var placements = ReaderCommentPlacements()
        placements.limitsHotCardsPerPage = limited
        let hot = ReviewCardContent(kind: .hotComment, title: "神评论", count: "", number: "",
                                    comments: [.init(user: "书友", likes: "3", content: "妙。")])
        var bubbleHrefs: [String] = []
        for index in paragraphs.indices {
            let href = "ydreview://r?d=page-limit-bubble-\(index)"
            bubbleHrefs.append(href)
            placements.bubbles[index] = .init(count: index + 11, href: href, title: "段评")
            // Identical hrefs deliberately do NOT identify a candidate. Both cards in each
            // paragraph, and cards on later pages, have distinct placement marker IDs.
            placements.cards[index] = [
                .init(content: hot, href: Self.sharedHotHref),
                .init(content: hot, href: Self.sharedHotHref),
            ]
        }
        placements.chapterEnd = [
            .init(content: .sample(for: .authorSay), href: Self.authorHref),
            .init(content: .sample(for: .chapterSay), href: Self.chapterHref),
        ]
        let pieces = ReaderCommentPieces(settings: settings, textColor: .black,
                                         columnWidth: size.width - Self.insets.left - Self.insets.right)
        let decorations = try #require(await pieces.decorations(placements, in: source, paragraphs: paragraphs))
        let spliced = try #require(ReaderTranslationLayout.splice(
            source, mode: bilingual ? .bilingual : .off, decorations: decorations,
            translation: { _ in bilingual ? "The wind rises." : nil }))
        return Fixture(source: source, display: spliced.display, mapping: spliced.layout,
                       decorations: decorations, settings: settings, bubbleHrefs: bubbleHrefs)
    }

    private func linkLength(_ href: String, in text: NSAttributedString) -> Int {
        var length = 0
        text.enumerateAttribute(HTMLAttributedStringBuilder.internalLinkAttribute,
                                in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if value as? String == href { length += range.length }
        }
        return length
    }

    private func links(in text: NSAttributedString) -> [String: Int] {
        var result: [String: Int] = [:]
        text.enumerateAttribute(HTMLAttributedStringBuilder.internalLinkAttribute,
                                in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let href = value as? String { result[href, default: 0] += range.length }
        }
        return result
    }

    private func assertMapping(_ mapping: ReaderTranslationLayout, source: NSAttributedString,
                               display: NSAttributedString) throws {
        #expect(mapping.sourceText == source.string)
        #expect(mapping.sourceLength == source.length)
        try #require(mapping.displayLength == display.length)
        let original = source.string as NSString
        let shown = display.string as NSString
        for offset in 0..<source.length {
            let mapped = mapping.displayOffset(charOffset: offset, translationOffset: nil)
            try #require(mapped >= 0 && mapped < display.length)
            #expect(shown.character(at: mapped) == original.character(at: offset), "source UTF-16 \(offset)")
            let back = mapping.sourcePosition(displayOffset: mapped)
            #expect(back.charOffset == offset && back.translationOffset == nil)
        }
        // Also exercise remapped inserted blocks: bubbles, kept cards, translations, and
        // chapter-end cards have no source character but must remain navigable positions.
        for offset in 0..<display.length {
            let position = mapping.sourcePosition(displayOffset: offset)
            #expect(mapping.displayOffset(charOffset: position.charOffset,
                                          translationOffset: position.translationOffset) == offset,
                    "display UTF-16 \(offset)")
        }
        let end = mapping.sourcePosition(displayOffset: display.length)
        #expect(end.charOffset == source.length && end.translationOffset == nil)
        #expect(mapping.displayOffset(charOffset: source.length, translationOffset: nil) == display.length)
        let copiedText = mapping.displayRanges(forSource: NSRange(location: 0, length: source.length))
            .map { shown.substring(with: $0) }.joined()
        #expect(copiedText == source.string, "annotations/TTS still address all source characters")
    }

    private func assertFinalLayout(_ layout: CoreTextPaginator.ChapterLayout, fixture: Fixture,
                                   context: String) throws {
        let original = ReaderHotCommentPageLimit.candidates(in: fixture.display)
        let kept = ReaderHotCommentPageLimit.candidates(in: layout.attributedString)
        try #require(layout.pageRanges.count > 1, "\(context): genuine multi-page chapter")
        #expect(!layout.isPartial)
        #expect(kept.count >= 2, "\(context): not a chapter-wide prefix(1)")
        #expect(Set(kept.map(\.id)).count == kept.count)
        #expect(kept.first?.id == original.first?.id, "\(context): retain the first card")
        #expect(ReaderHotCommentPageLimit.duplicateIDs(in: layout.attributedString,
                                                     pages: layout.pageRanges).isEmpty)
        var covered = Set<String>()
        var pagesWithCards = 0
        for (index, page) in layout.pageRanges.enumerated() {
            let onPage = kept.filter { $0.anchor >= page.location && $0.anchor < page.location + page.length }
            #expect(onPage.count <= 1, "\(context), actual page \(index): \(onPage.map(\.id))")
            if !onPage.isEmpty { pagesWithCards += 1 }
            covered.formUnion(onPage.map(\.id))
        }
        #expect(covered == Set(kept.map(\.id)), "no candidate hidden outside the final page ranges")
        #expect(pagesWithCards >= 2, "cards remain embedded on different reading pages")
        for card in kept {
            #expect((layout.attributedString.string as NSString).character(at: card.anchor) == 0xFFFC)
            #expect(layout.attributedString.attribute(NSAttributedString.Key(kCTRunDelegateAttributeName as String),
                                                      at: card.anchor, effectiveRange: nil) != nil,
                    "the retained card is an actual inline attachment, not a floating action")
            #expect(layout.attributedString.attribute(HTMLAttributedStringBuilder.internalLinkAttribute,
                                                      at: card.anchor, effectiveRange: nil) as? String == Self.sharedHotHref)
        }
        for href in fixture.bubbleHrefs + [Self.authorHref, Self.chapterHref] {
            let before = linkLength(href, in: fixture.display)
            #expect(before > 0, "the original piece must really have rendered: \(href)")
            #expect(linkLength(href, in: layout.attributedString) == before,
                    "\(context): preserve the entire linked bubble/chapter-end card: \(href)")
        }
        let keptIDs = Set(kept.map(\.id))
        let expectedElisions = original.filter { !keptIDs.contains($0.id) }.map(\.range)
        #expect(layout.hotCommentElisions == expectedElisions,
                "elisions name whole cards in ORIGINAL display coordinates")
        // Reconstruct independently, rather than validating the deletion helper with itself.
        let removed = NSMutableAttributedString(attributedString: fixture.display)
        for range in layout.hotCommentElisions.reversed() { removed.deleteCharacters(in: range) }
        #expect(removed.string == layout.attributedString.string, "nothing except hot-card pieces was removed")
        #expect(removed.length == fixture.display.length - layout.hotCommentElisions.reduce(0) { $0 + $1.length })
        let remapped = fixture.mapping.removingHotCommentDisplayRanges(layout.hotCommentElisions)
        try assertMapping(remapped, source: fixture.source, display: layout.attributedString)
    }

    @Test("320×500 / 390×844, 18 / 28 pt, horizontal / vertical: one hot card per FINAL page; all bubbles remain",
          arguments: [false, true])
    func actualPagination(vertical: Bool) async throws {
        for size in [CGSize(width: 320, height: 500), CGSize(width: 390, height: 844)] {
            for fontSize in [CGFloat(18), CGFloat(28)] {
                let chapter = try await fixture(size: size, fontSize: fontSize, vertical: vertical)
                let candidates = ReaderHotCommentPageLimit.candidates(in: chapter.display)
                try #require(candidates.count == Self.paragraphCount * 2)
                #expect(Set(candidates.map(\.id)).count == candidates.count,
                        "same href, distinct candidate IDs")
                let paginator = CoreTextPaginator()
                let revision = ContentRevision()
                // MUST precede the full request on a fresh paginator, otherwise a full-cache
                // hit would make the opening-page parity assertion vacuous.
                let first = try #require(await paginator.paginateFirstPage(
                    spineIndex: 0, attrStr: chapter.display, renderSize: size, fontSize: fontSize,
                    contentInsets: Self.insets, writingMode: chapter.settings.writingMode, revision: revision))
                #expect(first.isPartial)
                #expect(first.pageRanges.count == 1)
                let full = await paginator.paginate(
                    spineIndex: 0, attrStr: chapter.display, renderSize: size, fontSize: fontSize,
                    contentInsets: Self.insets, writingMode: chapter.settings.writingMode, revision: revision)
                let context = "\(size), \(fontSize) pt, vertical=\(vertical)"
                try assertFinalLayout(full, fixture: chapter, context: context)
                let partialRange = try #require(first.pageRanges.first)
                let fullRange = try #require(full.pageRanges.first)
                #expect(partialRange.location == fullRange.location && partialRange.length == fullRange.length,
                        "\(context): opening/full first-page ranges")
                let partialText = first.attributedString.attributedSubstring(
                    from: NSRange(location: partialRange.location, length: partialRange.length))
                let fullText = full.attributedString.attributedSubstring(
                    from: NSRange(location: fullRange.location, length: fullRange.length))
                #expect(partialText.string == fullText.string, "\(context): first-page content does not jump")
                #expect(links(in: partialText) == links(in: fullText))
                #expect(ReaderHotCommentPageLimit.candidates(in: partialText).map(\.id)
                        == ReaderHotCommentPageLimit.candidates(in: fullText).map(\.id))
                let partialArtifact = try #require(first.pageArtifacts.first)
                let fullArtifact = try #require(full.pageArtifacts.first)
                #expect(partialArtifact.lineOrigins == fullArtifact.lineOrigins,
                        "\(context): actual first-page geometry does not jump")
            }
        }
    }

    @Test("only whole hot-card pieces are marked; dense actual pages elide cards and remap bilingual blocks")
    func markersElisionsAndBilingualMapping() async throws {
        let size = CGSize(width: 390, height: 844)
        let chapter = try await fixture(size: size, fontSize: 18, vertical: false, bilingual: true)
        for index in 0..<Self.paragraphCount {
            let paragraph = try #require(chapter.decorations.paragraphs[index])
            let bubble = try #require(paragraph.trailing)
            #expect(ReaderHotCommentPageLimit.candidates(in: bubble).isEmpty, "count bubbles are never candidates")
            #expect(linkLength(chapter.bubbleHrefs[index], in: bubble) > 0)
            try #require(paragraph.below.count == 2)
            for piece in paragraph.below {
                let markers = ReaderHotCommentPageLimit.candidates(in: piece)
                try #require(markers.count == 1)
                let marker = try #require(markers.first)
                #expect(!marker.id.isEmpty)
                #expect(marker.range == NSRange(location: 0, length: piece.length),
                        "the marker includes all card padding and its newline, not only the image")
                #expect(linkLength(Self.sharedHotHref, in: piece) > 0)
            }
        }
        try #require(chapter.decorations.chapterEnd.count == 2)
        for piece in chapter.decorations.chapterEnd {
            #expect(ReaderHotCommentPageLimit.candidates(in: piece).isEmpty, "作者说/本章说 are not hot cards")
        }
        #expect(chapter.mapping.blocks.contains { $0.translation.length > 0 })
        let unrestricted = NSMutableAttributedString(attributedString: chapter.display)
        unrestricted.removeAttribute(ReaderHotCommentPageLimit.attribute,
                                     range: NSRange(location: 0, length: unrestricted.length))
        let baseline = await CoreTextPaginator().paginate(
            spineIndex: 0, attrStr: unrestricted, renderSize: size, fontSize: 18,
            contentInsets: Self.insets, writingMode: .horizontal)
        #expect(baseline.hotCommentElisions.isEmpty)
        #expect(baseline.attributedString.length == chapter.display.length)
        let candidates = ReaderHotCommentPageLimit.candidates(in: chapter.display)
        var rejected = Set<String>()
        for page in baseline.pageRanges {
            let onPage = candidates.filter { $0.anchor >= page.location && $0.anchor < page.location + page.length }
            rejected.formUnion(onPage.dropFirst().map(\.id))
        }
        try #require(!rejected.isEmpty, "the control must contain competing cards on real CoreText pages")
        #expect(ReaderHotCommentPageLimit.duplicateIDs(in: chapter.display, pages: baseline.pageRanges) == rejected)
        let limited = await CoreTextPaginator().paginate(
            spineIndex: 0, attrStr: chapter.display, renderSize: size, fontSize: 18,
            contentInsets: Self.insets, writingMode: .horizontal)
        #expect(!limited.hotCommentElisions.isEmpty, "the final-page limiter actually deletes competing cards")
        try assertFinalLayout(limited, fixture: chapter, context: "bilingual dense control")
        let mapping = chapter.mapping.removingHotCommentDisplayRanges(limited.hotCommentElisions)
        for block in mapping.blocks where block.translation.length > 0 {
            #expect((limited.attributedString.string as NSString).substring(with: block.translation) == "The wind rises.")
            #expect(limited.attributedString.attribute(ReaderTranslationLayout.attribute,
                                                       at: block.translation.location, effectiveRange: nil) as? Bool == true)
        }
    }

    @Test("sources that do not opt in keep all hot cards, bubbles, and chapter-end cards")
    func unmarkedPlacementsAreNotLimited() async throws {
        let size = CGSize(width: 390, height: 844)
        let chapter = try await fixture(size: size, fontSize: 18, vertical: false, limited: false)
        #expect(ReaderHotCommentPageLimit.candidates(in: chapter.display).isEmpty)
        let layout = await CoreTextPaginator().paginate(
            spineIndex: 0, attrStr: chapter.display, renderSize: size, fontSize: 18,
            contentInsets: Self.insets, writingMode: .horizontal)
        #expect(layout.hotCommentElisions.isEmpty)
        #expect(layout.attributedString.string == chapter.display.string)
        #expect(links(in: layout.attributedString) == links(in: chapter.display))
        #expect(linkLength(Self.sharedHotHref, in: layout.attributedString) > 0)
        #expect(chapter.mapping.removingHotCommentDisplayRanges([]) == chapter.mapping)
        try assertMapping(chapter.mapping, source: chapter.source, display: layout.attributedString)
    }
}
