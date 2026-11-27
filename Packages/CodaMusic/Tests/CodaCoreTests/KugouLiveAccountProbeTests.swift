#if os(macOS)
import Foundation
import Testing
@testable import CodaCore

/// 用本机 Coda Dev 的酷狗账号只读调用首页相关接口。账号只放在内存里，不写回钥匙串；
/// 只输出成功与否、数量和标题。设置 CODA_KUGOU_LIVE_ACCOUNT_AUDIT=1 时运行。
@Suite("Kugou logged-in home audit", .enabled(if: ProcessInfo.processInfo.environment["CODA_KUGOU_LIVE_ACCOUNT_AUDIT"] == "1"))
struct KugouLiveAccountProbeTests {
    private static func devCredentials() throws -> [String: String] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "wow.caicai.coda.dev.music-accounts", "-a", "beans.kugou.auth.v2", "-w"]
        let pipe = Pipe(); process.standardOutput = pipe; process.standardError = Pipe()
        try process.run()
        let raw = pipe.fileHandleForReading.readDataToEndOfFile(); process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw URLError(.userAuthenticationRequired) }
        let text = String(decoding: raw, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        var bytes = Data(text.utf8)
        if !text.hasPrefix("{") {
            bytes = Data(); var index = text.startIndex
            while index < text.endIndex {
                let end = text.index(index, offsetBy: 2, limitedBy: text.endIndex) ?? text.endIndex
                bytes.append(try #require(UInt8(text[index..<end], radix: 16))); index = end
            }
        }
        return try JSONDecoder().decode([String: String].self, from: bytes)
    }

    private static func report(_ name: String, _ work: () async throws -> String) async {
        do { print("✅ \(name): \(try await work())") } catch { print("❌ \(name): \(error)") }
    }

    private static func rows(_ json: [String: Any], _ path: [String]) -> [[String: Any]] {
        var node: Any? = json
        for key in path { node = (node as? [String: Any])?[key] }
        return node as? [[String: Any]] ?? []
    }

    private static func summary(_ json: [String: Any], _ path: [String], _ title: String) -> String {
        let list = rows(json, path)
        let status = json["status"].map { "\($0)" } ?? "?"
        let code = (json["error_code"] ?? json["errcode"]).map { "\($0)" } ?? "?"
        guard !list.isEmpty else {
            let message = (json["error"] ?? json["error_msg"] ?? json["msg"]).map { "\($0)" } ?? ""
            return "空 (status=\(status) code=\(code) \(message))"
        }
        return "\(list.count) 条 · " + list.prefix(3).map { "\($0[title] ?? "?")" }.joined(separator: " / ")
    }

    @Test func auditHomeEndpointsWithAccount() async throws {
        KugouMusicAuth.shared.useInMemoryForTesting(try Self.devCredentials())
        let auth = KugouMusicAuth.shared
        print("账号已登录: \(auth.isLoggedIn), VIP: \(auth.vipBadge ?? "无")")
        try #require(auth.isLoggedIn)
        let api = KugouMusicAPI.shared
        let userID = Int(auth.userId) ?? 0

        print("—— App 现有首页接口")
        await Self.report("排行榜") { "\(try await api.topLists().count) 个" }
        await Self.report("新碟") { "\(try await api.newAlbums().count) 张" }
        await Self.report("推荐歌手") { "\(try await api.hotSingers(limit: 100).count) 位" }
        await Self.report("推荐歌单") { "\(try await api.recommendPlaylists().count) 个" }
        await Self.report("每日推荐") { "\(try await api.everydayRecommend().count) 首" }
        await Self.report("私人漫游") { "\(try await api.personalFM().count) 首" }
        await Self.report("热搜") { "\(try await api.hotWords().count) 个" }

        for card in KugouMusicAPI.SongCard.allCases {
            await Self.report("推荐卡片 \(card)") {
                let songs = try await api.cardSongs(card)
                return "\(songs.count) 首 · " + songs.prefix(3).map(\.name).joined(separator: " / ")
            }
        }
        await Self.report("新歌速递") {
            let songs = try await api.newSongs()
            var playable = 0
            for song in songs.prefix(5) where (try? await api.songURL(song: song))??.isEmpty == false { playable += 1 }
            return "\(songs.count) 首，前 5 首可播放 \(playable) 首"
        }

        print("—— 候选接口")
        let cards = [(1, "私人专属好歌"), (2, "经典怀旧金曲"), (3, "热门好歌精选"), (4, "小众宝藏佳作"), (6, "VIP 专属推荐")]
        for (id, name) in cards {
            await Self.report("卡片 \(id) \(name)") {
                let time = Int(Date().timeIntervalSince1970 * 1000)
                let fakem = "60f7ebf1f812edbac3c63a7310001701760f"
                let response = try await api.upstreamRequest(
                    "/singlecardrec.service/v1/single_card_recommend", method: "POST",
                    params: ["card_id": "\(id)", "fakem": fakem, "area_code": "1", "platform": "ios"],
                    data: ["appid": 1005, "clientver": 20489, "platform": "android", "clienttime": time, "userid": userID,
                           "key": api.upstreamParamsKey("\(time)"), "fakem": fakem, "area_code": 1, "mid": auth.mid,
                           "uuid": "-", "client_playlist": [], "u_info": "a0c35cd40af564444b5584c2754dedec"])
                return Self.summary(response.json, ["data", "song_list"], "songname")
            }
        }
        await Self.report("新歌速递") {
            let response = try await api.upstreamRequest("/musicadservice/container/v1/newsong_publish", method: "POST",
                data: ["rank_id": 21608, "userid": userID, "page": 1, "pagesize": 30, "tags": []])
            return Self.summary(response.json, ["data"], "songname")
        }
        await Self.report("歌单分类") {
            let response = try await api.upstreamRequest("/pubsongs/v1/get_tags_by_type", method: "POST",
                data: ["tag_type": "collection", "tag_id": 0, "source": 3])
            let groups = Self.rows(response.json, ["data"])
            return "\(groups.count) 组 · " + groups.map { "\($0["tag_name"] ?? "?")(\(($0["son"] as? [Any])?.count ?? 0))" }.joined(separator: " ")
        }
        for (id, name) in [(0, "推荐"), (9, "流行"), (587, "学习"), (11292, "Hi-Res")] {
            await Self.report("分类歌单 \(name)") {
                let time = Int(Date().timeIntervalSince1970)
                let response = try await api.upstreamRequest("/v2/special_recommend", method: "POST", data: [
                    "appid": 1005, "mid": auth.mid, "clientver": 20489, "platform": "android", "clienttime": time,
                    "userid": userID, "module_id": 1, "page": 1, "pagesize": 30, "key": api.upstreamParamsKey("\(time)"),
                    "special_recommend": ["withtag": 1, "withsong": 0, "sort": 1, "ugc": 1, "is_selected": 0,
                                          "withrecommend": 1, "area_code": 1, "categoryid": id],
                    "req_multi": 1, "retrun_min": 5, "return_special_falg": 1,
                ], headers: ["x-router": "specialrec.service.kugou.com"])
                return Self.summary(response.json, ["data", "special_list"], "specialname")
            }
        }
        await Self.report("风格推荐") {
            let response = try await api.upstreamRequest("/everydayrec.service/everyday_style_recommend", method: "POST",
                params: ["tagids": ""], data: [:])
            let data = response.json["data"] as? [String: Any] ?? [:]
            return "字段 \(data.keys.sorted().prefix(8).joined(separator: ",")) · " + Self.summary(response.json, ["data", "song_list"], "songname")
        }
        await Self.report("历史推荐") {
            let response = try await api.upstreamRequest("/everyday/api/v1/get_history", method: "POST",
                params: ["mode": "list", "platform": "ios"], headers: ["x-router": "everydayrec.service.kugou.com"])
            return String(String(describing: response.json["data"] ?? "nil").prefix(220))
        }
        await Self.report("主题歌单") {
            let response = try await api.upstreamRequest("/v2/getthemelist", method: "POST",
                data: ["platform": "android", "clientver": 20489, "clienttime": Int(Date().timeIntervalSince1970 * 1000),
                       "area_code": 1, "module_id": 1, "userid": userID],
                headers: ["x-router": "everydayrec.service.kugou.com"])
            let first = Self.rows(response.json, ["data", "theme_list"]).first ?? [:]
            return "首项字段 \(first.keys.sorted().prefix(12).joined(separator: ",")) · " + "\(first["title"] ?? first["name"] ?? first["theme_title"] ?? "?")"
        }
        await Self.report("场景音乐") {
            let response = try await api.upstreamRequest("/scene/v1/scene/list")
            let data = response.json["data"]
            return "data 类型 \(type(of: data as Any)) · " + String(String(describing: data ?? "nil").prefix(220))
        }
        await Self.report("继续播放") {
            let response = try await api.upstreamRequest("/playque/devque/v1/get_latest_songs", method: "POST",
                data: ["area_code": "1", "sources": ["pc", "mobile", "tv", "car"], "userid": userID,
                       "ret_info": 1, "token": auth.token, "pagesize": 10])
            let data = response.json["data"] as? [String: Any] ?? [:]
            return "status=\(response.json["status"] ?? "?") 字段 \(data.keys.sorted().prefix(8).joined(separator: ","))"
        }
    }
}
#endif
