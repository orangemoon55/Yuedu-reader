import CoreFoundation
import Foundation

/// A score keeps its provider and provenance; generic site scores never become TMDB/IMDb scores.
enum MovieRatingProvider: String, Sendable, Hashable {
    case source, douban, imdb, tmdb
    var titleKey: String {
        switch self {
        case .source: return "片源評分"
        case .douban: return "豆瓣"
        case .imdb: return "IMDb"
        case .tmdb: return "TMDB"
        }
    }
}
enum MovieRatingOrigin: String, Sendable, Hashable { case source, tmdbAPI }
struct MovieRating: Sendable, Hashable {
    let provider: MovieRatingProvider
    let value: Double
    let voteCount: Int?
    var origin: MovieRatingOrigin = .source
    var sourceField: String = ""
    var valueText: String { String(format: "%.1f", locale: Locale(identifier: "en_US_POSIX"), value) }
}
enum MovieMetadataKind: String, Sendable, Hashable { case movie, tv }
struct MovieMetadataIdentity: Sendable, Hashable {
    var tmdbID: Int? = nil
    var imdbID: String? = nil
    var kind: MovieMetadataKind? = nil
    var year: Int? = nil
}

/// Public CatVod/MacCMS aliases. Missing, boolean, non-finite and out-of-scale values are absent,
/// not zero, and an invalid earlier alias cannot hide a later valid value.
enum MovieRatingParser {
    static let fieldGroups: [(MovieRatingProvider, [String], [String])] = [
        (.douban, ["vod_douban_score", "douban_score", "douban_rating"], ["vod_douban_votes", "douban_votes", "douban_vote_count"]),
        (.imdb, ["imdb_rating", "imdb_score", "vod_imdb_score"], ["imdb_votes", "imdb_vote_count"]),
        (.tmdb, ["tmdb_vote_average", "tmdb_rating", "tmdb_score"], ["tmdb_vote_count", "tmdb_votes"]),
        (.source, ["vod_score", "vod_scroe", "rating", "score"], ["vod_score_num", "rating_count", "score_count"])
    ]

    static func ratings(in item: [String: Any]) -> [MovieRating] {
        var values: [MovieRating] = []
        for (provider, fields, countFields) in fieldGroups {
            guard let pair = fields.compactMap({ key in score(item[key]).map { (key, $0) } }).first else { continue }
            let count = countFields.compactMap { Self.count(item[$0]) }.first
            guard count != 0 else { continue }
            values.append(MovieRating(provider: provider, value: pair.1, voteCount: count, sourceField: pair.0))
        }
        if let value = score(item["vote_average"]) {
            let provider: MovieRatingProvider = identity(in: item).tmdbID == nil ? .source : .tmdb
            let votes = count(item["vote_count"])
            if votes != 0, !values.contains(where: { $0.provider == provider }) {
                values.append(MovieRating(provider: provider, value: value, voteCount: votes, sourceField: "vote_average"))
            }
        }
        return values
    }

    static func identity(in item: [String: Any]) -> MovieMetadataIdentity {
        let id = ["tmdb_id", "vod_tmdb_id", "tmdbId"].compactMap { positiveID(item[$0]) }.first
        let imdb = ["imdb_id", "vod_imdb_id"].compactMap { key -> String? in
            guard let text = item[key] as? String else { return nil }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.range(of: #"^tt[0-9]{7,10}$"#, options: .regularExpression) == nil ? nil : trimmed
        }.first
        let kind = ["tmdb_media_type", "tmdb_type", "media_type"].compactMap { key -> MovieMetadataKind? in
            guard let raw = item[key] as? String else { return nil }
            return MovieMetadataKind(rawValue: raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }.first
        let text = yearText(in: item)
        let year: Int?
        if text.range(of: #"^[0-9]{4}(?:-[0-9]{2}(?:-[0-9]{2})?)?$"#, options: .regularExpression) != nil,
           let value = Int(text.prefix(4)), (1800...2100).contains(value) { year = value }
        else { year = nil }
        return MovieMetadataIdentity(tmdbID: id, imdbID: imdb, kind: kind, year: year)
    }

    /// One precedence for both display and matching. Never round malformed numeric years.
    static func yearText(in item: [String: Any]) -> String {
        for key in ["year", "vod_year"] {
            if let raw = item[key] as? String {
                let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { return text }
            } else if let value = number(item[key]), value.isFinite,
                      value.rounded() == value, (1800...2100).contains(value) {
                return String(Int(value))
            }
        }
        return ""
    }

    static func score(_ raw: Any?) -> Double? {
        let value: Double?
        if let text = raw as? String {
            var normalized = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if normalized.hasSuffix("/10") { normalized = String(normalized.dropLast(3)).trimmingCharacters(in: .whitespaces) }
            if normalized.hasSuffix("分") { normalized = String(normalized.dropLast()).trimmingCharacters(in: .whitespaces) }
            value = Double(normalized)
        } else { value = number(raw) }
        guard let value, value.isFinite, value > 0, value <= 10 else { return nil }
        return value
    }

    private static func number(_ raw: Any?) -> Double? {
        guard let value = raw as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() else { return nil }
        return value.doubleValue
    }
    private static func count(_ raw: Any?) -> Int? {
        let value = (raw as? String).flatMap(Double.init) ?? number(raw)
        guard let value, value.isFinite, value >= 0, value <= Double(Int32.max), value.rounded() == value else { return nil }
        return Int(value)
    }
    private static func positiveID(_ raw: Any?) -> Int? {
        guard let result = count(raw), result > 0 else { return nil }
        return result
    }

    static func merging(_ source: [MovieRating], tmdb: MovieRating?) -> [MovieRating] {
        guard let tmdb, tmdb.provider == .tmdb, tmdb.origin == .tmdbAPI,
              tmdb.value.isFinite, tmdb.value > 0, tmdb.value <= 10, (tmdb.voteCount ?? 0) > 0 else { return source }
        return source.filter { $0.provider != .tmdb } + [tmdb]
    }
}
