import CoreImage
import Foundation
import UIKit
import os

/// Geometry includes the book block behind each upright cover. Backdrops reuse the
/// exact image reported by the cover view; this type never loads another image.
enum BookshelfRingPresentation {
    nonisolated static let coverDecodeSize = CGSize(width: 120, height: 168)

    nonisolated static func coverSize(diameter: CGFloat, count: Int) -> CGSize {
        let width = layout(diameter: diameter, count: count).width
        return CGSize(width: width, height: width * 1.4)
    }

    nonisolated static func orbitRadius(diameter: CGFloat, count: Int) -> CGFloat {
        layout(diameter: diameter, count: count).radius
    }

    /// The Tang mirror has a wider engraved rim and a larger miniature mirror boss.
    /// Keep the old geometry API for existing styles and transition regressions.
    nonisolated static func mirrorCoverSize(diameter: CGFloat, count: Int) -> CGSize {
        let width = layout(diameter: diameter, count: count, outerLimit: 0.411, bossRadius: 0.083).width
        return CGSize(width: width, height: width * 1.4)
    }

    nonisolated static func mirrorOrbitRadius(diameter: CGFloat, count: Int) -> CGFloat {
        layout(diameter: diameter, count: count, outerLimit: 0.411, bossRadius: 0.083).radius
    }

    private struct Layout {
        var width: CGFloat = 0
        var radius: CGFloat = 0
    }

    nonisolated private static func layout(diameter: CGFloat, count: Int,
                                            outerLimit: CGFloat = 0.465, bossRadius: CGFloat = 0.055) -> Layout {
        guard diameter.isFinite, diameter > 0, count > 0 else { return Layout() }
        let count = min(count, 9)
        // Keep a tiny numerical reserve in addition to the required two points.
        let gap: CGFloat = 2.01
        let outerRadius = diameter * outerLimit - 0.01
        let badgeRadius = diameter * bossRadius
        let desiredRatio: CGFloat
        switch count {
        case 1...4: desiredRatio = 0.21
        case 5: desiredRatio = 0.19
        case 6: desiredRatio = 0.175
        case 7: desiredRatio = 0.16
        case 8: desiredRatio = 0.15
        default: desiredRatio = 0.14
        }

        func radii(for width: CGFloat) -> (minimum: CGFloat, maximum: CGFloat) {
            let height = width * 1.4
            let depthX = min(max(width * 0.06, 2), 4)
            let depthY = min(max(height * 0.045, 2.5), 4.5)
            let corner = hypot(width / 2 + depthX, height / 2 + depthY)
            // A full rotation aligns the most distant corner with the radial
            // direction, both toward the outer circle and toward the badge.
            var minimum = max(diameter * 0.275, corner + badgeRadius + gap)
            if count > 1 {
                // Centre differences rotate through every direction. The visual
                // rectangle's diagonal plus the gap is the minimum safe chord;
                // adjacent books have the shortest chord of all pairs.
                let chord = hypot(width + depthX, height + depthY) + gap
                minimum = max(minimum, chord / (2 * sin(.pi / CGFloat(count))))
            }
            return (minimum, outerRadius - corner)
        }

        let empty = radii(for: 0)
        guard empty.minimum < empty.maximum else { return Layout() }
        var low: CGFloat = 0
        var high = diameter * desiredRatio
        let desired = radii(for: high)
        if desired.minimum <= desired.maximum {
            low = high
        } else {
            // The lower orbit bound rises monotonically with width while the
            // upper bound falls. Find the largest safe width below the target.
            for _ in 0..<40 {
                let middle = low + (high - low) / 2
                let bounds = radii(for: middle)
                if bounds.minimum <= bounds.maximum { low = middle } else { high = middle }
            }
        }
        guard low > 0 else { return Layout() }
        let bounds = radii(for: low)
        return Layout(width: low, radius: min(max(diameter * 0.28, bounds.minimum), bounds.maximum))
    }

    private struct BackdropEntry: Sendable {
        // Retaining the source also prevents ObjectIdentifier reuse while cached.
        let source: UIImage
        let output: UIImage?
    }

    private struct BackdropState: Sendable {
        var entries: [ObjectIdentifier: BackdropEntry] = [:]
        var order: [ObjectIdentifier] = []
    }

    nonisolated private static let backdrops = OSAllocatedUnfairLock(initialState: BackdropState())
    /// CIContext is thread-safe; filters and their inputs remain local to each render.
    nonisolated private static let context = CIContext(options: [.cacheIntermediates: false])

    /// Call from a utility task when the displayed UIImage changes, never per frame.
    /// Concurrent requests for the same instance share one render. The bounded
    /// cache retains at most two nine-book shelves, including failed rasterizations.
    nonisolated static func makeBackdrop(from image: UIImage) -> UIImage? {
        backdrops.withLock { state in
            let key = ObjectIdentifier(image)
            if let cached = state.entries[key] { return cached.output }
            let output = renderBackdrop(from: image)
            if state.order.count >= 18 {
                state.entries.removeValue(forKey: state.order.removeFirst())
            }
            state.entries[key] = BackdropEntry(source: image, output: output)
            state.order.append(key)
            return output
        }
    }

    nonisolated private static func renderBackdrop(from image: UIImage) -> UIImage? {
        let source: CIImage
        if let cgImage = image.cgImage {
            source = CIImage(cgImage: cgImage)
        } else if let ciImage = image.ciImage {
            source = ciImage
        } else {
            return nil
        }
        let oriented = source.oriented(forExifOrientation: exifOrientation(image.imageOrientation))
        let extent = oriented.extent
        guard !extent.isNull, !extent.isInfinite,
              extent.minX.isFinite, extent.minY.isFinite,
              extent.width.isFinite, extent.height.isFinite,
              extent.width > 0, extent.height > 0 else { return nil }

        let scale = min(1, 320 / max(extent.width, extent.height))
        let width = max(1, min(320, (extent.width * scale).rounded(.down)))
        let height = max(1, min(320, (extent.height * scale).rounded(.down)))
        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        let scaled = oriented
            .transformed(by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY))
            .transformed(by: CGAffineTransform(scaleX: width / extent.width, y: height / extent.height))
            .cropped(to: bounds)
        // Composite before blurring so transparent artwork cannot acquire black
        // fringes. Clamp before the blur and crop after it to keep opaque edges.
        let base = CIImage(color: CIColor(red: 0.94, green: 0.92, blue: 0.86, alpha: 1))
            .cropped(to: bounds)
        let output = scaled.composited(over: base)
            .clampedToExtent()
            .applyingFilter("CIGaussianBlur", parameters: [
                kCIInputRadiusKey: min(2.8, max(0.5, max(width, height) * 0.009))
            ])
            .cropped(to: bounds)
            .applyingFilter("CIColorControls", parameters: [
                kCIInputSaturationKey: 0.6,
                kCIInputContrastKey: 0.96
            ])
            .composited(over: base)
        guard let cgImage = context.createCGImage(
            output, from: bounds, format: .RGBA8, colorSpace: CGColorSpaceCreateDeviceRGB()
        ) else { return nil }
        return UIImage(cgImage: cgImage, scale: 1, orientation: .up)
    }

    nonisolated private static func exifOrientation(_ orientation: UIImage.Orientation) -> Int32 {
        switch orientation {
        case .up: return 1
        case .upMirrored: return 2
        case .down: return 3
        case .downMirrored: return 4
        case .leftMirrored: return 5
        case .right: return 6
        case .rightMirrored: return 7
        case .left: return 8
        @unknown default: return 1
        }
    }
}
