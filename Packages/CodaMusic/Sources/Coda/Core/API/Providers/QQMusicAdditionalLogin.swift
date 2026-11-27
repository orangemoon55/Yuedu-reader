// Native adaptations of the upstream WeChat QR and MQTT login channels.
import Foundation

enum QQMusicLoginChannel: String, CaseIterable, Identifiable {
    case qq, wechat, qqmusic
    var id: String { rawValue }

    var name: String {
        switch self {
        case .qq: return "QQ"
        case .wechat: return "微信"
        case .qqmusic: return "QQ 音乐 App"
        }
    }
}

@MainActor
enum QQMusicAdditionalLogin {
    static func signIn(_ channel: QQMusicLoginChannel, onImage: (Data) -> Void,
                       onScanned: () -> Void) async throws -> (credentials: [String: String], nickname: String) {
        switch channel {
        case .wechat: return try await wechat(onImage: onImage, onScanned: onScanned)
        case .qqmusic: return try await musicApp(onImage: onImage, onScanned: onScanned)
        case .qq: throw MusicProviderError.unsupported
        }
    }

    private static func wechat(onImage: (Data) -> Void, onScanned: () -> Void) async throws
        -> (credentials: [String: String], nickname: String) {
        let appID = "wx48db31d50e334801"
        let entry = "https://open.weixin.qq.com/connect/qrconnect"
        var url = URLComponents(string: entry)!
        url.queryItems = [
            URLQueryItem(name: "appid", value: appID),
            URLQueryItem(name: "redirect_uri", value: "https://y.qq.com/portal/wx_redirect.html?login_type=2&surl=https://y.qq.com/"),
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "scope", value: "snsapi_login"),
            URLQueryItem(name: "state", value: "STATE"),
            URLQueryItem(name: "href", value: "https://y.qq.com/mediastyle/music_v17/src/css/popup_wechat.css#wechat_redirect")
        ]
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let page = try await get(session, url.url!)
        let text = String(decoding: page, as: UTF8.self)
        guard let uuid = captures(#"uuid=([A-Za-z0-9_-]+)""#, in: text).first else {
            throw ProviderRequestError.decoding("WeChat QR identifier")
        }
        let imageURL = URL(string: "https://open.weixin.qq.com/connect/qrcode/\(uuid)")!
        let image = try await get(session, imageURL, referer: entry)
        try Task.checkCancellation()
        onImage(image)
        let deadline = Date().addingTimeInterval(180)
        var scanned = false
        while Date() < deadline {
            var poll = URLComponents(string: "https://lp.open.weixin.qq.com/connect/l/qrconnect")!
            poll.queryItems = [URLQueryItem(name: "uuid", value: uuid),
                               URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000)))]
            if scanned { poll.queryItems?.append(.init(name: "last", value: "404")) }
            let data: Data
            do {
                data = try await get(session, poll.url!, referer: "https://open.weixin.qq.com/")
            } catch let error as URLError where error.code == .timedOut {
                continue
            }
            try Task.checkCancellation()
            let fields = captures(#"window\.wx_errcode\s*=\s*(\d+);\s*window\.wx_code\s*=\s*'([^']*)'"#,
                                  in: String(decoding: data, as: UTF8.self))
            guard fields.count == 2 else { throw ProviderRequestError.decoding("WeChat QR status") }
            switch fields[0] {
            case "408": continue
            case "404": scanned = true; onScanned()
            case "405":
                guard !fields[1].isEmpty else { throw ProviderRequestError.decoding("WeChat OAuth code") }
                let response = try await QQMusicAPI.shared.loginCall("Login",
                    params: ["code": fields[1], "strAppid": appID], comm: ["tmeLoginType": 1])
                return try credentials(response, defaultLoginType: 1)
            case "402": throw expired
            case "403": throw ProviderRequestError.unknown("微信已取消登录")
            default: throw ProviderRequestError.unknown("微信扫码失败（\(fields[0])）")
            }
        }
        throw expired
    }

    private static func musicApp(onImage: (Data) -> Void, onScanned: () -> Void) async throws
        -> (credentials: [String: String], nickname: String) {
        let data = try await QQMusicAPI.shared.loginCall("CreateQRCode",
            params: ["tmeAppID": "qqmusic", "ct": 11, "cv": 14090008], comm: ["ct": 23, "cv": 0])
        guard let id = data["qrcodeID"] as? String, !id.isEmpty,
              let encoded = (data["qrcode"] as? String)?.split(separator: ",").last,
              let image = Data(base64Encoded: String(encoded)),
              image.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else {
            throw ProviderRequestError.decoding("QQ Music App QR")
        }
        let ttl = max(10, min(data["expiresIn"] as? Int ?? 180, 180))
        let session = URLSession(configuration: .ephemeral, delegate: ProviderNoRedirectDelegate(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var path = "/ws/handshake"
        for redirect in 0...3 {
            let socket = session.webSocketTask(with: URL(string: "wss://mu.y.qq.com" + path)!, protocols: ["mqtt"])
            socket.resume()
            let reader = QQMusicQRSocket(socket: socket)
            let timeout = Task {
                try await Task.sleep(for: .seconds(ttl))
                socket.cancel(with: .goingAway, reason: nil)
            }
            defer {
                timeout.cancel()
                socket.cancel(with: .normalClosure, reason: nil)
            }
            let handshake = try await withTaskCancellationHandler {
                try await socket.send(.data(QQMusicQRSocket.connect(id)))
                return try await reader.next()
            } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
            guard handshake.header >> 4 == 2, handshake.body.count >= 3 else {
                throw ProviderRequestError.decoding("QQ Music MQTT handshake")
            }
            let reason = handshake.body[1]
            if reason != 0 {
                let properties = try QQMusicQRSocket.properties(handshake.body, offset: 2)
                guard [0x9c, 0x9d].contains(reason), redirect < 3, let ref = properties.fields["serverReference"],
                      ref.range(of: #"^[A-Za-z0-9._:-]+$"#, options: .regularExpression) != nil else {
                    throw ProviderRequestError.unknown("QQ 音乐 App 扫码连接被拒绝（\(reason)）")
                }
                path = "/ws/handshake/" + ref
                continue
            }

            return try await withTaskCancellationHandler {
                try await socket.send(.data(QQMusicQRSocket.subscribe(id)))
                let ping = Task {
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(30))
                        try await socket.send(.data(Data([0xc0, 0])))
                    }
                }
                defer { ping.cancel() }
                while true {
                    let packet = try await reader.next()
                    try Task.checkCancellation()
                    switch packet.header >> 4 {
                    case 9:
                        guard let code = packet.body.last, code < 0x80 else {
                            throw ProviderRequestError.decoding("QQ Music MQTT subscription")
                        }
                        onImage(image)
                    case 3:
                        let event = try QQMusicQRSocket.event(packet)
                        switch event.type {
                        case "scanned": onScanned()
                        case "cookies":
                            guard let jar = event.payload["cookies"] as? [String: [String: Any]],
                                  let musicID = string(jar["qqmusic_uin"]?["value"]), let number = UInt64(musicID),
                                  let token = string(jar["qqmusic_key"]?["value"]) else {
                                throw ProviderRequestError.decoding("QQ Music App credentials")
                            }
                            let fallback = string(jar["tmeLoginType"]?["value"]) == "1" ? 1 : 6
                            let response = try await QQMusicAPI.shared.loginCall("Login",
                                params: ["musicid": NSNumber(value: number), "qrCodeID": id, "token": token], comm: ["tmeLoginType": 6])
                            return try credentials(response, defaultLoginType: fallback)
                        case "timeout": throw expired
                        case "canceled": throw ProviderRequestError.unknown("已在 QQ 音乐 App 取消登录")
                        case "loginFailed": throw ProviderRequestError.unknown("QQ 音乐 App 登录失败，请刷新二维码")
                        default: break
                        }
                    default: break
                    }
                }
            } onCancel: { socket.cancel(with: .goingAway, reason: nil) }
        }
        throw ProviderRequestError.network
    }

    static func credentials(_ data: [String: Any], defaultLoginType: Int) throws -> (credentials: [String: String], nickname: String) {
        let id = [data["str_musicid"], data["musicid"]].compactMap(string).first { $0 != "0" }
        guard let id, let key = string(data["musickey"]) else { throw ProviderRequestError.decoding("QQ Music credentials") }
        let loginType = (data["loginType"] as? Int) ?? defaultLoginType
        var result = ["uin": id, "str_musicid": id, "qqmusic_key": key, "qm_keyst": key, "musickey": key,
                      "music_login_type": String(loginType)]
        if loginType == 1 { result["wxuin"] = "o" + id }
        for key in ["encryptUin", "openid", "unionid", "refresh_token", "refresh_key", "musickeyCreateTime", "keyExpiresIn", "logo", "nick"] {
            result[key] = string(data[key])
        }
        if loginType == 1 { result["wxopenid"] = result["openid"] }
        return (result, result["nick"] ?? "QQ 音乐用户")
    }

    private static var expired: ProviderRequestError { .unknown("二维码已过期，请刷新") }

    private static func get(_ session: URLSession, _ url: URL, referer: String? = nil) async throws -> Data {
        var request = URLRequest(url: url, timeoutInterval: 16)
        request.setValue(referer, forHTTPHeaderField: "Referer")
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw ProviderRequestError.network }
        return data
    }

    private static func captures(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return [] }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: text).map { String(text[$0]) } }
    }

    private static func string(_ value: Any?) -> String? {
        let value = (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
        return value.isEmpty ? nil : value
    }
}

@MainActor
private final class QQMusicQRSocket {
    typealias Packet = (header: UInt8, body: [UInt8])
    private let socket: URLSessionWebSocketTask
    private var bytes: [UInt8] = []

    init(socket: URLSessionWebSocketTask) { self.socket = socket }

    func next() async throws -> Packet {
        while true {
            if !bytes.isEmpty, let length = Self.variable(bytes, at: 1), bytes.count >= length.next + length.value {
                let end = length.next + length.value
                let packet = (bytes[0], Array(bytes[length.next..<end]))
                bytes.removeFirst(end)
                return packet
            }
            guard bytes.count < 1_048_576 else { throw Self.invalid }
            guard case .data(let data) = try await socket.receive() else { throw Self.invalid }
            bytes.append(contentsOf: data)
        }
    }

    static func connect(_ id: String) -> Data {
        let values = [("tmeAppID", "qqmusic"), ("business", "management"), ("hashTag", id),
                      ("clientTag", "management.user"), ("userID", id)]
        let props = [UInt8(0x15)] + utf8("pass") + userProperties(values)
        let clientID = "\(Int(Date().timeIntervalSince1970 * 1000))\(Int.random(in: 1000...9999))"
        return packet(0x10, utf8("MQTT") + [5, 2, 0, 45] + length(props.count) + props + utf8(clientID))
    }

    static func subscribe(_ id: String) -> Data {
        let props = userProperties([("authorization", "tmelogin"), ("pubsub", "unicast")])
        return packet(0x82, [0, 1] + length(props.count) + props + utf8("management.qrcode_login/" + id) + [0])
    }

    static func event(_ packet: Packet) throws -> (type: String, payload: [String: Any]) {
        let topic = try readString(packet.body, at: 0)
        let offset = topic.next + ((packet.header & 6) == 0 ? 0 : 2)
        let props = try properties(packet.body, offset: offset)
        let data = Data(packet.body[props.next...])
        let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        return (props.fields["type"] ?? "", payload)
    }

    static func properties(_ bytes: [UInt8], offset: Int) throws -> (fields: [String: String], next: Int) {
        guard let size = variable(bytes, at: offset), size.next + size.value <= bytes.count else { throw invalid }
        let end = size.next + size.value
        var cursor = size.next
        var result: [String: String] = [:]
        while cursor < end {
            let id = bytes[cursor]
            cursor += 1
            switch id {
            case 0x26:
                let key = try readString(bytes, at: cursor)
                let value = try readString(bytes, at: key.next)
                result[key.value] = value.value
                cursor = value.next
            case 0x03, 0x08, 0x12, 0x15, 0x1a, 0x1c, 0x1f, 0x09, 0x16:
                let value = try readString(bytes, at: cursor)
                if id == 0x1c { result["serverReference"] = value.value }
                cursor = value.next
            case 0x13, 0x21, 0x22, 0x23: cursor += 2
            case 0x02, 0x11, 0x18, 0x27: cursor += 4
            case 0x01, 0x17, 0x19, 0x24, 0x25, 0x28, 0x29, 0x2a: cursor += 1
            case 0x0b:
                guard let value = variable(bytes, at: cursor) else { throw invalid }
                cursor = value.next
            default: throw invalid
            }
            guard cursor <= end else { throw invalid }
        }
        return (result, end)
    }

    private static var invalid: ProviderRequestError { .decoding("QQ Music MQTT packet") }

    private static func readString(_ bytes: [UInt8], at offset: Int) throws -> (value: String, next: Int) {
        guard offset + 2 <= bytes.count else { throw invalid }
        let start = offset + 2
        let end = start + Int(bytes[offset]) * 256 + Int(bytes[offset + 1])
        guard end <= bytes.count else { throw invalid }
        return (String(decoding: bytes[start..<end], as: UTF8.self), end)
    }

    private static func variable(_ bytes: [UInt8], at offset: Int) -> (value: Int, next: Int)? {
        var result = 0
        for i in 0..<4 where offset + i < bytes.count {
            let byte = bytes[offset + i]
            result |= Int(byte & 127) << (7 * i)
            if byte & 128 == 0 { return (result, offset + i + 1) }
        }
        return nil
    }

    private static func length(_ count: Int) -> [UInt8] {
        var remaining = count
        var result: [UInt8] = []
        repeat {
            let byte = UInt8(remaining & 127)
            remaining >>= 7
            result.append(remaining > 0 ? byte | 128 : byte)
        } while remaining > 0
        return result
    }

    private static func utf8(_ string: String) -> [UInt8] {
        let bytes = Array(string.utf8)
        return [UInt8((bytes.count >> 8) & 255), UInt8(bytes.count & 255)] + bytes
    }

    private static func userProperties(_ values: [(String, String)]) -> [UInt8] {
        values.flatMap { [0x26] + utf8($0.0) + utf8($0.1) }
    }

    private static func packet(_ header: UInt8, _ body: [UInt8]) -> Data {
        Data([header] + length(body.count) + body)
    }
}
