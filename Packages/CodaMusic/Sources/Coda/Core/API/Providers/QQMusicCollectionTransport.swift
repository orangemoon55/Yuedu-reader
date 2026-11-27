// Collection transport adapted from yakult-green-tea/qq-music-api (MIT).
// See ThirdPartyNotices/QQMusicProtocolReferences.md.
import CommonCrypto
import CryptoKit
import Foundation
import Security

struct QQMusicCollectionCredential: Equatable {
    let id: String
    let key: String
    let loginType: Int
    let encryptedID: String

    func matchesLogin(_ other: Self) -> Bool {
        id == other.id && key == other.key && loginType == other.loginType
    }

    var cookie: String {
        "uin=\(id); qqmusic_uin=\(id); qm_keyst=\(key); qqmusic_key=\(key)"
    }

    var albumStatusOwner: Any {
        if let value = Int(id), value <= 9_007_199_254_740_991 { return value }
        return id
    }
}

/// QQ rejected the saved login (1000 / 104400 / 104401 on musicu, 4000 on the web fcgi endpoints).
enum QQMusicSessionError: LocalizedError {
    case expired

    static func isExpiredCode(_ code: Int) -> Bool { [1000, 4000, 104400, 104401].contains(code) }

    var errorDescription: String? { "QQ 音乐登录已过期，请重新扫码登录" }
}

actor QQMusicCollectionTransport {
    private let session: URLSession
    private let defaults: UserDefaults?
    private let defaultsKey = "qq.collection-device.v1"
    private var device: Device
    private var bootstrap: Task<Device, Error>?

    init(configuration: URLSessionConfiguration, persistDevice: Bool) {
        defaults = persistDevice ? .standard : nil
        if let data = defaults?.data(forKey: defaultsKey), let saved = try? JSONDecoder().decode(Device.self, from: data) {
            device = saved
        } else {
            device = Device()
        }
        session = URLSession(configuration: configuration, delegate: ProviderNoRedirectDelegate(), delegateQueue: nil)
    }

    func call(_ module: String, _ method: String, _ param: [String: Any], credential: QQMusicCollectionCredential,
              isCurrent: () -> Bool) async throws -> [String: Any] {
        let device = try await readyDevice()
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        return try await Self.rpc(session, device: device, module: module, method: method, param: param, credential: credential)
    }

    func loginCall(_ method: String, params: [String: Any], comm: [String: Any] = [:],
                   credential: QQMusicCollectionCredential? = nil) async throws -> [String: Any] {
        let device = try await readyDevice()
        try Task.checkCancellation()
        return try await Self.rpc(session, device: device, module: "music.login.LoginServer", method: method,
                                  param: params, credential: credential, overrides: comm)
    }

    func webArtistCall(_ method: String, params: [String: Any], credential: QQMusicCollectionCredential,
                       webCookie: String, legacyToken: Int, isCurrent: () -> Bool) async throws -> [String: Any] {
        let owner: Any = credential.id.count < 14 ? (Int(credential.id) ?? 0) as Any : credential.id
        let comm: [String: Any] = [
            "cv": 4747474, "ct": 24, "format": "json", "inCharset": "utf-8", "outCharset": "utf-8",
            "notice": 0, "platform": "yqq.json", "needNewCode": 1, "uin": owner,
            "g_tk": legacyToken, "g_tk_new_20200303": QQMusicAuth.hash5381(credential.key)
        ]
        let body = try JSONSerialization.data(withJSONObject: [
            "comm": comm, "req_0": ["module": "Concern.ConcernSystemServer", "method": method, "param": params]
        ])
        // Website zzc/ag-1 envelope. The transport key is the published protocol constant.
        let key = SymmetricKey(data: Data([189, 48, 95, 16, 208, 255, 116, 182, 239, 84, 218, 184, 53, 181, 225, 207]))
        let encrypted = try AES.GCM.seal(body, using: key)
        guard let ciphertext = encrypted.combined else { throw ProviderRequestError.decoding("QQ Music web request") }
        var url = URLComponents(string: "https://u6.y.qq.com/cgi-bin/musics.fcg")!
        url.queryItems = [
            URLQueryItem(name: "_", value: String(Int(Date().timeIntervalSince1970 * 1000))),
            URLQueryItem(name: "encoding", value: "ag-1"),
            URLQueryItem(name: "sign", value: Self.webSignature(body))
        ]
        var request = URLRequest(url: url.url!, timeoutInterval: 15)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("https://y.qq.com", forHTTPHeaderField: "Origin")
        request.setValue("https://y.qq.com/", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue(webCookie, forHTTPHeaderField: "Cookie")
        request.httpBody = ciphertext.base64EncodedData()
        try Task.checkCancellation()
        guard isCurrent() else { throw CancellationError() }
        let (bytes, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw ProviderRequestError.network
        }
        let mask: [UInt8] = [122, 63, 140, 29, 94, 155, 47, 10, 108, 77, 126, 139, 31, 58, 92, 157, 14, 43, 111, 74, 129]
        let decoded = Data(bytes.enumerated().map { $0.element ^ mask[$0.offset % mask.count] })
        return try Self.unpack(decoded, method: method)
    }

    private static func webSignature(_ body: Data) -> String {
        let digest = Array(Insecure.SHA1.hash(data: body))
        let hex = Array(digest.map { String(format: "%02X", $0) }.joined())
        let prefix = String([23, 14, 6, 36, 16, 7, 19].map { hex[$0] })
        let suffix = String([16, 1, 32, 12, 19, 27, 8, 5].map { hex[$0] })
        let mask: [UInt8] = [89, 39, 179, 150, 218, 82, 58, 252, 177, 52, 186, 123, 120, 64, 242, 133, 143, 161, 121, 179]
        let middle = Data(zip(digest, mask).map { $0 ^ $1 }).base64EncodedString().filter { !"/+=".contains($0) }
        return ("zzc" + prefix + middle + suffix).lowercased()
    }

    private func readyDevice() async throws -> Device {
        if let bootstrap { return try await bootstrap.value }
        if let expires = device.qimeiExpiry, expires > Date(), device.sid != nil { return device }

        // Persist the same installation identity even when the bootstrap fails.
        defaults?.set(try? JSONEncoder().encode(device), forKey: defaultsKey)
        let task = Task { [session, device] in
            var device = device
            if (device.qimeiExpiry ?? .distantPast) <= Date() {
                do {
                    try await Self.fetchQIMEI(session, device: &device, at: Date())
                } catch let error as QimeiClockError {
                    try await Self.fetchQIMEI(session, device: &device, at: error.serverTime)
                }
            }
            let data = try await Self.rpc(session, device: device, module: "music.getSession.session",
                                          method: "GetSession", param: ["uid": device.uid ?? "", "vkey": 0, "caller": 0])
            let info = data["session"] as? [String: Any]
            guard let uid = Self.identifier(info?["uid"]), let sid = Self.identifier(info?["sid"]) else {
                throw ProviderRequestError.decoding("QQ Music GetSession")
            }
            device.uid = uid
            device.sid = sid
            return device
        }
        bootstrap = task
        defer { bootstrap = nil }
        let ready = try await task.value
        device = ready
        defaults?.set(try? JSONEncoder().encode(ready), forKey: defaultsKey)
        return ready
    }

    private struct Device: Codable {
        let openID: String
        let androidID: String
        let fingerprint: String
        let imei: String
        let kernel: String
        var qimei: String?
        var qimei36: String?
        var qimeiExpiry: Date?
        var uid: String?
        var sid: String?

        init() {
            openID = QQMusicCollectionTransport.randomHex(32)
            androidID = QQMusicCollectionTransport.randomHex(16)
            fingerprint = "xiaomi/iarim/sagit:10/eomam.200122.001/\(Int.random(in: 1_000_000...9_999_999)):user/release-keys"
            let digits = (0..<14).map { _ in Int.random(in: 0...9) }
            let sum = digits.enumerated().reduce(0) { total, entry in
                let value = entry.offset.isMultiple(of: 2) ? entry.element : entry.element * 2
                return total + (value > 9 ? value - 9 : value)
            }
            imei = (digits + [(10 - sum % 10) % 10]).map(String.init).joined()
            kernel = "Linux 5.4.0-54-generic-\(QQMusicCollectionTransport.randomHex(8)) (android-build@google.com)"
        }

        var comm: [String: Any] {
            var fields: [String: Any] = [
                "ct": 11, "cv": 14090008, "v": 14090008, "chid": "10003505", "tmeAppID": "qqmusic",
                "QIMEI": qimei ?? "", "QIMEI36": qimei36 ?? "", "OpenUDID": openID,
                "udid": openID, "OpenUDID2": openID, "aid": androidID, "os_ver": "10",
                "phonetype": "MI 6", "devicelevel": "29", "newdevicelevel": "29", "rom": fingerprint
            ]
            fields["uid"] = uid
            fields["sid"] = sid
            return fields
        }
    }

    private static func rpc(_ session: URLSession, device: Device, module: String, method: String,
                            param: [String: Any], credential: QQMusicCollectionCredential? = nil,
                            overrides: [String: Any] = [:]) async throws -> [String: Any] {
        var comm = device.comm
        var request = URLRequest(url: URL(string: "https://u.y.qq.com/cgi-bin/musicu.fcg")!, timeoutInterval: 25)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("QQMusic 14090008(android 10)", forHTTPHeaderField: "User-Agent")
        if let credential {
            comm["qq"] = credential.id
            comm["authst"] = credential.key
            comm["tmeLoginType"] = credential.loginType
            request.setValue(credential.cookie, forHTTPHeaderField: "Cookie")
        }
        comm.merge(overrides) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "comm": comm, "req_0": ["module": module, "method": method, "param": param]
        ])
        let (bytes, response) = try await session.data(for: request)
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw ProviderRequestError.network
        }
        return try unpack(bytes, method: method)
    }

    private static func unpack(_ bytes: Data, method: String) throws -> [String: Any] {
        // QQ sometimes sends invalid UTF-8 in text fields. Keep the envelope and business codes strict.
        guard let json = dictionary(bytes) ?? dictionary(String(decoding: bytes, as: UTF8.self)) else {
            throw ProviderRequestError.decoding("QQ Music \(method)")
        }
        try checkCode(json["code"], method: method)
        guard let block = json["req_0"] as? [String: Any] else { throw ProviderRequestError.decoding("QQ Music \(method)") }
        try checkCode(block["code"], method: method)
        if let subcode = block["subcode"] { try checkCode(subcode, method: method) }
        guard let data = block["data"] as? [String: Any] else { throw ProviderRequestError.decoding("QQ Music \(method)") }
        return data
    }

    private static func checkCode(_ value: Any?, method: String) throws {
        guard let code = value as? Int else { throw ProviderRequestError.decoding("QQ Music \(method)") }
        if QQMusicSessionError.isExpiredCode(code) { throw QQMusicSessionError.expired }
        guard code == 0 else { throw ProviderRequestError.unknown("QQ 音乐 \(method) 失败（\(code)）") }
    }

    private struct QimeiClockError: Error { let serverTime: Date }

    private static func fetchQIMEI(_ session: URLSession, device: inout Device, at date: Date) async throws {
        let timestamp = Int(date.timeIntervalSince1970)
        let appKey = "0AND0HD6FE4HY80F"
        let key = randomHex(16)
        let nonce = randomHex(16)
        let extra = "{\"appKey\":\"\(appKey)\"}"
        let utc = ISO8601DateFormatter()
        let month = String(utc.string(from: date).prefix(7))
        let beaconDate = "\(month)-01\(Int.random(in: 100_000...999_999)).\(Int.random(in: 100_000_000...999_999_999))"
        let dated: Set = [1, 2, 13, 14, 17, 18, 21, 22, 25, 26, 29, 30, 33, 34, 37, 38]
        let beacon = (1...40).map { index -> String in
            let value: String
            switch index {
            case 3: value = "0000000000000000"
            case 4: value = randomHex(16).replacingOccurrences(of: "0", with: "1")
            case _ where dated.contains(index): value = beaconDate
            default: value = String(Int.random(in: 0..<10_000))
            }
            return "k\(index):\(value);"
        }.joined()
        let uptime = utc.string(from: date.addingTimeInterval(-Double.random(in: 0...14_400)))
            .replacingOccurrences(of: "T", with: " ").prefix(19)
        let reserved = try JSONSerialization.data(withJSONObject: [
            "harmony": "0", "clone": "0", "containe": "", "oz": "UhYmelwouA+V2nPWbOvLTgN2/m8jwGB+yUB5v9tysQg=",
            "oo": "Xecjt+9S1+f8Pz2VLSxgpw==", "kelong": "0", "uptimes": String(uptime), "multiUser": "0",
            "bod": "Xiaomi", "dv": "sagit", "firstLevel": "", "manufact": "Xiaomi", "name": "MI 6",
            "host": "se.infra", "kernel": device.kernel
        ])
        let payload = try JSONSerialization.data(withJSONObject: [
            "androidId": device.androidID, "platformId": 1, "appKey": appKey, "appVersion": "14.9.0.8",
            "beaconIdSrc": beacon, "brand": "Xiaomi", "channelId": "10003505", "cid": "", "imei": device.imei,
            "imsi": "", "mac": "", "model": "MI 6", "networkType": "unknown", "oaid": "",
            "osVersion": "Android 10,level 29", "qimei": "", "qimei36": "", "sdkVersion": "1.2.13.6",
            "targetSdkVersion": "33", "audit": "", "userId": "{}", "packageId": "com.tencent.qqmusic",
            "deviceType": "Phone", "sdkName": "", "reserved": String(decoding: reserved, as: UTF8.self)
        ])
        let wrappedKey = try encryptKey(Data(key.utf8)).base64EncodedString()
        let params = try encryptPayload(payload, key: Data(key.utf8)).base64EncodedString()
        var request = URLRequest(url: URL(string: "https://api.tencentmusic.com/tme/trpc/proxy")!, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("GetQimei", forHTTPHeaderField: "method")
        request.setValue("trpc.tme_datasvr.qimeiproxy.QimeiProxy", forHTTPHeaderField: "service")
        request.setValue("qimei_qq_android", forHTTPHeaderField: "appid")
        request.setValue(md5("qimei_qq_androidpzAuCmaFAaFaHrdakPjLIEqKrGnSOOvH" + String(timestamp)), forHTTPHeaderField: "sign")
        request.setValue("QQMusic", forHTTPHeaderField: "User-Agent")
        request.setValue(String(timestamp), forHTTPHeaderField: "timestamp")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "app": 0, "os": 1, "qimeiParams": [
                "key": wrappedKey, "params": params, "time": String(timestamp), "nonce": nonce,
                "sign": md5(wrappedKey + params + String(timestamp * 1000) + nonce + "ZdJqM15EeO2zWc08" + extra),
                "extra": extra
            ]
        ])
        let (bytes, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let outer = dictionary(bytes)
        let inner = dictionary(outer?["data"])
        let data = inner?["data"] as? [String: Any]
        guard http?.statusCode == 200, let q16 = identifier(data?["q16"]), let q36 = identifier(data?["q36"]) else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let header = http?.value(forHTTPHeaderField: "Date"), let serverTime = formatter.date(from: header),
               abs(serverTime.timeIntervalSince(date)) > 300 {
                throw QimeiClockError(serverTime: serverTime)
            }
            let code = identifier(inner?["code"]) ?? identifier(outer?["code"]) ?? String(http?.statusCode ?? 0)
            throw ProviderRequestError.unknown("QQ 音乐设备验证失败（\(code)）")
        }
        device.qimei = q16
        device.qimei36 = q36
        device.qimeiExpiry = Date().addingTimeInterval(86_400)
    }

    private static func encryptKey(_ key: Data) throws -> Data {
        // PKCS#1 DER form of the upstream bootstrap public key.
        let der = Data(base64Encoded: "MIGJAoGBAMQjGDCi61/CgnFwZB552A/sUb2poi5LSrN9HyBaSuRNkozaJYefZqNCkFFmMxKhJ/r4oka9qvY5GEF+kNfJW1kIqmotD4UuSmdwKUpUisHC/o8fJS+4JvSshquaAOfOR9ACpW58S1HriJrMYMpq28n3LoH00xsd10ZIBSZFMKsdAgMBAAE=")!
        let attributes: [String: Any] = [kSecAttrKeyType as String: kSecAttrKeyTypeRSA, kSecAttrKeyClass as String: kSecAttrKeyClassPublic]
        guard let publicKey = SecKeyCreateWithData(der as CFData, attributes as CFDictionary, nil),
              let wrapped = SecKeyCreateEncryptedData(publicKey, .rsaEncryptionPKCS1, key as CFData, nil) else {
            throw ProviderRequestError.unknown("QQ 音乐设备密钥加密失败")
        }
        return wrapped as Data
    }

    private static func encryptPayload(_ payload: Data, key: Data) throws -> Data {
        var encrypted = Data(count: payload.count + kCCBlockSizeAES128)
        var length = 0
        let status = encrypted.withUnsafeMutableBytes { output in
            key.withUnsafeBytes { material in
                payload.withUnsafeBytes { input in
                    CCCrypt(CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), CCOptions(kCCOptionPKCS7Padding),
                            material.baseAddress, key.count, material.baseAddress, input.baseAddress, payload.count,
                            output.baseAddress, output.count, &length)
                }
            }
        }
        guard status == kCCSuccess else { throw ProviderRequestError.unknown("QQ 音乐设备请求加密失败") }
        return encrypted.prefix(length)
    }

    private static func randomHex(_ count: Int) -> String {
        let alphabet = Array("0123456789abcdef")
        return String((0..<count).map { _ in alphabet[Int.random(in: 0..<alphabet.count)] })
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func identifier(_ value: Any?) -> String? {
        let text = (value as? String) ?? (value as? NSNumber)?.stringValue ?? ""
        return text.isEmpty ? nil : text
    }

    private static func dictionary(_ value: Any?) -> [String: Any]? {
        if let object = value as? [String: Any] { return object }
        guard let data = (value as? Data) ?? (value as? String).map({ Data($0.utf8) }) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}
