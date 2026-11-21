import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class SourcePickerLayoutTests: XCTestCase {
    func testSourcePickerIsCompactAndOpensAtTheSelectedSource() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ReadccSourceLayout-\(UUID())")
        let suite = "ReadccSourceLayout-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = BookSourceStore(directory: directory)
        let sources = (0..<60).map {
            BookSource(bookSourceUrl: "https://source-\($0).fixture.invalid", bookSourceName: "Synthetic Source \($0)")
        }
        store.replaceSourcesFromSync(sources)
        let selected = sources[46]
        let pins = DiscoverySourcePins(defaults: defaults)
        pins.togglePin(sources[3].id, availableIDs: Set(sources.map(\.id)))
        let view = NavigationStack {
            DiscoverySourcePickerList(sources: sources, selectedURL: selected.bookSourceUrl,
                                      choose: { _ in }, close: {}, store: store, pins: pins)
        }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: view)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
            store.waitForQueuedWrites()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        var selectedElement: NSObject?
        for _ in 0..<45 {
            host.view.layoutIfNeeded()
            let elements = HomeRankAX.elements(in: host.view)
            selectedElement = elements.first {
                $0.accessibilityLabel?.contains("Synthetic Source 46") == true
                    && $0.accessibilityTraits.contains(.isSelected)
            }
            if let selectedElement,
               selectedElement.accessibilityFrame.intersects(window.frame) { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        let element = try XCTUnwrap(selectedElement)
        XCTAssertTrue(element.accessibilityFrame.intersects(window.frame), "Opening must bring the actual selected source on screen")
        XCTAssertGreaterThanOrEqual(element.accessibilityFrame.height, 44)
        XCTAssertLessThanOrEqual(element.accessibilityFrame.height, 64, "Rows must not have the former doubled hit-height padding")
        let scroll = try XCTUnwrap(descendants(host.view).compactMap { $0 as? UIScrollView }.first {
            $0.contentSize.height > $0.bounds.height + 100
        })
        XCTAssertGreaterThan(scroll.contentOffset.y, 0, "Selection is near the end, not the first row")
        scroll.setContentOffset(CGPoint(x: 0, y: -scroll.adjustedContentInset.top), animated: false)
        for _ in 0..<12 {
            try await Task.sleep(for: .milliseconds(30))
            host.view.layoutIfNeeded()
        }
        let screenshot = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        screenshot.name = "Readcc34-source-picker-compact-search-top"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCTAssertEqual(store.sources.map(\.id), sources.map(\.id), "Locating must not reorder real sources")
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
}
