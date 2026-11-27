// NCBL wire format adapted from NeteaseCloudMusicApiEnhanced/api-enhanced
// 984cc021 (MIT). See ThirdPartyNotices/NeteasePlaybackLog.md.
import Foundation
import Security

/// The clientlog upload protocol is independent of WEAPI/EAPI. Keep its
/// cryptography and framing isolated from account and music requests.
enum NeteasePlaybackLog {
    enum EncodingError: Error { case invalidInput, randomness }

    struct Song: Sendable {
        let id: Int
        let sourceID: Int
        let duration: Int
        let quality: String?
        let fee: Int
        // Desktop log bitrate uses kbps; unknown values stay omitted.
        var bitrate: Int? = nil
    }

    enum Event: String { case start = "_plv", finish = "_pld" }

    struct Upload {
        let request: URLRequest
        let filename: String
    }

    static func upload(song: Song, event: Event, seconds: Int, completed: Bool,
                       cookies: [String: String], deviceID: String, now: Date = .now) throws -> Upload {
        guard song.id > 0, cookies["MUSIC_U"]?.isEmpty == false else { throw EncodingError.invalidInput }
        let version = "3.1.35"
        let millis = Int64(now.timeIntervalSince1970 * 1000)
        // Use one consistent PC profile in both encrypted metadata and Cookie.
        // Never mix an imported iOS appver with the desktop log protocol.
        let metadata: [String: String] = [
            "JSESSIONID-WYYY": cookies["JSESSIONID-WYYY"] ?? "",
            "MUSIC_U": cookies["MUSIC_U"]!, "__csrf": cookies["__csrf"] ?? "",
            "NMTID": cookies["NMTID"] ?? "", "WEVNSM": "1.0.0",
            "WNMCID": cookies["WNMCID"] ?? "\(deviceID.prefix(6).lowercased()).\(millis).01.0",
            "_iuqxldmzr_": "33", "_ntes_nnid": cookies["_ntes_nnid"] ?? ",",
            "_ntes_nuid": cookies["_ntes_nuid"] ?? "",
            "appver": "\(version).205293", "channel": "netease",
            "clientSign": cookies["clientSign"] ?? "", "deviceId": deviceID,
            "mode": "", "ntes_kaola_ad": "1", "os": "pc",
            "osver": "Microsoft-Windows-10-Professional-build-19045-64bit",
        ]
        let record = try record(song: song, event: event, seconds: seconds, completed: completed, now: now,
                                vipType: cookies["vipType"] ?? "")
        let packet = try encode(metadata: JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]), body: record)
        let filename = "op_\(Int.random(in: 10000...99999))_0_\(UInt32.random(in: 1...UInt32.max))"
        let boundary = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var body = Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: multipart/form-data\r\n\r\n".utf8)
        body.append(packet)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://clientlog3.music.163.com/api/clientlog/encrypt/upload?multiupload=true")!)
        request.httpMethod = "POST"
        request.httpShouldHandleCookies = false
        request.timeoutInterval = 15
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("https://music.163.com/di", forHTTPHeaderField: "Referer")
        request.setValue("Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Safari/537.36 Chrome/91.0.4472.164 NeteaseMusicDesktop/\(version)", forHTTPHeaderField: "User-Agent")
        request.setValue("zh-CN,zh;q=0.8", forHTTPHeaderField: "Accept-Language")
        var headerCookies = metadata
        headerCookies["__remember_me"] = "true"
        request.setValue(headerCookies.keys.sorted().map { "\($0)=\(headerCookies[$0]!)" }.joined(separator: "; "), forHTTPHeaderField: "Cookie")
        request.httpBody = body
        return Upload(request: request, filename: filename)
    }

    static func record(song: Song, event: Event, seconds: Int, completed: Bool, now: Date,
                       vipType: String = "") throws -> Data {
        var fields: [String: Any] = [
            "mode": "circulation", "download": 0, "alg": "", "status": "front",
            "id": String(song.id), "type": "song", "is_listentogether": 0,
            "source": "list", "is_heart": 0, "resource_ratio": "",
            "resource_time": max(0, song.duration), "musiceffect_id": "", "app_mode": event == .start ? 2 : 1,
            "vipType": vipType, "fee": song.fee,
            "file": 4, "rightSource": 0, "sourceId": String(song.sourceID),
            "sourcetype": "track", "libra_abt": "", "channel": "netease", "curStartChannel": "",
        ]
        // Do not invent bitrate, membership, source referrals or listening time.
        if let quality = song.quality { fields["bitrate_level"] = quality }
        if let bitrate = song.bitrate, bitrate > 0 { fields["bitrate"] = bitrate }
        if event == .finish {
            let elapsed = song.duration > 0 ? min(max(0, seconds), song.duration) : max(0, seconds)
            fields["time"] = elapsed
            fields["realtime"] = elapsed
            fields["end"] = completed ? "playend" : "interrupt"
        }
        let json = try JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys])
        return Data("\(Int64(now.timeIntervalSince1970))\u{01}\(event.rawValue)\u{01}".utf8) + json
    }

    /// Fixed entropy parameters are internal test seams for independent vectors.
    static func encode(metadata: Data, body: Data, key: Data? = nil, uuid: Data? = nil,
                       sequence: UInt16? = nil, compressedBody: Data? = nil) throws -> Data {
        var key = try key ?? random(count: 32)
        guard key.count == 32, metadata.count <= Int(UInt16.max) - 74,
              body.count <= 1_048_576 else { throw EncodingError.invalidInput }
        if key[0] >= 0xa3 { key[0] = 0xa2 }
        var identifier = try uuid ?? random(count: 16)
        guard identifier.count == 16 else { throw EncodingError.invalidInput }
        if uuid == nil {
            identifier[6] = (identifier[6] & 0x0f) | 0x40
            identifier[8] = (identifier[8] & 0x3f) | 0x80
        }
        let base = try sequence ?? UInt16(little32(try random(count: 4), 0) & 0xffff)
        let wrapped = rsaWrap(key)
        let counter = little32(identifier, 12) >> 2
        let nonce = Data(identifier.prefix(12))
        let encryptedMetadata = chacha20(metadata, key: wrapped, nonce: nonce, counter: counter)
        let compressed = compressedBody ?? zstdFrame(body)
        var frames = Data()
        var count: UInt32 = 0
        for offset in stride(from: 0, to: compressed.count, by: 0x8000) {
            let slice = Data(compressed[offset..<min(offset + 0x8000, compressed.count)])
            let cipher = chacha20(slice, key: key, nonce: nonce, counter: counter)
            frames.appendLE(UInt16(cipher.count))
            frames.appendLE(UInt32(base) + count)
            frames.append(cipher)
            count += 1
        }
        var packet = Data("NCBL".utf8)
        packet.appendLE(UInt32(3))
        packet.appendLE(UInt16(74 + metadata.count))
        packet.append(identifier)
        packet.append(wrapped)
        packet.appendLE(UInt32(base))
        packet.appendLE(UInt32(base) + count - 1)
        packet.appendLE(UInt32(frames.count))
        packet.appendLE(UInt16(0x4343))
        packet.appendLE(UInt16(encryptedMetadata.count))
        packet.append(encryptedMetadata)
        packet.append(frames)
        return packet
    }

    private static func random(count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        guard SecRandomCopyBytes(kSecRandomDefault, count, &bytes) == errSecSuccess else { throw EncodingError.randomness }
        return Data(bytes)
    }

    /// Standards-compliant Zstandard frame using raw blocks. These small logs
    /// do not need entropy compression; raw Zstd avoids a bundled compressor
    /// while preserving the format expected by NCBL's ingestion pipeline.
    /// Descriptor: single segment, 4-byte content size, no dictionary/checksum.
    static func zstdFrame(_ data: Data) -> Data {
        precondition(data.count <= 1_048_576)
        var output = Data([0x28, 0xb5, 0x2f, 0xfd, 0xa0])
        output.appendLE(UInt32(data.count))
        var offset = 0
        repeat {
            let count = min(128 * 1024, data.count - offset)
            let last = offset + count == data.count
            let block = UInt32(count) << 3 | (last ? 1 : 0)
            output.append(contentsOf: (0..<3).map { UInt8(truncatingIfNeeded: block >> ($0 * 8)) })
            output.append(data[offset..<(offset + count)])
            offset += count
            if last { break }
        } while offset < data.count
        return output
    }

    static func little32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }

    static func chacha20(_ data: Data, key: Data, nonce: Data, counter: UInt32) -> Data {
        precondition(key.count == 32 && nonce.count == 12)
        func rotate(_ value: UInt32, _ bits: UInt32) -> UInt32 { (value << bits) | (value >> (32 - bits)) }
        func round(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
            s[a] = s[a] &+ s[b]; s[d] = rotate(s[d] ^ s[a], 16)
            s[c] = s[c] &+ s[d]; s[b] = rotate(s[b] ^ s[c], 12)
            s[a] = s[a] &+ s[b]; s[d] = rotate(s[d] ^ s[a], 8)
            s[c] = s[c] &+ s[d]; s[b] = rotate(s[b] ^ s[c], 7)
        }
        var output = [UInt8](repeating: 0, count: data.count)
        let input = [UInt8](data)
        for offset in stride(from: 0, to: data.count, by: 64) {
            let state: [UInt32] = [0x61707865, 0x3320646e, 0x79622d32, 0x6b206574]
                + stride(from: 0, to: 32, by: 4).map { little32(key, $0) }
                + [counter &+ UInt32(offset / 64)] + [0, 4, 8].map { little32(nonce, $0) }
            var work = state
            for _ in 0..<10 {
                round(&work, 0, 4, 8, 12); round(&work, 1, 5, 9, 13)
                round(&work, 2, 6, 10, 14); round(&work, 3, 7, 11, 15)
                round(&work, 0, 5, 10, 15); round(&work, 1, 6, 11, 12)
                round(&work, 2, 7, 8, 13); round(&work, 3, 4, 9, 14)
            }
            for i in 0..<min(64, data.count - offset) {
                let word = work[i / 4] &+ state[i / 4]
                output[offset + i] = input[offset + i] ^ UInt8(truncatingIfNeeded: word >> ((i % 4) * 8))
            }
        }
        return Data(output)
    }

    /// Fixed 256-bit modulus, exponent 65537. Small limb arithmetic avoids
    /// adding a general BigInt dependency or relying on unsupported RSA sizes.
    static func rsaWrap(_ key: Data) -> Data {
        precondition(key.count == 32 && key[0] < 0xa3)
        let modulus: [UInt32] = [0x5cb4139d, 0x89b31c1d, 0xfa5d7aab, 0x5c564879,
                                  0xf263b90d, 0x3fec2fbc, 0x6ff9bc8a, 0xfd90bd46]
        func add(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
            var sum = [UInt32](repeating: 0, count: 8)
            var carry: UInt64 = 0
            for i in 0..<8 {
                let value = UInt64(a[i]) + UInt64(b[i]) + carry
                sum[i] = UInt32(truncatingIfNeeded: value); carry = value >> 32
            }
            let greater = (0..<8).reversed().first(where: { sum[$0] != modulus[$0] }).map { sum[$0] > modulus[$0] } ?? true
            if carry != 0 || greater {
                var borrow: UInt64 = 0
                for i in 0..<8 {
                    let rhs = UInt64(modulus[i]) + borrow
                    let lhs = UInt64(sum[i])
                    sum[i] = UInt32(truncatingIfNeeded: lhs &- rhs); borrow = lhs < rhs ? 1 : 0
                }
            }
            return sum
        }
        func multiply(_ a: [UInt32], _ b: [UInt32]) -> [UInt32] {
            var result = [UInt32](repeating: 0, count: 8)
            var value = a
            for bit in 0..<256 {
                if b[bit / 32] & (UInt32(1) << (bit % 32)) != 0 { result = add(result, value) }
                value = add(value, value)
            }
            return result
        }
        let bytes = Data(key.reversed())
        let base = stride(from: 0, to: 32, by: 4).map { little32(bytes, $0) }
        var value = base
        for _ in 0..<16 { value = multiply(value, value) }
        value = multiply(value, base)
        var output = Data()
        for word in value.reversed() {
            for shift in [24, 16, 8, 0] { output.append(UInt8(truncatingIfNeeded: word >> shift)) }
        }
        return output
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ integer: T) {
        var little = integer.littleEndian
        Swift.withUnsafeBytes(of: &little) { append(contentsOf: $0) }
    }
}
