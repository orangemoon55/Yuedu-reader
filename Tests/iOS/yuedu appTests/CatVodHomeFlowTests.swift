import Foundation
import Testing
@testable import yuedu_app

@MainActor
@Suite("CatVod home source", .serialized)
struct CatVodHomeFlowTests {
    private let feed = CatVodFeedRef(sourceID: "synthetic-bundle-a", siteKey: "fixture", siteName: "示例站", categoryID: "comedy", categoryName: "喜剧")
    @Test func editorSaveReopenReplaceHideAndRemove() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("explore_home.json")
        let store = HomePageStore(fileURL: file)
        let original = HomeSection(layout: .row, title: "已有栏目", binding: .bookshelf)
        store.save(HomePage(sections: [original]))
        let model = HomeModel(providers: { [CatVodHomeProvider()] }, waitForSources: {})
        let editor = HomeSectionEditor(newSectionIn: store, layout: .row, preview: model)
        editor.choose(.catVod(feed), itemTitle: feed.title); #expect(editor.add())
        store.waitForPendingWritesForTesting()
        let reopened = HomePageStore(fileURL: file)
        let section = try #require(reopened.page?.sections.last)
        #expect(reopened.page?.sections.first == original)
        #expect(section.binding == .catVod(feed))
        #expect(section.editorTitle() == "示例站 · 喜剧")
        let encoded = try String(decoding: JSONEncoder().encode(section.binding), as: UTF8.self)
        #expect(!encoded.contains("http")); #expect(!encoded.lowercased().contains("cookie")); #expect(!encoded.contains("port"))
        let replacement = CatVodFeedRef(sourceID: feed.sourceID, siteKey: "other", siteName: "站二", categoryID: nil, categoryName: nil)
        let edit = HomeSectionEditor(section: section, store: reopened, preview: model)
        edit.choose(.catVod(replacement)); edit.setTitle("我的影视"); edit.setEnabled(false)
        reopened.waitForPendingWritesForTesting()
        let again = HomePageStore(fileURL: file)
        #expect(again.page?.sections.last?.binding == .catVod(replacement))
        #expect(again.page?.sections.last?.title == "我的影视"); #expect(again.page?.sections.last?.isEnabled == false)
        again.edit { $0.removeSection(section.id) }; again.waitForPendingWritesForTesting()
        #expect(HomePageStore(fileURL: file).page?.sections == [original])
    }
    @Test func actualCardOpensMovieNotBookAndHeaderReopensBoundSite() throws {
        let data = Data(#"{"list":[{"vod_id":"7","vod_name":"测试片","vod_pic":"https://fixture.invalid/poster.png"}]}"#.utf8)
        let page = try CatVodContentParser.page(data, requestedPage: 1)
        let cards = CatVodHomeProvider.entries(page.videos, for: feed, poster: { URL(string: $0) })
        let first = try #require(cards.first); let detail = try #require(WorkDetailRoute(first))
        #expect(detail.record.contentKind == .video)
        let expected = CatVodMovieRef(sourceID: feed.sourceID, siteKey: feed.siteKey, siteName: feed.siteName, videoID: "7", title: "测试片")
        #expect(ExplorePush.card(detail, in: .catVod(feed)) == .catVodMovie(expected))
        let provider = CatVodHomeProvider(), section = HomeSection(layout: .row, binding: .catVod(feed))
        #expect(provider.loadPolicy(for: section) == .serialPerSource)
        #expect(provider.loadPolicy(for: HomeSection(layout: .row, binding: .latest)) == nil)
        let row = HomeModel.Row(id: "example", section: section, source: provider.instance, sourceName: feed.title, policy: .serialPerSource, state: .loaded(cards))
        #expect(ExplorePlace.showAll(row, aozoraIndex: nil) == .catVodFeed(feed))
    }
    @Test func missingSourceDoesNotRegisterAReplacement() async {
        let provider = CatVodHomeProvider()
        do { _ = try await provider.load(HomeSection(layout: .row, binding: .catVod(feed))); Issue.record("removed source was silently replaced") }
        catch { #expect(error is CatVodUseError) }
    }
}
