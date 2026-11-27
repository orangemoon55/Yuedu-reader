import Foundation

/// Decides whether a search hit on another platform is the same recording.
/// Strict on purpose: playing nothing beats playing the wrong version.
enum AudioSourceTrackMatcher {
    static let maximumDurationDifferenceMS = 5_000
    /// Only the top hits are considered; deeper results are rarely the song.
    static let candidateLimit = 5

    /// The best acceptable candidate, or nil when none passes.
    static func best<Payload>(_ query: UnblockQuery, in candidates: [UnblockCandidate<Payload>]) -> Payload? {
        candidates.prefix(candidateLimit)
            .compactMap { candidate in score(query, candidate).map { (candidate.payload, $0) } }
            .max { $0.1 < $1.1 }?.0
    }

    /// Nil rejects the candidate; a higher score is a closer match.
    static func score<Payload>(_ query: UnblockQuery, _ candidate: UnblockCandidate<Payload>) -> Int? {
        guard query.durationMS > 0, candidate.durationMS > 0 else { return nil }
        let difference = abs(candidate.durationMS - query.durationMS)
        guard difference <= maximumDurationDifferenceMS else { return nil }

        let exactTitle = normalized(candidate.title) == normalized(query.title)
        guard exactTitle || (!normalized(stripped(query.title)).isEmpty
            && normalized(stripped(candidate.title)) == normalized(stripped(query.title)))
        else { return nil }
        guard !hasVersionConflict(original: query.title, candidate: candidate.title) else { return nil }

        let expected = query.artists.map(normalized).filter { !$0.isEmpty }
        guard let primary = expected.first else { return nil }
        let offered = artistNames(in: candidate.artist)
        guard offered.contains(primary) else { return nil }

        var score = 100 - difference / 100
        if exactTitle { score += 20 }
        if !query.album.isEmpty, normalized(candidate.album) == normalized(query.album) { score += 15 }
        if Set(offered) == Set(expected) { score += 10 }
        return score
    }

    private static let versionMarkers = [
        "live", "remix", "伴奏", "dj", "cover", "翻唱", "instrumental", "karaoke", "现场", "纯音乐"
    ]

    private static func hasVersionConflict(original: String, candidate: String) -> Bool {
        let originalMarkers = Set(versionMarkers.filter { normalized(original).contains($0) })
        let candidateMarkers = Set(versionMarkers.filter { normalized(candidate).contains($0) })
        return originalMarkers != candidateMarkers
    }

    /// Drops bracketed annotations and a trailing " - subtitle", e.g.
    /// "晴天 (电影《XX》插曲)" → "晴天".
    static func stripped(_ title: String) -> String {
        var result = title
        let pairs: [(Character, Character)] = [("(", ")"), ("（", "）"), ("[", "]"), ("【", "】"), ("《", "》")]
        for (open, close) in pairs {
            while let start = result.firstIndex(of: open),
                  let end = result[start...].firstIndex(of: close) {
                result.removeSubrange(start...end)
            }
        }
        if let dash = result.range(of: " - ") { result = String(result[..<dash.lowerBound]) }
        return result.trimmingCharacters(in: .whitespaces)
    }

    private static func artistNames(in value: String) -> [String] {
        value.split(whereSeparator: { "/&、,，;；".contains($0) })
            .map { normalized(String($0)) }
            .filter { !$0.isEmpty }
    }

    static func normalized(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .unicodeScalars
            .filter(CharacterSet.alphanumerics.contains)
            .map { String($0) }
            .joined()
    }
}
