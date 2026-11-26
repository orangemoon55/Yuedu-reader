import Foundation
import Testing
@testable import yuedu_app

struct TMDBClientTests {
    private func page(_ json: String, kind: MovieMetadataKind, find: Bool = false) -> [TMDBRecord] {
        TMDBMatching.page(from: Data(json.utf8), kind: kind, findResponse: find)?.records ?? []
    }

    @Test func v3KeyIsScopedToOfficialHTTPSQuery() throws {
        let request = try #require(TMDBRequestBuilder.request(
            path: "/search/movie", query: [URLQueryItem(name: "query", value: "A title")],
            credential: "fake-v3-key-not-real"
        ))
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == "api.themoviedb.org")
        #expect(request.url?.path == "/3/search/movie")
        let requestURL = try #require(request.url)
        let items = try #require(URLComponents(url: requestURL, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(items.first(where: { $0.name == "api_key" })?.value == "fake-v3-key-not-real")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func v4ReadTokenUsesBearerHeaderNotQuery() throws {
        let request = try #require(TMDBRequestBuilder.request(
            path: "/find/tt1234567", query: [URLQueryItem(name: "external_source", value: "imdb_id")],
            credential: "header.payload.signature"
        ))
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer header.payload.signature")
        let items = URLComponents(url: try #require(request.url), resolvingAgainstBaseURL: false)?.queryItems ?? []
        #expect(!items.contains(where: { $0.name == "api_key" }))
        #expect(items.first(where: { $0.name == "external_source" })?.value == "imdb_id")
    }

    @Test func requestBuilderRejectsPathsOutsideFixedAPI() {
        #expect(TMDBRequestBuilder.request(path: "https://attacker.invalid/", query: [], credential: "fake") == nil)
        #expect(TMDBRequestBuilder.request(path: "/../3/movie/1", query: [], credential: "fake") == nil)
    }

    @Test func exactLocalizedOrOriginalTitleAndYearMatch() {
        let records = page(#"{"total_pages":1,"results":[{"id":11,"adult":false,"title":"Arrival","original_title":"降臨","release_date":"2016-11-11","vote_average":7.6,"vote_count":9000},{"id":12,"adult":false,"title":"Arrival","original_title":"Arrival","release_date":"1996-01-01","vote_average":6.2,"vote_count":800}]}"#, kind: .movie)
        #expect(TMDBMatching.match(records: records, title: "降臨", sourceYear: 2016, kind: .movie)?.id == 11)
        #expect(TMDBMatching.match(records: records, title: "Arrival", sourceYear: 2016, kind: .movie)?.id == 11)
        #expect(TMDBMatching.match(records: records, title: "arrival", sourceYear: 2020, kind: .movie) == nil)
    }

    @Test func noYearRefusesDuplicateTitlesAndKnownYearMustBeExact() {
        let records = page(#"{"total_pages":1,"results":[{"id":1,"adult":false,"title":"Dune","original_title":"Dune","release_date":"1984-01-01","vote_average":6.3,"vote_count":100},{"id":2,"adult":false,"title":"Dune","original_title":"Dune","release_date":"2021-01-01","vote_average":8.0,"vote_count":1000}]}"#, kind: .movie)
        #expect(TMDBMatching.match(records: records, title: "Dune", sourceYear: nil, kind: .movie) == nil)
        #expect(TMDBMatching.match(records: records, title: "Dune", sourceYear: 2021, kind: .movie)?.id == 2)
        #expect(TMDBMatching.match(records: records, title: "Dune", sourceYear: 2022, kind: .movie) == nil)
    }

    @Test func unknownKindRefusesMovieAndTVTitleCollision() {
        let records = page(#"{"movie_results":[{"id":31,"adult":false,"title":"The Office","original_title":"The Office","release_date":"2005-01-01","vote_average":8.5,"vote_count":5000}],"tv_results":[{"id":32,"adult":false,"name":"The Office","original_name":"The Office","first_air_date":"2005-03-24","vote_average":9.0,"vote_count":6000}]}"#, kind: .movie, find: true)
        #expect(records.count == 2)
        #expect(TMDBMatching.match(records: records, title: "The Office", sourceYear: 2005, kind: nil) == nil)
        #expect(TMDBMatching.match(records: records, title: "The Office", sourceYear: 2005, kind: .tv)?.id == 32)
    }

    @Test func imdbFindRequiresExactTitleAndSourceYear() {
        let records = page(#"{"movie_results":[{"id":41,"adult":false,"title":"Example","original_title":"Example","release_date":"2020-01-01","vote_average":7.2,"vote_count":200}],"tv_results":[]}"#, kind: .movie, find: true)
        #expect(TMDBMatching.match(records: records, title: "Example", sourceYear: 2020, kind: nil)?.id == 41)
        #expect(TMDBMatching.match(records: records, title: "Other", sourceYear: 2020, kind: nil) == nil)
        #expect(TMDBMatching.match(records: records, title: "Example", sourceYear: 2019, kind: nil) == nil)
    }

    @Test func adultFilteredButUnratedIdentitiesRemainAmbiguous() {
        let records = page(#"{"total_pages":1,"results":[{"id":1,"adult":true,"title":"Safe","original_title":"Safe","release_date":"2020-01-01","vote_average":9,"vote_count":10},{"id":2,"adult":false,"title":"Safe","original_title":"Safe","release_date":"2020-01-01","vote_average":0,"vote_count":10},{"id":3,"adult":false,"title":"Safe","original_title":"Safe","release_date":"2020-01-01","vote_average":10.1,"vote_count":10},{"id":4,"adult":false,"title":"Safe","original_title":"Safe","release_date":"2020-01-01","vote_average":8.5,"vote_count":0},{"id":5,"adult":false,"title":"Safe","original_title":"Safe","release_date":"2020-01-01","vote_average":8.5,"vote_count":20}]}"#, kind: .movie)
        #expect(records.map(\.id) == [2, 3, 4, 5])
        #expect(records.filter(\.hasValidRating).map(\.id) == [5])
        #expect(TMDBMatching.match(records: records, title: "Safe", sourceYear: 2020, kind: .movie) == nil)
        #expect(records.allSatisfy { $0.voteAverage.isFinite })
    }

    @Test func booleanAverageAndOverflowIDNeverBecomeRatings() {
        let records = page(#"{"total_pages":1,"results":[{"id":1,"adult":false,"title":"Bool","vote_average":true,"vote_count":100},{"id":1e100,"adult":false,"title":"Overflow","vote_average":8,"vote_count":100}]}"#, kind: .movie)
        #expect(records.count == 1)
        #expect(records.first?.hasValidRating == false)
        #expect(TMDBMatching.sourceYear("2024更新") == nil)
        #expect(TMDBMatching.sourceYear("2024.6") == nil)
    }
    @Test func detailRequiresPositiveIDAndValidFiniteRating() {
        let good = Data(#"{"id":81,"adult":false,"title":"Film","original_title":"Film","release_date":"2022-01-01","vote_average":7.25,"vote_count":88}"#.utf8)
        #expect(TMDBMatching.detail(from: good, kind: .movie)?.id == 81)
        let bad = Data(#"{"id":81,"adult":false,"title":"Film","original_title":"Film","release_date":"2022-01-01","vote_average":null,"vote_count":88}"#.utf8)
        #expect(TMDBMatching.detail(from: bad, kind: .movie) == nil)
        #expect(TMDBMatching.sourceYear("2022-05-01") == 2022)
    }
}
