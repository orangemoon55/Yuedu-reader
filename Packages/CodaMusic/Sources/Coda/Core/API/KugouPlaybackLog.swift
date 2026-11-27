import CommonCrypto
import CryptoKit
import Foundation
import Security
import zlib

/// KuGou CSCC concept-client protocol. Endpoint/field reference:
/// MakcRe/KuGouMusicApi module/user_listen_report.js. No automatic event retries:
/// a lost response may already have been counted by the service.
actor KugouPlaybackLogClient {
    enum Event: String { case start, end }
    struct Device: Equatable, Sendable {
        let model: String
        let system: String
        let width: Int
        let height: Int
    }
    struct CipherSession {
        let cookie: String
        let clienttime: String
        let serverstr: String
        let field2: String
        let expires: Date
    }
    enum Failure: LocalizedError {
        case invalidIdentity, invalidEnvelope, rejected(String, Int), network(String, Int)
        var errorDescription: String? {
            switch self {
            case .invalidIdentity: return "酷狗播放上报缺少账号或设备标识"
            case .invalidEnvelope: return "酷狗播放上报会话无法解析"
            case let .rejected(stage, code): return "酷狗播放上报被拒绝（\(stage)，\(code)）"
            case let .network(stage, code): return "酷狗播放上报连接失败（\(stage)，\(code)）"
            }
        }
    }
    private static let appKey = "LnT6xpN3khm36zse0QzvmgTZ3waWdRSA"
    private static let version = "10597"
    private static let publicKey = "MIGfMA0GCSqGSIb3DQEBAQUAA4GNADCBiQKBgQDECi0Np2UR87scwrvTr72L6oO01rBbbBPriSDFPxr3Z5syug0O24QyQO8bg27+0+4kBzTBTBOZ/WWU0WryL1JSXRTXLgFVxtzIY41Pe7lPOgsfTCn5kZcvKhYKJesKnnJDNr5/abvTGf+rHG3YRwsCHcQ08/q6ifSioBszvb3QiwIDAQAB"
    private let session: URLSession
    private let uuid: String
    private let mid: String
    private let userID: String
    private let device: Device
    private let randomField: @Sendable () -> String
    private var cipher: CipherSession?
    private var handshake: Task<CipherSession, Error>?

    init(credentials: [String: String], device: Device, configuration: URLSessionConfiguration? = nil,
         randomField: @escaping @Sendable () -> String = { UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() }) throws {
        uuid = (credentials["KUGOU_API_GUID"] ?? credentials["uuid"] ?? "").replacingOccurrences(of: "-", with: "")
        mid = credentials["KUGOU_API_MID"] ?? credentials["mid"] ?? ""
        userID = credentials["userid"] ?? credentials["user_id"] ?? ""
        self.device = device
        self.randomField = randomField
        guard uuid.count == 32, uuid.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber) }),
              !mid.isEmpty, Self.clean(mid), Int64(userID).map({ $0 > 0 }) == true,
              credentials["token"]?.isEmpty == false, Self.clean(device.model), device.model.count <= 128,
              device.system.range(of: #"^\d+(\.\d+)*$"#, options: .regularExpression) != nil,
              (1...65535).contains(device.width), (1...65535).contains(device.height) else { throw Failure.invalidIdentity }
        let config = configuration ?? .ephemeral
        config.timeoutIntervalForRequest = 15
        config.httpShouldSetCookies = false
        config.httpCookieStorage = nil
        config.httpCookieAcceptPolicy = .never
        session = URLSession(configuration: config)
    }

    func report(event: Event, songID: String, durationMS: Int = 0, completed: Bool = false) async throws {
        guard Int64(songID).map({ $0 > 0 }) == true, durationMS >= 0 else { throw Failure.invalidIdentity }
        do {
            let context = try await context()
            let now = Date()
            let fields = Self.eventData(event: event, songID: songID, durationMS: durationMS, completed: completed,
                uuid: uuid, mid: mid, userID: userID, device: device, now: now, nonce: UUID().uuidString)
            let packet = try Self.packet(eventData: fields, uuid: uuid, mid: mid, userID: userID, device: device, session: context, now: now)
            _ = try await request("/v2/post", query: packet.query, body: packet.body, kind: "Post")
        } catch {
            cipher = nil
            throw error
        }
    }

    private func context() async throws -> CipherSession {
        if let cipher, cipher.expires > Date() { return cipher }
        if let handshake { return try await handshake.value }
        let pending = Task { try await self.openContext() }
        handshake = pending
        defer { handshake = nil }
        let value = try await pending.value
        cipher = value
        return value
    }

    private func openContext() async throws -> CipherSession {
        let now = Date(), seconds = String(Int(now.timeIntervalSince1970))
        let body = try JSONSerialization.data(withJSONObject: ["machine": device.model, "mid": mid, "uuid": uuid,
                                                               "wh": [device.width, device.height]], options: [.sortedKeys, .withoutEscapingSlashes])
        let sign = Self.md5(Data("_t\(seconds)appidand02pbKC7zn{4U*ydo2M1Rir".utf8) + body)
        let deviceResponse = try await request("/v3/qrydid", query: ["appid": "and02", "_t": seconds, "sign": sign], body: body, kind: "Gen")
        guard let data = deviceResponse["data"] as? [String: Any],
              let deviceID = data["deviceid"], !String(describing: deviceID).isEmpty else { throw Failure.invalidEnvelope }
        let field2 = randomField()
        guard field2.utf8.count == 32 else { throw Failure.invalidEnvelope }
        let text = "\(uuid)\t\(field2)\t\(Int64(Date().timeIntervalSince1970 * 1000))\t\(deviceID)"
        let envelope = try Self.rsa(Data(text.utf8)).base64EncodedString()
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let reply = try await request("/v2/gen", query: ["s": envelope, "appid": "3116", "_t": timestamp,
            "sign": Self.md5(Data("_t\(timestamp)appid3116s\(envelope)\(Self.appKey)".utf8))], kind: "Gen")
        guard let encoded = reply["data"] as? String, let encrypted = Data(base64Encoded: encoded),
              let object = try JSONSerialization.jsonObject(with: Self.aes(encrypted, key: field2, iv: String(uuid.prefix(16)), decrypt: true)) as? [String: Any],
              let cookie = object["cookie"] as? String, !cookie.isEmpty,
              let clienttime = object["clienttime"], let serverstr = object["serverstr"] as? String, !serverstr.isEmpty else { throw Failure.invalidEnvelope }
        return .init(cookie: cookie, clienttime: String(describing: clienttime), serverstr: serverstr, field2: field2,
                     expires: Date().addingTimeInterval(30 * 60))
    }

    private func request(_ path: String, query: [String: String], body: Data? = nil, kind: String) async throws -> [String: Any] {
        // CSCC is served by this official HTTP endpoint; the credential envelope
        // is RSA-encrypted and playback payloads are AES-encrypted. Never send
        // the user's token as a URL parameter or add arbitrary Cookie headers.
        var components = URLComponents(string: "http://d.kugou.com\(path)")!
        components.queryItems = query.sorted { $0.key < $1.key }.map { .init(name: $0.key, value: $0.value) }
        components.percentEncodedQuery = components.percentEncodedQuery?.replacingOccurrences(of: "+", with: "%2B")
        guard let url = components.url else { throw Failure.invalidEnvelope }
        var request = URLRequest(url: url)
        request.httpMethod = body == nil ? "GET" : "POST"
        request.httpBody = body
        if body != nil { request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type") }
        if path != "/v3/qrydid" {
            request.setValue("1", forHTTPHeaderField: "KG-Rec")
            request.setValue("Android\(device.system)-1070-\(Self.version)-18-0-Cscc\(kind)-wifi", forHTTPHeaderField: "User-Agent")
        }
        let bytes: Data, response: URLResponse
        do { (bytes, response) = try await session.data(for: request) }
        catch { throw Failure.network(path, (error as NSError).code) }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              let result = (try? JSONSerialization.jsonObject(with: bytes)) as? [String: Any], !result.isEmpty else {
            throw Failure.rejected(path, (response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        func code(_ value: Any?) -> Int? { value.flatMap { Int(String(describing: $0)) } }
        let errorCode = code(result["errcode"] ?? result["error_code"]) ?? 0
        let status = code(result["status"])
        let acknowledged = status == 1 || status == 200 || code(result["errcode"] ?? result["error_code"]) == 0
        guard acknowledged, status != 0, errorCode == 0 else { throw Failure.rejected(path, errorCode) }
        return result
    }

    nonisolated static func eventData(event: Event, songID: String, durationMS: Int, completed: Bool,
                                      uuid: String, mid: String, userID: String, device: Device, now: Date, nonce: String) -> Data {
        var fields = event == .start
            ? ["type_id=20431", "action=play", "spt=0", "sty=手动", "mixsongid=\(songID)", "source=46", "ivar1=1", "fo=Coda"]
            : ["type_id=4", "action=play", "duration=\(durationMS)", "svar3=0", "svar2=0", "fo=Coda", "sty=手动",
               "state=\(completed ? "完整播放" : "中断播放")", "mixsongid=\(songID)", "source=46", "ivar3=0", "type=1", "fs=1.0", "ivar1=1"]
        fields += ["mid=\(mid)", "uuid=\(uuid)", "ss1=1", "ss2=1", "sys=\(device.system)", "mod=\(device.model)", "channelid=18",
                   "ip=0.0.0.0", "net=1", "ver=\(version)", "gitversion=7aa8a76", "time=\(Int64(now.timeIntervalSince1970 * 1000))",
                   "userid=\(userID)", "ss3=\(md5(Data(nonce.utf8)))"]
        return Data(fields.joined(separator: "&").utf8)
    }

    nonisolated static func packet(eventData: Data, uuid: String, mid: String, userID: String, device: Device,
                                   session: CipherSession, now: Date) throws -> (body: Data, query: [String: String]) {
        let line1 = ["4", "1", uuid, "0", "3116", version, "18", device.system, device.model, uuid, mid, "0", String(repeating: "0", count: 36)].joined(separator: "\t")
        let line2 = [String(eventData.count), "10048", "0", String(Int(now.timeIntervalSince1970)), "1", userID, "0", "0"].joined(separator: "\t")
        let plain = Data("\(line1)\r\n\(line2)\r\n".utf8) + (try compress(eventData))
        let key = md5(Data("\(uuid)\(session.clienttime)\(session.field2)\(session.serverstr)".utf8))
        let encrypted = try aes(compress(plain), key: key, iv: String(uuid.prefix(16)))
        var query = ["cookie": session.cookie, "length": String(plain.count), "appid": "3116", "_t": String(Int(now.timeIntervalSince1970))]
        let signed = query.keys.sorted().map { $0 + query[$0]! }.joined() + appKey
        query["sign"] = md5(Data(signed.utf8) + encrypted)
        return (encrypted, query)
    }

    nonisolated static func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    nonisolated static func compress(_ input: Data) throws -> Data {
        var length = compressBound(uLong(input.count))
        var output = Data(count: Int(length))
        let result = output.withUnsafeMutableBytes { dst in
            input.withUnsafeBytes { src in compress2(dst.bindMemory(to: Bytef.self).baseAddress!, &length,
                src.bindMemory(to: Bytef.self).baseAddress!, uLong(input.count), Z_DEFAULT_COMPRESSION) }
        }
        guard result == Z_OK else { throw Failure.invalidEnvelope }
        output.count = Int(length)
        return output
    }
    nonisolated static func aes(_ data: Data, key: String, iv: String, decrypt: Bool = false) throws -> Data {
        let key = Data(key.utf8), iv = Data(iv.utf8)
        guard key.count == 32, iv.count == 16 else { throw Failure.invalidEnvelope }
        var result = Data(count: data.count + kCCBlockSizeAES128), size = 0
        let capacity = result.count
        let status = result.withUnsafeMutableBytes { dst in data.withUnsafeBytes { src in key.withUnsafeBytes { k in iv.withUnsafeBytes { v in
            CCCrypt(CCOperation(decrypt ? kCCDecrypt : kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                    k.baseAddress, k.count, v.baseAddress, src.baseAddress, data.count, dst.baseAddress, capacity, &size)
        } } } }
        guard status == kCCSuccess else { throw Failure.invalidEnvelope }
        result.count = size
        return result
    }
    nonisolated private static func rsa(_ data: Data) throws -> Data {
        guard let bytes = Data(base64Encoded: publicKey),
              let key = SecKeyCreateWithData(bytes as CFData, [kSecAttrKeyType: kSecAttrKeyTypeRSA, kSecAttrKeyClass: kSecAttrKeyClassPublic] as CFDictionary, nil),
              let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionPKCS1, data as CFData, nil) else { throw Failure.invalidEnvelope }
        return encrypted as Data
    }
    nonisolated private static func clean(_ text: String) -> Bool {
        !text.isEmpty && !text.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) || $0 == "&" }
    }
}
