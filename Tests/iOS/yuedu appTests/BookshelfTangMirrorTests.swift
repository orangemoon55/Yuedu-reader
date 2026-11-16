import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class BookshelfTangMirrorTests: XCTestCase {
    func testCoverPaperClearsMirrorBossEngravedRimAndOtherBooksThroughoutRotation() {
        for diameter: CGFloat in [240, 288, 320, 393, 440] {
            for count in 1...9 {
                let size = BookshelfRingPresentation.mirrorCoverSize(diameter: diameter, count: count)
                let radius = BookshelfRingPresentation.mirrorOrbitRadius(diameter: diameter, count: count)
                XCTAssertGreaterThan(size.width, 0)
                let dx = min(max(size.width * 0.06, 2), 4)
                let dy = min(max(size.height * 0.045, 2.5), 4.5)
                var outer: CGFloat = 0, centerGap = CGFloat.infinity, bookGap = CGFloat.infinity
                for degree in 0..<360 {
                    let bounds = (0..<count).map { slot -> CGRect in
                        let angle = (CGFloat(degree) + CGFloat(slot) * 360 / CGFloat(count) - 90) * .pi / 180
                        return CGRect(x: cos(angle) * radius - size.width / 2,
                                      y: sin(angle) * radius - size.height / 2,
                                      width: size.width + dx, height: size.height + dy)
                    }
                    for (index, rect) in bounds.enumerated() {
                        for x in [rect.minX, rect.maxX] {
                            for y in [rect.minY, rect.maxY] { outer = max(outer, hypot(x, y)) }
                        }
                        centerGap = min(centerGap, hypot(max(rect.minX, min(0, rect.maxX)),
                                                         max(rect.minY, min(0, rect.maxY))) - diameter * 0.083)
                        for other in bounds.dropFirst(index + 1) {
                            bookGap = min(bookGap, hypot(max(0, max(rect.minX - other.maxX, other.minX - rect.maxX)),
                                                          max(0, max(rect.minY - other.maxY, other.minY - rect.maxY))))
                        }
                    }
                }
                XCTAssertLessThanOrEqual(outer, diameter * 0.411, "\(diameter)pt / \(count) books")
                XCTAssertGreaterThanOrEqual(centerGap, 2)
                if count > 1 { XCTAssertGreaterThanOrEqual(bookGap, 2) }
            }
        }
    }

    func testTwinMirrorsRemainOppositeAndOutsideCoverAnnulus() {
        for diameter: CGFloat in [240, 320, 393, 440] {
            for angle: CGFloat in [-10000, -180, 0, 23, 90, 2200] {
                let centers = TangTwinMirrorGeometry.centers(diameter: diameter, rotation: angle)
                XCTAssertEqual(centers.count, 2)
                XCTAssertEqual(centers[0].x + centers[1].x, diameter, accuracy: 0.000001)
                XCTAssertEqual(centers[0].y + centers[1].y, diameter, accuracy: 0.000001)
                let r = TangTwinMirrorGeometry.mirrorRatio * diameter / 2
                for c in centers {
                    let orbit = hypot(c.x - diameter / 2, c.y - diameter / 2)
                    XCTAssertGreaterThan(orbit - r, diameter * 0.411)
                    XCTAssertLessThan(orbit + r, diameter * 0.49)
                }
            }
        }
        XCTAssertTrue(TangTwinMirrorGeometry.centers(diameter: 0, rotation: 0).isEmpty)
        XCTAssertTrue(TangTwinMirrorGeometry.centers(diameter: 320, rotation: .nan).isEmpty)
        XCTAssertTrue(TangMirrorSectorLines(count: 0).path(in: CGRect(x: 0, y: 0, width: 320, height: 320)).isEmpty)
        XCTAssertTrue(TangMirrorSelectedSector(slot: 0, count: 4).path(in: .zero).isEmpty)
    }

    func testMirrorTextureExistsAndCenterIsTheSameMiniature() throws {
        for style: UIUserInterfaceStyle in [.light, .dark] {
            let image = try XCTUnwrap(UIImage(named: "BookshelfTangMirror", in: .main,
                                             compatibleWith: UITraitCollection(userInterfaceStyle: style)))
            XCTAssertGreaterThanOrEqual(image.size.width * image.scale, 720)
            XCTAssertEqual(image.size.width, image.size.height, accuracy: 0.01)
        }
        let boss = ImageRenderer(content: BookshelfRingCenterBadge(diameter: 96)
            .environment(\.colorScheme, .dark).frame(width: 96, height: 96))
        boss.scale = 2
        let image = try XCTUnwrap(boss.uiImage)
        XCTAssertEqual(image.size.width, 96, accuracy: 0.01)
        attach(image, "grape-mirror-draw-button")
    }

    func testNativeNightCopperMirrorAndOrbitRenderAtRestAndInMotion() throws {
        for spinning in [false, true] {
            let renderer = ImageRenderer(content: BookshelfTangMirror(
                diameter: 360, rotation: 32, count: 9, selectedSlot: 2,
                isSpinning: spinning, isDrawing: spinning
            ).environment(\.colorScheme, .dark).frame(width: 360, height: 360))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            XCTAssertEqual(image.size.width, 360, accuracy: 0.01)
            attach(image, spinning ? "night-copper-twin-mirrors" : "night-copper-tang-mirror")
        }
    }

    private func attach(_ image: UIImage, _ name: String) {
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
