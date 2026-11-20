import XCTest
import UIKit
@testable import yuedu_app

@MainActor
final class BookSourceFileExportTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("source-export-test-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }

    func testSelectedSourcesWriteRealJSONAndRoundTripOnlyTheSnapshot() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        var chosen = BookSource(bookSourceUrl: "https://chosen.fixture", bookSourceName: "选中源")
        chosen.ruleContent.content = "正文规则"
        let request = BookSourceExportRequest(title: "导出", filenameLabel: "选中源", sources: [chosen])
        let file = try BookSourceExportFile.write(request, in: root)
        XCTAssertEqual(file.url.lastPathComponent, "选中源.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
        let data = try Data(contentsOf: file.url)
        let decoded = try JSONDecoder().decode([BookSource].self, from: data)
        XCTAssertEqual(decoded.count, 1)
        XCTAssertEqual(decoded.first?.id, chosen.id)
        XCTAssertEqual(decoded.first?.bookSourceUrl, chosen.bookSourceUrl)
        XCTAssertEqual(decoded.first?.ruleContent.content, "正文规则")
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertNil(object.first?["loginInfo"], "Runtime credentials are not part of source export")
        XCTAssertNil(object.first?["cookies"])
        file.remove()
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }

    func testSameFilenameExportsAreIndependentAndRetainTheirOwnBytes() throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let a = BookSource(bookSourceUrl: "https://a.fixture", bookSourceName: "A")
        let b = BookSource(bookSourceUrl: "https://b.fixture", bookSourceName: "B")
        var first: BookSourceExportFile? = try .write(.init(title: "export", filenameLabel: "same", sources: [a]), in: root)
        let second = try BookSourceExportFile.write(.init(title: "export", filenameLabel: "same", sources: [b]), in: root)
        let firstURL = try XCTUnwrap(first?.url)
        XCTAssertNotEqual(firstURL, second.url)
        XCTAssertEqual(firstURL.lastPathComponent, second.url.lastPathComponent)
        XCTAssertNotEqual(try Data(contentsOf: firstURL), try Data(contentsOf: second.url))
        first = nil
        XCTAssertFalse(FileManager.default.fileExists(atPath: firstURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: second.url.path))
    }

    func testInvalidAndLongNamesRemainSafeJSONFilenameComponents() {
        let names = ["", "a/b:c?d\\e\nf", String(repeating: "📚", count: 200)]
        for name in names {
            let file = BookSourceExportFile.filename(for: name)
            XCTAssertTrue(file.hasSuffix(".json"))
            XCTAssertLessThanOrEqual(file.utf8.count, 245)
            XCTAssertFalse(file.contains("/"))
            XCTAssertFalse(file.contains("\\"))
            XCTAssertFalse(file.contains("\n"))
        }
    }

    func testExportLaunchesNativeActivityFromItsOwnAnchorAndReleasesFileOnCancel() async throws {
        let root = try folder()
        defer { try? FileManager.default.removeItem(at: root) }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previous = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let presenter = UIViewController()
        window.rootViewController = presenter
        window.makeKeyAndVisible()
        defer {
            presenter.dismiss(animated: false)
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        let view = UIView(frame: CGRect(x: 20, y: 100, width: 120, height: 44))
        presenter.view.addSubview(view)
        for _ in 0..<100 where view.window == nil { try await Task.sleep(for: .milliseconds(20)) }
        let anchor = BookSourceShareAnchor()
        anchor.view = view
        let source = BookSource(bookSourceUrl: "https://share.fixture", bookSourceName: "share fixture")
        let file = try BookSourceExportFile.write(.init(title: "export", filenameLabel: "share", sources: [source]), in: root)
        var completed = false
        XCTAssertTrue(anchor.present(file) { error in
            XCTAssertNil(error)
            completed = true
        })
        let activity = try XCTUnwrap(presenter.presentedViewController as? UIActivityViewController)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path), "File must survive activity target selection")
        XCTAssertTrue(activity.popoverPresentationController?.sourceView === view || UIDevice.current.userInterfaceIdiom == .phone)
        activity.completionWithItemsHandler?(nil, false, nil, nil)
        for _ in 0..<100 where !completed { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(completed)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.url.path))
    }
}
