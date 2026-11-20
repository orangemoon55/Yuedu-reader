import CoreGraphics
import Foundation
import Nuke
import UIKit

// MARK: - Crop borders processor
//
// Crop only uniform scanning borders. Work in the original CGImage's pixel space so
// a narrow mark on an edge, or UIImage's orientation, cannot move the crop inward.

struct FixedPageCropBordersProcessor: ImageProcessing {

    var identifier: String {
        "com.yuedu.reader.cropBorders.v2"
    }

    // Do not allocate another unbounded bitmap for a very long strip. If we cannot
    // examine the original pixels, keeping the page is safer than a sampled crop.
    private let maxScanPixels = 8_000_000

    func process(_ image: PlatformImage) -> PlatformImage? {
        guard let cgImage = image.cgImage,
              let cropRect = contentRect(in: image),
              let cropped = cgImage.cropping(to: cropRect) else { return image }
        return PlatformImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }

    /// The part of `image` to keep, in unrotated CGImage pixels (top-left origin), or nil
    /// when there is no confidently detected border. PDF and fixed-layout EPUB renderers
    /// convert this rectangle to proportions to keep the crop stable across zoom levels.
    func contentRect(in image: PlatformImage) -> CGRect? {
        guard let cgImage = image.cgImage else { return nil }
        let width = cgImage.width
        let height = cgImage.height
        guard width > 10, height > 10, width <= maxScanPixels / height else { return nil }

        return autoreleasepool {
            let bitmapInfo = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            guard let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: bitmapInfo
            ), let pixels = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }

            defer { withExtendedLifetime(context) {} }
            context.setBlendMode(.copy)
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))

            // A border must extend across the edge and match that edge's outermost color.
            // In particular a black panel after a white margin is not more margin.
            func matchesBorder(from start: Int, step: Int, count: Int, sample: Int) -> Bool {
                let sampleOffset = sample * 4
                let alpha = pixels[sampleOffset + 3]
                let gray = pixels[sampleOffset]
                guard alpha == 0 || (alpha == 255 && (gray <= 5 || gray >= 250)
                    && pixels[sampleOffset + 1] == gray && pixels[sampleOffset + 2] == gray) else { return false }

                for index in 0..<count {
                    let offset = (start + index * step) * 4
                    if pixels[offset + 3] != alpha { return false }
                    if alpha != 0 && (pixels[offset] != gray || pixels[offset + 1] != gray || pixels[offset + 2] != gray) {
                        return false
                    }
                }
                return true
            }

            var top = 0
            var bottom = height
            while top < bottom, matchesBorder(from: top * width, step: 1, count: width, sample: 0) {
                top += 1
            }
            let bottomSample = (height - 1) * width
            while top < bottom, matchesBorder(from: (bottom - 1) * width, step: 1, count: width, sample: bottomSample) {
                bottom -= 1
            }
            guard top < bottom else { return nil }

            var left = 0
            var right = width
            let firstRow = top * width
            while left < right, matchesBorder(from: firstRow + left, step: width, count: bottom - top, sample: firstRow) {
                left += 1
            }
            while left < right, matchesBorder(
                from: firstRow + right - 1, step: width, count: bottom - top, sample: firstRow + width - 1
            ) {
                right -= 1
            }

            let cropWidth = right - left
            let cropHeight = bottom - top
            guard (Double(width - cropWidth) > Double(width) * 0.01
                    || Double(height - cropHeight) > Double(height) * 0.01),
                  Double(cropWidth) > Double(width) * 0.4,
                  Double(cropHeight) > Double(height) * 0.4 else { return nil }
            return CGRect(x: left, y: top, width: cropWidth, height: cropHeight)
        }
    }
}
