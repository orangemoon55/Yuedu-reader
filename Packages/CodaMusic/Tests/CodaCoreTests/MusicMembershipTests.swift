import Foundation
import Testing
@testable import CodaCore

@Suite("Platform membership identities")
struct MusicMembershipTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func neteaseUsesActiveProductsRatherThanGrowthLevel() {
        let future = 1_900_000_000_000 as Int64
        #expect(MusicMembership.netease(["code": 200, "data": ["redplus": ["expireTime": future]]], now: now) == .neteaseSVIP)
        #expect(MusicMembership.netease(["code": 200, "data": ["redplus": ["expireTime": 1], "associator": ["expireTime": future]]], now: now) == .neteaseVIP)
        #expect(MusicMembership.netease(["code": 200, "data": ["musicPackage": ["expireTime": future]]], now: now) == .neteasePackage)
        #expect(MusicMembership.netease(["code": 200, "data": ["redVipLevel": 11, "associator": ["expireTime": 0]]], now: now) == .none)
    }

    private func qq(_ identity: [String: Any], code: Int = 0) -> MusicMembership {
        .qq(["code": 0, "req_0": ["code": code, "data": ["identity": identity]]], now: now)
    }

    @Test func qqSvipDoesNotMeanSuperMembershipAndLevelsAreNotTiers() {
        #expect(qq(["svip": 1, "level": 11]) == .qqDeluxe)
        #expect(qq(["LMFlag": 1]) == .qqDeluxe)
        #expect(qq(["vip": 1]) == .qqGreen)
        #expect(qq(["HugeVip": 1, "svip": 1]) == .qqSuper)
        #expect(qq(["HugeVip": 1, "HugeVipEnd": "2020-01-01", "svip": 1, "overdate": "2030-01-01"]) == .qqDeluxe)
        #expect(qq(["vip": 1, "overdate": "20200101"]) == .none)
        #expect(qq(["vip": 0, "svip": 0, "level": 11]) == .none)
    }

    @Test func kugouUsesItsOwnUnionVipTypeAndExpiry() {
        #expect(MusicMembership.kugou(["status": 1, "data": ["vip_type": 6]], now: now) == .kugouSuper)
        #expect(MusicMembership.kugou(["status": 1, "data": ["vip_type": 11]], now: now) == .kugouDeluxe)
        #expect(MusicMembership.kugou(["status": 1, "data": ["vip_type": 6, "expire_time": 1]], now: now) == .none)
        #expect(MusicMembership.kugou(["status": 1, "data": ["vip_type": 0]], now: now) == .none)
    }

    @Test func errorsMissingFieldsAndUnrelatedMembershipsStayUnknown() {
        #expect(qq(["svip_days_left": 30]) == .unknown)
        #expect(qq(["HugeVip": 1], code: 1000) == .unknown)
        #expect(MusicMembership.netease(["code": 301]) == .unknown)
        #expect(MusicMembership.netease(["code": 200, "data": [:]]) == .unknown)
        #expect(MusicMembership.kugou(["status": 0, "data": ["vip_type": 6]]) == .unknown)
    }

    @Test func oldSavedAccountsDecodeWithoutMembership() throws {
        let json = #"{"id":"qq:42","provider":"qq","userID":"42","nickname":"Fixture","credentials":{}}"#
        let item = try JSONDecoder().decode(MusicAccount.self, from: Data(json.utf8))
        #expect(item.membership == nil)
    }

    @MainActor @Test func isolatedQQMembershipSessionDoesNotPublishLoginChanges() {
        let observer = NotificationCenter.default.addObserver(forName: .qqLoginDidUpdate, object: nil, queue: nil) { _ in
            Issue.record("An isolated membership query must not change the active login")
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let auth = QQMusicAuth(persistsSession: false)
        auth.importCookies(["uin": "42", "qqmusic_key": "fixture-key"], nickname: "Fixture")
        #expect(auth.uin == "42")
    }
}
