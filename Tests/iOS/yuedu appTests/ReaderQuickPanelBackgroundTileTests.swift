import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

/// Background samples must fit their offered half/quarter-page column with labels
/// underneath; saved landscape pictures must clip to the same responsive sample frame.
@MainActor
struct ReaderQuickPanelBackgroundTileTests {
    private static let tileSize = CGSize(
        width: DSLayout.readerQuickPanelBackgroundTileWidth,
        height: DSLayout.readerQuickPanelReadingBackgroundTileHeight
    )

    @Test("a tile keeps to its own width whatever the shape of its picture", arguments: [
        CGSize(width: 120, height: 90),  // 4:3
        CGSize(width: 160, height: 90),  // 16:9
        CGSize(width: 90, height: 90),   // square — still wider than 74×82
        CGSize(width: 90, height: 120),  // portrait, which never overflowed
    ])
    func tileWidthIgnoresPictureAspect(pictureSize: CGSize) {
        // Only the aspect matters; render at 1× so the bitmaps stay tiny.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let picture = UIGraphicsImageRenderer(size: pictureSize, format: format).image { context in
            UIColor.gray.setFill()
            context.fill(CGRect(origin: .zero, size: pictureSize))
        }
        let tile = ReaderQuickPanelBackgroundTile(
            fill: DSColor.neutralControlFill,
            image: picture,
            title: "Landscape",
            titleColor: DSColor.textPrimary,
            selected: true
        )
        let host = UIHostingController(rootView: tile)

        // A responsive sample occupies exactly its offered column, even when the
        // imported image is landscape. The label sits below the 48pt sample.
        for width: CGFloat in [64, 74, 96, 140] {
            let fitted = host.sizeThatFits(in: CGSize(width: width, height: 300))
            #expect(abs(fitted.width - width) < 1,
                    "picture \(pictureSize) offered \(width) fitted \(fitted)")
            #expect(fitted.height > DSLayout.readerQuickPanelBackgroundSampleHeight)
            #expect(fitted.height < 220)
        }
    }

    @Test("built-in captions have their own height and a clear gap below the painted sample",
          arguments: [DynamicTypeSize.large, .xxxLarge, .accessibility3, .accessibility5])
    func builtInCaptionsStayBelowPaintedSample(size: DynamicTypeSize) throws {
        let backgrounds: [(ReaderTheme, String)] = [
            (.night, "黑色"), (.white, "白色"), (.green, "护眼绿"), (.sepia, "棕色")
        ]
        // The actual column widths of a 320pt panel: four columns normally, two
        // at accessibility sizes. Test selected and unselected painting alike.
        let columns: CGFloat = size.isAccessibilitySize ? 2 : 4
        let width = (320 - 2 * DSSpacing.lg - (columns - 1) * DSSpacing.md) / columns
        let sample = try render(BackgroundSampleHeightProbe(), width: width, size: size)
        for (background, title) in backgrounds {
            let caption = try render(
                Text(title).font(DSFont.readerMenu(.caption))
                    .multilineTextAlignment(.center).lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity), width: width, size: size
            )
            for selected in [false, true] {
                let tile = ReaderQuickPanelBackgroundTile(
                    fill: background.previewBackgroundColor, image: nil, title: title,
                    titleColor: background.previewTextColor, selected: selected,
                    captionSpacing: DSSpacing.sm
                )
                let image = try render(tile, width: width, size: size)
                #expect(abs(image.size.width - width) <= 1)
                #expect(abs(image.size.height - (sample.size.height + DSSpacing.sm + caption.size.height)) <= 2,
                        "The complete caption must contribute to the measured panel height: \(title), \(size)")
                #expect(image.size.height >= DSLayout.minimumTapTarget)
                try expectClearCaptionGap(in: image, sampleHeight: sample.size.height)
            }
        }
    }

    private func render<Content: View>(
        _ content: Content, width: CGFloat, size: DynamicTypeSize
    ) throws -> UIImage {
        let renderer = ImageRenderer(content: content
            .environment(\.dynamicTypeSize, size)
            .environment(\.colorScheme, .light)
            .background(Color.white))
        renderer.proposedSize = ProposedViewSize(width: width, height: nil)
        renderer.scale = 1
        return try #require(renderer.uiImage)
    }

    private func expectClearCaptionGap(in image: UIImage, sampleHeight: CGFloat) throws {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let clear = try pixels.withUnsafeMutableBytes { bytes -> Bool in
            let context = try #require(CGContext(
                data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let data = bytes.bindMemory(to: UInt8.self)
            // Leave a pixel at each edge for fractional-point rasterization.
            // Size-only assertions cannot catch GeometryReader's paint overflow.
            let start = Int(ceil(sampleHeight)) + 1
            let end = Int(floor(sampleHeight + DSSpacing.sm)) - 1
            guard start < end, end < height else { return false }
            for y in start..<end {
                for x in 0..<width {
                    let offset = (y * width + x) * 4
                    if data[offset] < 250 || data[offset + 1] < 250 || data[offset + 2] < 250 {
                        return false
                    }
                }
            }
            return true
        }
        #expect(clear, "No sample fill, preview text or selection badge may paint into the caption gap")
    }
}

private struct BackgroundSampleHeightProbe: View {
    @ScaledMetric(relativeTo: .caption) private var height = DSLayout.readerQuickPanelBackgroundSampleHeight
    var body: some View { Color.clear.frame(height: height) }
}
