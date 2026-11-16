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
        let toothMidpoint = .pi / CGFloat(CyberGearShape.toothCount)
        let band = CGPoint(x: center.x + cos(toothMidpoint) * diameter * 0.47,
                           y: center.y + sin(toothMidpoint) * diameter * 0.47)
        #expect(path.contains(band))
    }

    @Test("28 deep teeth keep the book annulus clear and the tips prominent")
    func toothProfileAndClearance() {
        #expect(CyberGearShape.toothCount == 28)
        #expect(CyberGearShape.innerRadius == 0.466)
        #expect(CyberGearShape.rootRadius == 0.468)
        #expect(CyberGearShape.tipRadius == 0.497)
        let diameter: CGFloat = 320
        let center = CGPoint(x: diameter / 2, y: diameter / 2)
        let path = CyberGearShape().path(in: CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))
        let tipAngle = -CGFloat.pi / 2 + CGFloat.pi / CGFloat(CyberGearShape.toothCount)
        let tip = CGPoint(x: center.x + cos(tipAngle) * diameter * 0.495,
                          y: center.y + sin(tipAngle) * diameter * 0.495)
        let rootAngle = -CGFloat.pi / 2
        let outsideRoot = CGPoint(x: center.x + cos(rootAngle) * diameter * 0.47,
                                  y: center.y + sin(rootAngle) * diameter * 0.47)
        let rootBand = CGPoint(x: center.x + cos(rootAngle) * diameter * 0.467,
                               y: center.y + sin(rootAngle) * diameter * 0.467)
        #expect(path.contains(tip))
        #expect(!path.contains(outsideRoot))
        #expect(path.contains(rootBand))
        for index in 0..<720 {
            let angle = CGFloat(index) * .pi / 360
            let coverEdge = CGPoint(x: center.x + cos(angle) * diameter * 0.465,
                                    y: center.y + sin(angle) * diameter * 0.465)
            #expect(!path.contains(coverEdge))
        }
    }

    @Test("Gear facets stay within bounds and avoid book covers")
    func facetsStayOnOuterRim() {
        let rect = CGRect(x: 16, y: 22, width: 320, height: 320)
        let path = CyberGearFacets().path(in: rect)
        #expect(!path.isEmpty)
        #expect(rect.contains(path.boundingRect))
        #expect(path.boundingRect.maxY <= rect.maxY)
        #expect(path.boundingRect.minY >= rect.minY)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        #expect(!path.contains(center))
        for index in 0..<360 {
            let angle = CGFloat(index) * .pi / 180
            let coverPoint = CGPoint(x: center.x + cos(angle) * rect.width * 0.465,
                                     y: center.y + sin(angle) * rect.width * 0.465)
            #expect(!path.contains(coverPoint))
        }
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
