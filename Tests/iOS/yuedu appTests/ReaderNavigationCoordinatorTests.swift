import Testing
import Foundation
import UIKit
@testable import yuedu_app

/// Covers the opening-transition gate that keeps non-first-page reader work
/// (neighbour pagination, cover decode) out of the card animation's render
/// pass. The gate's dangerous failure is parking a waiter that nothing will
/// ever release — that would stall an ordinary page turn forever, so both
/// tests here pin the "never latches closed" side of the contract.
///
/// The in-flight half (gate closed for the duration of a real push, waiters
/// released on commit) depends on UIKit transition timing and is verified on
/// device through the `⏱ reader.open.transition` and
/// `⏱ reader.open.deferredPreload` spans instead of a flaky unit test.
@MainActor
@Suite("ReaderNavigationCoordinator opening gate", .serialized)
struct ReaderNavigationOpeningGateTests {

    @Test("an idle coordinator never parks a waiter")
    func idleGateReturnsImmediately() async {
        let coordinator = ReaderNavigationCoordinator()
        #expect(coordinator.isOpeningTransitionActive == false)
        // Reaching the next line at all is the assertion: a gate that parked
        // here would hang every page turn made on a settled reader.
        await coordinator.awaitOpeningTransitionEnd()
        #expect(coordinator.isOpeningTransitionActive == false)
    }

    @Test("an open that never starts a push leaves the gate open")
    func refusedOpenDoesNotCloseGate() async {
        // No navigation controller attached, so the push can never start. The
        // gate must not latch closed here: nothing would ever reopen it, and
        // every later deferred preload would park permanently.
        let coordinator = ReaderNavigationCoordinator()
        coordinator.open(
            bookID: UUID(),
            destination: { UIViewController() }
        )
        #expect(coordinator.isOpeningTransitionActive == false)
        await coordinator.awaitOpeningTransitionEnd()
    }
}

@MainActor
@Suite("Reader card close fallback", .serialized)
struct ReaderCardCloseFallbackTests {
    @Test("a close with no cover fades the full-size page and restores it on cancellation",
          arguments: [false, true])
    func sourceLessCloseFadesPage(cancelled: Bool) throws {
        let context = ReaderCloseTransitionContext()
        context.transitionWasCancelled = cancelled
        var completions: [Bool] = []
        let animator = ReaderCardTransitionAnimator(
            operation: .pop,
            source: .fallback(bookID: UUID()),
            completion: { completions.append($0) }
        )
        #expect(animator.transitionDuration(using: context) == DSAnimation.readerBookReducedMotionDuration)
        let timeline = try #require(
            animator.interruptibleAnimator(using: context) as? UIViewPropertyAnimator
        )
        // The declarative path has installed its endpoint on the model layer.
        // A source-less close must fade a full-size page, never shrink it under
        // the blank cover seen in the reported video.
        #expect(context.reader.view.transform == .identity)
        let opacity = try #require(
            context.reader.view.layer.animation(forKey: "readerTransition.opacity") as? CAKeyframeAnimation
        )
        #expect((opacity.values?.first as? NSNumber)?.doubleValue == 1)
        #expect((opacity.values?.last as? NSNumber)?.doubleValue == 0)
        #expect(context.reader.view.layer.animation(forKey: "readerTransition.transform") == nil)

        timeline.startAnimation()
        timeline.stopAnimation(false)
        timeline.finishAnimation(at: .end)

        #expect(context.completed == !cancelled)
        #expect(completions == [!cancelled])
        #expect(context.reader.view.alpha == 1)
        #expect(context.reader.view.transform == .identity)
        #expect(context.reader.view.layer.animationKeys()?.isEmpty != false)
        let remaining = context.containerView.subviews
        #expect(remaining.count == 1)
        #expect(remaining.first === (cancelled ? context.reader.view : context.shelf.view))
    }

    @Test("a live cover retains the full book close while a missing target uses the short fallback")
    func liveCoverKeepsCardClose() {
        let frame = CGRect(x: 20, y: 40, width: 90, height: 135)
        let image = UIGraphicsImageRenderer(size: frame.size).image { context in
            UIColor.blue.setFill()
            context.fill(CGRect(origin: .zero, size: frame.size))
        }
        var liveFrame: CGRect? = frame
        let source = ReaderTransitionSource(
            bookID: UUID(), frameProvider: { liveFrame }, snapshot: image
        )
        let close = ReaderCardTransitionAnimator(operation: .pop, source: source) { _ in }
        let expectedCardDuration = UIAccessibility.isReduceMotionEnabled
            ? DSAnimation.readerBookReducedMotionDuration
            : DSAnimation.readerBookTransitionDuration
        #expect(close.transitionDuration(using: nil) == expectedCardDuration)
        liveFrame = nil
        // UIKit can ask for the duration more than once during a transaction.
        #expect(close.transitionDuration(using: nil) == expectedCardDuration)
        let missingTarget = ReaderCardTransitionAnimator(operation: .pop, source: source) { _ in }
        #expect(missingTarget.transitionDuration(using: nil) == DSAnimation.readerBookReducedMotionDuration)
        let open = ReaderCardTransitionAnimator(operation: .push, source: .fallback(bookID: UUID())) { _ in }
        #expect(open.transitionDuration(using: nil) == close.transitionDuration(using: nil))
    }
}

/// Drives the real animator synchronously, without UIKit's navigation timing.
@MainActor
private final class ReaderCloseTransitionContext: NSObject, UIViewControllerContextTransitioning {
    let containerView = UIView(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
    let reader = UIViewController()
    let shelf = UIViewController()
    let isAnimated = true
    let isInteractive = false
    var transitionWasCancelled = false
    let presentationStyle: UIModalPresentationStyle = .none
    let targetTransform: CGAffineTransform = .identity
    private(set) var completed: Bool?

    override init() {
        super.init()
        reader.view.frame = containerView.bounds
        shelf.view.frame = containerView.bounds
        containerView.addSubview(reader.view)
    }

    func updateInteractiveTransition(_ percentComplete: CGFloat) {}
    func finishInteractiveTransition() {}
    func cancelInteractiveTransition() {}
    func pauseInteractiveTransition() {}
    func completeTransition(_ didComplete: Bool) { completed = didComplete }

    func viewController(forKey key: UITransitionContextViewControllerKey) -> UIViewController? {
        key == .from ? reader : shelf
    }

    func view(forKey key: UITransitionContextViewKey) -> UIView? {
        key == .from ? reader.view : shelf.view
    }

    func initialFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
    func finalFrame(for vc: UIViewController) -> CGRect { containerView.bounds }
}
