import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class FloatingRootTabBarTests: XCTestCase {
    func testWidthsKeepHitTargetsForOneThroughFiveTabs() {
        for width: CGFloat in [240, 320, 375, 390, 430, 744] {
            for count in 1...5 {
                for search in [false, true] {
                    let layout = FloatingRootTabBarLayout(
                        availableWidth: width, mainTabCount: count,
                        hasSearch: search, height: 64
                    )
                    XCTAssertGreaterThanOrEqual(layout.itemWidth, 48)
                    XCTAssertGreaterThanOrEqual(layout.height - FloatingRootTabBarLayout.surfacePadding * 2, 44)
                    if search { XCTAssertGreaterThanOrEqual(layout.searchDiameter, 44) }
                    XCTAssertLessThanOrEqual(layout.viewportWidth, width)
                    XCTAssertGreaterThanOrEqual(layout.rows, 1)
                    XCTAssertEqual(layout.contentWidth, layout.capsuleWidth + layout.gap + layout.searchHitWidth)
                }
            }
        }
        let three = FloatingRootTabBarLayout(availableWidth: 390, mainTabCount: 3, hasSearch: true, height: 64)
        XCTAssertEqual(three.itemWidth, 82)
        XCTAssertEqual(three.capsuleWidth, 254)
        XCTAssertEqual(three.capsuleWidth / 390, 254 / 390, accuracy: 0.001)
        XCTAssertEqual(three.searchDiameter, 52)
        XCTAssertGreaterThanOrEqual(three.itemWidth, 48)
        let five = FloatingRootTabBarLayout(availableWidth: 744, mainTabCount: 5, hasSearch: true, height: 64)
        XCTAssertEqual(five.itemWidth, FloatingRootTabBarLayout.maximumItemWidth)

        let narrow = FloatingRootTabBarLayout(availableWidth: 200, mainTabCount: 5, hasSearch: true, height: 64)
        XCTAssertEqual(narrow.contentWidth, narrow.viewportWidth)
        XCTAssertGreaterThan(narrow.rows, 1, "Narrow layouts wrap instead of scrolling")
        let searchOnly = FloatingRootTabBarLayout(availableWidth: 320, mainTabCount: 0, hasSearch: true, height: 64)
        XCTAssertEqual(searchOnly.capsuleWidth, 0)
        XCTAssertEqual(searchOnly.searchDiameter, 52)
        XCTAssertEqual(searchOnly.searchHitWidth, 64)
        let compact = FloatingRootTabBarLayout(availableWidth: 390, mainTabCount: 2, hasSearch: true, height: 56)
        XCTAssertEqual(compact.height, 56)
        XCTAssertEqual(compact.itemWidth, 80)
        XCTAssertEqual(compact.contentWidth, 240)
        XCTAssertEqual(compact.touchHeight, 68)
        XCTAssertEqual(compact.rows, 1)
        XCTAssertGreaterThanOrEqual(compact.height - FloatingRootTabBarLayout.surfacePadding * 2, 44)
    }

    func testFixedBarIsNotHorizontallyScrollableAndHitTargetsAreExpanded() async throws {
        var selection: RootTabItem = .explore
        let view = FloatingRootTabBar(tabs: [.explore, .bookshelf, .settings, .search],
                                      selection: Binding(get: { selection }, set: { selection = $0 }))
        try await withAccessibilityHost(in: view) { host in
            let ready = await eventually(host) {
                HomeRankAX.elements(in: host).filter { $0.accessibilityTraits.contains(.button) }.count >= 4
            }
            XCTAssertTrue(ready)
            let all = descendants(of: host)
            XCTAssertFalse(all.contains(where: { $0 is UIScrollView }))
            let buttons = HomeRankAX.elements(in: host).filter { $0.accessibilityTraits.contains(.button) }
            XCTAssertGreaterThanOrEqual(buttons.count, 4)
            for button in buttons {
                XCTAssertGreaterThanOrEqual(button.accessibilityFrame.width, 48)
                XCTAssertGreaterThanOrEqual(button.accessibilityFrame.height, 64)
            }
            for first in buttons.indices {
                for second in buttons.indices where second > first {
                    let overlap = buttons[first].accessibilityFrame.intersection(buttons[second].accessibilityFrame)
                    XCTAssertTrue(overlap.isNull || overlap.width * overlap.height < 1)
                }
            }
        }
    }

    func testSearchDetachesWithoutChangingOrderSelectionOrHiddenPreferences() {
        var selection: RootTabItem = .search
        let binding = Binding(get: { selection }, set: { selection = $0 })
        let bar = FloatingRootTabBar(tabs: [.settings, .search, .explore, .bookshelf], selection: binding)
        XCTAssertEqual(bar.mainTabs, [.settings, .explore, .bookshelf])
        XCTAssertTrue(bar.hasSearch)
        XCTAssertEqual(selection, .search)
        bar.selection = .bookshelf
        XCTAssertEqual(selection, .bookshelf, "The bar uses the TabView's binding")
        let hidden = FloatingRootTabBar(tabs: [.settings], selection: binding, hidesLabels: true)
        XCTAssertFalse(hidden.hasSearch)
        XCTAssertEqual(hidden.mainTabs, [.settings])
    }

    func testHiddenRequestsStayIndependentOfFloatingAndKeyboardPolicy() {
        let visibility = RootTabBarVisibility()
        let reader = UUID(), editing = UUID()
        XCTAssertTrue(visibility.hidesSystemTabBar(isFloating: true))
        XCTAssertFalse(visibility.isTabBarHidden)
        XCTAssertTrue(visibility.showsFloatingTabBar(isFloating: true, keyboardVisible: false))
        XCTAssertFalse(visibility.showsFloatingTabBar(isFloating: true, keyboardVisible: true))
        XCTAssertFalse(visibility.isTabBarHidden, "Keyboard and native replacement must not register screen requests")
        visibility.setRequest(reader, hidesTabBar: true)
        visibility.setRequest(editing, hidesTabBar: true)
        visibility.setRequest(reader, hidesTabBar: false)
        XCTAssertTrue(visibility.isTabBarHidden)
        XCTAssertFalse(visibility.showsFloatingTabBar(isFloating: true, keyboardVisible: false))
        visibility.setRequest(editing, hidesTabBar: false)
        visibility.setRequest(editing, hidesTabBar: false)
        XCTAssertFalse(visibility.hidesSystemTabBar())
        XCTAssertTrue(visibility.showsFloatingTabBar(isFloating: true, keyboardVisible: false))
        XCTAssertFalse(visibility.showsFloatingTabBar(isFloating: false, keyboardVisible: false))
    }

    func testKeyboardOcclusionHandlesDockedFloatingAndHardwareKeyboards() {
        let bounds = CGRect(x: 0, y: 0, width: 390, height: 844)
        func occludes(_ frame: CGRect) -> Bool {
            RootTabKeyboardObserver.isOccluding(keyboardFrame: frame, windowBounds: bounds, bottomSafeArea: 34)
        }
        XCTAssertTrue(occludes(CGRect(x: 0, y: 510, width: 390, height: 334)))
        XCTAssertTrue(occludes(CGRect(x: 80, y: 400, width: 240, height: 220)))
        XCTAssertFalse(occludes(CGRect(x: 0, y: 844, width: 390, height: 334)))
        XCTAssertFalse(occludes(CGRect(x: 0, y: 810, width: 390, height: 34)))
        XCTAssertFalse(occludes(CGRect(x: 500, y: 510, width: 390, height: 334)))
    }

    func testHostingLightDarkCustomIconsAndAccessibleSize() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let window = UIWindow(windowScene: scene)
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let bitmap = UIGraphicsImageRenderer(size: CGSize(width: 30, height: 30)).image { context in
            UIColor.systemOrange.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 30, height: 30))
            UIColor.systemPurple.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 15, height: 30))
        }
        let variants: [(ColorScheme, DynamicTypeSize, Bool)] = [
            (.light, .large, false), (.dark, .large, false), (.dark, .accessibility3, true),
        ]
        var sizes: [CGSize] = []
        for (scheme, typeSize, opaque) in variants {
            var drawn: Set<RootTabItem> = []
            let bar = FloatingRootTabBar(
                tabs: [.explore, .bookshelf, .settings, .search], selection: .constant(.search),
                iconSize: 36, tint: .orange, customIcon: { tab in
                    drawn.insert(tab)
                    return RootTabRenderedIcon(image: bitmap, isTemplate: false)
                },
                reduceTransparencyOverride: opaque
            )
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize)
            let host = UIHostingController(rootView: bar)
            window.rootViewController = host
            window.makeKeyAndVisible()
            let size = host.sizeThatFits(in: CGSize(width: 320, height: 400))
            sizes.append(size)
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            await Task.yield()
            XCTAssertEqual(size.width, 320, accuracy: 1)
            XCTAssertGreaterThanOrEqual(size.height, 64)
            XCTAssertLessThan(size.height, 300)
            XCTAssertEqual(drawn, Set([.explore, .bookshelf, .settings, .search]))
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            XCTAssertNotNil(image.cgImage)
            let attachment = XCTAttachment(image: image)
            attachment.name = "FloatingRootTabBar-\(scheme)-\(typeSize)-opaque-\(opaque)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let accessibleSize = try XCTUnwrap(sizes.last)
        let standardSize = try XCTUnwrap(sizes.first)
        XCTAssertGreaterThan(accessibleSize.height, standardSize.height)
    }

    func testSettingsLastRowStopsAboveMeasuredFloatingBarAndRemainsHitTestable() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: FloatingBarBottomInsetHarness())
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }

        let bar = try await waitForView(in: host.view) { view -> UIView? in
            view.accessibilityIdentifier == "floatingBar.measurement" ? view : nil
        }
        let scroll = try await waitForView(in: host.view) { view -> UIScrollView? in
            guard let scroll = view as? UIScrollView,
                  scroll.contentSize.height > scroll.bounds.height + 100 else { return nil }
            return scroll
        }
        // A Form virtualizes rows. Scroll first, then look for the final row.
        for _ in 0..<3 {
            host.view.layoutIfNeeded()
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            try await Task.sleep(for: .milliseconds(100))
        }
        let about = try await waitForView(in: host.view) { view -> UIView? in
            view.accessibilityIdentifier == "settings.about" ? view : nil
        }
        host.view.layoutIfNeeded()

        let aboutFrame = about.convert(about.bounds, to: window)
        let barFrame = bar.convert(bar.bounds, to: window)
        let viewport = scroll.convert(scroll.bounds, to: window)
        XCTAssertGreaterThan(viewport.maxY, barFrame.maxY - 1,
                             "The scroll viewport must extend behind the floating capsule, not stop above it")
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "floating15-settings-last-row"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertTrue(barFrame.minY.isFinite)
        XCTAssertTrue(aboutFrame.maxY.isFinite)
        XCTAssertLessThanOrEqual(
            aboutFrame.maxY, barFrame.minY + 1,
            "The last settings row must remain fully above the floating bar"
        )
        let hit = window.hitTest(CGPoint(x: aboutFrame.midX, y: aboutFrame.midY), with: nil)
        XCTAssertTrue(
            hit.map { isDescendant($0, of: about) } == true,
            "The visible About row must remain touchable"
        )
    }

    func testPushedFormKeepsFullViewportAndReachableFinalAction() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let host = UIHostingController(rootView: FloatingBarPushedFormHarness())
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        let bar = try await waitForView(in: host.view) { $0.accessibilityIdentifier == "floatingBar.measurement" ? $0 : nil }
        let scroll = try await waitForView(in: host.view) { view -> UIScrollView? in
            guard let result = view as? UIScrollView, result.contentSize.height > result.bounds.height + 100 else { return nil }
            return result
        }
        for _ in 0..<3 {
            host.view.layoutIfNeeded()
            scroll.setContentOffset(CGPoint(x: 0, y: max(-scroll.adjustedContentInset.top,
                scroll.contentSize.height - scroll.bounds.height + scroll.adjustedContentInset.bottom)), animated: false)
            await Task.yield()
        }
        let action = try await waitForView(in: host.view) { $0.accessibilityIdentifier == "settings.about" ? $0 : nil }
        let barFrame = bar.convert(bar.bounds, to: window)
        let viewport = scroll.convert(scroll.bounds, to: window)
        let actionFrame = action.convert(action.bounds, to: window)
        XCTAssertGreaterThan(viewport.maxY, barFrame.maxY - 1)
        XCTAssertLessThanOrEqual(actionFrame.maxY, barFrame.minY + 1)
        XCTAssertTrue(window.hitTest(CGPoint(x: actionFrame.midX, y: actionFrame.midY), with: nil)
            .map { isDescendant($0, of: action) } == true)
        let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        })
        attachment.name = "floating15-pushed-module-form"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testUIKitReaderHostingReceivesRootVisibilityAndReleasesItsRequest() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let previous = scene.windows.first(where: \.isKeyWindow)
        let visibility = RootTabBarVisibility()
        let window = UIWindow(windowScene: scene)
        let navigation = UINavigationController(rootViewController: UIViewController())
        window.rootViewController = navigation
        defer { window.isHidden = true; window.rootViewController = nil; previous?.makeKey() }
        window.makeKeyAndVisible()
        let appeared = expectation(description: "UIKit-pushed reader appeared")
        let disappeared = expectation(description: "UIKit-pushed reader disappeared")
        // Same environment boundary as HomeView's actual destination factory. This
        // verifies iOS 17's detached hosting path, not just UIKit tabBar.isHidden.
        let reader = ReaderHostingController(content: AnyView(
            Text("Reader")
                .hidesRootTabBar()
                .onAppear { appeared.fulfill() }
                .onDisappear { disappeared.fulfill() }
                .environment(\.rootTabBarVisibility, visibility)
        ))
        navigation.pushViewController(reader, animated: false)
        await fulfillment(of: [appeared], timeout: 3)
        await Task.yield()
        XCTAssertTrue(visibility.isTabBarHidden)
        XCTAssertFalse(visibility.showsFloatingTabBar(isFloating: true, keyboardVisible: false))
        navigation.popViewController(animated: false)
        await fulfillment(of: [disappeared], timeout: 3)
        await Task.yield()
        XCTAssertFalse(visibility.isTabBarHidden)
        XCTAssertTrue(visibility.showsFloatingTabBar(isFloating: true, keyboardVisible: false))
    }
}

@MainActor
private extension FloatingRootTabBarTests {
    func descendants(of view: UIView) -> [UIView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    func isDescendant(_ view: UIView, of ancestor: UIView) -> Bool {
        view === ancestor || view.isDescendant(of: ancestor)
    }

    func waitForView<T>(in root: UIView, _ match: (UIView) -> T?) async throws -> T {
        for _ in 0..<120 {
            root.setNeedsLayout()
            root.layoutIfNeeded()
            if let result = descendants(of: root).compactMap(match).first { return result }
            try await Task.sleep(for: .milliseconds(25))
        }
        throw NSError(domain: "FloatingRootTabBarTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "The expected hosted view did not appear"])
    }
}

/// Uses the production overlay: its Form stays full height behind the capsule.
private struct FloatingBarBottomInsetHarness: View {
    var body: some View {
        NavigationStack {
            Form {
                ForEach(0..<20, id: \.self) { index in
                    Text("Settings row \(index)").frame(minHeight: 48)
                }
                BottomInsetProbe(isButton: true)
                    .frame(height: 48)
            }
            .navigationTitle("Settings")
        }
        .modifier(FloatingRootTabBarContainer(isPresented: true) {
            FloatingRootTabBar(tabs: [.bookshelf, .settings, .search], selection: .constant(.settings))
                .background { BottomInsetProbe(isButton: false) }
        })
    }
}

private struct BottomInsetProbe: UIViewRepresentable {
    let isButton: Bool
    func makeUIView(context: Context) -> UIView {
        if isButton {
            let button = UIButton(type: .system)
            button.setTitle("关于轻云出岫", for: .normal)
            button.accessibilityIdentifier = "settings.about"
            return button
        }
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityIdentifier = "floatingBar.measurement"
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

private struct FloatingBarPushedFormHarness: View {
    @State private var path = [1]
    var body: some View {
        NavigationStack(path: $path) {
            Color.clear.navigationTitle("Settings")
                .navigationDestination(for: Int.self) { _ in
                    Form {
                        ForEach(0..<25, id: \.self) { index in
                            Text("Module option \(index)").frame(minHeight: 48)
                        }
                        BottomInsetProbe(isButton: true).frame(height: 48)
                    }
                    .navigationTitle("Module details")
                    .toolbarTitleDisplayMode(.inline)
                }
        }
        .modifier(FloatingRootTabBarContainer(isPresented: true) {
            FloatingRootTabBar(tabs: [.explore, .bookshelf, .settings, .search], selection: .constant(.settings))
                .background { BottomInsetProbe(isButton: false) }
        })
    }
}
