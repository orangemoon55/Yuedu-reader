import CoreGraphics
import Foundation
import UIKit

// MARK: - Fixed page split processor
//
// Detects two-page spreads and splits them into two single pages for optimal
// reading on vertical screens, matching Aidoku's splitWideImages behavior.

enum FixedPageSplitProcessor {

    /// Whether an image has a landscape aspect ratio typical of a 2-page manga spread.
    static func isWideImage(_ image: UIImage) -> Bool {
        guard image.size.height > 0 else { return false }
        return (image.size.width / image.size.height) >= 1.15
    }

    /// Crops the requested visual left or right half, retaining an odd last column on the right.
    static func cropHalf(from image: UIImage, side: FixedPage.SubPageSide) -> UIImage {
        guard let cgImage = image.cgImage else { return image }
        // The bitmap may carry EXIF orientation rather than being physically rotated.
        // Pick the raw axis and direction that correspond to increasing display X.
        let alongRows: Bool
        let forward: Bool
        switch image.imageOrientation {
        case .up, .downMirrored: (alongRows, forward) = (false, true)
        case .down, .upMirrored: (alongRows, forward) = (false, false)
        case .left, .leftMirrored: (alongRows, forward) = (true, true)
        case .right, .rightMirrored: (alongRows, forward) = (true, false)
        @unknown default: return image
        }
        let count = alongRows ? cgImage.height : cgImage.width
        guard count > 1 else { return image }
        let length = side == .left ? count / 2 : count - count / 2
        let start = (side == .left) == forward ? 0 : count - length
        let cropRect = alongRows
            ? CGRect(x: 0, y: start, width: cgImage.width, height: length)
            : CGRect(x: start, y: 0, width: length, height: cgImage.height)

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    /// Splits a wide image into left and right half images.
    static func split(image: UIImage) -> (left: UIImage, right: UIImage)? {
        guard isWideImage(image) else { return nil }
        return (
            left: cropHalf(from: image, side: .left),
            right: cropHalf(from: image, side: .right)
        )
    }
}
