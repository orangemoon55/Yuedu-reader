import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class MangaCanvasLayoutTests: XCTestCase {
    func testCanvasInsetsTheWholeViewportWithoutMaskingOrCropping() async throws {
        XCTAssertEqual(MangaCanvasLayout.sideMargin, 8)
        XCTAssertEqual(MangaCanvasLayout.horizontalInset(isManga: false), 0)
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let oldWindow = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        let parent = UIViewController()
        window.rootViewController = parent
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; oldWindow?.makeKey() }
        for manga in [false, true] {
            for width: CGFloat in [320, 390, 744] {
                var pageView: UIView?
                let content = CanvasViewportProbe { pageView = $0 }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .mangaCanvasMargins(isManga: manga)
                    .ignoresSafeArea()
                let host = UIHostingController(rootView: content)
                parent.addChild(host)
                parent.view.addSubview(host.view)
                host.view.frame = CGRect(x: 0, y: 0, width: width, height: 600)
                host.didMove(toParent: parent)
                for _ in 0..<8 {
                    host.view.setNeedsLayout()
                    host.view.layoutIfNeeded()
                    await Task.yield()
                    try await Task.sleep(for: .milliseconds(20))
                }
                let page = try XCTUnwrap(pageView)
                let frame = page.convert(page.bounds, to: host.view)
                let margin: CGFloat = manga ? 8 : 0
                XCTAssertEqual(frame.minX, margin, accuracy: 0.5)
                XCTAssertEqual(frame.maxX, width - margin, accuracy: 0.5)
                XCTAssertEqual(frame.width, width - margin * 2, accuracy: 0.5)
                XCTAssertNil(page.layer.mask, "A gutter is not a source-image crop mask")
                host.willMove(toParent: nil)
                host.view.removeFromSuperview()
                host.removeFromParent()
            }
        }
    }

    func testMangaTopRowRetainsButtonsAndAddsNovelRefreshAtCompactWidth() async throws {
        var refreshed = 0
        let row = MangaReaderTopBar(
            chapterTitle: "第 6 话", isModal: false, isLoading: false, hasChapters: true,
            onClose: {}, onContents: {}, onRefresh: { refreshed += 1 }, onSettings: {},
            onOfflineCache: {}, onChangeSource: {}
        ).frame(width: 320)
        try await withAccessibilityHost(in: row) { host in
            for _ in 0..<8 { await Task.yield() }
            let buttons = HomeRankAX.elements(in: host).filter { $0.accessibilityTraits.contains(.button) }
            XCTAssertEqual(buttons.count, 6)
            for button in buttons {
                XCTAssertGreaterThanOrEqual(button.accessibilityFrame.width, 44)
                XCTAssertGreaterThanOrEqual(button.accessibilityFrame.height, 44)
            }
            let refresh = try XCTUnwrap(buttons.first { $0.accessibilityLabel == localized("刷新") })
            XCTAssertTrue(refresh.accessibilityActivate())
            XCTAssertEqual(refreshed, 1)
            for i in buttons.indices {
                for j in buttons.indices where j > i {
                    let overlap = buttons[i].accessibilityFrame.intersection(buttons[j].accessibilityFrame)
                    XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 1)
                }
            }
            let image = UIGraphicsImageRenderer(bounds: host.bounds).image { _ in
                host.drawHierarchy(in: host.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "Readcc33-manga-top-row-320pt"
            attachment.lifetime = .keepAlways
            self.add(attachment)
        }
        XCTAssertEqual(ReaderChromeActionItem.refresh.defaultSystemImage, "arrow.clockwise")
    }

    func testRefreshingDisablesDuplicateRefreshTaps() async throws {
        var refreshed = 0
        let row = MangaReaderTopBar(chapterTitle: "Synthetic", isModal: false,
                                   isLoading: true, hasChapters: false,
                                   onClose: {}, onContents: {}, onRefresh: { refreshed += 1 }, onSettings: {})
        try await withAccessibilityHost(in: row) { host in
            for _ in 0..<8 { await Task.yield() }
            let button = try XCTUnwrap(HomeRankAX.elements(in: host).first {
                $0.accessibilityLabel == localized("刷新") && $0.accessibilityTraits.contains(.button)
            })
            XCTAssertTrue(button.accessibilityTraits.contains(.notEnabled))
            _ = button.accessibilityActivate()
            XCTAssertEqual(refreshed, 0)
        }
    }
}

private struct CanvasViewportProbe: UIViewRepresentable {
    let mounted: (UIView) -> Void
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .white
        mounted(view)
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
