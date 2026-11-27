// SPDX-License-Identifier: AGPL-3.0-or-later
// Swift adaptation of libresoda 5edd2ff, src/soda/crypto.rs (AGPL-3.0-or-later).
// Attribution and corresponding source are listed in ThirdPartyNotices/Qishui-API.md.
import CommonCrypto
import Foundation

enum QishuiAudio {
    static let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Coda-Qishui-Audio", isDirectory: true)

    static func localURL(_ url: URL) -> URL? {
        let path = url.standardizedFileURL
        guard url.isFileURL, path.deletingLastPathComponent().path == directory.standardizedFileURL.path,
              path.pathExtension == "m4a", path.deletingPathExtension().lastPathComponent.count == 64 else { return nil }
        return path
    }

    static func key(from playAuth: String) throws -> Data {
        guard let data = Data(base64Encoded: playAuth.trimmingCharacters(in: .whitespacesAndNewlines)), data.count >= 3 else {
            throw QishuiError.encryptedAudio
        }
        let padding = Int(data[0] ^ data[1] ^ data[2]) - 48
        guard padding >= 0, padding <= data.count - 2 else { throw QishuiError.encryptedAudio }
        let encoded = Array(data[1..<(data.count - padding)])
        let prefix: [UInt8] = [0xfa, 0x55]
        let decoded = encoded.enumerated().map { index, byte in
            let previous = index < 2 ? prefix[index] : encoded[index - 2]
            let value = Int(byte ^ previous) - index.nonzeroBitCount - 21
            return UInt8(value < 0 ? value + 255 : value)
        }
        guard let skip = Int(String(UnicodeScalar(decoded[0])), radix: 36),
              decoded.count - skip == 33 else { throw QishuiError.encryptedAudio }
        let hex = String(decoding: decoded[1..<33], as: UTF8.self)
        guard hex.utf8.count == 32, hex.utf8.allSatisfy({ $0 < 128 }) else { throw QishuiError.encryptedAudio }
        let digits = Array(hex)
        var key = Data()
        for offset in stride(from: 0, to: 32, by: 2) {
            guard let value = UInt8(String(digits[offset...offset + 1]), radix: 16) else { throw QishuiError.encryptedAudio }
            key.append(value)
        }
        return key
    }

    private struct Box {
        let type: String
        let start: Int
        let payload: Range<Int>
        var end: Int { payload.upperBound }
    }

    private static func read(_ bytes: Data, _ offset: Int, _ count: Int = 4) -> UInt64 {
        bytes[offset..<offset + count].reduce(0) { ($0 << 8) | UInt64($1) }
    }

    private static func boxes(in bytes: Data, range: Range<Int>) throws -> [Box] {
        var boxes: [Box] = []
        var cursor = range.lowerBound
        while cursor < range.upperBound {
            let remaining = range.upperBound - cursor
            guard remaining >= 8, boxes.count < 8192 else { throw QishuiError.encryptedAudio }
            var size = read(bytes, cursor)
            let header = size == 1 ? 16 : 8
            if size == 1 {
                guard remaining >= header else { throw QishuiError.encryptedAudio }
                size = read(bytes, cursor + 8, 8)
            } else if size == 0 {
                size = UInt64(remaining)
            }
            guard size >= header, size <= remaining else { throw QishuiError.encryptedAudio }
            let end = cursor + Int(size)
            let type = String(decoding: bytes[cursor + 4..<cursor + 8], as: UTF8.self)
            boxes.append(.init(type: type, start: cursor, payload: cursor + header..<end))
            cursor = end
        }
        return boxes
    }

    private static func sampleTable(in bytes: Data, movie: Box) throws -> Box {
        var current = movie
        for type in ["trak", "mdia", "minf", "stbl"] {
            guard let box = try boxes(in: bytes, range: current.payload).first(where: { $0.type == type }) else {
                throw QishuiError.encryptedAudio
            }
            current = box
        }
        return current
    }

    /// Bytes from the start of the file that hold `ftyp` and the whole `moov`,
    /// or nil while more are needed. Qishui files are fast-start: `moov` sits
    /// before `mdat` and is not encrypted.
    static func headerLength(_ bytes: Data) -> Int? {
        var cursor = 0
        while cursor + 8 <= bytes.count {
            var size = Int(read(bytes, bytes.startIndex + cursor))
            let type = String(decoding: bytes[(bytes.startIndex + cursor + 4)..<(bytes.startIndex + cursor + 8)], as: UTF8.self)
            if size == 1, cursor + 16 <= bytes.count { size = Int(read(bytes, bytes.startIndex + cursor + 8, 8)) }
            guard size >= 8 else { return nil }
            if type == "moov" { return cursor + size }
            if type == "mdat" { return nil }
            cursor += size
        }
        return nil
    }

    /// The tier of the audio described by a file's header (`ftyp` + `moov`),
    /// read from the protected sample entry's original format and its codec
    /// configuration. Nil when the header does not say (lossy or unknown codecs).
    static func headerTier(_ header: Data) -> AudioQuality? {
        guard let length = headerLength(header) else { return nil }
        let bytes = Data(header.prefix(length))
        guard let movie = try? boxes(in: bytes, range: 0..<bytes.count).first(where: { $0.type == "moov" }),
              let table = try? sampleTable(in: bytes, movie: movie),
              let description = try? boxes(in: bytes, range: table.payload).first(where: { $0.type == "stsd" }),
              description.payload.count >= 8,
              let entry = try? boxes(in: bytes, range: description.payload.lowerBound + 8..<description.end).first,
              entry.payload.count >= 28,
              let children = try? boxes(in: bytes, range: entry.payload.lowerBound + 28..<entry.end) else { return nil }
        let protection = children.first { $0.type == "sinf" }
        let protectionChildren = protection.flatMap { try? boxes(in: bytes, range: $0.payload) } ?? []
        let original = (protectionChildren.first { $0.type == "frma" && $0.payload.count >= 4 })
            .map { String(decoding: bytes[$0.payload.lowerBound..<$0.payload.lowerBound + 4], as: UTF8.self) } ?? entry.type
        switch original {
        case "fLaC":
            // dfLa: full box header, then FLAC metadata blocks starting with STREAMINFO.
            guard let config = children.first(where: { $0.type == "dfLa" }), config.payload.count >= 4 + 4 + 34 else { return nil }
            let info = config.payload.lowerBound + 8
            let packed = read(bytes, info + 10, 8)
            let rate = Double(packed >> 44)
            let depth = Int((packed >> 36) & 31) + 1
            return rate > 0 ? AudioQualityCheck.losslessTier(sampleRate: rate, bitDepth: depth) : nil
        case "alac":
            // alac: full box header, then ALACSpecificConfig.
            guard let config = children.first(where: { $0.type == "alac" }), config.payload.count >= 4 + 24 else { return nil }
            let base = config.payload.lowerBound + 4
            let depth = Int(bytes[base + 5])
            let rate = Double(read(bytes, base + 20))
            return rate > 0 && depth > 0 ? AudioQualityCheck.losslessTier(sampleRate: rate, bitDepth: depth) : nil
        default:
            return nil
        }
    }

    static func decryptFile(_ source: URL, to destination: URL, key: Data) throws {
        let bytes = try Data(contentsOf: source, options: .mappedIfSafe)
        let top = try boxes(in: bytes, range: 0..<bytes.count)
        guard let movie = top.first(where: { $0.type == "moov" }),
              let media = top.first(where: { $0.type == "mdat" }), key.count == 16 else {
            throw QishuiError.encryptedAudio
        }
        let table = try sampleTable(in: bytes, movie: movie)
        let children = try boxes(in: bytes, range: table.payload)
        let movieChildren = try boxes(in: bytes, range: movie.payload)
        guard let sizes = children.first(where: { $0.type == "stsz" }), sizes.payload.count >= 12,
              let description = children.first(where: { $0.type == "stsd" }), description.payload.count >= 8,
              let encryption = (children + movieChildren).first(where: { $0.type == "senc" }),
              encryption.payload.count >= 8 else { throw QishuiError.encryptedAudio }

        let sizeOffset = sizes.payload.lowerBound
        let fixedSize = Int(read(bytes, sizeOffset + 4))
        let sampleCount = Int(read(bytes, sizeOffset + 8))
        var info = encryption.payload.lowerBound
        let flags = read(bytes, info) & 0x00ff_ffff
        guard flags & ~2 == 0, sampleCount > 0, sampleCount <= 4_194_304,
              sampleCount == Int(read(bytes, info + 4)),
              fixedSize != 0 || sampleCount <= (sizes.payload.count - 12) / 4 else {
            throw QishuiError.encryptedAudio
        }
        info += 8

        let entries = try boxes(in: bytes, range: description.payload.lowerBound + 8..<description.end)
        guard let entry = entries.first(where: { $0.type == "enca" }), entry.payload.count >= 28 else { throw QishuiError.encryptedAudio }
        let entryChildren = try boxes(in: bytes, range: entry.payload.lowerBound + 28..<entry.end)
        let protection = (entryChildren + children).first { $0.type == "sinf" }
        let protectionChildren = try protection.map { try boxes(in: bytes, range: $0.payload) } ?? []
        let format = (protectionChildren + entryChildren).first { $0.type == "frma" && $0.payload.count >= 4 }
        let original = format.map { bytes.subdata(in: $0.payload.lowerBound..<$0.payload.lowerBound + 4) } ?? Data("mp4a".utf8)
        let scheme = protectionChildren.first { $0.type == "schi" }
        let trackEncryption = try scheme.flatMap { try boxes(in: bytes, range: $0.payload).first { $0.type == "tenc" } }
        let ivLength = trackEncryption.flatMap { $0.payload.count >= 8 ? Int(bytes[$0.payload.lowerBound + 7]) : nil } ?? 8
        guard [8, 16].contains(ivLength), sampleCount <= (encryption.end - info) / ivLength else { throw QishuiError.encryptedAudio }

        let manager = FileManager.default
        let folder = destination.deletingLastPathComponent()
        try manager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let staging = folder.appendingPathComponent(UUID().uuidString)
        guard manager.createFile(atPath: staging.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw QishuiError.unavailable
        }
        defer { try? manager.removeItem(at: staging) }
        let output = try FileHandle(forWritingTo: staging)
        defer { try? output.close() }

        func writeClear(_ range: Range<Int>) throws {
            let typeOffset = entry.start + 4
            if range.contains(typeOffset) {
                try output.write(contentsOf: bytes[range.lowerBound..<typeOffset])
                try output.write(contentsOf: original)
                try output.write(contentsOf: bytes[typeOffset + 4..<range.upperBound])
            } else {
                try output.write(contentsOf: bytes[range])
            }
        }
        try writeClear(0..<media.payload.lowerBound)
        var position = media.payload.lowerBound
        for sample in 0..<sampleCount {
            if sample.isMultiple(of: 256) { try Task.checkCancellation() }
            let size = fixedSize > 0 ? fixedSize : Int(read(bytes, sizeOffset + 12 + sample * 4))
            guard size > 0, size <= media.end - position, ivLength <= encryption.end - info else {
                throw QishuiError.encryptedAudio
            }
            var iv = Data(bytes[info..<info + ivLength])
            iv.append(contentsOf: repeatElement(UInt8(0), count: 16 - ivLength))
            info += ivLength
            let end = position + size
            let cipher = try Cipher(key: key, iv: iv)
            if flags & 2 == 0 {
                try output.write(contentsOf: cipher.apply(bytes[position..<end]))
                position = end
                continue
            }
            guard encryption.end - info >= 2 else { throw QishuiError.encryptedAudio }
            let count = Int(read(bytes, info, 2))
            info += 2
            guard count <= (encryption.end - info) / 6 else { throw QishuiError.encryptedAudio }
            for _ in 0..<count {
                let clear = Int(read(bytes, info, 2))
                let encrypted = Int(read(bytes, info + 2))
                info += 6
                guard clear <= end - position, encrypted <= end - position - clear else { throw QishuiError.encryptedAudio }
                try output.write(contentsOf: bytes[position..<position + clear])
                position += clear
                if encrypted > 0 { try output.write(contentsOf: cipher.apply(bytes[position..<position + encrypted])) }
                position += encrypted
            }
            try output.write(contentsOf: bytes[position..<end])
            position = end
        }
        guard position == media.end, info == encryption.end else { throw QishuiError.encryptedAudio }
        try writeClear(media.end..<bytes.count)
        try output.close()
        try Task.checkCancellation()
        do {
            try manager.moveItem(at: staging, to: destination)
        } catch {
            // Another resolver may have committed the same verified asset.
            guard manager.fileExists(atPath: destination.path) else { throw error }
        }
    }

    private final class Cipher {
        private let ref: CCCryptorRef
        init(key: Data, iv: Data) throws {
            var cryptor: CCCryptorRef?
            let status = key.withUnsafeBytes { key in
                iv.withUnsafeBytes { iv in
                    CCCryptorCreateWithMode(CCOperation(kCCDecrypt), CCMode(kCCModeCTR), CCAlgorithm(kCCAlgorithmAES),
                        CCPadding(ccNoPadding), iv.baseAddress, key.baseAddress, key.count, nil, 0, 0,
                        CCModeOptions(kCCModeOptionCTR_BE), &cryptor)
                }
            }
            guard status == kCCSuccess, let cryptor else { throw QishuiError.encryptedAudio }
            ref = cryptor
        }
        deinit { CCCryptorRelease(ref) }

        func apply(_ input: Data) throws -> Data {
            var result = Data(count: input.count)
            var written = 0
            let status = result.withUnsafeMutableBytes { output in
                input.withUnsafeBytes { input in
                    CCCryptorUpdate(ref, input.baseAddress, input.count, output.baseAddress, output.count, &written)
                }
            }
            guard status == kCCSuccess, written == input.count else { throw QishuiError.encryptedAudio }
            return result
        }
    }
}
