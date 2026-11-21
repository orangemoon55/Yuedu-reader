import CoreGraphics
import Foundation
import Testing
import UIKit
@testable import yuedu_app

@Suite("Manga edge crop", .serialized)
@MainActor
struct MangaEdgeCropTests {

    @Test("left and right crop values are independent, bounded, and Codable")
    func edgeCropValuesStayIndependentAndBounded() throws {
        let crop = FixedPageEdgeCrop(left: 0.12, right: 0.07)
        #expect(crop.left == 0.12)
        #expect(crop.right == 0.07)
        #expect(crop.retainedWidthFraction == 0.81)
        #expect(FixedPageEdgeCrop(left: -1, right: .infinity).left == 0)
        #expect(FixedPageEdgeCrop(left: .nan, right: 1).left == 0)
        #expect(FixedPageEdgeCrop(left: 1, right: 1).left == FixedPageEdgeCrop.maximumPerSide)
        #expect(FixedPageEdgeCrop(left: 1, right: 1).retainedWidthFraction == 0.6)

        let restored = try JSONDecoder().decode(FixedPageEdgeCrop.self, from: JSONEncoder().encode(crop))
        #expect(restored == crop)
    }

    @Test("edge crop settings survive the per-book settings file")
    func edgeCropSettingsPersistPerBook() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaEdgeCropTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let fileURL = directory.appendingPathComponent("reader-settings.json")
        let bookID = UUID()
        var configuration = FixedPageReadingMode.rtl.recommendedConfiguration
        configuration.horizontalEdgeCrop = FixedPageEdgeCrop(left: 0.08, right: 0.03)

        BookReaderSettingsStore(fileURL: fileURL).setFixedPageConfiguration(configuration, for: bookID)
        let reopened = BookReaderSettingsStore(fileURL: fileURL)
            .fixedPageConfiguration(for: bookID)
        #expect(reopened.horizontalEdgeCrop == configuration.horizontalEdgeCrop)
    }

    @Test("old settings without an edge crop remain uncropped")
    func oldConfigurationDefaultsToNoEdgeCrop() throws {
        let data = try JSONEncoder().encode(FixedPageReadingMode.rtl.recommendedConfiguration)
        var legacy = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        legacy.removeValue(forKey: "horizontalEdgeCrop")
        let restored = try JSONDecoder().decode(
            FixedPageReaderConfiguration.self,
            from: JSONSerialization.data(withJSONObject: legacy)
        )
        #expect(restored.horizontalEdgeCrop == .zero)
    }

    @Test("cropped viewport keeps only the selected interior and preserves spine alignment")
    func croppedViewportGeometry() throws {
        let crop = FixedPageEdgeCrop(left: 0.10, right: 0.20)
        let centered = try #require(crop.imageFrame(
            imageSize: CGSize(width: 100, height: 200),
            viewportSize: CGSize(width: 100, height: 200)
        ))
        #expect(centered.minX == 5)
        #expect(centered.width == 100)
        #expect(centered.minX + crop.left * centered.width == 15)
        #expect(centered.maxX - crop.right * centered.width == 85)

        let leading = try #require(crop.imageFrame(
            imageSize: CGSize(width: 100, height: 200),
            viewportSize: CGSize(width: 100, height: 200),
            alignment: .leading
        ))
        let trailing = try #require(crop.imageFrame(
            imageSize: CGSize(width: 100, height: 200),
            viewportSize: CGSize(width: 100, height: 200),
            alignment: .trailing
        ))
        #expect(leading.minX == -10)
        #expect(trailing.maxX == 120)
        #expect(crop.imageFrame(imageSize: .zero, viewportSize: CGSize(width: 100, height: 200)) == nil)
    }

    @Test("manual crop clips the displayed page without changing original image pixels")
    func displayedCropLeavesSourceFileAndImagePixelsUntouched() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("MangaEdgeCropTests-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let size = CGSize(width: 100, height: 200)
        let sourcePNG = UIGraphicsImageRenderer(size: size, format: format).pngData { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 10, height: 200))
            UIColor.green.setFill()
            context.fill(CGRect(x: 10, y: 0, width: 70, height: 200))
            UIColor.blue.setFill()
            context.fill(CGRect(x: 80, y: 0, width: 20, height: 200))
        }
        try sourcePNG.write(to: url)
        let originalFileBytes = try Data(contentsOf: url)
        let sourceImage = try #require(UIImage(contentsOfFile: url.path))
        let originalPixelSize = CGSize(width: sourceImage.cgImage!.width, height: sourceImage.cgImage!.height)
        let page = FixedPage(id: 0, imageURL: url.absoluteString, headers: [:], localURL: url)
        var configuration = FixedPageReadingMode.rtl.recommendedConfiguration
        configuration.horizontalEdgeCrop = FixedPageEdgeCrop(left: 0.10, right: 0.20)
        let controller = FixedPagePageViewController(
            page: page,
            index: 0,
            fixedPageReaderConfiguration: configuration,
            targetWidth: 100
        )
        controller.view.frame = CGRect(origin: .zero, size: size)
        controller.view.layoutIfNeeded()
        await controller.loadTask?.value
        controller.view.layoutIfNeeded()

        #expect(controller.view.clipsToBounds)
        #expect(controller.imageView.image?.cgImage?.width == Int(originalPixelSize.width))
        #expect(controller.imageView.image?.cgImage?.height == Int(originalPixelSize.height))
        #expect(try Data(contentsOf: url) == originalFileBytes)
        #expect(controller.imageView.frame.minX == 5)
        #expect(controller.imageView.frame.maxX == 105)
        let mask = try #require(controller.imageView.layer.mask as? CAShapeLayer)
        let visible = try #require(mask.path).boundingBoxOfPath
        #expect(visible.minX == 10)
        #expect(visible.maxX == 80)
        #expect(visible.height == 200)
        let visibleOnPage = controller.imageView.convert(visible, to: controller.view)
        #expect(visibleOnPage.minX == 15)
        #expect(visibleOnPage.maxX == 85)
    }
}
