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
}
