import XCTest
import SwiftUI
import UIKit
@testable import yuedu_app

@MainActor
final class ReaderTOCEdgeRenderingTests: XCTestCase {
    func testListAtBottomReturnsToFirstThenLatestWithoutOpeningAnyChapter() async throws {
        try await exercise(.horizontalList)
    }

    func testVerticalColumnsReturnToFirstThenLatestWithoutOpeningAnyChapter() async throws {
        try await exercise(.verticalRTLColumns)
    }

    private func exercise(_ mode: TOCLayoutMode) async throws {
        let library = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        defer { dlclose(library) }
        typealias Get = @convention(c) () -> Bool
        typealias Set = @convention(c) (Bool) -> Void
        let get = unsafeBitCast(try XCTUnwrap(dlsym(library, "_AXSAutomationEnabled")), to: Get.self)
        let set = unsafeBitCast(try XCTUnwrap(dlsym(library, "_AXSSetAutomationEnabled")), to: Set.self)
        let original = get(); set(true)
        defer { set(original) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let presenter = TOCEdgeTestPresenter()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        try await wait { presenter.appeared }
        let chapters = (0..<80).map { BookChapter(index: $0 * 2, title: "第\($0 + 1)章 测试目录", content: "") }
        var selections = 0
        var isPresented = true
        let host = TOCEdgeTestHost(rootView: ReaderTOCView(
            chapters: chapters, bookTitle: "首尾跳转验证", currentPage: 0, totalPages: 0,
            tocLayoutMode: mode, pageOffsets: [:], showsPageNumbers: false,
            currentIndex: chapters.last!.index, currentChapterID: chapters.last!.id,
            uncachedChapterIndexes: [], onSelectChapter: { _ in selections += 1 },
            isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })
        ))
        host.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            presenter.present(host, animated: false) { done.resume() }
        }
        do {
            try await wait { host.appeared }
            // The TOC opens on the existing last chapter, so it is already at the bottom.
            try await wait { self.edgeButton(in: host.view, title: localized("回頂部")) != nil }
            let back = try XCTUnwrap(edgeButton(in: host.view, title: localized("回頂部")))
            XCTAssertTrue(back.accessibilityActivate())
            try await wait { self.edgeButton(in: host.view, title: localized("去底部")) != nil }
            let latest = try XCTUnwrap(edgeButton(in: host.view, title: localized("去底部")))
            XCTAssertTrue(latest.accessibilityActivate())
            try await wait { self.edgeButton(in: host.view, title: localized("回頂部")) != nil }
            XCTAssertEqual(selections, 0, "Scrolling the TOC must not select or open a chapter")
            XCTAssertTrue(isPresented, "Jumping is not a read action or dismissal")
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image {
                window.layer.render(in: $0.cgContext)
            })
            attachment.name = "toc-edge-\(mode)-back-to-first"; attachment.lifetime = .keepAlways
            add(attachment)
        } catch {
            await close(presenter, window, previous)
            throw error
        }
        await close(presenter, window, previous)
    }

    private func close(_ presenter: UIViewController, _ window: UIWindow, _ previous: UIWindow?) async {
        if presenter.presentedViewController != nil {
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                presenter.dismiss(animated: false) { done.resume() }
            }
        }
        await Task.yield()
        window.isHidden = true
        window.rootViewController = nil
        previous?.makeKeyAndVisible()
    }

    private func edgeButton(in root: NSObject, title: String) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> NSObject? {
            guard seen.count < 5000, seen.insert(ObjectIdentifier(object)).inserted,
                  !object.accessibilityElementsHidden else { return nil }
            if let v = object as? UIView, v.isHidden || v.alpha < 0.01 { return nil }
            if object.accessibilityLabel == title, object.accessibilityTraits.contains(.button) { return object }
            let children = (object.accessibilityElements as? [NSObject]) ?? []
            let subviews: [NSObject] = (object as? UIView)?.subviews ?? []
            for child in children + subviews { if let hit = visit(child) { return hit } }
            return nil
        }
        return visit(root)
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<200 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: "ReaderTOCEdgeRenderingTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The TOC edge action did not update after scrolling"])
    }
}

@MainActor
private final class TOCEdgeTestPresenter: UIViewController {
    private(set) var appeared = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appeared = true }
}

@MainActor
private final class TOCEdgeTestHost: UIHostingController<ReaderTOCView> {
    private(set) var appeared = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appeared = true }
}
