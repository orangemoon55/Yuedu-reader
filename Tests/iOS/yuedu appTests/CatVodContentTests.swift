import Foundation
import Testing
@testable import yuedu_app

struct CatVodContentTests {
    private func data(_ text: String) -> Data { Data(text.utf8) }

    @Test func categoriesAndFilters() throws {
        let home = try CatVodContentParser.home(data(CatVodFixtures.categories))
        #expect(home.categories == [CatVodCategory(id: "1", name: "电影")])
        #expect(home.filters["1"]?.first?.id == "year")
        #expect(home.filters["1"]?.first?.initial == "2024")
        #expect(home.filters["1"]?.first?.options.first == CatVodFilterOption(name: "全部", value: ""))
    }
    @Test func stringifiedJSON() throws {
        let encoded = try JSONSerialization.data(withJSONObject: CatVodFixtures.stringified, options: [.fragmentsAllowed])
        #expect(try CatVodContentParser.page(encoded, requestedPage: 1).videos.first?.title == "片名")
    }
    @Test func wrappedStringifiedJSON() throws {
        #expect(try CatVodContentParser.home(data(CatVodFixtures.wrappedStringified)).videos.isEmpty)
    }
    @Test func successfulEmpty() throws {
        let page = try CatVodContentParser.page(data(CatVodFixtures.empty), requestedPage: 1)
        #expect(page.videos.isEmpty)
        #expect(!page.hasMore)
    }
    @Test func explicitError() {
        #expect(throws: CatVodContentError.self) { try CatVodContentParser.home(data(CatVodFixtures.explicitError)) }
    }
    @Test func nonzeroBusinessCode() {
        #expect(throws: CatVodContentError.self) { try CatVodContentParser.page(data(CatVodFixtures.nonzeroCode), requestedPage: 1) }
    }
    @Test func invalidJSON() {
        #expect(throws: CatVodContentError.self) { try CatVodContentParser.home(data(CatVodFixtures.invalidJSON)) }
    }
    @Test func groupedEpisodesPreserveDollarAndComma() throws {
        let video = try CatVodContentParser.detail(data(CatVodFixtures.groupedEpisodes))
        #expect(video.routes.count == 2)
        #expect(video.routes[0].episodes.count == 2)
        #expect(video.routes[0].episodes[0].playID == "https://e.test/a$x,y")
        #expect(video.routes[1].flag == "b")
    }
    @Test func dictionaryHeaders() throws {
        #expect(try CatVodContentParser.playback(data(CatVodFixtures.dictionaryHeaders)).headers["Referer"] == "https://e.test/")
    }
    @Test func stringHeaders() throws {
        #expect(try CatVodContentParser.playback(data(CatVodFixtures.stringHeaders)).headers["User-Agent"] == "Readcc")
    }
    @Test func parseOneRemainsWebParsing() throws {
        #expect(try CatVodContentParser.playback(data(CatVodFixtures.parseOne)).requiresWebParsing)
    }
    @Test func booleanJX() throws {
        #expect(try CatVodContentParser.playback(data(CatVodFixtures.booleanJX)).requiresWebParsing)
    }
    @Test func alternatingQualityURLs() throws {
        let result = try CatVodContentParser.playback(data(CatVodFixtures.qualityURLs))
        #expect(result.url == "https://e.test/hd")
        #expect(result.headers["X-Test"] == "yes")
    }
    @Test func missingURLThrows() {
        #expect(throws: CatVodContentError.self) { try CatVodContentParser.playback(data(CatVodFixtures.missingURL)) }
    }
    @Test func relativeURLPreservesPathUntilSourceResolution() throws {
        #expect(try CatVodContentParser.playback(data(CatVodFixtures.relativeURL)).url == "/proxy/video.m3u8")
    }
    @Test func pageTwo() throws {
        let result = try CatVodContentParser.page(data(CatVodFixtures.pageTwo), requestedPage: 1)
        #expect(result.page == 2)
        #expect(result.pageCount == 3)
        #expect(result.videos.count == 1)
        #expect(result.hasMore)
    }
    @Test func unknownPaginationStops() throws {
        let result = try CatVodContentParser.page(data(CatVodFixtures.unknownPagination), requestedPage: 2)
        #expect(result.videos.count == 1)
        #expect(!result.hasMore)
    }
    @Test func totalAndLimitPagination() throws {
        let result = try CatVodContentParser.page(data(CatVodFixtures.totalHasMore), requestedPage: 2)
        #expect(result.videos.count == 1)
        #expect(result.hasMore)
        #expect(try !CatVodContentParser.page(data(CatVodFixtures.totalHasMore), requestedPage: 3).hasMore)
    }
    @Test func nextPageNumber() throws {
        let result = try CatVodContentParser.page(data(CatVodFixtures.nextNumber), requestedPage: 2)
        #expect(result.videos.count == 1)
        #expect(result.hasMore)
    }
    @Test func malformedOnlyPageStopsDespiteAdvertisedNext() throws {
        let result = try CatVodContentParser.page(data(#"{"page":2,"pagecount":3,"list":[{"vod_id":2}]}"#), requestedPage: 2)
        #expect(result.videos.isEmpty)
        #expect(!result.hasMore)
    }
    @Test func outerErrorNotHiddenByData() {
        #expect(throws: CatVodContentError.self) { try CatVodContentParser.home(data(CatVodFixtures.hiddenOuterError)) }
    }
}
