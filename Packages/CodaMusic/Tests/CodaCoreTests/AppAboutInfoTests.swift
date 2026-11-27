import Foundation
import Testing
@testable import CodaCore

@Suite("About page information")
struct AppAboutInfoTests {
    @Test func websiteIsTheRepositoryPagesAddress() throws {
        let url = try #require(AppAboutInfo.pagesURL(for: "Wow-CaiCai/Coda"))
        #expect(url.absoluteString == "https://wow-caicai.github.io/Coda/")
        #expect(AppAboutInfo.displayAddress(url) == "wow-caicai.github.io/Coda")
        #expect(AppAboutInfo.pagesURL(for: "invalid") == nil)
    }

    @Test func missingInfoFallsBackToRepositoryIdentity() {
        let info = AppAboutInfo(bundle: Bundle(for: BundleToken.self), repository: "Owner/Product")
        #expect(info.developer == "Owner")
        #expect(info.repositoryURL?.absoluteString == "https://github.com/Owner/Product")
        #expect(info.issuesURL?.absoluteString == "https://github.com/Owner/Product/issues")
    }

    @Test func parsesNoticeTablesByLicenseColumn() {
        let markdown = """
        # Index

        ## 1. 派生来源

        | 仓库 | 许可证 | 说明 |
        | --- | --- | --- |
        | [missuo/kumone](https://github.com/missuo/kumone) | LGPL-3.0（[Kumone-LGPL-3.0.txt](Kumone-LGPL-3.0.txt)） | Upstream |
        | [XerWandeRer/kumone](https://github.com/XerWandeRer/kumone) | — | Models |

        ## 3. 依赖包与运行时下载资源

        | 仓库 | 版本 | 许可证 | 用途 |
        | --- | --- | --- | --- |
        | [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.x | MIT 类（见上游 LICENSE） | Updates |
        | 字节跳动安全 SDK（`bdms.js`） | — | 各自条款 / MIT | Login |
        """
        let groups = ThirdPartyNotices.parse(markdown)
        #expect(groups.map(\.title) == ["派生来源", "依赖包与运行时下载资源"])
        #expect(groups[0].entries == [
            .init(name: "missuo/kumone", url: URL(string: "https://github.com/missuo/kumone"), license: "LGPL-3.0"),
            .init(name: "XerWandeRer/kumone", url: URL(string: "https://github.com/XerWandeRer/kumone"), license: nil),
        ])
        #expect(groups[1].entries[0].license == "MIT 类")
        #expect(groups[1].entries[1].url == nil)
        #expect(groups[1].entries[1].license == "各自条款 / MIT")
    }

    @Test func repositoryNoticeIndexYieldsEveryGroup() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ThirdPartyNotices/README.md")
        let groups = ThirdPartyNotices.parse(try String(contentsOf: url, encoding: .utf8))
        #expect(groups.count == 4)
        #expect(groups.allSatisfy { !$0.entries.isEmpty })
        #expect(groups.flatMap(\.entries).contains { $0.name == "youshen2/MeloX" && $0.license == "GPL-3.0-only" })
    }
}

private final class BundleToken {}
