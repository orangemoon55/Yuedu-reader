import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class ReaderChapterTitlePresentationTests: XCTestCase {
    func testStandaloneTitleFormHasVisibleWorkingControl() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let originalStyle = ReaderConfig.shared.chapterTitleStyle
        defer {
            ReaderConfig.shared.chapterTitleStyle = originalStyle
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        let host = UIHostingController(rootView: ReaderSettingsView(
            fontSize: .constant(18),
            theme: .constant(.white),
            initialSection: .chapterTitleStyle
        ))
        window.rootViewController = host
        window.makeKeyAndVisible()

        let toggle = try await waitForView(in: host.view) { view -> UISwitch? in
            guard view.accessibilityIdentifier == "reader.chapterTitleStyle.advancedCSS" else { return nil }
            return view as? UISwitch
        }
        let form = try XCTUnwrap(
            descendants(of: host.view).first { $0.accessibilityIdentifier == "reader.chapterTitleStyle.form" },
            "The standalone route must materialize the title Form"
        )
        XCTAssertGreaterThan(form.bounds.width, 0)
        XCTAssertGreaterThan(form.bounds.height, 0)
        let frame = toggle.convert(toggle.bounds, to: window)
        XCTAssertTrue(window.bounds.intersects(frame))
        XCTAssertGreaterThan(frame.height, 0)

        let wasEnabled = ReaderConfig.shared.chapterTitleStyle.advancedCSSEnabled
        toggle.setOn(!wasEnabled, animated: false)
        toggle.sendActions(for: .valueChanged)
        await Task.yield()
        XCTAssertEqual(ReaderConfig.shared.chapterTitleStyle.advancedCSSEnabled, !wasEnabled)
    }

    func testHeaderFooterRouteHasNoEmbeddedChapterTitleForm() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: ReaderSettingsView(
            fontSize: .constant(18),
            theme: .constant(.white),
            initialSection: .headerFooter
        ))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        try await waitUntil {
            !self.descendants(of: host.view).isEmpty
        }
        XCTAssertNil(
            descendants(of: host.view).first { $0.accessibilityIdentifier == "reader.chapterTitleStyle.form" },
            "Header/footer must not instantiate a nested chapter-title Form"
        )
        XCTAssertNil(
            descendants(of: host.view).first { $0.accessibilityIdentifier == "reader.chapterTitleStyle.advancedCSS" },
            "Header/footer must not expose the chapter-title control"
        )
    }

    private func waitForView<T>(
        in root: UIView,
        _ match: (UIView) -> T?
    ) async throws -> T {
        for _ in 0..<80 {
            root.setNeedsLayout()
            root.layoutIfNeeded()
            if let result = descendants(of: root).compactMap(match).first { return result }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "ReaderChapterTitlePresentationTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The chapter-title control did not appear; the page may be blank"])

    }

    private func waitUntil(_ predicate: @escaping () -> Bool) async throws {
        for _ in 0..<80 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(25))
        }
        XCTFail("Timed out waiting for hosted SwiftUI content")
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}
