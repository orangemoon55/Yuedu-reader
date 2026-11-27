import Foundation

/// Metadata belongs to the recording found in that provider's catalog. Missing
/// fields remain missing: the current track's album must never fill a search hit.
struct LyricsCandidate {
    let source: LyricsSource
    let id: String
    let title: String
    let artists: [String]
    let album: String?
    let duration: TimeInterval?
    let response: LyricResponse
    /// Found by the track's own id in that catalog (Netease id, QQ mid, Qishui
    /// track id, Kugou hash), so its recording identity is certain.
    var matchedByID = false
}

struct LyricsSelection {
    let source: LyricsSource
    let response: LyricResponse
}

enum LyricsMatching {
    static func normalized(_ text: String) -> String {
        let simplified = text.applyingTransform(StringTransform("Traditional-Simplified"), reverse: false) ?? text
        return simplified.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                                  locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isLetter || $0.isNumber }
    }

    static func artists(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet(charactersIn: "/、,，;&＆"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    /// Whether a catalog title names the track's song and recording: equal
    /// base titles (or one's annotation or the track's alias naming the other)
    /// and exactly the same version tags. Annotations such as translations or
    /// "电视剧《X》插曲" never decide identity; Live, 伴奏 or Remix always do.
    ///
    /// Lyric catalogs often drop "(Live)" from a live recording's title
    /// (Kugou lists "出现又离开 (Live)" as "出现又离开"). An untagged title
    /// may therefore name a Live track, but only with near-identical duration
    /// (`needsDuration`). The reverse, a Live title for a studio track, and
    /// any other missing tag (伴奏 has the original's exact length) still fail.
    static func titleMatch(_ title: String, track: Track) -> (exact: Bool, sameBase: Bool, needsDuration: Bool)? {
        let found = LyricsTitle(title), own = LyricsTitle(track.name)
        let untaggedLive = found.versions.isEmpty && own.versions == ["live"]
        guard !found.base.isEmpty, found.versions == own.versions || untaggedLive else { return nil }
        if found.base == own.base { return (normalized(title) == normalized(track.name), true, untaggedLive) }
        let ownNames = own.names(aliases: track.alias + track.transNames)
        return found.names().isDisjoint(with: ownNames) ? nil : (false, false, untaggedLive)
    }

    /// Provider artist keys, split only when the whole string is not already
    /// one of the track's artists (band names may contain '&' or '/').
    private static func artistKeys(_ artists: [String], expected: [Set<String>]) -> Set<String> {
        Set(artists.flatMap { artist -> [String] in
            let key = LyricsArtistName.key(artist)
            return expected.contains { $0.contains(key) } ? [key] : self.artists(in: artist).map(LyricsArtistName.key)
        }.filter { !$0.isEmpty })
    }

    static func artistMatches(_ artists: [String], track: Track) -> Bool {
        let expected = LyricsArtistAliases.shared.keys(for: track)
        guard let primary = expected.first else { return false }
        return !primary.isDisjoint(with: artistKeys(artists, expected: expected))
    }

    /// Identity is a gate, rather than a bonus that word timing could outweigh.
    ///
    /// The primary artist must match by name or catalog alias. One narrow
    /// exception covers instrumentals that catalogs credit under another name
    /// ("Yiruma" / "李闰珉"): the same base title and version and a duration
    /// within two seconds. Sung lyrics never take it, even on the same album:
    /// covers reuse titles, lengths and album names. `instrumental` is nil
    /// while a provider pre-filters hits whose lyrics are not yet known. The
    /// path scores well below any artist match.
    static func metadataScore(title: String, artists: [String], album: String?,
                              duration: TimeInterval?, track: Track, instrumental: Bool? = nil) -> Double? {
        guard let match = titleMatch(title, track: track) else { return nil }
        var score: Double = 40 + (match.exact ? 4 : match.sameBase ? 0 : -4)
        var delta: TimeInterval?
        if let duration, duration.isFinite, duration > 0, track.duration > 0 {
            let difference = abs(duration - track.duration)
            // Short songs need a tighter bound; twelve seconds is the ceiling.
            guard difference <= min(12, max(3, track.duration * 0.04)) else { return nil }
            delta = difference
            score += max(0, 18 - difference * 2)
        }
        if match.needsDuration {
            guard let delta, delta <= 2 else { return nil }
            score -= 6
        }
        let albumKey = album.map { LyricsTitle($0).base } ?? ""
        let expectedAlbum = LyricsTitle(track.album.name).base
        let sameAlbum = !albumKey.isEmpty && albumKey == expectedAlbum
        if !albumKey.isEmpty, !expectedAlbum.isEmpty {
            score += sameAlbum ? 12 : -6
        }
        let expected = LyricsArtistAliases.shared.keys(for: track)
        let found = artistKeys(artists, expected: expected)
        let matched = expected.map { !$0.isDisjoint(with: found) }
        if matched.first == true {
            let artistScore = 30 * Double(matched.filter { $0 }.count) / Double(expected.count)
            // Extra artists can indicate a different duet or cover recording.
            let extras = found.filter { key in !expected.contains { $0.contains(key) } }.count
            return score + artistScore - min(8, Double(extras) * 4)
        }
        guard match.sameBase, let delta, delta <= 2, instrumental != false else { return nil }
        return score - 15
    }

    /// Score real word coverage rather than trusting a provider's format label.
    static func qualityScore(_ response: LyricResponse, duration: TimeInterval, track: Track? = nil) -> Double? {
        let parsed = LyricsParser.parse(response, track: track)
        if parsed.isInstrumental { return 0 }
        // Credit lines are already removed by the parser.
        let lines = parsed.lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !lines.isEmpty else { return nil }
        var previous: TimeInterval = -1
        for line in lines {
            guard line.time.isFinite, line.time >= 0, line.time >= previous,
                  duration <= 0 || line.time <= duration + 10 else { return nil }
            previous = line.time
        }
        let timed = lines.filter { line in
            guard let words = line.words, words.count > 1 else { return false }
            var end = line.time
            for word in words {
                guard word.start.isFinite, word.duration.isFinite, word.duration > 0,
                      word.start >= end - 0.05, duration <= 0 || word.end <= duration + 10 else { return false }
                end = word.end
            }
            return normalized(words.map(\.text).joined()) == normalized(line.text)
        }.count
        let wordBonus = 24 * Double(timed) / Double(lines.count)
        let translated = lines.filter { $0.translation?.isEmpty == false }.count
        return wordBonus + 2 * Double(translated) / Double(lines.count)
    }

    static func isInstrumental(_ candidate: LyricsCandidate) -> Bool {
        candidate.response.pureMusic == true || LyricsParser.parse(candidate.response).isInstrumental
    }

    static func score(_ candidate: LyricsCandidate, for track: Track) -> Double? {
        guard candidate.source != .automatic,
              let quality = qualityScore(candidate.response, duration: track.duration, track: track) else { return nil }
        if candidate.matchedByID { return 100 + quality }
        guard let metadata = metadataScore(title: candidate.title, artists: candidate.artists, album: candidate.album,
                                           duration: candidate.duration, track: track,
                                           instrumental: isInstrumental(candidate)) else { return nil }
        return metadata + quality
    }

    /// Each platform reports instrumentals its own way; providers translate
    /// that into `pureMusic`. A catalog that knows the track by id has the
    /// final word. Otherwise matched candidates vote: instrumental only when
    /// none of them has real lyrics, since an instrumental flag on a
    /// mismatched recording (an accompaniment upload) is the likelier error.
    static func best(_ candidates: [LyricsCandidate], for track: Track) -> LyricsSelection? {
        let scored = candidates.compactMap { candidate -> (candidate: LyricsCandidate, score: Double, instrumental: Bool)? in
            guard let score = score(candidate, for: track) else { return nil }
            return (candidate, score, isInstrumental(candidate))
        }
        if let native = scored.first(where: { $0.candidate.matchedByID && $0.instrumental }) {
            return LyricsSelection(source: native.candidate.source, response: native.candidate.response)
        }
        let ranked = scored.sorted { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            let order = LyricsSource.providers
            let left = order.firstIndex(of: lhs.candidate.source) ?? order.count
            let right = order.firstIndex(of: rhs.candidate.source) ?? order.count
            if left != right { return left < right }
            return lhs.candidate.id < rhs.candidate.id
        }
        let chosen = ranked.first { !$0.instrumental } ?? ranked.first
        return chosen.map { LyricsSelection(source: $0.candidate.source, response: $0.candidate.response) }
    }
}

/// Only successful automatic matches are cached, by full track metadata. Manual
/// selection always makes a fresh request; errors never poison later retries.
actor LyricsSelectionCache {
    static let shared = LyricsSelectionCache()
    private var entries: [Track: (date: Date, selection: LyricsSelection)] = [:]

    func value(for track: Track) -> LyricsSelection? {
        guard let entry = entries[track], Date().timeIntervalSince(entry.date) < 900 else {
            entries[track] = nil
            return nil
        }
        return entry.selection
    }

    func store(_ selection: LyricsSelection, for track: Track) {
        if entries.count >= 40, let oldest = entries.min(by: { $0.value.date < $1.value.date })?.key {
            entries[oldest] = nil
        }
        entries[track] = (Date(), selection)
    }
}
