import Foundation
import Testing
@testable import CodaCore

struct SceneViewportSizeTests {
    @Test func snapshotLayoutsDoNotResizeAnExistingPage() {
        var viewport = SceneViewportSize()
        let original = CGSize(width: 860, height: 1000)
        viewport.record(original, active: true)
        for snapshot in [CGSize.zero, CGSize(width: 430, height: 500), CGSize(width: 1200, height: 1400)] {
            viewport.record(snapshot, active: false)
            #expect(viewport.resolved(snapshot, active: false) == original)
        }
        // Reattachment can first propose zero even after activation.
        #expect(viewport.resolved(.zero, active: true) == original)
        #expect(viewport.lastActiveSize == original)
    }

    @Test func foregroundRotationAndMultitaskingStillResize() {
        var viewport = SceneViewportSize()
        let portrait = CGSize(width: 700, height: 1000)
        let landscape = CGSize(width: 1000, height: 700)
        viewport.record(portrait, active: true)
        #expect(viewport.resolved(landscape, active: true) == landscape)
        viewport.record(landscape, active: true)
        #expect(viewport.resolved(.zero, active: false) == landscape)
        let split = CGSize(width: 500, height: 700)
        viewport.record(split, active: true)
        #expect(viewport.lastActiveSize == split)
    }

    @Test func invalidGeometryCannotReplaceTheLastViewport() {
        var viewport = SceneViewportSize()
        let valid = CGSize(width: 700, height: 1000)
        viewport.record(valid, active: true)
        for invalid in [CGSize.zero, CGSize(width: -1, height: 500),
                        CGSize(width: CGFloat.infinity, height: 500), CGSize(width: CGFloat.nan, height: 500)] {
            viewport.record(invalid, active: true)
            #expect(viewport.resolved(invalid, active: true) == valid)
        }
    }
}
