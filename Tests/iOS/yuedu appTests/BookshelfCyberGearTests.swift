import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import yuedu_app

@Suite("Cyber gear decorative bounds")
struct BookshelfCyberGearTests {
    @Test("Gear remains inside its square and never covers the book annulus", arguments: [CGFloat(240), 320, 440])
    func narrowRim(diameter: CGFloat) {
        let rect = CGRect(x: 20, y: 30, width: diameter, height: diameter)
        let path = CyberGearShape().path(in: rect)
        #expect(!path.isEmpty)
        #expect(rect.contains(path.boundingRect))
        let center = CGPoint(x: rect.midX, y: rect.midY)
        #expect(!path.contains(center))
        for index in 0..<360 {
            let angle = CGFloat(index) * .pi / 180
            let inside = CGPoint(x: center.x + cos(angle) * diameter * 0.46,
                                 y: center.y + sin(angle) * diameter * 0.46)
            #expect(!path.contains(inside))
        }
        let band = CGPoint(x: center.x + diameter * 0.47, y: center.y)
        #expect(path.contains(band))
    }

    @Test("Empty and invalid geometry produces no path")
    func invalidBounds() {
        #expect(CyberGearShape().path(in: .zero).isEmpty)
        #expect(CyberGearShape().path(in: CGRect(x: 0, y: 0, width: -10, height: 100)).isEmpty)
    }

    @Test("Static and spinning gear artwork can render without a time loop")
    @MainActor
    func rendersInteractionStates() throws {
        for spinning in [false, true] {
            let view = BookshelfCyberGear(diameter: 320, rotation: 35, colorScheme: .light,
                                         isSpinning: spinning, selectedSlot: 2)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            #expect(image.width == 640 && image.height == 640)
        }
    }
}
