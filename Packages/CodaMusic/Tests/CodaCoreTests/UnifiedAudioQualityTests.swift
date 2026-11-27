import Foundation
import Testing
@testable import CodaCore

@Suite("Unified audio quality presentation")
struct UnifiedAudioQualityTests {
    @Test func actualRatesUseCommonNamesWithoutCodecNames() {
        #expect(AudioQualityOption.unifiedTitle(quality: .standard, bitrate: 128001) == "标准 · 128 kbps")
        #expect(AudioQualityOption.unifiedTitle(quality: .exhigh, bitrate: 320000) == "高品质 · 320 kbps")
        #expect(AudioQualityOption.unifiedTitle(quality: .lossless, bitrate: 935088) == "无损 · 935.1 kbps")
        #expect(AudioQualityOption.unifiedTitle(quality: .hires, bitrate: 1608000) == "高解析度无损 · 1608 kbps")
        #expect(AudioQualityOption.unifiedTitle(quality: .lossless, bitrate: 1714000) == "无损 · 1714 kbps")
    }
    @Test func reportedBitrateWinsAndSizeDurationIsTheMarkedFallback() {
        #expect(AudioQualityOption.unifiedTitle(quality: .lossless, reportedBitrate: 1_676_000,
                                                byteCount: 31529673, durationSeconds: 269) == "无损 · 1676 kbps")
        #expect(AudioQualityOption.unifiedTitle(quality: .lossless, reportedBitrate: 0,
                                                byteCount: 31529673, durationSeconds: 269) == "无损 · 约937.7 kbps")
        #expect(AudioQualityOption.unifiedTitle(quality: .lossless, reportedBitrate: nil,
                                                byteCount: nil, durationSeconds: 269) == "无损")
        #expect(AudioQualityOption.qishui(quality: .hires, bitrate: nil, byteCount: 0, durationMS: 0).title
                == AudioQuality.hires.displayName)
    }
    @Test func allProvidersShareSizeDurationFallbackAndRejectInvalidMetadata() {
        let bitrate = AudioQualityOption.estimatedBitrate(byteCount: 31529673, durationSeconds: 269)
        #expect(AudioQualityOption.unifiedTitle(quality: .lossless, bitrate: bitrate, estimated: true) == "无损 · 约937.7 kbps")
        #expect(AudioQualityOption.estimatedBitrate(byteCount: nil, durationSeconds: 269) == nil)
        #expect(AudioQualityOption.estimatedBitrate(byteCount: 10, durationSeconds: 0) == nil)
        #expect(AudioQualityOption.estimatedBitrate(byteCount: .infinity, durationSeconds: 1) == nil)
    }

    @Test func missingOrInvalidRatesNeverBecomeInventedNumbers() {
        for rate: Double? in [nil, 0, -1, .nan, .infinity] {
            #expect(AudioQualityOption.unifiedTitle(quality: .hires, bitrate: rate) == "高解析度无损")
        }
    }
    @Test func estimatesAreExplicitAndComputedFromResourceBytes() {
        let rates = QQMusicAPI.averageBitrates(file: ["size_flac": 25863277, "size_320mp3": 7688557], duration: 192)
        #expect(AudioQualityOption.unifiedTitle(quality: .lossless, bitrate: rates["F000"], estimated: true) == "无损 · 约1077.6 kbps")
        #expect(QQMusicAPI.averageBitrates(file: ["size_flac": 1], duration: 0).isEmpty)
    }
    @Test func highQualityOffersOneBestResourceAndKeeps192When320IsAbsent() {
        let lower = AudioQualityOption(quality: .higher, title: "高品质 · 192 kbps")
        let higher = AudioQualityOption(quality: .exhigh, title: "高品质 · 320 kbps")
        #expect(AudioQualityOption.unified([lower, higher]) == [higher])
        #expect(AudioQualityOption.unified([lower]) == [lower])
    }
}
