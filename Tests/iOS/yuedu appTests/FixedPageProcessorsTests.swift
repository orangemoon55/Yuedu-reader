import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import yuedu_app

@Suite("FixedPage Processors Tests")
struct FixedPageProcessorsTests {

    @Test("FixedPageSplitProcessor detects wide landscape images")
    func testWideImageDetection() {
        let portrait = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 1200)).image { _ in }
        let square = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 1000)).image { _ in }
        let landscape = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 1000)).image { _ in }

        #expect(!FixedPageSplitProcessor.isWideImage(portrait))
        #expect(!FixedPageSplitProcessor.isWideImage(square))
        #expect(FixedPageSplitProcessor.isWideImage(landscape))
    }

    @Test("FixedPageSplitProcessor splits image into left and right halves")
    func testSplitHalves() {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 100))
        let wideImage = renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 100, height: 100))
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 100, y: 0, width: 100, height: 100))
        }

        let halves = FixedPageSplitProcessor.split(image: wideImage)
        #expect(halves != nil)
        guard let (left, right) = halves else { return }

        #expect(Int(left.size.width) == 100)
        #expect(Int(left.size.height) == 100)
        #expect(Int(right.size.width) == 100)
        #expect(Int(right.size.height) == 100)
    }

    @Test("FixedPageCropBordersProcessor crops border from framed image")
    func testCropBorders() {
        // 200x200 image with a 30px white border and a 140x140 blue center
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200))
        let borderedImage = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 200, height: 200))

            UIColor.blue.setFill()
            ctx.fill(CGRect(x: 30, y: 30, width: 140, height: 140))
        }

        let processor = FixedPageCropBordersProcessor()
        let result = processor.process(borderedImage)
        #expect(result != nil)
        guard let cropped = result else { return }

        // Cropped width and height should be smaller than original 200x200
        #expect(cropped.size.width < 200)
        #expect(cropped.size.height < 200)
    }

    @Test("Optional border crop retains exact grid coordinates", arguments: [
        CGSize(width: 73, height: 217), CGSize(width: 231, height: 91), CGSize(width: 59, height: 1201)
    ])
    @MainActor
    func testGridThroughLocalLoader(size: CGSize) async throws {
        let rect = CGRect(x: 11, y: 7, width: size.width - 28, height: size.height - 16)
        let grid = Self.makeGrid(size: size, content: rect)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID()).png")
        try #require(grid.pngData()).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let page = FixedPage(id: 0, imageURL: url.absoluteString, headers: [:], localURL: url)
        let full = try #require(await FixedPageImageLoader.loadImage(for: page, targetWidth: 0, renderScale: 1))
        let trimmed = try #require(await FixedPageImageLoader.loadImage(
            for: page, targetWidth: 0, renderScale: 1, cropBorders: true
        ))
        #expect(full.cgImage?.width == Int(size.width))
        #expect(full.cgImage?.height == Int(size.height))
        #expect(trimmed.cgImage?.width == Int(rect.width))
        #expect(trimmed.cgImage?.height == Int(rect.height))
        #expect(Self.pixel(full, x: 0, y: 0) == [255, 255, 255, 255])
        for x in [0, Int(rect.width) - 1] {
            for y in [0, Int(rect.height) - 1] {
                let expected = Self.pixel(grid, x: Int(rect.minX) + x, y: Int(rect.minY) + y)
                #expect(expected != nil)
                #expect(Self.pixel(trimmed, x: x, y: y) == expected)
                #expect(Self.pixel(full, x: Int(rect.minX) + x, y: Int(rect.minY) + y) == expected)
            }
        }
    }

    @Test("Crop keeps a black edge mark and uses unrotated pixel coordinates")
    func testCropOfRotatedGrid() throws {
        let size = CGSize(width: 97, height: 201)
        let rect = CGRect(x: 11, y: 7, width: 67, height: 185)
        let grid = Self.makeGrid(size: size, content: rect, edgeMark: true)
        let rotated = UIImage(cgImage: try #require(grid.cgImage), scale: 1, orientation: .right)
        let processor = FixedPageCropBordersProcessor()
        #expect(processor.contentRect(in: rotated) == CGRect(x: 11, y: 2, width: 84, height: 190))
        let result = try #require(processor.process(rotated))
        #expect(result.imageOrientation == .right)
        #expect(Self.pixel(result, x: 83, y: 0) == [0, 0, 0, 255])
    }

    @Test("Odd oriented split preserves both outer edges and the centre columns")
    func testSplitOfRotatedGrid() throws {
        let size = CGSize(width: 97, height: 201)
        let grid = Self.makeGrid(size: size, content: CGRect(origin: .zero, size: size))
        let rotated = UIImage(cgImage: try #require(grid.cgImage), scale: 1, orientation: .right)
        let halves = try #require(FixedPageSplitProcessor.split(image: rotated))
        #expect(halves.left.cgImage?.height == 100)
        #expect(halves.right.cgImage?.height == 101)
        for x in [0, 96] {
            #expect(Self.pixel(halves.left, x: x, y: 0) == Self.pixel(grid, x: x, y: 101))
            #expect(Self.pixel(halves.left, x: x, y: 99) == Self.pixel(grid, x: x, y: 200))
            #expect(Self.pixel(halves.right, x: x, y: 0) == Self.pixel(grid, x: x, y: 0))
            #expect(Self.pixel(halves.right, x: x, y: 100) == Self.pixel(grid, x: x, y: 100))
        }
    }

    private static func makeGrid(size: CGSize, content: CGRect, edgeMark: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            let x = content.minX + floor(content.width / 3)
            let y = content.minY + floor(content.height * 0.6)
            UIColor.red.setFill()
            context.fill(CGRect(x: content.minX, y: content.minY, width: x - content.minX, height: y - content.minY))
            UIColor.blue.setFill()
            context.fill(CGRect(x: x, y: content.minY, width: content.maxX - x, height: y - content.minY))
            UIColor.green.setFill()
            context.fill(CGRect(x: content.minX, y: y, width: x - content.minX, height: content.maxY - y))
            UIColor.yellow.setFill()
            context.fill(CGRect(x: x, y: y, width: content.maxX - x, height: content.maxY - y))
            if edgeMark {
                UIColor.black.setFill()
                context.fill(CGRect(x: size.width - 3, y: 2, width: 1, height: 1))
            }
        }
    }

    private static func pixel(_ image: UIImage, x: Int, y: Int) -> [UInt8]? {
        guard let pixel = image.cgImage?.cropping(to: CGRect(x: x, y: y, width: 1, height: 1)),
              let context = CGContext(
                data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
              ), let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        defer { withExtendedLifetime(context) {} }
        context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        return Array(UnsafeBufferPointer(start: data, count: 4))
    }
}
