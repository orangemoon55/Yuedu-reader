import SwiftUI
import UIKit
import XCTest
@testable import yuedu_app

@MainActor
final class HomeRankNativeTests: XCTestCase {
    func testRankGroupRendersAtPhoneWidthsAndLargeText() async throws {
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let main = HomeLayoutSample.standard.cards(for: .coverIntroCard)
        let compact = Array(HomeLayoutSample.standard.cards(for: .compactReadingCard).prefix(3))
        XCTAssertFalse(main.isEmpty)
        XCTAssertFalse(compact.isEmpty)
        for (width, scheme, typeSize): (CGFloat, ColorScheme, DynamicTypeSize) in [
            (390, .light, .large), (320, .light, .large), (390, .dark, .large), (390, .light, .accessibility2)
        ] {
            let root = VStack(alignment: .leading, spacing: DSSpacing.md) {
                Text("示例月票榜").font(DSFont.title2).padding(.horizontal, DSSpacing.lg)
                HomeRankCarousel(cards: main, open: { _, _ in }, previewRelated: compact)
            }
            .padding(.vertical, DSSpacing.lg)
            .environment(\.homeRankPreview, true)
            .environment(\.homeRowWidth, width)
            .environment(\.colorScheme, scheme)
            .environment(\.dynamicTypeSize, typeSize)
            .background(DSColor.surface)
            let host = UIHostingController(rootView: root)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: width, height: 1500)
            window.rootViewController = host
            window.makeKeyAndVisible()
            let size = host.sizeThatFits(in: CGSize(width: width, height: 1500))
            host.view.frame = CGRect(origin: .zero, size: size)
            host.view.setNeedsLayout(); host.view.layoutIfNeeded()
            await Task.yield()
            XCTAssertEqual(size.width, width, accuracy: 1)
            XCTAssertGreaterThan(size.height, 350)
            XCTAssertLessThan(size.height, 1500)
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let attachment = XCTAttachment(image: image)
            attachment.name = "rank16-group-\(width)-\(scheme)-\(typeSize)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.isHidden = true; window.rootViewController = nil
        }
        previous?.makeKey()
    }

    func testSaveIsVisibleBeforeSlowNetworkPreviewCompletes() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let suite = "RankNativeSave.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let store = HomePageStore(fileURL: directory.appendingPathComponent("home.json"), defaults: defaults)
        store.save(HomePage(sections: []))
        defer {
            store.waitForPendingWritesForTesting()
            try? FileManager.default.removeItem(at: directory)
            defaults.removePersistentDomain(forName: suite)
        }
        let model = HomeModel(providers: { [] }, waitForSources: { try? await Task.sleep(for: .seconds(10)) })
        let editor = HomeSectionEditor(newSectionIn: store, layout: .coverIntroCard, preview: model)
        editor.choose(.gutenbergFeed(url: "https://rank.test/feed"), itemTitle: "慢速預覽")
        let root = NavigationStack {
            HomeSectionForm(editor: editor, isInSheet: false)
        }.environmentObject(BookStore())
        try await withAccessibilityHost(in: root) { host in
            let present = await eventually(host, within: .seconds(3)) {
                HomeRankAX.find("homeSection.add", in: host) != nil
            }
            XCTAssertTrue(present, "Save must not wait for the preview task")
            XCTAssertFalse(model.isReady)
            let save = try XCTUnwrap(HomeRankAX.find("homeSection.add", in: host))
            XCTAssertTrue(save.accessibilityTraits.contains(.button))
            XCTAssertFalse(save.accessibilityTraits.contains(.notEnabled))
            XCTAssertGreaterThan(save.accessibilityFrame.width, 10)
            let attachment = XCTAttachment(image: UIGraphicsImageRenderer(bounds: host.bounds).image { _ in
                host.drawHierarchy(in: host.bounds, afterScreenUpdates: true)
            })
            attachment.name = "rank16-save-before-network"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testProductionCarouselActuallySwitchesAfterThirtySeconds() async throws {
        let first = HomeCardContent(sample: "FirstRotationBook", author: "Author", kind: .text, cover: nil, blurb: "Intro")
        let second = HomeCardContent(sample: "SecondRotationBook", author: "Author", kind: .text, cover: nil, blurb: "Intro")
        let root = HomeRankCarousel(cards: [first, second], open: { _, _ in })
            .environment(\.scenePhase, .active)
            .environment(\.homeRowWidth, 390)
        try await withAccessibilityHost(in: root) { host in
            func visibleBook() -> String? {
                HomeRankAX.find("home.rank.current", in: host)?.accessibilityLabel
            }
            let initial = await eventually(host) { visibleBook()?.contains("FirstRotationBook") == true }
            XCTAssertTrue(initial)
            try await Task.sleep(for: .seconds(29))
            XCTAssertTrue(visibleBook()?.contains("FirstRotationBook") == true)
            let switched = await eventually(host, within: .seconds(3)) {
                visibleBook()?.contains("SecondRotationBook") == true
            }
            XCTAssertTrue(switched)
        }
    }
}
