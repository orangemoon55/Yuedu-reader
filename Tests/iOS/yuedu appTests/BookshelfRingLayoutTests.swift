import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@MainActor
@Suite("Ring header layout and opaque artwork", .serialized)
struct BookshelfRingLayoutTests {
    private let widths: [CGFloat] = [320, 360, 430]
    private let typeSizes: [DynamicTypeSize] = [.large, .xxxLarge]

    @Test("Reading prompt reserves the same height as book and chapter text change")
    func readingPromptKeepsHeight() throws {
        var heights: [DynamicTypeSize: CGFloat] = [:]
        for type in typeSizes {
            for width in widths {
                let short = book(title: "山", chapter: 0)
                let long = book(title: String(repeating: "很長的書名與遠方的故事", count: 12), chapter: 123456789)
                let a = context(short)
                let b = context(long)
                #expect(a.currentTitle != b.currentTitle)
                #expect(a.readingPrompt.count < b.readingPrompt.count)
                let host = UIHostingController(rootView: prompt(short, type: type))
                let first = host.sizeThatFits(in: CGSize(width: width, height: 2000))
                // Reuse the host as selection changes, rather than measuring a constant wrapper.
                host.rootView = prompt(long, type: type)
                let changed = host.sizeThatFits(in: CGSize(width: width, height: 2000))
                #expect(first.height > 0 && first.height.isFinite)
                #expect(abs(first.height - changed.height) < 0.5)
                #expect(abs(changed.width - width) < 0.5)
                if let previous = heights[type] { #expect(abs(previous - changed.height) < 0.5) }
                heights[type] = changed.height
                let image = try render(prompt(long, type: type), width: width, height: changed.height)
                if width == 360 { try save(image, name: "prompt-360-\(type)") }
            }
        }
        let largeHeight = try #require(heights[.large])
        let xxxLargeHeight = try #require(heights[.xxxLarge])
        #expect(xxxLargeHeight > largeHeight)
    }

    @Test("Selected card has equal short/long title height and cover pixels reach both edges")
    func selectedCardKeepsHeightAndFullBleedCover() async throws {
        let settings = GlobalSettings.shared
        let oldForce = settings.useDefaultCoverForAllBooks
        settings.useDefaultCoverForAllBooks = false
        defer { settings.useDefaultCoverForAllBooks = oldForce }
        let pipeline = try await localCoverPipeline()
        var heights: [DynamicTypeSize: CGFloat] = [:]
        for type in typeSizes {
            for width in widths {
                let short = book(title: "山", chapter: 0)
                let long = book(title: String(repeating: "很長的書名與遠方的故事", count: 12), chapter: 123456789)
                let first = fitted(card(short, type: type, pipeline: pipeline), width: width)
                let changed = fitted(card(long, type: type, pipeline: pipeline), width: width)
                #expect(first.height > 0 && first.height.isFinite)
                #expect(abs(first.height - changed.height) < 0.5)
                #expect(abs(changed.width - width) < 0.5)
                if let previous = heights[type] { #expect(abs(previous - changed.height) < 0.5) }
                heights[type] = changed.height
                let image = try render(card(long, type: type, pipeline: pipeline), width: width, height: changed.height)
                let pixels = try Pixels(image)
                // Away from the rounded corners, the same red cover reaches the top,
                // middle and bottom. An inset thumbnail cannot pass this assertion.
                for y in [2, pixels.height / 2, pixels.height - 3] {
                    let p = pixels.sample(x: 60, y: y)
                    #expect(p.r > p.g + 100 && p.r > p.b + 100 && p.a > 250)
                }
                if width == 360 { try save(image, name: "selected-card-360-\(type)") }
            }
        }
        let largeHeight = try #require(heights[.large])
        let xxxLargeHeight = try #require(heights[.xxxLarge])
        #expect(xxxLargeHeight > largeHeight)
    }

    @Test("Center badge produces opaque blue brand pixels")
    func centerBadgeRendersBlueIcon() throws {
        let image = try render(BookshelfRingCenterBadge(diameter: 96), width: 96, height: 96)
        let pixels = try Pixels(image)
        // Sample the blue field above the book drawing, inside the circular mask.
        let blue = pixels.sample(x: pixels.width / 2, y: pixels.height / 6)
        #expect(blue.b > blue.r + 15 && blue.a > 250)
        let corner = pixels.sample(x: 0, y: 0)
        #expect(corner.a < 20)
        try save(image, name: "center-badge")
    }

    @Test("Four sectors paint their own cover and leave the center and exterior clipped")
    func fourSectorArtworkClipsCovers() throws {
        let covers = [UIColor.red, .green, .blue, .yellow].map { solid($0) }
        let artwork = ZStack {
            Color(uiColor: .magenta)
            ForEach(0..<4) { slot in
                BookshelfRingSectorArtwork(image: covers[slot], slot: slot, count: 4,
                    diameter: 320, rotation: 0, isSelected: false, colorScheme: .light)
            }
        }
        let image = try render(artwork, width: 320, height: 320)
        let pixels = try Pixels(image)
        let top = pixels.sample(x: 320, y: 140)
        let right = pixels.sample(x: 500, y: 320)
        let bottom = pixels.sample(x: 320, y: 500)
        let left = pixels.sample(x: 140, y: 320)
        #expect(top.r > top.g + 80 && top.r > top.b + 80)
        #expect(right.g > right.r + 80 && right.g > right.b + 80)
        #expect(bottom.b > bottom.r + 80 && bottom.b > bottom.g + 80)
        #expect(left.r > left.b + 80 && left.g > left.b + 80)
        for point in [CGPoint(x: 320, y: 320), CGPoint(x: 10, y: 10)] {
            let p = pixels.sample(x: Int(point.x), y: Int(point.y))
            #expect(p.r > 240 && p.b > 240 && p.g < 20)
        }
        try save(image, name: "four-sector-clipping")
    }

    private func book(title: String, chapter: Int) -> ReadingBook {
        var value = ReadingBook(title: title, author: "Local author", contentFilename: "ring-local.pdf")
        value.contentPipelineKind = .fixedPage
        value.mangaChapterIndex = chapter
        value.currentPosition = 0.37
        value.latestChapterTitle = String(repeating: "最新章節", count: chapter == 0 ? 1 : 30)
        value.coverImagePath = "ring-layout-local.png"
        return value
    }

    private func context(_ book: ReadingBook) -> BookshelfRingChapterContext {
        BookshelfRingChapterContext(book: book, chapters: [], textPosition: nil)
    }

    private func prompt(_ book: ReadingBook, type: DynamicTypeSize) -> some View {
        BookshelfRingReadingPrompt(book: book, context: context(book), onOpen: {})
            .environment(\.dynamicTypeSize, type)
    }

    private func card(_ book: ReadingBook, type: DynamicTypeSize, pipeline: CoverImagePipeline) -> some View {
        BookshelfRingSelectedCard(book: book, context: context(book), colorScheme: .light, onOpen: {})
            .environment(\.dynamicTypeSize, type)
            .environment(\.coverImagePipeline, pipeline)
            .environment(\.displayScale, 2)
    }

    private func fitted<V: View>(_ view: V, width: CGFloat) -> CGSize {
        UIHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 2000))
    }

    private func render<V: View>(_ view: V, width: CGFloat, height: CGFloat) throws -> CGImage {
        let renderer = ImageRenderer(content: view.frame(width: width, height: height)
            .environment(\.colorScheme, .light).environment(\.displayScale, 2)
            .environment(\.locale, Locale(identifier: "en_US")))
        renderer.scale = 2
        return try #require(renderer.cgImage)
    }

    private func solid(_ color: UIColor) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 120, height: 168), format: format).image { ctx in
            color.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 168))
        }
    }

    private func localCoverPipeline() async throws -> CoverImagePipeline {
        let data = try #require(solid(.red).pngData())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ring-layout-local")
        // The @Sendable I/O closures capture only immutable Data and URL.
        let io = CoverImageIO(locate: { _ in root }, read: { _ in data },
            decode: { bytes, size in CoverImageDecoder.thumbnail(from: bytes, filling: size) },
            networkCovers: root, write: { _, _ in })
        let pipeline = CoverImagePipeline(io: io, logsSummaries: false)
        let size = try #require(CoverPixelSize.fitting(pointSize: BookshelfRingPresentation.coverDecodeSize, scale: 2))
        let loaded = await pipeline.image(for: CoverImageRequest(
            source: .bookCover(filename: "ring-layout-local.png"), size: size))
        #expect(loaded.image != nil)
        return pipeline
    }

    private func save(_ image: CGImage, name: String) throws {
        #if targetEnvironment(simulator)
        let directory: URL
        if let path = ProcessInfo.processInfo.environment["QINGYUN_SCREENSHOT_DIR"], !path.isEmpty {
            directory = URL(fileURLWithPath: path, isDirectory: true)
        } else {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("qingyun-layout-preview", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try #require(UIImage(cgImage: image).pngData())
        try data.write(to: directory.appendingPathComponent("ring-layout-\(name).png"), options: .atomic)
        #endif
    }

    private struct Pixels {
        let image: CGImage
        let width: Int
        let height: Int

        init(_ image: CGImage) throws {
            self.image = image
            width = image.width
            height = image.height
            #expect(width > 0 && height > 0)
        }

        func sample(x: Int, y: Int) -> (r: Int, g: Int, b: Int, a: Int) {
            // Crop in CGImage's top-left pixel coordinates before drawing. A 1x1
            // bitmap avoids depending on a CGContext's vertical row orientation.
            guard let pixel = image.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)) else {
                Issue.record("Could not sample rendered pixel at \(x),\(y)")
                return (0, 0, 0, 0)
            }
            var bytes = [UInt8](repeating: 0, count: 4)
            let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
                guard let ctx = CGContext(data: raw.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
                else { return false }
                ctx.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
                return true
            }
            #expect(drawn)
            return (Int(bytes[0]), Int(bytes[1]), Int(bytes[2]), Int(bytes[3]))
        }
    }
}
