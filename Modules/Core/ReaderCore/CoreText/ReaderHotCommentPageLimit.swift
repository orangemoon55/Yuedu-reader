import Foundation
import CoreFoundation

/// Only module hot-card blocks carry this marker. Badges, source text, 作者說 and 本章說 do not.
/// Selection happens after CoreText pagination; every pass deletes candidates, so it converges.
enum ReaderHotCommentPageLimit {
    static let attribute = NSAttributedString.Key("YDModuleHotCardPageCandidate")

    struct Candidate: Equatable {
        let id: String
        let range: NSRange
        let anchor: Int
    }

    static func candidates(in text: NSAttributedString) -> [Candidate] {
        guard text.length > 0 else { return [] }
        let string = text.string as NSString
        var result: [Candidate] = []
        text.enumerateAttribute(attribute, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
            guard let id = value as? String else { return }
            let glyph = string.range(of: "\u{FFFC}", options: [], range: range)
            result.append(Candidate(id: id, range: range, anchor: glyph.location == NSNotFound ? range.location : glyph.location))
        }
        return result
    }

    static func duplicateIDs(in text: NSAttributedString, pages: [CFRange]) -> Set<String> {
        var occupied = Set<Int>()
        var rejected = Set<String>()
        var page = 0
        for candidate in candidates(in: text) {
            while page < pages.count && candidate.anchor >= pages[page].location + pages[page].length { page += 1 }
            guard page < pages.count, candidate.anchor >= pages[page].location else { continue }
            if !occupied.insert(page).inserted { rejected.insert(candidate.id) }
        }
        return rejected
    }

    static func removing(_ ranges: [NSRange], from text: NSAttributedString) -> NSAttributedString {
        guard !ranges.isEmpty else { return text }
        let copy = NSMutableAttributedString(attributedString: text)
        for range in ranges.sorted(by: { $0.location > $1.location }) { copy.deleteCharacters(in: range) }
        return NSAttributedString(attributedString: copy)
    }

    /// Remap display positions only. Source characters and badge links are never removed.
    static func mappedOffset(_ offset: Int, deleting ranges: [NSRange]) -> Int {
        var removed = 0
        for range in ranges {
            if offset <= range.location { break }
            removed += min(range.length, offset - range.location)
        }
        return max(0, offset - removed)
    }

    static func mappedRange(_ range: NSRange, deleting ranges: [NSRange]) -> NSRange {
        let start = mappedOffset(range.location, deleting: ranges)
        let end = mappedOffset(NSMaxRange(range), deleting: ranges)
        return NSRange(location: start, length: max(0, end - start))
    }
}
