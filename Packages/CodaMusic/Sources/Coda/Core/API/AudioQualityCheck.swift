import AudioToolbox
import Foundation

enum AudioQualityCheck {
    static func bitrateBPS(_ value: Double) -> Double? {
        guard value.isFinite, value > 0 else { return nil }
        return value < 1000 ? value * 1000 : value
    }

    static func lossyTier(bitrate: Double?, fallback: AudioQuality? = nil) -> AudioQuality? {
        if let bitrate {
            if bitrate <= 128_000 { return .standard }
            if bitrate <= 192_000 { return .higher }
            return .exhigh
        }
        if let fallback, [.standard, .higher, .exhigh].contains(fallback) { return fallback }
        return nil
    }

    static func isLossless(_ codec: String) -> Bool {
        ["flac", "alac", "wav", "wave", "pcm", "lpcm", "ape"].contains(codec.lowercased())
    }

    static func isLossy(_ codec: String) -> Bool {
        ["aac", "mp4a", "he-aac", "mp3", "mpeg", "opus", "vorbis", "ogg"].contains(codec.lowercased())
    }

    static func losslessTier(sampleRate: Double, bitDepth: Int) -> AudioQuality {
        // Match the existing Coda FLAC distinction above CD-class resolution.
        sampleRate > 48_000 || bitDepth > 16 ? .hires : .lossless
    }

    static func flacTier(header: Data) -> AudioQuality? {
        let bytes = Array(header.prefix(42))
        guard bytes.count == 42, bytes.prefix(4).elementsEqual("fLaC".utf8),
              bytes[4] & 0x7f == 0, bytes[5] == 0, bytes[6] == 0, bytes[7] == 34 else { return nil }
        let info = bytes[18..<26].reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        let sampleRate = info >> 44
        let bitDepth = ((info >> 36) & 31) + 1
        guard sampleRate > 0 else { return nil }
        return losslessTier(sampleRate: Double(sampleRate), bitDepth: Int(bitDepth))
    }

    static func remoteTier(url address: String, session: URLSession, bitrate: Double? = nil) async -> AudioQuality? {
        guard let url = URL(string: address), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
              url.host != nil else { return nil }
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue("bytes=0-41", forHTTPHeaderField: "Range")
        guard let (bytes, response) = try? await session.bytes(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        var header = Data()
        do {
            for try await byte in bytes {
                header.append(byte)
                if header.count == 42 { break }
            }
        } catch { return nil }
        return tier(header: header, mimeType: http.mimeType, bitrate: bitrate)
    }

    /// Tier from the first bytes of a stream (at least 42 for FLAC), e.g. a
    /// Range probe that already fetched them.
    static func tier(header: Data, mimeType: String?, bitrate: Double? = nil) -> AudioQuality? {
        if let tier = flacTier(header: header) { return tier }
        let type = mimeType?.lowercased()
        let mp3 = type == "audio/mpeg" && header.starts(with: "ID3".utf8)
        let adts = type == "audio/aac" && header.count >= 2 && header[0] == 0xff && header[1] & 0xf6 == 0xf0
        return mp3 || adts ? (lossyTier(bitrate: bitrate) ?? .standard) : nil
    }

    static func localLevel(url: URL, reported: String?) -> String? {
        guard let reported, let tier = AudioQuality(rawValue: reported),
              [.lossless, .hires].contains(tier) else { return reported }
        return localTier(url: url, bitrate: nil, fallback: tier)?.rawValue ?? reported
    }

    static func localBitrate(url: URL) -> Int? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return nil }
        defer { AudioFileClose(file) }
        return bitrate(of: file)
    }

    private static func bitrate(of file: AudioFileID) -> Int? {
        var bitrate: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyBitRate, &size, &bitrate) == noErr, bitrate > 0 else { return nil }
        return Int(bitrate)
    }

    static func localTier(url: URL, bitrate: Double?, fallback: AudioQuality) -> AudioQuality? {
        var file: AudioFileID?
        guard AudioFileOpenURL(url as CFURL, .readPermission, 0, &file) == noErr, let file else { return nil }
        defer { AudioFileClose(file) }
        var format = AudioStreamBasicDescription()
        var size = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
        guard AudioFileGetProperty(file, kAudioFilePropertyDataFormat, &size, &format) == noErr else { return nil }
        switch format.mFormatID {
        case kAudioFormatFLAC, kAudioFormatAppleLossless, kAudioFormatLinearPCM:
            let flagDepths: [UInt32: Int] = [1: 16, 2: 20, 3: 24, 4: 32]
            let depth = format.mBitsPerChannel > 0 ? Int(format.mBitsPerChannel) : flagDepths[format.mFormatFlags] ?? 0
            return losslessTier(sampleRate: format.mSampleRate, bitDepth: depth)
        case kAudioFormatMPEG4AAC, kAudioFormatMPEG4AAC_HE, kAudioFormatMPEG4AAC_HE_V2,
             kAudioFormatMPEGLayer3, kAudioFormatOpus:
            let rate = Self.bitrate(of: file).map(Double.init) ?? bitrate
            return lossyTier(bitrate: rate, fallback: fallback) ?? .standard
        default: return nil
        }
    }
}
