#if os(iOS)
import SwiftUI

/// iPadOS 16 can route touches to NavigationStack's UIKit content underneath
/// SwiftUI overlays. Give the shared bottom controls their own native sibling
/// above that navigation host, with a boundary limited to the chrome's height.
struct CompactChromeHost<Content: View, Chrome: View>: UIViewControllerRepresentable {
    let chromeHeight: CGFloat
    var onPageBackgroundChange: (Color?) -> Void = { _ in }
    @ViewBuilder var content: () -> Content
    @ViewBuilder var chrome: () -> Chrome
    @Environment(\.self) private var environment

    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ controller: Controller, context: Context) {
        controller.update(
            content: AnyView(content().environment(\.self, environment)
                .onPreferenceChange(AppPageBackgroundKey.self, perform: onPageBackgroundChange)),
            chrome: AnyView(chrome().environment(\.self, environment).ignoresSafeArea()),
            height: chromeHeight
        )
    }

    final class Controller: UIViewController {
        private let contentHost = UIHostingController(rootView: AnyView(EmptyView()))
        private let chromeHost = UIHostingController(rootView: AnyView(EmptyView()))
        private let touchBoundary = ChromeTouchBoundary()
        private var chromeHeight: NSLayoutConstraint!

        override func loadView() {
            view = UIView()
            view.backgroundColor = .clear
            attach(contentHost, to: view)

            touchBoundary.backgroundColor = .clear
            touchBoundary.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(touchBoundary)
            chromeHeight = touchBoundary.heightAnchor.constraint(equalToConstant: 0)
            NSLayoutConstraint.activate([
                touchBoundary.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                touchBoundary.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                touchBoundary.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                chromeHeight
            ])
            attach(chromeHost, to: touchBoundary)
        }

        private func attach(_ child: UIViewController, to container: UIView) {
            addChild(child)
            child.view.backgroundColor = .clear
            child.view.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child.view)
            NSLayoutConstraint.activate([
                child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                child.view.topAnchor.constraint(equalTo: container.topAnchor),
                child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
            child.didMove(toParent: self)
        }

        func update(content: AnyView, chrome: AnyView, height: CGFloat) {
            loadViewIfNeeded()
            contentHost.rootView = content
            chromeHost.rootView = chrome
            chromeHeight.constant = height
            view.bringSubviewToFront(touchBoundary)
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            view.bringSubviewToFront(touchBoundary)
        }
    }
}

/// Child controls get first refusal. Padding and gaps consume touches here
/// even when SwiftUI's transparent hosting view returns no hit-tested child.
private final class ChromeTouchBoundary: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard isUserInteractionEnabled, !isHidden, alpha > 0.01,
              self.point(inside: point, with: event) else { return nil }
        return super.hitTest(point, with: event) ?? self
    }
}
#endif
