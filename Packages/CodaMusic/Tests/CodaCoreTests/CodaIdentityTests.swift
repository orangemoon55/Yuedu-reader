import Foundation
import Testing
@testable import CodaCore

@Suite("Coda product isolation")
struct CodaIdentityTests {
    @Test func releasesAndDevelopmentHaveSeparateNamespaces() {
        #expect(CodaIdentity.namespace(for: "wow.caicai.coda") == "wow.caicai.coda")
        #expect(CodaIdentity.namespace(for: "wow.caicai.coda.dev") == "wow.caicai.coda.dev")
        #expect(CodaIdentity.namespace(for: "sb.moe.kumone.dev") == "sb.moe.kumone.dev.coda-music")
        #expect(CodaIdentity.namespace(for: "com.local.readcc") == "com.local.readcc.coda-music")
        #expect(CodaIdentity.namespace(for: nil) == "local.coda-music")
        #expect(CodaIdentity.namespace(for: "") == "local.coda-music")
        #expect(CodaIdentity.isEmbedded(in: "com.local.readcc"))
        #expect(!CodaIdentity.isEmbedded(in: "wow.caicai.coda"))
        #expect(CodaPaths.applicationSupport.lastPathComponent == CodaIdentity.namespace)
        #expect(CodaPaths.imageCache.path.contains(CodaIdentity.namespace + "/images"))
    }

    @Test func unreleasedRepositoryHasAnUnderstandableResponse() throws {
        let url = try #require(URL(string: "https://api.github.com/repos/Wow-CaiCai/Coda/releases/latest"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 404, httpVersion: nil, headerFields: nil))
        #expect(throws: ReleaseChecker.UpdateError.self) {
            try ReleaseChecker.parseLatest(data: Data(), response: response)
        }
    }

    @Test func newReleaseUsesCodaAsset() throws {
        let url = try #require(URL(string: "https://api.github.com/repos/Wow-CaiCai/Coda/releases/latest"))
        let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
        let payload = Data(#"{"tag_name":"v0.1.1","html_url":"https://github.com/Wow-CaiCai/Coda/releases/tag/v0.1.1","assets":[{"name":"Coda-iOS-0.1.1.ipa","browser_download_url":"https://github.com/Wow-CaiCai/Coda/releases/download/v0.1.1/Coda-iOS-0.1.1.ipa"}]}"#.utf8)
        let release = try ReleaseChecker.parseLatest(data: payload, response: response)
        #expect(release.version == "0.1.1")
        #expect(release.ipaURL?.lastPathComponent == "Coda-iOS-0.1.1.ipa")
    }
    @MainActor @Test func loginTransferRejectsOtherProductBeforeCredentialAccess() throws {
        let account = MusicAccount(id: "netease:42", provider: .netease, userID: "42",
                                   nickname: "Fixture", credentials: ["MUSIC_U": "synthetic"])
        let encoder = JSONEncoder()
        let old = MusicAccountManager.LoginTransfer(format: "kumone-login", version: 1, accounts: [account])
        let text = String(decoding: try encoder.encode(old), as: UTF8.self)
        #expect(throws: (any Error).self) { try MusicAccountManager.decodeLoginTransfer(text) }
        let current = MusicAccountManager.LoginTransfer(format: "coda-login", version: 1, accounts: [account])
        let accepted = try MusicAccountManager.decodeLoginTransfer(String(decoding: try encoder.encode(current), as: UTF8.self))
        #expect(accepted.accounts.first?.id == "netease:42")
    }
    @Test func requestEncryptionRetainsUpstreamProtocolConstants() {
        let result = NeteaseCrypto.weapi(payload: Data("{}".utf8))
        #expect(result["params"] == "5mw8zRQyOCBTOQT0PwAPQxLmYc/qef/kC0BeaiRwIKA=")
        #expect(result["encSecKey"]?.count == 256)
    }
}
