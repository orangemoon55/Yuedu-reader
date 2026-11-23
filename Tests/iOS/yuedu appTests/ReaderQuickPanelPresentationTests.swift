import Combine
import Observation
import SwiftUI
import XCTest
@testable import yuedu_app

/// Runs the production iOS-17 routing branch even on the newest simulator. This
/// checks real UIKit sheet lifecycles; a device-specific freeze still needs iOS 17.
@MainActor
final class ReaderQuickPanelPresentationTests: XCTestCase {
    func testHeaderFooterReopensWithoutStackingSheetsOrWritingPreferences() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let flow = QuickPanelHandoffFlow()
        let host = UIHostingController(rootView: QuickPanelHandoffHarness(flow: flow))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKey()
        }
        // Settle the ReaderConfig singleton once before checking for passive writes.
        ReaderConfig.shared.syncFromGlobalSettings()
        let originalLayout = GlobalSettings.shared.readerBarLayout
        let originalPreferences = ReaderPreferences.current()
        let rootShown = expectation(description: "Root view is responsive")
        DispatchQueue.main.async { rootShown.fulfill() }
        await fulfillment(of: [rootShown], timeout: 5)

        for cycle in 0..<3 {
            let quickShown = expectation(description: "Quick panel shown \(cycle)")
            let settingsShown = expectation(description: "Header/footer page shown \(cycle)")
            let settingsClosed = expectation(description: "Header/footer page dismissed \(cycle)")
            flow.quickAppeared = { quickShown.fulfill() }
            flow.settingsAppeared = { settingsShown.fulfill() }
            flow.settingsDismissed = { settingsClosed.fulfill() }
            flow.showsQuick = true
            await fulfillment(of: [quickShown], timeout: 10)
            XCTAssertNotNil(host.presentedViewController)
            XCTAssertNil(flow.target)

            flow.navigation.select(.headerFooter) { flow.request($0) }
            // Selecting a second route during dismissal must have no effect.
            flow.navigation.select(.decoration) { flow.request($0) }
            await fulfillment(of: [settingsShown], timeout: 10)
            XCTAssertEqual(flow.target, .headerFooter)
            XCTAssertNil(flow.navigation.settingsDestination)
            XCTAssertEqual(flow.quickDismissals, cycle + 1)
            XCTAssertTrue(flow.events.suffix(2).elementsEqual(["quick.dismissed", "settings.appeared"]))
            XCTAssertEqual(GlobalSettings.shared.readerBarLayout, originalLayout)
            XCTAssertEqual(ReaderPreferences.current(), originalPreferences)
            let page = try XCTUnwrap(host.presentedViewController)
            XCTAssertNil(page.presentedViewController, "Settings must not be stacked inside the dismissed quick panel")
            page.view.layoutIfNeeded()
            let heartbeat = expectation(description: "Main queue remains responsive inside settings")
            DispatchQueue.main.async { heartbeat.fulfill() }
            await fulfillment(of: [heartbeat], timeout: 5)
            if cycle == 0 {
                let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                    window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
                }
                let attachment = XCTAttachment(image: image)
                attachment.name = "header-footer-safe-handoff"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
            flow.target = nil
            await fulfillment(of: [settingsClosed], timeout: 10)
            XCTAssertNil(host.presentedViewController)
        }
        XCTAssertEqual(flow.quickDismissals, 3)
        XCTAssertEqual(flow.settingsDismissals, 3)
        XCTAssertNil(flow.pending.pendingRoute)
    }
}

@MainActor @Observable
private final class QuickPanelHandoffFlow {
    let navigation = ReaderQuickPanelNavigation(osMajorVersion: 17)
    var showsQuick = false
    var target: ReaderQuickPanelRoute?
    var pending = DismissalSequencedPresentation<ReaderQuickPanelRoute>()
    var quickDismissals = 0
    var settingsDismissals = 0
    var events: [String] = []
    @ObservationIgnored var quickAppeared: (() -> Void)?
    @ObservationIgnored var settingsAppeared: (() -> Void)?
    @ObservationIgnored var settingsDismissed: (() -> Void)?

    func request(_ route: ReaderQuickPanelRoute) {
        pending.select(route)
        showsQuick = false
    }
    func quickDidDismiss() {
        quickDismissals += 1
        events.append("quick.dismissed")
        target = pending.consumeAfterDismissal()
    }
}

private struct QuickPanelHandoffHarness: View {
    @Bindable var flow: QuickPanelHandoffFlow
    var body: some View {
        Color.gray
            .sheet(isPresented: $flow.showsQuick, onDismiss: flow.quickDidDismiss) {
                ReaderQuickThemePanelView(
                    fontSize: .constant(18), readerTheme: .constant(.white),
                    pageTurnOption: .fastFade, isVerticalWritingMode: false,
                    onSelectPageTurnOption: { _ in }, onSelectRoute: flow.request,
                    panelNavigation: flow.navigation
                )
                .environment(\.dynamicTypeSize, .large)
                .background(HandoffAppearanceProbe { flow.quickAppeared?() })
            }
            .sheet(item: $flow.target, onDismiss: {
                flow.settingsDismissals += 1
                flow.settingsDismissed?()
            }) { _ in
                ReaderSettingsView(fontSize: .constant(18), theme: .constant(.white), initialSection: .headerFooter)
                    .environment(\.dynamicTypeSize, .large)
                    .background(HandoffAppearanceProbe {
                        flow.events.append("settings.appeared")
                        flow.settingsAppeared?()
                    })
            }
    }
}

private struct HandoffAppearanceProbe: UIViewControllerRepresentable {
    let appeared: () -> Void
    func makeUIViewController(context: Context) -> Controller { Controller(appeared: appeared) }
    func updateUIViewController(_ uiViewController: Controller, context: Context) {}
    final class Controller: UIViewController {
        let appeared: () -> Void
        private var didNotify = false
        init(appeared: @escaping () -> Void) {
            self.appeared = appeared
            super.init(nibName: nil, bundle: nil)
        }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            guard !didNotify else { return }
            didNotify = true
            appeared()
        }
    }
}
