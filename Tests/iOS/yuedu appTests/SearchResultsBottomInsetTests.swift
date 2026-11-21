import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class SearchResultsBottomInsetTests: XCTestCase {
    func testInsetIsIdempotentPreservesOtherEdgesAndClearsWhenBarHides() {
        let controller = IOS17SearchResultTableViewController()
        controller.loadViewIfNeeded()
        controller.tableView.contentInset = UIEdgeInsets(top: 12, left: 3, bottom: 0, right: 4)
        controller.setFloatingBottomInset(80)
        controller.setFloatingBottomInset(80)
        XCTAssertEqual(controller.tableView.contentInset.bottom, 88)
        XCTAssertEqual(controller.tableView.contentInset.top, 12)
        XCTAssertEqual(controller.tableView.contentInset.left, 3)
        XCTAssertEqual(controller.tableView.contentInset.right, 4)
        XCTAssertEqual(controller.tableView.verticalScrollIndicatorInsets.bottom, 80)
        controller.setFloatingBottomInset(120)
        XCTAssertEqual(controller.tableView.contentInset.bottom, 128)
        controller.setFloatingBottomInset(0)
        XCTAssertEqual(controller.tableView.contentInset.bottom, 0)
        XCTAssertEqual(controller.tableView.verticalScrollIndicatorInsets.bottom, 0)
        controller.setFloatingBottomInset(.infinity)
        XCTAssertEqual(controller.tableView.contentInset.bottom, 0)
    }

    func testNativeSearchLastRowScrollsClearOfTheRealFloatingBarAndRemainsSelectable() async throws {
        let rows = (0..<48).map { index in
            IOS17SearchResultTableRow(id: UUID(), content: SearchBookListRowContent(
                title: "Synthetic result \(index)", titleTag: nil, author: "Fixture author", detail: "1 source"
            ), coverURL: "")
        }
        let expectedID = try XCTUnwrap(rows.last?.id)
        var selected: UUID?
        let state = SearchInsetVisibility()
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let host = UIHostingController(rootView: SearchInsetHarness(
            content: IOS17SearchResultTableContent(rows: rows), state: state, selected: { selected = $0 }))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        var table: UITableView?
        var marker: UIView?
        for _ in 0..<40 {
            host.view.layoutIfNeeded()
            table = descendants(host.view).compactMap { $0 as? UITableView }.first
            marker = descendants(host.view).first { $0.tag == 35035 }
            if let table, table.numberOfRows(inSection: 0) == rows.count,
               table.contentInset.bottom > 8, marker?.bounds.height ?? 0 > 0 { break }
            try await Task.sleep(for: .milliseconds(30))
        }
        let list = try XCTUnwrap(table)
        let bar = try XCTUnwrap(marker)
        XCTAssertGreaterThan(list.contentInset.bottom, 8, "The measured root-bar reservation must cross the SwiftUI/UIKit bridge")
        let originalBounds = list.bounds.size
        for _ in 0..<6 {
            let y = max(-list.adjustedContentInset.top,
                        list.contentSize.height - list.bounds.height + list.adjustedContentInset.bottom)
            list.setContentOffset(CGPoint(x: 0, y: y), animated: false)
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(30))
        }
        let index = IndexPath(row: rows.count - 1, section: 0)
        let last = list.convert(list.rectForRow(at: index), to: window)
        let barFrame = bar.convert(bar.bounds, to: window)
        XCTAssertLessThanOrEqual(last.maxY, barFrame.minY + 1,
                                 "The entire final result must be able to scroll above the floating capsule")
        XCTAssertGreaterThan(last.minY, 0)
        let hit = try XCTUnwrap(window.hitTest(CGPoint(x: last.midX, y: last.midY), with: nil))
        XCTAssertTrue(isDescendant(hit, of: list), "The row's visible middle must hit the result table, not the root bar")
        list.delegate?.tableView?(list, didSelectRowAt: index)
        XCTAssertEqual(selected, expectedID)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "Readcc35-search-final-result-clear-of-floating-bar"
        attachment.lifetime = .keepAlways
        add(attachment)
        state.showsBar = false
        for _ in 0..<10 {
            await Task.yield()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertEqual(list.contentInset.bottom, 0)
        XCTAssertEqual(list.bounds.size, originalBounds, "Hiding the bar must change scroll room, not shorten the viewport")
    }

    private func descendants(_ view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants($0) }
    }
    private func isDescendant(_ view: UIView, of ancestor: UIView) -> Bool {
        var current: UIView? = view
        while let item = current {
            if item === ancestor { return true }
            current = item.superview
        }
        return false
    }
}

@MainActor
private final class SearchInsetVisibility: ObservableObject {
    @Published var showsBar = true
}

private struct SearchInsetHarness: View {
    let content: IOS17SearchResultTableContent
    @ObservedObject var state: SearchInsetVisibility
    let selected: (UUID) -> Void
    var body: some View {
        IOS17SearchResultTable(content: content, onSelect: selected)
            .modifier(FloatingRootTabBarContainer(isPresented: state.showsBar) {
                FloatingRootTabBar(tabs: [.explore, .bookshelf, .settings, .search],
                                   selection: .constant(.search))
                    .padding(.top, FloatingRootTabBarLayout.topSpacing)
                    .background(SearchInsetBarMarker())
            })
    }
}

private struct SearchInsetBarMarker: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.tag = 35035
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: UIView, context: Context) {}
}
