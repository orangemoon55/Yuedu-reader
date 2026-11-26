import SwiftUI
import Testing
@testable import yuedu_app

@MainActor
@Suite("Fixed video presentation contract")
struct MediaHubVideoLayoutTests {
    @Test("the rendered template constructs exactly three equal flexible columns")
    func fixedColumns() {
        #expect(MediaHubVideoLayout.posterColumnCount == 3)
        let columns = MediaHubVideoLayout.columns
        #expect(columns.count == MediaHubVideoLayout.posterColumnCount)
        for column in columns {
            if case .flexible(let minimum, let maximum) = column.size {
                #expect(minimum == 0)
                #expect(maximum == .infinity)
            } else {
                Issue.record("Every fixed video column must be flexible, not adaptive or fixed-width")
            }
            #expect(column.spacing == MediaHubVideoLayout.spacing)
        }
    }

    @Test("loaded covers and skeleton covers share the screenshot's portrait 2:3 contract")
    func coverGeometry() {
        #expect(MediaHubVideoLayout.posterAspectRatio == 2.0 / 3.0)
        #expect(MediaHubVideoLayout.skeletonCount == 9)
        #expect(MediaHubVideoLayout.skeletonCount % MediaHubVideoLayout.posterColumnCount == 0)
    }

    @Test("skeletons exist only for an active request with no displayable items")
    func finiteLoadingStates() {
        #expect(MediaHubVideoLayout.showsSkeleton(loading: true, itemCount: 0))
        #expect(!MediaHubVideoLayout.showsSkeleton(loading: false, itemCount: 0)) // empty/error/offline
        #expect(!MediaHubVideoLayout.showsSkeleton(loading: false, itemCount: 6))
        #expect(!MediaHubVideoLayout.showsSkeleton(loading: true, itemCount: 6)) // more/refresh keeps content
    }

    @Test("language comes from the selected API, never a site's marketing name")
    func truthfulLanguage() {
        let misleading = site(api: "/spider/ordinary", type: 3, name: "Python hmtv")
        let label = MediaHubVideoLayout.sourceKindLabel(for: misleading)
        #expect(!label.contains("Python"))
        #expect(!label.contains("JavaScript"))
        #expect(label.contains("3"))
        #expect(MediaHubVideoLayout.sourceKindLabel(for: site(api: "/spider/actual.py")).contains("Python"))
        #expect(MediaHubVideoLayout.sourceKindLabel(for: site(api: "/spider/actual.JS")).contains("JavaScript"))
    }

    @Test("type badge changes with the selected site's actual declaration")
    func selectedSiteKind() {
        let first = MediaHubVideoLayout.sourceKindLabel(for: site(api: "/spider/one", type: 1))
        let second = MediaHubVideoLayout.sourceKindLabel(for: site(api: "/spider/two", type: 4))
        #expect(first != second)
        #expect(first.contains("1"))
        #expect(second.contains("4"))
    }

    @Test("query parameters cannot impersonate a source language")
    func apiPathOnly() {
        let label = MediaHubVideoLayout.sourceKindLabel(for: site(api: "/spider/real?label=fake.py"))
        #expect(!label.contains("Python"))
    }

    private func site(api: String, type: Int = 3, name: String = "真實站點") -> CatVodSite {
        CatVodSite(key: "site", name: name, api: api, type: type,
                   searchable: true, filterable: true, indexs: true)
    }
}
