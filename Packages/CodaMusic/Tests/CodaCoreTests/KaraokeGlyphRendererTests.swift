import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import CodaCore

@MainActor
@Suite struct KaraokeGlyphRendererTests {
    @Test func preservesVisibleWrappedRubyAndUnicodeAcrossTheWipe() throws {
        let text = "夜空を見上げて office café 👩🏽‍🚀 いつまでも歌おう"
        let words = [LyricWord(text: text, start: 10, duration: 3)]
        let line = LyricLine(id: 0, time: 10, text: text, words: words)
        let segments = [RubySegment("夜空", ruby: "よぞら"), RubySegment(String(text.dropFirst(2)))]
        let style = RubyAttributedString.Style(size: 34, weight: .bold, color: .white,
            rubyColor: .white, rubyScale: 0.5, alignment: .left, rounded: false)
        var renderer = KaraokeGlyphRenderer()
        renderer.update(line: line, words: words, segments: segments, style: style)
        let width = 360
        let height = 180
        func render(_ time: Double) throws -> CGImage {
            let context = try #require(CGContext(data: nil, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            renderer.draw(in: CGRect(x: 8, y: 8, width: width - 16, height: height - 16), context: context, at: time)
            return try #require(context.makeImage())
        }
        let times = [9.9, 11.4, 14.0]
        let images = try times.map(render)
        func alphaSum(_ image: CGImage) -> Int {
            let data = image.dataProvider!.data! as Data
            return stride(from: 3, to: data.count, by: 4).reduce(0) { $0 + Int(data[$1]) }
        }
        let before = alphaSum(images[0])
        let after = alphaSum(images[2])
        #expect(before > 10_000)
        #expect(after > before * 2)
        #expect(after < before * 5)
        // Export only on explicit host verification; never starts a device runner.
        if let path = ProcessInfo.processInfo.environment["CODA_LYRICS_RENDER_PREVIEW"] {
            let sheet = try #require(CGContext(data: nil, width: width, height: height * 3,
                bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            sheet.setFillColor(CGColor(red: 0.10, green: 0.13, blue: 0.20, alpha: 1))
            sheet.fill(CGRect(x: 0, y: 0, width: width, height: height * 3))
            for (index, image) in images.enumerated() {
                sheet.draw(image, in: CGRect(x: 0, y: (2 - index) * height, width: width, height: height))
            }
            let destination = try #require(CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil))
            CGImageDestinationAddImage(destination, try #require(sheet.makeImage()), nil)
            #expect(CGImageDestinationFinalize(destination))
        }
    }
}
