import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class ReadccBackdropBlurTests: XCTestCase {
    func testSystemMaterialTracksLightAndDarkAppearance() {
        XCTAssertEqual(ReadccBackdropBlurMaterial.resolve(dark: false), .light)
        XCTAssertEqual(ReadccBackdropBlurMaterial.resolve(dark: true), .dark)
        XCTAssertEqual(ReadccBackdropBlurMaterial.light.uiBlurStyle, .systemMaterialLight)
        XCTAssertEqual(ReadccBackdropBlurMaterial.dark.uiBlurStyle, .systemMaterialDark)
    }

    func testOpaqueAndAccessibilityFallbacksDoNotRequestBackdropBlur() {
        XCTAssertFalse(InterfaceGlassPolicy.shouldUseBackdropBlur(
            transparency: 0, isEnabled: true, systemReduceTransparency: false
        ))
        XCTAssertTrue(InterfaceGlassPolicy.shouldUseBackdropBlur(
            transparency: 1, isEnabled: true, systemReduceTransparency: false
        ))
        XCTAssertFalse(InterfaceGlassPolicy.shouldUseBackdropBlur(
            transparency: 1, isEnabled: true, systemReduceTransparency: true
        ))
        XCTAssertFalse(InterfaceGlassPolicy.shouldUseBackdropBlur(
            transparency: 1, isEnabled: false, systemReduceTransparency: false
        ))
    }

    func testNativeBackdropMountsWithoutChangingForegroundLayout() async throws {
        let settings = GlobalSettings.shared
        let oldGlass = settings.interfaceFrostedGlass
        let oldTransparency = settings.interfaceGlassTransparency
        settings.interfaceFrostedGlass = true
        settings.interfaceGlassTransparency = 1
        defer {
            settings.interfaceFrostedGlass = oldGlass
            settings.interfaceGlassTransparency = oldTransparency
        }

        let plain = Text("Readable label").frame(width: 128, height: 48)
        let surface = plain.floatingSurfaceBackground(
            in: Capsule(style: .continuous),
            reduceTransparencyOverride: false
        )
        let proposal = CGSize(width: 320, height: 120)
        let plainSize = UIHostingController(rootView: plain).sizeThatFits(in: proposal)
        let surfaceSize = UIHostingController(rootView: surface).sizeThatFits(in: proposal)
        XCTAssertEqual(surfaceSize.width, plainSize.width, accuracy: 0.01)
        XCTAssertEqual(surfaceSize.height, plainSize.height, accuracy: 0.01)

        let scene = try XCTUnwrap(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        )
        let oldWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
        let host = UIHostingController(rootView: surface.environment(\.colorScheme, .light))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            oldWindow?.makeKey()
        }

        for _ in 0..<6 {
            await Task.yield()
            try await Task.sleep(for: .milliseconds(25))
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
        }

        let effects = descendants(host.view).compactMap { $0 as? UIVisualEffectView }
        XCTAssertEqual(effects.count, 1, "The foreground label should have one native backdrop surface")
        XCTAssertTrue(effects.allSatisfy { !$0.isUserInteractionEnabled })
        XCTAssertTrue(effects.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 })
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
