import Foundation

enum MusicMembership: String, Codable {
    case qishuiVIP = "汽水会员"
    case unknown = "会员状态未知"
    case none = "非会员"
    case neteasePackage = "音乐包"
    case neteaseVIP = "黑胶VIP"
    case neteaseSVIP = "黑胶SVIP"
    case qqGreen = "绿钻"
    case qqDeluxe = "豪华绿钻"
    case qqSuper = "超级会员"
    case kugouVIP = "VIP会员"
    case kugouDeluxe = "豪华VIP"
    case kugouSuper = "超级VIP"

    var isMember: Bool { self != .unknown && self != .none }

    static func netease(_ response: [String: Any], now: Date = Date()) -> Self {
        guard integer(response["code"]) == 200, let data = response["data"] as? [String: Any] else { return .unknown }
        let products: [(String, Self)] = [("redplus", .neteaseSVIP), ("associator", .neteaseVIP), ("musicPackage", .neteasePackage)]
        var recognized = false
        for (key, tier) in products {
            guard let product = data[key] as? [String: Any], let end = expiry(product["expireTime"]) else { continue }
            recognized = true
            if end > now { return tier }
        }
        return recognized ? .none : .unknown
    }

    static func qq(_ response: [String: Any], now: Date = Date()) -> Self {
        guard integer(response["code"]) == 0,
              let rpc = response["req_0"] as? [String: Any], integer(rpc["code"]) == 0,
              let data = rpc["data"] as? [String: Any], let identity = data["identity"] as? [String: Any] else { return .unknown }
        func active(_ flag: String, end: String) -> Bool {
            guard (integer(identity[flag]) ?? 0) > 0 else { return false }
            return expiry(identity[end]).map { $0 > now } ?? true
        }
        // `svip` is a green-diamond identity in this RPC. The separate
        // HugeVip flag identifies QQ Music's super subscription.
        if active("HugeVip", end: "HugeVipEnd") { return .qqSuper }
        if active("LMFlag", end: "LMEnd") || active("svip", end: "overdate") { return .qqDeluxe }
        if active("vip", end: "overdate") { return .qqGreen }
        let flags = ["HugeVip", "LMFlag", "svip", "vip"].compactMap { integer(identity[$0]) }
        return flags.isEmpty ? .unknown : .none
    }

    static func kugou(_ response: [String: Any], now: Date = Date()) -> Self {
        guard integer(response["status"]) == 1,
              let data = response["data"] as? [String: Any], let type = integer(data["vip_type"]) else { return .unknown }
        if type == 0 { return .none }
        if let end = expiry(data["expire_time"] ?? data["vip_end_time"]), end <= now { return .none }
        if let name = data["vip_name"] as? String {
            if name == "超级VIP" { return .kugouSuper }
            if name == "豪华VIP" { return .kugouDeluxe }
        }
        // get_union_vip's 6 means super VIP; the product code `svip` on
        // KuGou's purchase pages instead names the deluxe subscription.
        switch type {
        case 6: return .kugouSuper
        case 11: return .kugouDeluxe
        default: return .kugouVIP
        }
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private static func expiry(_ value: Any?) -> Date? {
        if let number = value as? NSNumber { return timestamp(number.doubleValue) }
        guard let text = value as? String else { return nil }
        if text.count != 8, let number = Double(text) { return timestamp(number) }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Shanghai")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd", "yyyyMMdd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: text) { return date }
        }
        return nil
    }

    private static func timestamp(_ number: Double) -> Date {
        Date(timeIntervalSince1970: number > 100_000_000_000 ? number / 1000 : number)
    }
}

struct MusicMembershipSnapshot: Codable {
    let membership: MusicMembership
    let checkedAt: Date
}
