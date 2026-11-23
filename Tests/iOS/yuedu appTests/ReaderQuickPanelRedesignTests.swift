import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class ReaderQuickPanelRedesignTests: XCTestCase {
    func testCompactPanelAndLargeTextRenderWithoutHorizontalOverflow() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let variants: [(CGFloat, ReaderTheme, DynamicTypeSize)] = [
            (390, .white, .large), (390, .night, .large), (320, .white, .large),
            (390, .white, .accessibility3)
        ]
        for (width, theme, size) in variants {
            let view = ReaderQuickThemePanelView(fontSize: .constant(19), readerTheme: .constant(theme),
                pageTurnOption: .ripple, isVerticalWritingMode: false,
                onSelectPageTurnOption: { _ in }, onSelectRoute: { _ in })
                .environment(\.dynamicTypeSize, size)
            let host = UIHostingController(rootView: view)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 844)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.frame = window.bounds
            for _ in 0..<8 { host.view.layoutIfNeeded(); await Task.yield() }
            let scrolls = descendants(host.view).compactMap { $0 as? UIScrollView }
            XCTAssertFalse(scrolls.isEmpty)
            for scroll in scrolls where scroll.bounds.width > 200 {
                XCTAssertLessThanOrEqual(scroll.contentSize.width, scroll.bounds.width + 1,
                    "No page modes or default backgrounds may require horizontal scrolling")
            }
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            })
            attachment.name = "reader15-\(Int(width))-\(theme.epubJSName)-\(size)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
