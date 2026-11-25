import Foundation
import Testing
@testable import yuedu_app

struct MovieRatingTests {
    @Test func aliasesKeepProviderAndVotes() {
        let result = MovieRatingParser.ratings(in: ["vod_douban_score": "8.6", "douban_votes": 123,
            "vod_score": "7.2", "vod_score_num": "31", "imdb_rating": 8.1, "tmdb_score": "7.5"])
        #expect(result.map(\.provider) == [.douban, .imdb, .tmdb, .source])
        #expect(result[0].value == 8.6)
        #expect(result[0].voteCount == 123)
        #expect(result[0].sourceField == "vod_douban_score")
        #expect(result.allSatisfy { $0.origin == .source })
    }
    @Test func malformedAndUnratedScoresAreAbsent() {
        let invalid: [Any] = [NSNull(), true, false, "暂无评分", "NaN", "Infinity", "-1", "0", 11, "90%", "8.1/5"]
        for value in invalid {
            #expect(MovieRatingParser.score(value) == nil)
        }
        #expect(MovieRatingParser.score(" 8.5分 ") == 8.5)
        #expect(MovieRatingParser.score(" 7.4 /10 ") == 7.4)
        #expect(MovieRatingParser.ratings(in: ["tmdb_score": 8.5, "tmdb_votes": 0]).isEmpty)
    }
    @Test func invalidEarlierAliasDoesNotHideValidAlias() {
        let ratings = MovieRatingParser.ratings(in: ["vod_douban_score": NSNull(), "douban_rating": 8.2])
        #expect(ratings.first?.value == 8.2)
        #expect(ratings.first?.sourceField == "douban_rating")
    }
    @Test func genericVoteAverageNeedsTMDBIdentityForAttribution() {
        #expect(MovieRatingParser.ratings(in: ["vote_average": 8.0]).first?.provider == .source)
        #expect(MovieRatingParser.ratings(in: ["vote_average": 8.0, "tmdb_id": 123]).first?.provider == .tmdb)
        #expect(MovieRatingParser.ratings(in: ["vote_average": 8.0, "tmdb_id": true]).first?.provider == .source)
    }
    @Test func identityOnlyAcceptsNamespacedIDs() {
        let parsed = MovieRatingParser.identity(in: ["tmdb_id": "123", "imdb_id": "tt1234567", "media_type": "tv", "vod_year": "2024"])
        #expect(parsed == MovieMetadataIdentity(tmdbID: 123, imdbID: "tt1234567", kind: .tv, year: 2024))
        #expect(MovieRatingParser.identity(in: ["id": 123, "type_id": "电影"]).tmdbID == nil)
        #expect(MovieRatingParser.identity(in: ["tmdb_id": -3, "imdb_id": "https://e.test", "year": "2024更新"]) == MovieMetadataIdentity())
    }
    @Test func homePageAndDetailKeepRatingsWithoutTouchingPlayback() throws {
        let item: [String: Any] = ["vod_id": "a", "vod_name": "fixture", "vod_douban_score": "8.3", "tmdb_id": 44,
                                 "vod_play_from": "original", "vod_play_url": "ep$https://fixture.invalid/media?a=1"]
        let payload = try JSONSerialization.data(withJSONObject: ["list": [item]])
        let home = try CatVodContentParser.home(payload).videos[0]
        let page = try CatVodContentParser.page(payload, requestedPage: 1).videos[0]
        let detail = try CatVodContentParser.detail(payload)
        #expect(home.ratings == detail.ratings)
        #expect(page.metadataIdentity == detail.metadataIdentity)
        #expect(detail.routes.first?.episodes.first?.playID == "https://fixture.invalid/media?a=1")
        #expect(home.routes.isEmpty)
    }
    @Test func voteCountsNeverCrossProviderBoundaries() {
        let ratings = MovieRatingParser.ratings(in: ["tmdb_score": 8.2, "vote_average": 6.0, "vote_count": 0])
        #expect(ratings.count == 1)
        #expect(ratings.first?.provider == .tmdb)
        #expect(ratings.first?.voteCount == nil)
        let counted = MovieRatingParser.ratings(in: ["tmdb_score": 8.2, "vote_average": 6.0, "vote_count": 42])
        #expect(counted.first(where: { $0.provider == .tmdb })?.voteCount == nil)
        #expect(counted.first(where: { $0.provider == .source })?.voteCount == 42)
    }
    @Test func yearDisplayAndIdentityHaveOneStrictPrecedence() throws {
        let item: [String: Any] = ["vod_id": "y", "vod_name": "Year", "year": "2024", "vod_year": "1999"]
        let payload = try JSONSerialization.data(withJSONObject: ["list": [item]])
        let video = try CatVodContentParser.detail(payload)
        #expect(video.year == "2024")
        #expect(video.metadataIdentity.year == 2024)
        #expect(MovieRatingParser.identity(in: ["vod_year": 2024.6]).year == nil)
        #expect(MovieRatingParser.identity(in: ["vod_year": 2024.6, "year": "2024"]).year == 2024)
    }
    @Test func enrichmentOnlyReplacesTMDBScore() {
        let source = MovieRating(provider: .source, value: 7.2, voteCount: nil)
        let douban = MovieRating(provider: .douban, value: 8.6, voteCount: 5)
        let old = MovieRating(provider: .tmdb, value: 7.4, voteCount: nil)
        let fresh = MovieRating(provider: .tmdb, value: 8.0, voteCount: 300, origin: .tmdbAPI)
        #expect(MovieRatingParser.merging([source, douban, old], tmdb: fresh) == [source, douban, fresh])
        #expect(MovieRatingParser.merging([source], tmdb: nil) == [source])
        #expect(MovieRatingParser.merging([source], tmdb: MovieRating(provider: .tmdb, value: 8, voteCount: 0, origin: .tmdbAPI)) == [source])
    }
}
