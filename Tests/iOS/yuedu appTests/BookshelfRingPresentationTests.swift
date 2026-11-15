import CoreGraphics
import CoreImage
import Foundation
import Testing
import UIKit
@testable import yuedu_app

@Suite("Ring cover geometry and cached artwork backdrops")
struct BookshelfRingPresentationTests {
    @Test("Paper bounds clear every other book, the badge and the outer circle",
          arguments: [CGFloat(240), 288, 320, 360, 393, 430, 440], 1...9)
    func allRotations(diameter: CGFloat, count: Int) {
        let size = BookshelfRingPresentation.coverSize(diameter: diameter, count: count)
        let radius = BookshelfRingPresentation.orbitRadius(diameter: diameter, count: count)
        #expect(size.width > 0)
        #expect(abs(size.height - size.width * 1.4) < 0.000001)
        var largestCorner: CGFloat = 0
        var smallestBadgeGap = CGFloat.infinity
        var smallestBookGap = CGFloat.infinity
        // Covers stay upright while their centres orbit. Quarter-degree samples
        // include seams and half-way positions, not merely the resting slots.
        for tick in 0...1440 {
            let rotation = CGFloat(tick) / 4
            let rects = (0..<count).map { slot in
                let angle = (CGFloat(slot) * 360 / CGFloat(count) + rotation - 90) * .pi / 180
                return visualBounds(center: CGPoint(x: cos(angle) * radius, y: sin(angle) * radius), size: size)
            }
            for (index, rect) in rects.enumerated() {
                for x in [rect.minX, rect.maxX] {
                    for y in [rect.minY, rect.maxY] {
                        largestCorner = max(largestCorner, hypot(x, y))
                    }
                }
                let closestX = max(rect.minX, min(0, rect.maxX))
                let closestY = max(rect.minY, min(0, rect.maxY))
                smallestBadgeGap = min(smallestBadgeGap, hypot(closestX, closestY) - diameter * 0.055)
                for other in rects.dropFirst(index + 1) {
                    let dx = max(0, max(other.minX - rect.maxX, rect.minX - other.maxX))
                    let dy = max(0, max(other.minY - rect.maxY, rect.minY - other.maxY))
                    smallestBookGap = min(smallestBookGap, hypot(dx, dy))
                }
            }
        }
        #expect(largestCorner <= diameter * 0.465)
        #expect(smallestBadgeGap >= 2)
        if count > 1 { #expect(smallestBookGap >= 2) }
    }

    @Test("Four covers are materially wider than v8 at every supported diameter",
          arguments: [CGFloat(240), 288, 320, 360, 393, 430, 440])
    func enlargedCovers(diameter: CGFloat) {
        let size = BookshelfRingPresentation.coverSize(diameter: diameter, count: 4)
        let previous = min(60, diameter * 0.153)
        #expect(size.width >= previous * 1.3)
        #expect(size.width >= diameter * 0.20)
        #expect(size.width <= diameter * 0.21)
        let radius = BookshelfRingPresentation.orbitRadius(diameter: diameter, count: 4)
        #expect(radius >= diameter * 0.275)
        #expect(radius <= diameter * 0.282)
        for count in 1...6 {
            #expect(BookshelfRingPresentation.coverSize(diameter: diameter, count: count).width > previous)
        }
        #expect(BookshelfRingPresentation.coverDecodeSize == CGSize(width: 120, height: 168))
    }

    @Test("Invalid dimensions and empty shelves remain finite, overflow clamps to nine")
    func invalidInputs() {
        for diameter: CGFloat in [.nan, .infinity, -.infinity, -100, 0, .leastNonzeroMagnitude, 1] {
            #expect(BookshelfRingPresentation.coverSize(diameter: diameter, count: 4) == .zero)
            #expect(BookshelfRingPresentation.orbitRadius(diameter: diameter, count: 4) == 0)
        }
        for count in [Int.min, -1, 0] {
            #expect(BookshelfRingPresentation.coverSize(diameter: 320, count: count) == .zero)
            #expect(BookshelfRingPresentation.orbitRadius(diameter: 320, count: count) == 0)
        }
        for count in [10, 100, Int.max] {
            #expect(BookshelfRingPresentation.coverSize(diameter: 320, count: count)
                    == BookshelfRingPresentation.coverSize(diameter: 320, count: 9))
            #expect(BookshelfRingPresentation.orbitRadius(diameter: 320, count: count)
                    == BookshelfRingPresentation.orbitRadius(diameter: 320, count: 9))
        }
        let large = BookshelfRingPresentation.coverSize(diameter: .greatestFiniteMagnitude, count: 9)
        #expect(large.width.isFinite && large.height.isFinite)
        #expect(BookshelfRingPresentation.orbitRadius(diameter: .greatestFiniteMagnitude, count: 9).isFinite)
    }

    private func visualBounds(center: CGPoint, size: CGSize) -> CGRect {
        // Match BookshelfRingBookDepth's actual positive x/y offsets, including
        // its minimum thickness on small devices. Projection shadows are excluded.
        let depthX = min(max(size.width * 0.06, 2), 4)
        let depthY = min(max(size.height * 0.045, 2.5), 4.5)
        return CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2,
                      width: size.width + depthX, height: size.height + depthY)
    }

    @Test("Backdrop keeps cover artwork, reduces saturation and limits raster pixels")
    @MainActor
    func artworkRaster() async throws {
        let source = fixture(size: CGSize(width: 600, height: 840), scale: 2)
        let result = await Task.detached { BookshelfRingPresentation.makeBackdrop(from: source) }.value
        let image = try #require(result)
        let bitmap = try #require(image.cgImage)
        #expect(bitmap.width == 228)
        #expect(bitmap.height == 320)
        #expect(image.scale == 1)
        #expect(image.imageOrientation == .up)
        let pixels = try self.readPixels(of: image)
        let left = pixels.sample(x: bitmap.width / 4, y: bitmap.height / 2)
        let right = pixels.sample(x: bitmap.width * 3 / 4, y: bitmap.height / 2)
        #expect(left.red > left.blue + 40)
        #expect(right.blue > right.red + 40)
        #expect(left.red - left.blue < 230)
        #expect(right.blue - right.red < 230)
        #expect(pixels.isOpaque)
        // Blur softens the red/blue boundary without replacing the whole picture
        // by one average colour. The two sides remain clearly distinguishable.
        let boundary = pixels.sample(x: bitmap.width / 2, y: bitmap.height / 2)
        #expect(abs(boundary.red - boundary.blue) < 100)
    }

    @Test("Transparent input gets an opaque base without losing visible artwork")
    @MainActor
    func transparentArtwork() async throws {
        let source = fixture(size: CGSize(width: 80, height: 120), transparentRight: true)
        let result = await Task.detached { BookshelfRingPresentation.makeBackdrop(from: source) }.value
        let image = try #require(result)
        let bitmap = try #require(image.cgImage)
        #expect(bitmap.width == 80 && bitmap.height == 120)
        let pixels = try self.readPixels(of: image)
        #expect(pixels.isOpaque)
        let artwork = pixels.sample(x: 20, y: 60)
        let base = pixels.sample(x: 70, y: 60)
        #expect(artwork.red > artwork.blue + 40)
        #expect(base.red > 180 && base.green > 180 && base.blue > 180)
    }

    @Test("All UIImage orientations match UIKit's displayed artwork")
    @MainActor
    func imageOrientations() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let original = UIGraphicsImageRenderer(size: CGSize(width: 80, height: 120), format: format).image { context in
            for (color, rect) in [
                (UIColor.red, CGRect(x: 0, y: 0, width: 40, height: 60)),
                (UIColor.green, CGRect(x: 40, y: 0, width: 40, height: 60)),
                (UIColor.blue, CGRect(x: 0, y: 60, width: 40, height: 60)),
                (UIColor.yellow, CGRect(x: 40, y: 60, width: 40, height: 60))
            ] {
                color.setFill()
                context.fill(rect)
            }
        }
        let raw = try #require(original.cgImage)
        for orientation: UIImage.Orientation in [.up, .down, .left, .right, .upMirrored, .downMirrored, .leftMirrored, .rightMirrored] {
            let source = UIImage(cgImage: raw, scale: 1, orientation: orientation)
            let result = await Task.detached { BookshelfRingPresentation.makeBackdrop(from: source) }.value
            let image = try #require(result)
            let swapsAxes = [UIImage.Orientation.left, .right, .leftMirrored, .rightMirrored].contains(orientation)
            let size = swapsAxes ? CGSize(width: 120, height: 80) : CGSize(width: 80, height: 120)
            #expect(image.size == size)
            #expect(image.imageOrientation == .up)
            let expected = UIGraphicsImageRenderer(size: size, format: format).image { _ in
                source.draw(in: CGRect(origin: .zero, size: size))
            }
            let actualPixels = try readPixels(of: image)
            let expectedPixels = try readPixels(of: expected)
            for x in [Int(size.width) / 4, Int(size.width) * 3 / 4] {
                for y in [Int(size.height) / 4, Int(size.height) * 3 / 4] {
                    #expect(actualPixels.sample(x: x, y: y).tone == expectedPixels.sample(x: x, y: y).tone)
                }
            }
            #expect(actualPixels.isOpaque)
        }
    }

    @Test("Repeated and concurrent calls reuse one raster; a new cover gets new artwork")
    @MainActor
    func cachedRaster() async throws {
        let source = fixture(size: CGSize(width: 48, height: 64))
        let results = await withTaskGroup(of: UIImage?.self, returning: [UIImage?].self) { group in
            for _ in 0..<8 {
                group.addTask { BookshelfRingPresentation.makeBackdrop(from: source) }
            }
            var images: [UIImage?] = []
            for await result in group { images.append(result) }
            return images
        }
        let first = try #require(results.first ?? nil)
        for result in results { #expect(result === first) }
        let repeated = await Task.detached { BookshelfRingPresentation.makeBackdrop(from: source) }.value
        #expect(repeated === first)
        let changed = fixture(size: CGSize(width: 48, height: 64), transparentRight: true)
        let changedResult = await Task.detached { BookshelfRingPresentation.makeBackdrop(from: changed) }.value
        let replacement = try #require(changedResult)
        #expect(replacement !== first)
        let oldPixel = try readPixels(of: first).sample(x: 40, y: 32)
        let newPixel = try readPixels(of: replacement).sample(x: 40, y: 32)
        #expect(oldPixel.blue > oldPixel.red + 40)
        #expect(abs(newPixel.red - newPixel.blue) < 40)
    }

    @Test("Finite CI-backed images rasterize and empty or infinite images fail safely")
    func ciBackedImages() throws {
        let solid = CIImage(color: CIColor(red: 0.2, green: 0.4, blue: 0.8))
        let finite = UIImage(ciImage: solid.cropped(to: CGRect(x: -20, y: 15, width: 64, height: 96)))
        let result = try #require(BookshelfRingPresentation.makeBackdrop(from: finite))
        #expect(result.cgImage?.width == 64)
        #expect(result.cgImage?.height == 96)
        #expect(BookshelfRingPresentation.makeBackdrop(from: UIImage()) == nil)
        #expect(BookshelfRingPresentation.makeBackdrop(from: UIImage(ciImage: solid)) == nil)
    }

    @MainActor
    private func fixture(size: CGSize, scale: CGFloat = 1, transparentRight: Bool = false) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = false
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height))
            if !transparentRight {
                UIColor.blue.setFill()
                context.fill(CGRect(x: size.width / 2, y: 0, width: size.width / 2, height: size.height))
            }
        }
    }

    private struct Pixel {
        let red: Int
        let green: Int
        let blue: Int

        var tone: Int {
            if red > blue + 20 && green > blue + 20 { return 3 }
            if red > green + 20 && red > blue + 20 { return 0 }
            if green > red + 20 && green > blue + 20 { return 1 }
            if blue > red + 20 && blue > green + 20 { return 2 }
            return -1
        }
    }

    private struct Pixels {
        let bytes: [UInt8]
        let width: Int

        var isOpaque: Bool { stride(from: 3, to: bytes.count, by: 4).allSatisfy { bytes[$0] == 255 } }

        func sample(x: Int, y: Int) -> Pixel {
            let offset = (y * width + x) * 4
            return Pixel(red: Int(bytes[offset]), green: Int(bytes[offset + 1]), blue: Int(bytes[offset + 2]))
        }
    }

    private func readPixels(of image: UIImage) throws -> Pixels {
        let bitmap = try #require(image.cgImage)
        let width = bitmap.width
        let height = bitmap.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let didDraw = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(bitmap, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        #expect(didDraw)
        return Pixels(bytes: bytes, width: width)
    }
}
