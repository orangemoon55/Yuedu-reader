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

    @Test func upstreamFongMiURLObjectHonorsPositionAndKeepsAlternatives() throws {
        let response = #"{"url":{"values":[{"n":"原画","v":"https://e.test/original"},{"n":"高清","v":"/proxy/hd.m3u8"},{"n":"标清","v":"https://e.test/sd"}],"position":1},"header":{"Referer":"https://e.test/"}}"#
        let result = try CatVodContentParser.playback(data(response))
        #expect(result.url == "/proxy/hd.m3u8")
        #expect(result.choices.map(\.name) == ["高清", "原画", "标清"])
        #expect(result.choices.map(\.address) == ["/proxy/hd.m3u8", "https://e.test/original", "https://e.test/sd"])
        #expect(result.choices.map(\.id) == [0, 1, 2])
        #expect(result.headers["Referer"] == "https://e.test/")
    }

    @Test func upstreamInvalidPositionUsesOriginalOrder() throws {
        for position in ["-1", "99", #""not-an-int""#, "1.25", "true", "null"] {
            let response = "{\"url\":{\"values\":[{\"n\":\"A\",\"v\":\"https://e.test/a\"},{\"n\":\"B\",\"v\":\"https://e.test/b\"}],\"position\":\(position)}}"
            let result = try CatVodContentParser.playback(data(response))
            #expect(result.choices.map(\.name) == ["A", "B"])
        }
        let response = #"{"url":{"values":[{"n":"A","v":"https://e.test/a"},{"n":"B","v":"https://e.test/b"}],"position":"1"}}"#
        #expect(try CatVodContentParser.playback(data(response)).choices.map(\.name) == ["B", "A"])
    }

    @Test func upstreamInvalidPreferredURLFallsBackWithoutLosingOrder() throws {
        let response = #"{"url":{"values":[{"n":"原画","v":"https://e.test/first"},{"n":"","v":"/proxy/second.m3u8"},{"n":"坏地址","v":"javascript:alert(1)"},{"n":"空","v":" "},null],"position":2}}"#
        let result = try CatVodContentParser.playback(data(response))
        #expect(result.url == "https://e.test/first")
        #expect(result.choices.map(\.name) == ["原画", "默认"])
        #expect(result.choices.map(\.id) == [1, 2])
        #expect(result.choices.last?.address == "/proxy/second.m3u8")
        #expect(throws: CatVodContentError.invalidPlaybackURL) {
            try CatVodContentParser.playback(data(#"{"url":{"values":[{"v":"ftp://e.test/a"},{"v":"//foreign.test/a"},{"v":true},{"v":""}]}}"#))
        }
        #expect(try CatVodContentParser.playback(data(#"{"url":{"values":[]},"play":"https://e.test/fallback"}"#)).url == "https://e.test/fallback")
    }

    @Test func upstreamAlternatingPairsKeepNamesIgnoreLabelsAndOddTail() throws {
        let result = try CatVodContentParser.playback(data(#"{"url":["https://label.test/not-media","ftp://e.test/no","高清","https://e.test/hd","标清","/proxy/sd","https://e.test/unpaired"]}"#))
        #expect(result.choices.map(\.name) == ["高清", "标清"])
        #expect(result.choices.map(\.address) == ["https://e.test/hd", "/proxy/sd"])
        #expect(result.choices.map(\.id) == [1, 2])
    }

    @Test func upstreamAdapterRetainsPrefixFallbackNameAndScalarContract() {
        let entries: [[String: Any]] = [["n": "", "v": "/a"], ["n": 1080, "v": "/b"], ["n": "Bool", "v": true]]
        let value: [String: Any] = ["values": entries, "position": "1"]
        let choices = YingxiaPlaybackChoice.parse(value, prefix: "https://e.test", fallbackName: "Episode")
        #expect(choices.map(\.name) == ["1080", "Episode"])
        #expect(choices.map(\.address) == ["https://e.test/b", "https://e.test/a"])
        #expect(YingxiaPlaybackChoice.parse(NSNull(), fallbackName: "Episode").isEmpty)
        #expect(YingxiaPlaybackChoice.parse(true, fallbackName: "Episode").isEmpty)
        #expect(YingxiaPlaybackChoice.parse("  ", fallbackName: "Episode").isEmpty)
    }

    @Test func legacyPlaybackConstructorAndDirectURLArrayRemainUsable() throws {
        let constructed = CatVodPlayback(url: "/proxy/a", headers: [:], requiresWebParsing: false)
        #expect(constructed.choices.first?.address == constructed.url)
        let result = try CatVodContentParser.playback(data(#"{"url":["https://e.test/a","/proxy/b"]}"#))
        #expect(result.choices.map(\.address) == ["https://e.test/a", "/proxy/b"])
    }

    @Test func playbackWrappersRetainHeadersFlagsAndStringifiedURLObject() throws {
        let inner = #"{"url":{"values":[{"n":"HD","v":"/proxy/hd"},{"n":"SD","v":"https://e.test/sd"}],"position":0},"headers":{"X-Level":"inner"},"jx":true}"#
        let response: [String: Any] = ["header": ["Referer": "https://e.test/", "X-Level": "outer"], "parse": 1, "data": ["result": inner]]
        let bytes = try JSONSerialization.data(withJSONObject: response)
        let result = try CatVodContentParser.playback(bytes)
        #expect(result.url == "/proxy/hd")
        #expect(result.choices.count == 2)
        #expect(result.headers == ["Referer": "https://e.test/", "X-Level": "inner"])
        #expect(result.requiresWebParsing)
        #expect(result.choices.allSatisfy { $0.headers == result.headers && $0.requiresWebParsing })
    }

    @Test func playbackBusinessErrorsCannotBecomeQualityFallbacks() {
        for response in [
            #"{"code":503,"message":"offline","data":{"url":"https://e.test/a"}}"#,
            #"{"data":{"result":{"success":false,"message":"offline","url":"https://e.test/a"}}}"#,
            #"{"url":{"values":[{"v":"https://e.test/a"},{"code":401,"message":"offline","v":"https://e.test/b"}],"position":0}}"#
        ] {
            #expect(throws: CatVodContentError.businessFailure("offline")) {
                try CatVodContentParser.playback(data(response))
            }
        }
    }

    @Test func playbackStringAndWrapperDepthsAreBounded() throws {
        let leaf = #"{"url":"https://e.test/a"}"#
        let doubleString: [String: Any] = ["result": try String(decoding: JSONSerialization.data(withJSONObject: ["data": leaf]), as: UTF8.self)]
        #expect(throws: CatVodContentError.invalidResponse("字符串化 JSON 超过一层")) {
            try CatVodContentParser.playback(JSONSerialization.data(withJSONObject: doubleString))
        }
        var nested: Any = ["url": "https://e.test/a"]
        for _ in 0..<8 { nested = ["result": nested] }
        let bytes = try JSONSerialization.data(withJSONObject: nested)
        #expect(throws: CatVodContentError.invalidResponse("播放 URL 嵌套超过允许层数")) {
            try CatVodContentParser.playback(bytes)
        }
    }

    @Test func nestedStringifiedDetailUsesOnlyKnownEnvelopes() throws {
        let leaf = #"{"list":[{"vod_id":"nested","vod_name":"Nested detail"}]}"#
        let bytes = try JSONSerialization.data(withJSONObject: ["result": ["detail": leaf]])
        #expect(try CatVodContentParser.detail(bytes).id == "nested")
        let unknown = try JSONSerialization.data(withJSONObject: ["unrelated": leaf])
        #expect(throws: CatVodContentError.invalidResponse("详情缺少影片字段")) {
            try CatVodContentParser.detail(unknown)
        }
        let dataEnvelopes = #"{"data":{"data":{"video":{"vod_id":"d","vod_name":"D"}}}}"#
        #expect(try CatVodContentParser.detail(data(dataEnvelopes)).id == "d")
    }

    @Test func nestedStringifiedDetailKeepsEmptyMalformedAndBusinessFailures() throws {
        for (leaf, expected) in [
            (#"{"list":[]}"#, CatVodContentError.invalidResponse("详情未找到影片")),
            (#"{"video":{"id":"only-id"}}"#, .invalidResponse("详情缺少影片字段")),
            (#"{"code":401,"message":"需要登录","video":{"vod_id":"x","vod_name":"Hidden"}}"#, .businessFailure("需要登录")),
            (#"{"list":[],"msg":"请配置 Cookie"}"#, .businessFailure("请配置 Cookie")),
            ("{bad-json}", .invalidJSON)
        ] {
            let bytes = try JSONSerialization.data(withJSONObject: ["result": ["detail": leaf]])
            #expect(throws: expected) { try CatVodContentParser.detail(bytes) }
        }
        let inner = #"{"detail":"{\"vod_id\":\"x\",\"vod_name\":\"Nested\"}"}"#
        let bytes = try JSONSerialization.data(withJSONObject: ["result": inner])
        #expect(throws: CatVodContentError.invalidResponse("字符串化 JSON 超过一层")) {
            try CatVodContentParser.detail(bytes)
        }
    }

    @Test func contextualIDOnlyDetailIsOptInAndMatchesRequestedIdentity() throws {
        // Synthetic contract fixture, NOT the missing raw response for the reported title.
        let bytes = data(#"{"result":{"video":{"vod_id":"42"}}}"#)
        #expect(throws: CatVodContentError.invalidResponse("详情缺少影片字段")) {
            try CatVodContentParser.detail(bytes)
        }
        let named = try CatVodContentParser.detail(bytes, fallbackID: "42", fallbackTitle: "Selected title")
        #expect(named.id == "42")
        #expect(named.title == "Selected title")
        let numeric = try CatVodContentParser.detail(data(#"{"list":[{"vod_id":42,"vod_name":" "}]}"#), fallbackID: "42")
        #expect(numeric.id == "42")
        #expect(numeric.title == "42") // Yingxia Video.init's name ?? id contract.
    }

    @Test func contextualMissingIDRequiresNamedMovieEvidence() throws {
        let video = try CatVodContentParser.detail(data(#"{"detail":{"vod_name":"Named movie","vod_content":"Synopsis"}}"#), fallbackID: "requested")
        #expect(video.id == "requested")
        #expect(video.title == "Named movie")
        let route = try CatVodContentParser.detail(data(#"{"list":[{"title":"Cloud movie","play_url":"Play$quark://share/id"}]}"#), fallbackID: "cloud")
        #expect(route.id == "cloud")
        #expect(route.routes.first?.episodes.first?.playID == "quark://share/id")
    }

    @Test func contextualDetailDoesNotInventFilmsFromErrorsOrArbitraryObjects() {
        for response in [
            #"{}"#,
            #"{"video":{"id":"42"}}"#,
            #"{"unrelated":{"vod_id":"42"}}"#,
            #"{"vod_id":"other"}"#,
            #"{"vod_id":true}"#,
            #"{"vod_id":"42","vod_name":{}}"#,
            #"{"vod_id":"42","message":"需要登录"}"#,
            #"{"vod_id":"42","action":"LoginShow"}"#,
            #"{"detail":{"vod_name":"Only a name"}}"#,
            #"{"detail":{"title":"An article","summary":"Not a movie"}}"#,
            #"{"detail":{"vod_id":{},"vod_name":"Bad identity","vod_content":"Synopsis"}}"#
        ] {
            #expect(throws: CatVodContentError.invalidResponse("详情缺少影片字段")) {
                try CatVodContentParser.detail(data(response), fallbackID: "42", fallbackTitle: "Selected title")
            }
        }
        #expect(throws: CatVodContentError.invalidResponse("详情未找到影片")) {
            try CatVodContentParser.detail(data(#"{"vod_id":"42","list":[]}"#), fallbackID: "42")
        }
        #expect(throws: CatVodContentError.invalidResponse("详情请求缺少影片标识")) {
            try CatVodContentParser.detail(data(#"{"vod_id":"42"}"#), fallbackID: " ")
        }
        #expect(throws: CatVodContentError.businessFailure("需要登录")) {
            try CatVodContentParser.detail(data(#"{"result":{"code":401,"message":"需要登录","vod_id":"42"}}"#), fallbackID: "42")
        }
    }

    @Test func IDOnlyListEntriesRemainFilteredDespiteDetailContextContract() throws {
        let response = data(#"{"pagecount":3,"list":[{"vod_id":"42"},{"id":"alias"},{"vod_id":"valid","vod_name":"Named"}]}"#)
        #expect(try CatVodContentParser.home(response).videos.map(\.id) == ["valid"])
        #expect(try CatVodContentParser.page(response, requestedPage: 1).videos.map(\.id) == ["valid"])
        let idOnly = data(#"{"pagecount":3,"list":[{"vod_id":"42"}]}"#)
        #expect(try CatVodContentParser.page(idOnly, requestedPage: 1).videos.isEmpty)
        #expect(try !CatVodContentParser.page(idOnly, requestedPage: 1).hasMore)
    }

    @Test func outerErrorNotHiddenByData() {
        #expect(throws: CatVodContentError.self) { try CatVodContentParser.home(data(CatVodFixtures.hiddenOuterError)) }
    }
}
