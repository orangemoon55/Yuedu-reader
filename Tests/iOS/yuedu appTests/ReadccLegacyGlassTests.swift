import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class ReadccLegacyGlassTests: XCTestCase {
    func testPaletteIsBoundedAndUsesNoOSAvailabilitySwitch() {
        for dark in [false, true] {
            for high in [false, true] {
                let p = ReadccGlassPalette.resolve(dark: dark, increasedContrast: high)
                for value in [p.lightRim, p.darkRim, p.wash, p.selectedWash, p.sheen, p.shadow] {
                    XCTAssertTrue(value.isFinite && (0...1).contains(value))
                }
                XCTAssertGreaterThan(p.lightRim, p.darkRim)
                XCTAssertGreaterThan(p.edgeWidth, 0)
                XCTAssertLessThanOrEqual(p.edgeWidth, 1)
                XCTAssertEqual(p.selectedWash == 1, high)
            }
        }
    }

    func testSurfaceNeverChangesOriginalControlDimensions() {
        let plain = Text("筛选").frame(width: 104, height: 44)
        let painted = plain.readccGlassSurface(cornerRadius: 22)
        let selected = plain.readccGlassSurface(cornerRadius: 22, selected: true)
        let proposal = CGSize(width: 390, height: 400)
        let size = UIHostingController(rootView: plain).sizeThatFits(in: proposal)
        for measured in [UIHostingController(rootView: painted).sizeThatFits(in: proposal),
                         UIHostingController(rootView: selected).sizeThatFits(in: proposal)] {
            XCTAssertEqual(measured.width, size.width, accuracy: 0.01)
            XCTAssertEqual(measured.height, size.height, accuracy: 0.01)
        }
        XCTAssertEqual(size.width, 104, accuracy: 0.01)
        XCTAssertEqual(size.height, 44, accuracy: 0.01)
    }

    func testLiveBackdropAccessibilityFallbackAndLightDarkSnapshots() async throws {
        let settings = GlobalSettings.shared
        let originalGlass = settings.interfaceFrostedGlass
        let originalTransparency = settings.interfaceGlassTransparency
        settings.interfaceFrostedGlass = true
        settings.interfaceGlassTransparency = 1
        defer {
            settings.interfaceFrostedGlass = originalGlass
            settings.interfaceGlassTransparency = originalTransparency
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        defer { window.isHidden = true; window.rootViewController = nil; oldWindow?.makeKey() }
        for scheme in [ColorScheme.light, .dark] {
            for opaque in [false, true] {
                let content = GlassMaterialHarness()
                    .environment(\.colorScheme, scheme)
                    .environment(\.accessibilityReduceTransparency, opaque)
                let host = UIHostingController(rootView: content)
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                for _ in 0..<6 {
                    await Task.yield()
                    try await Task.sleep(for: .milliseconds(30))
                    host.view.layoutIfNeeded()
                }
                let blurs = descendants(host.view).compactMap { $0 as? UIVisualEffectView }
                if opaque {
                    XCTAssertTrue(blurs.isEmpty, "Reduce Transparency must not leave live blur layers")
                } else {
                    XCTAssertGreaterThanOrEqual(blurs.count, 3, "The iOS17-compatible path must mount real live backdrops")
                    XCTAssertTrue(blurs.allSatisfy { !$0.isUserInteractionEnabled })
                    XCTAssertTrue(blurs.allSatisfy { $0.bounds.width > 0 && $0.bounds.height > 0 })
                }
                let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
                let image = renderer.image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                XCTAssertNotNil(image.cgImage)
                let attachment = XCTAttachment(image: image)
                attachment.name = "Readcc33-glass-\(scheme)-opaque-\(opaque)"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}

private struct GlassMaterialHarness: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.cyan.opacity(0.35), .pink.opacity(0.15), .indigo.opacity(0.32)],
                           startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 32) {
                Text("Readcc · 玻璃材质").font(.title2.weight(.semibold))
                HStack(spacing: 12) {
                    DSCapsuleLabel(title: "未选中")
                    DSCapsuleLabel(title: "已选中", isSelected: true)
                }
                HStack(spacing: 24) {
                    ForEach(["gobackward.15", "play.fill", "goforward.15"], id: \.self) { name in
                        Image(systemName: name).font(.system(size: 24))
                            .frame(width: 52, height: 52)
                            .readccGlassSurface(cornerRadius: 26, onDark: true)
                            .foregroundStyle(.white)
                    }
                }
                Spacer()
                FloatingRootTabBar(tabs: [.bookshelf, .explore, .settings, .search],
                                   selection: .constant(.explore))
            }.padding(.vertical, 56)
        }
    }
}
