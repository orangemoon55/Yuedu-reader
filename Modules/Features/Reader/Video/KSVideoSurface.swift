import SwiftUI
import UIKit

/// Hosts KSMEPlayer's actual Metal/sample-buffer view beneath Readcc's existing controls.
struct KSVideoSurface: UIViewRepresentable {
    let renderView: UIView?
    let fillsScreen: Bool

    func makeUIView(context: Context) -> UIView {
        let container = UIView()
        container.backgroundColor = .black
        container.clipsToBounds = true
        return container
    }

    func updateUIView(_ container: UIView, context: Context) {
        if let renderView {
            if renderView.superview !== container {
                container.subviews.forEach { $0.removeFromSuperview() }
                renderView.removeFromSuperview()
                renderView.translatesAutoresizingMaskIntoConstraints = false
                container.addSubview(renderView)
                NSLayoutConstraint.activate([
                    renderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                    renderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                    renderView.topAnchor.constraint(equalTo: container.topAnchor),
                    renderView.bottomAnchor.constraint(equalTo: container.bottomAnchor)
                ])
            }
            renderView.contentMode = fillsScreen ? .scaleAspectFill : .scaleAspectFit
        } else {
            container.subviews.forEach { $0.removeFromSuperview() }
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ()) {
        uiView.subviews.forEach { $0.removeFromSuperview() }
    }
}
