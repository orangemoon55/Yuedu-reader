import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class FixedPageToolbarOfflineTests: XCTestCase {
    func testOfflineCacheButtonSitsAfterTOCAndInvokesOnlyItsAction() async throws {
        try await exercise(hasOfflineAction: true)
    }

    func testUnsupportedLocalReaderOffersNoNetworkCacheAction() async throws {
        try await exercise(hasOfflineAction: false)
    }

    private func exercise(hasOfflineAction: Bool) async throws {
        let ax = try XCTUnwrap(dlopen("/usr/lib/libAccessibility.dylib", RTLD_NOW))
        defer { dlclose(ax) }
        typealias Get = @convention(c) () -> Bool
        typealias Set = @convention(c) (Bool) -> Void
        let get = unsafeBitCast(try XCTUnwrap(dlsym(ax, "_AXSAutomationEnabled")), to: Get.self)
        let set = unsafeBitCast(try XCTUnwrap(dlsym(ax, "_AXSSetAutomationEnabled")), to: Set.self)
        let enabled = get(); set(true)
        defer { set(enabled) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let old = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        window.frame = scene.coordinateSpace.bounds
        let presenter = OfflineToolbarPresenter()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        try await wait { presenter.appeared }
        let state = FixedPageReaderState()
        state.chapterTitle = "第18话"
        state.chapterListItems = [.init(id: UUID(), index: 0, title: "第18话")]
        state.totalPages = 56
        var offlineCalls = 0, closes = 0
        let action: (() -> Void)? = hasOfflineAction ? { offlineCalls += 1 } : nil
        let host = UIHostingController(rootView: NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                FixedPageReaderControlsOverlay(state: state, onClose: { closes += 1 },
                    onOpenTouchZoneEditor: {}, onOfflineCache: action, offlineCacheEnabled: hasOfflineAction)
            }
            .toolbarTitleDisplayMode(.inline)
        }.tint(.white))
        host.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            presenter.present(host, animated: false) { done.resume() }
        }
        do {
            try await wait { self.button(in: host.view, title: localized("目錄")) != nil }
            if hasOfflineAction {
                try await wait { self.button(in: host.view, title: localized("离线缓存")) != nil }
                let cache = try XCTUnwrap(button(in: host.view, title: localized("离线缓存")))
                let toc = try XCTUnwrap(button(in: host.view, title: localized("目錄")))
                XCTAssertGreaterThan(cache.accessibilityFrame.midX, toc.accessibilityFrame.midX,
                                     "The cache control belongs immediately after the TOC on the leading side")
                XCTAssertGreaterThanOrEqual(cache.accessibilityFrame.width, 44)
                XCTAssertTrue(cache.accessibilityActivate())
                try await wait { offlineCalls == 1 }
                XCTAssertEqual(offlineCalls, 1)
                XCTAssertEqual(closes, 0)
                let image = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image {
                    window.layer.render(in: $0.cgContext)
                })
                image.name = "manga-offline-cache-after-toc"
                image.lifetime = .keepAlways
                add(image)
            } else {
                XCTAssertNil(button(in: host.view, title: localized("离线缓存")))
            }
            await close(presenter, window, old)
        } catch {
            await close(presenter, window, old)
            throw error
        }
    }

    private func button(in root: NSObject, title: String) -> NSObject? {
        var seen = Set<ObjectIdentifier>()
        func visit(_ object: NSObject) -> NSObject? {
            guard seen.count < 5000, seen.insert(ObjectIdentifier(object)).inserted,
                  !object.accessibilityElementsHidden else { return nil }
            if let view = object as? UIView, view.isHidden || view.alpha < 0.01 { return nil }
            if object.accessibilityLabel == title, object.accessibilityTraits.contains(.button) { return object }
            let children = (object.accessibilityElements as? [NSObject]) ?? []
            let views: [NSObject] = (object as? UIView)?.subviews ?? []
            for child in children + views { if let found = visit(child) { return found } }
            return nil
        }
        return visit(root)
    }

    private func close(_ presenter: UIViewController, _ window: UIWindow, _ old: UIWindow?) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            presenter.dismiss(animated: false) { done.resume() }
        }
        window.isHidden = true
        window.rootViewController = nil
        old?.makeKeyAndVisible()
    }

    private func wait(_ condition: () -> Bool) async throws {
        for _ in 0..<250 {
            if condition() { return }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw NSError(domain: "FixedPageToolbarOfflineTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Native toolbar did not become ready"])
    }
}

@MainActor
private final class OfflineToolbarPresenter: UIViewController {
    private(set) var appeared = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appeared = true }
}
