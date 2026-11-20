import Testing
import UIKit
@testable import yuedu_app

/// Offline only: synthetic messages, no account data, requests or source authentication.
@Suite("Source toast lifecycle", .serialized)
@MainActor
struct SourceToastLifecycleTests {
    private func withWindow(_ body: (UIWindow, UIViewController) async throws -> Void) async throws {
        let scene = try #require(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }.first { $0.activationState == .foregroundActive })
        let previous = scene.windows.first { $0.isKeyWindow }
        let window = UIWindow(windowScene: scene)
        let root = SourceToastTestPresenter()
        window.rootViewController = root
        window.makeKeyAndVisible()
        root.loadViewIfNeeded()
        window.layoutIfNeeded()
        for _ in 0..<250 where !root.appeared { try await Task.sleep(for: .milliseconds(30)) }
        try #require(root.appeared, "Present secondary UI only after the fixture window is on screen")
        func cleanup() async {
            SourceToastPresenter.hide()
            if root.presentedViewController != nil {
                await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                    root.dismiss(animated: false) { done.resume() }
                }
            }
            window.isHidden = true
            window.rootViewController = nil
            previous?.makeKeyAndVisible()
        }
        do {
            try await body(window, root)
            await cleanup()
        } catch {
            await cleanup()
            throw error
        }
    }

    private func toast(in window: UIWindow) -> UIView? {
        window.subviews.first { $0.accessibilityIdentifier == "source.toast" }
    }

    @Test func autoDismissDoesNotCreateModalOrDimBackdrop() async throws {
        try await withWindow { window, root in
            let initialSubviews = window.subviews.count
            SourceToastPresenter.show(message: "Synthetic toast", in: window, duration: 0.05)
            #expect(toast(in: window) != nil)
            #expect(root.presentedViewController == nil)
            #expect(root.view.isUserInteractionEnabled)
            try await Task.sleep(for: .milliseconds(200))
            #expect(toast(in: window) == nil)
            #expect(window.subviews.count == initialSubviews)
            #expect(root.presentedViewController == nil)
        }
    }

    @Test func oldTimerAndCloseCannotRemoveReplacementOrUnrelatedPresentation() async throws {
        try await withWindow { window, root in
            SourceToastPresenter.show(message: "Synthetic first", in: window, duration: 0.08)
            let old = try #require(toast(in: window))
            let oldClose = try #require(old.subviews.compactMap { $0 as? UIButton }.first)
            try await Task.sleep(for: .milliseconds(20))
            SourceToastPresenter.show(message: "Synthetic replacement", in: window, duration: 1)
            let replacement = try #require(toast(in: window))
            #expect(replacement !== old)
            oldClose.sendActions(for: .touchUpInside)
            let unrelated = UIViewController()
            root.present(unrelated, animated: false)
            try await Task.sleep(for: .milliseconds(180))
            #expect(toast(in: window) === replacement)
            #expect(root.presentedViewController === unrelated)
            BookSourceFormLoginView.dismissToastAlert {}
            #expect(toast(in: window) == nil)
            #expect(root.presentedViewController === unrelated)
            unrelated.dismiss(animated: false)
        }
    }

    @Test func explicitCloseAndCompletionRestoreOnlyToastState() async throws {
        try await withWindow { window, root in
            SourceToastPresenter.show(message: "Synthetic close", in: window, duration: 10)
            let view = try #require(toast(in: window))
            let close = try #require(view.subviews.compactMap { $0 as? UIButton }.first)
            close.sendActions(for: .touchUpInside)
            await Task.yield()
            #expect(toast(in: window) == nil)
            var completions = 0
            BookSourceFormLoginView.dismissToastAlert { completions += 1 }
            #expect(completions == 1)
            #expect(root.presentedViewController == nil)
        }
    }

    @Test func hiddenWindowNeverRetainsToast() async throws {
        try await withWindow { window, _ in
            window.isHidden = true
            SourceToastPresenter.show(message: "Synthetic hidden", in: window, duration: 0.01)
            #expect(toast(in: window) == nil)
        }
    }
}

@MainActor
private final class SourceToastTestPresenter: UIViewController {
    private(set) var appeared = false
    override func viewDidAppear(_ animated: Bool) { super.viewDidAppear(animated); appeared = true }
}

@Suite("Offline menu JS failure recovery", .serialized)
struct SourceMenuJSFailureRecoveryTests {
    @Test func exceptionDoesNotPoisonNextActionOrNestedEvaluation() async {
        let result = await SourceScriptThread.run {
            let engine = JSCoreEngine()
            _ = engine.evaluate("throw new Error('synthetic menu failure')")
            let hadError = engine.lastError != nil
            engine.sourceBridge.evalJSHandler = { [weak engine] js in engine?.evaluate(js) ?? "" }
            let next = engine.evaluate("source.evalJS('1 + 1')")
            return (hadError, next, engine.lastError)
        }
        #expect(result.0)
        #expect(result.1 == "2")
        #expect(result.2 == nil)
    }
}
