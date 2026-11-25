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
    @Test func detailAcceptsAliasesAndBoundedKnownEnvelopes() throws {
        #expect(try CatVodContentParser.detail(data(#"{"videos":[{"id":"videos-id","title":"Videos title"}]}"#)).id == "videos-id")
        #expect(try CatVodContentParser.detail(data(#"{"data":{"code":0,"list":[{"id":"data-id","title":"Data title"}]}}"#)).title == "Data title")
        #expect(try CatVodContentParser.detail(data(#"{"result":{"detail":{"vod_id":"result-id","vod_name":"Result title"}}}"#)).id == "result-id")
        #expect(try CatVodContentParser.detail(data(#"[{"vod_id":"array-id","vod_name":"Array title"}]"#)).title == "Array title")
    }

    @Test func detailAliasRoutesPreserveEncodedCloudIDsAndFlags() throws {
        let json = #"{"id":"pan-video","title":"两京十五日","play_from":"quark$$$uc","play_url":"第1集$quark://pan.example/s/A%2FB?pwd=x%23y%24z$tail#第2集$quark://pan.example/s/C%2FD?token=a%23b%24c$$$4K$https://media.example.invalid/4k.m3u8"}"#
        let video = try CatVodContentParser.detail(data(json))
        #expect(video.id == "pan-video")
        #expect(video.title == "两京十五日")
        #expect(video.routes.map(\.flag) == ["quark", "uc"])
        #expect(video.routes[0].episodes.map(\.playID) == [
            "quark://pan.example/s/A%2FB?pwd=x%23y%24z$tail",
            "quark://pan.example/s/C%2FD?token=a%23b%24c"
        ])
        #expect(video.routes[1].episodes.first?.playID == "https://media.example.invalid/4k.m3u8")
    }

    @Test func actualPanAdapterCloudDetailMayOmitMovieID() throws {
        // This is the adapter's observed m0({name, ...Vi(links)}) shape: title plus
        // encoded share IDs and routes, without vod_id/id.
        let response = #"{"list":[{"vod_name":"两京十五日","vod_pic":"https://poster.invalid/a.jpg","vod_play_from":"百度网盘$$$夸克网盘","vod_play_url":"全集$baidu://pan/1?pwd=a%23b%24c$$$4K$https://media.invalid/2160p.m3u8"}]}"#
        let video = try CatVodContentParser.detail(data(response))
        #expect(video.title == "两京十五日")
        #expect(video.id == "route:两京十五日")
        #expect(video.routes.count == 2)
        #expect(video.routes[0].episodes.first?.playID == "baidu://pan/1?pwd=a%23b%24c")
        #expect(video.routes[1].flag == "夸克网盘")
    }

    @Test func panAdapterNoShareAndLoginErrorsRemainActionable() {
        #expect(throws: CatVodContentError.businessFailure("请先配置百度网盘 Cookie")) {
            try CatVodContentParser.detail(data(#"{"list":[],"msg":"请先配置百度网盘 Cookie"}"#))
        }
        #expect(throws: CatVodContentError.businessFailure("未解析到可播放网盘资源")) {
            try CatVodContentParser.detail(data(#"{"data":{"list":[],"msg":"未解析到可播放网盘资源"}}"#))
        }
        #expect(throws: CatVodContentError.invalidResponse("详情未找到影片")) {
            try CatVodContentParser.detail(data(#"{"list":[]}"#))
        }
    }

    @Test func detailEmptyMalformedAndBusinessErrorsStayDistinct() {
        do {
            _ = try CatVodContentParser.detail(data(#"{"list":[]}"#))
            Issue.record("An explicit empty detail list was accepted")
        } catch let error as CatVodContentError {
            #expect(error == .invalidResponse("详情未找到影片"))
        } catch {
            Issue.record("Unexpected empty-detail error: \(error)")
        }
        for malformed in [#"{"video":{"id":"only-id"}}"#, #"{"unrelated":{"id":"x","title":"not a detail"}}"#] {
            do {
                _ = try CatVodContentParser.detail(data(malformed))
                Issue.record("A malformed or unrecognized object was accepted")
            } catch let error as CatVodContentError {
                #expect(error == .invalidResponse("详情缺少影片字段"))
            } catch {
                Issue.record("Unexpected malformed-detail error: \(error)")
            }
        }
        let tooDeep = #"{"result":{"result":{"result":{"result":{"result":{"vod_id":"deep","vod_name":"Deep"}}}}}}"#
        do {
            _ = try CatVodContentParser.detail(data(tooDeep))
            Issue.record("An over-deep detail envelope was accepted")
        } catch let error as CatVodContentError {
            #expect(error == .invalidResponse("详情包裹超过允许层数"))
        } catch {
            Issue.record("Unexpected over-deep error: \(error)")
        }
        for (json, message) in [
            (#"{"code":503,"message":"service unavailable","data":{"video":{"id":"x","title":"Hidden"}}}"#, "service unavailable"),
            (#"{"data":{"result":{"code":401,"message":"需要登录","video":{"id":"x","title":"Hidden"}}}}"#, "需要登录"),
            (#"{"data":{"result":{"success":false,"message":"需要登录","video":{"id":"x","title":"Hidden"}}}}"#, "需要登录")
        ] {
            do {
                _ = try CatVodContentParser.detail(data(json))
                Issue.record("A business/auth error was hidden by a detail envelope")
            } catch let error as CatVodContentError {
                #expect(error == .businessFailure(message))
            } catch {
                Issue.record("Unexpected business-error type: \(error)")
            }
        }
    }

    @Test func outerErrorNotHiddenByData() {
        #expect(throws: CatVodContentError.self) { try CatVodContentParser.home(data(CatVodFixtures.hiddenOuterError)) }
    }
}
