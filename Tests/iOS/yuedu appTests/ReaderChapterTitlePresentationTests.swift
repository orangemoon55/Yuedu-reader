import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class ReaderChapterTitlePresentationTests: XCTestCase {
    func testStandaloneTitleFormHasVisibleWorkingControl() async throws {
        let originalStyle = ReaderConfig.shared.chapterTitleStyle
        let presentation = try await present(.chapterTitleStyle)
        let host = presentation.host
        let window = presentation.window
        do {
        attach(window, name: "standalone-chapter-title-before-interaction")
        // SwiftUI may place the identifier on a hosting wrapper, not UISwitch itself.
        // This route's first switch is the production advanced-CSS control.
        let toggle = try await waitForView(in: host.view) { view -> UISwitch? in
            guard let control = view as? UISwitch, control.window === window,
                  !control.isHidden, control.alpha > 0 else { return nil }
            let frame = control.convert(control.bounds, to: window)
            return window.bounds.intersects(frame) ? control : nil
        }
        XCTAssertFalse(self.descendants(of: host.view).contains {
            $0.accessibilityIdentifier == "reader.settings.preview"
        }, "The title editor must not be embedded inside the generic preview/Form")
        XCTAssertNotNil(self.descendants(of: host.view).first { $0 is UIScrollView },
                        "The independent title Form must materialize its scrollable content")
        let frame = toggle.convert(toggle.bounds, to: window)
        XCTAssertTrue(window.bounds.intersects(frame))
        XCTAssertGreaterThan(frame.height, 0)

        let wasEnabled = ReaderConfig.shared.chapterTitleStyle.advancedCSSEnabled
        toggle.setOn(!wasEnabled, animated: false)
        toggle.sendActions(for: .valueChanged)
        try await waitUntil {
            ReaderConfig.shared.chapterTitleStyle.advancedCSSEnabled == !wasEnabled
        }
        XCTAssertEqual(ReaderConfig.shared.chapterTitleStyle.advancedCSSEnabled, !wasEnabled)
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = "standalone-chapter-title-visible-working-control"
        attachment.lifetime = .keepAlways
        add(attachment)
        } catch {
            await close(presentation)
            ReaderConfig.shared.chapterTitleStyle = originalStyle
            throw error
        }
        await close(presentation)
        ReaderConfig.shared.chapterTitleStyle = originalStyle
    }

    func testHeaderFooterRouteHasNoEmbeddedChapterTitleForm() async throws {
        let presentation = try await present(.headerFooter)
        let host = presentation.host
        do {
        _ = try await waitForView(in: host.view) { view -> UIView? in
            view.accessibilityIdentifier == "reader.settings.headerFooter.editor" ? view : nil
        }
        XCTAssertNil(
            descendants(of: host.view).first { $0.accessibilityIdentifier == "reader.chapterTitleStyle.form" },
            "Header/footer must not instantiate a nested chapter-title Form"
        )
        XCTAssertNil(
            descendants(of: host.view).first { $0.accessibilityIdentifier == "reader.chapterTitleStyle.advancedCSS" },
            "Header/footer must not expose the chapter-title control"
        )
        attach(presentation.window, name: "header-footer-without-title-form")
        } catch {
            await close(presentation)
            throw error
        }
        await close(presentation)
    }

    private struct Presentation {
        let window: UIWindow
        let previous: UIWindow?
        let presenter: UIViewController
        let host: ChapterSettingsTestHost
    }

    private func present(_ section: ReaderSettingsInitialSection) async throws -> Presentation {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let presenter = ChapterSettingsTestPresenter()
        presenter.view.backgroundColor = .systemBackground
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        do {
            try await waitUntil { presenter.didAppear && presenter.view.window === window }
        } catch {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
            throw error
        }
        let host = ChapterSettingsTestHost(rootView: ReaderSettingsView(
            fontSize: .constant(18), theme: .constant(.white), initialSection: section
        ))
        host.modalPresentationStyle = .pageSheet
        let presentation = Presentation(window: window, previous: previous,
                                        presenter: presenter, host: host)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            presenter.present(host, animated: false) { done.resume() }
        }
        do {
            try await waitUntil {
                host.didAppear && host.view.window === window && !host.isBeingPresented
            }
        } catch {
            await close(presentation)
            throw error
        }
        return presentation
    }

    private func close(_ presentation: Presentation) async {
        if presentation.host.presentingViewController != nil {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                presentation.presenter.dismiss(animated: false) { done.resume() }
            }
        }
        await Task.yield()
        XCTAssertNil(presentation.presenter.presentedViewController)
        XCTAssertTrue(presentation.host.didDisappear, "The settings page must finish dismissal before teardown")
        presentation.window.isHidden = true
        presentation.window.rootViewController = nil
        presentation.previous?.makeKeyAndVisible()
        await Task.yield()
    }

    private func attach(_ window: UIWindow, name: String) {
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        let attachment = XCTAttachment(image: image)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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
        throw NSError(domain: "ReaderChapterTitlePresentationTests", code: 2,
                      userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for the settings page lifecycle"])
    }

    private func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap(descendants)
    }
}

@MainActor
private final class ChapterSettingsTestHost: UIHostingController<ReaderSettingsView> {
    private(set) var didAppear = false
    private(set) var didDisappear = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        didDisappear = true
    }
}

@MainActor
private final class ChapterSettingsTestPresenter: UIViewController {
    private(set) var didAppear = false
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        didAppear = true
    }
}
