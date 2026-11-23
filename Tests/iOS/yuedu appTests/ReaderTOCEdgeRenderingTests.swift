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

    /// Uses the exact same window, visibility reporting, accessibility activation and
    /// first → latest assertions as the two existing novel directory tests.
    func testMangaDirectoryReturnsToFirstThenLatestWithoutSelectingOrReversing() async throws {
        try await exercise(.horizontalList, manga: true)
    }

    func testMangaEdgeButtonsAreDarkOnLightSheetDespiteInheritedWhiteTint() async throws {
        try await exercise(.horizontalList, manga: true, scheme: .light)
    }

    func testMangaEdgeButtonsAreLightOnDarkSheetDespiteInheritedWhiteTint() async throws {
        try await exercise(.horizontalList, manga: true, scheme: .dark)
    }

    private func exercise(_ mode: TOCLayoutMode, manga: Bool = false,
                          scheme: ColorScheme? = nil) async throws {
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
        let mangaState = FixedPageReaderState()
        mangaState.chapterListItems = chapters.map { .init(id: $0.id, index: $0.index, title: $0.title) }
        mangaState.currentChapterIndex = chapters.last!.index
        mangaState.currentPage = 6
        mangaState.onSelectChapter = { _ in selections += 1 }
        let originalItems = mangaState.chapterListItems
        let id = UUID()
        let oldOrder = UserDefaults.standard.stringArray(forKey: ChapterListOrder.descendingBooksKey)
        if manga { ChapterListOrder.store(.descending, for: id) }
        defer {
            if manga {
                if let oldOrder { UserDefaults.standard.set(oldOrder, forKey: ChapterListOrder.descendingBooksKey) }
                else { UserDefaults.standard.removeObject(forKey: ChapterListOrder.descendingBooksKey) }
            }
        }
        let root: AnyView
        if manga {
            root = AnyView(FixedPageChapterListView(state: mangaState, bookID: id, onClose: { isPresented = false })
                .environment(\.colorScheme, scheme ?? .light)
                .tint(.white))
        } else {
            root = AnyView(ReaderTOCView(
                chapters: chapters, bookTitle: "首尾跳转验证", currentPage: 0, totalPages: 0,
                tocLayoutMode: mode, pageOffsets: [:], showsPageNumbers: false,
                currentIndex: chapters.last!.index, currentChapterID: chapters.last!.id,
                uncachedChapterIndexes: [], onSelectChapter: { _ in selections += 1 },
                isPresented: Binding(get: { isPresented }, set: { isPresented = $0 })
            ))
        }
        let host = TOCEdgeTestHost(rootView: root)
        if let scheme { host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light }
        host.modalPresentationStyle = .fullScreen
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            presenter.present(host, animated: false) { done.resume() }
        }
        do {
            try await wait { host.appeared }
            // The TOC opens on the existing last chapter, so it is already at the bottom.
            try await wait { self.edgeButton(in: host.view, title: localized("回頂部")) != nil }
            let back = try XCTUnwrap(edgeButton(in: host.view, title: localized("回頂部")))
            if let scheme { try assertContrastingInk(back, on: window, scheme: scheme, action: "latest") }
            XCTAssertTrue(back.accessibilityActivate())
            try await wait { self.edgeButton(in: host.view, title: localized("去底部")) != nil }
            let latest = try XCTUnwrap(edgeButton(in: host.view, title: localized("去底部")))
            if let scheme { try assertContrastingInk(latest, on: window, scheme: scheme, action: "first") }
            XCTAssertTrue(latest.accessibilityActivate())
            try await wait { self.edgeButton(in: host.view, title: localized("回頂部")) != nil }
            XCTAssertEqual(selections, 0, "Scrolling the TOC must not select or open a chapter")
            XCTAssertTrue(isPresented, "Jumping is not a read action or dismissal")
            if manga {
                XCTAssertEqual(mangaState.chapterListItems, originalItems, "Never reverse the manga's source chapter array")
                XCTAssertEqual(mangaState.currentChapterIndex, chapters.last!.index)
                XCTAssertEqual(mangaState.currentPage, 6)
                XCTAssertEqual(ChapterListOrder.stored(for: id), .descending, "The obsolete preference is ignored, not rewritten")
            }
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

    /// Test the rendered title pixels, not just the label string or semantic color.
    /// The old inherited white tint produces no dark ink inside the light-sheet button.
    private func assertContrastingInk(_ button: NSObject, on window: UIWindow,
                                     scheme: ColorScheme, action: String) throws {
        window.layoutIfNeeded()
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.preferredRange = .standard
        let screenshot = UIGraphicsImageRenderer(bounds: window.bounds, format: format).image {
            window.layer.render(in: $0.cgContext)
        }
        let global = button.accessibilityFrame
        let rect = window.convert(global, from: nil).insetBy(dx: 2, dy: 2)
            .intersection(window.bounds).integral
        XCTAssertGreaterThan(rect.width, 10)
        XCTAssertGreaterThan(rect.height, 8)
        let cropped = try XCTUnwrap(screenshot.cgImage?.cropping(to: rect))
        let width = cropped.width, height = cropped.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let counts = try pixels.withUnsafeMutableBytes { buffer -> (Int, Int) in
            let ctx = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue))
            ctx.draw(cropped, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
            let bytes = buffer.bindMemory(to: UInt8.self)
            var dark = 0, light = 0
            for i in stride(from: 0, to: bytes.count, by: 4) {
                let luminance = (0.2126 * Double(bytes[i]) + 0.7152 * Double(bytes[i+1]) + 0.0722 * Double(bytes[i+2])) / 255
                if luminance < 0.30 { dark += 1 }
                if luminance > 0.70 { light += 1 }
            }
            return (dark, light)
        }
        XCTAssertGreaterThan(scheme == .light ? counts.0 : counts.1, 12,
                             "The action must have opposite-color visible ink: \(scheme), \(action)")
        let image = XCTAttachment(image: screenshot)
        image.name = "manga-toc-contrast-\(scheme)-\(action)"
        image.lifetime = .keepAlways
        add(image)
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
private final class TOCEdgeTestHost: UIHostingController<AnyView> {
    private(set) var appeared = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appeared = true }
}
