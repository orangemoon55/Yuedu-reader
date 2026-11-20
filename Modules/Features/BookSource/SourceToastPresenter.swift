import UIKit

/// Source scripts emit transient messages, not modal decisions. A window-owned toast must
/// never occupy UIKit's presentation chain: a missing dismissal otherwise disables every
/// control behind UIAlertController's dimming view (including the form's Cancel button).
@MainActor
enum SourceToastPresenter {
    private static var currentToast: UIView?
    private static var dismissalTask: Task<Void, Never>?

    static func show(message: String, in window: UIWindow, duration: TimeInterval = 2) {
        // Do not install UI on a detached/background window, especially during iOS 17
        // sheet transitions. No queued presentation is left to appear on a different form.
        guard !window.isHidden, window.windowScene?.activationState == .foregroundActive,
              window.rootViewController?.viewIfLoaded?.window === window else { return }
        hide()

        let toast = UIView()
        toast.accessibilityIdentifier = "source.toast"
        toast.translatesAutoresizingMaskIntoConstraints = false
        toast.backgroundColor = .secondarySystemBackground
        toast.layer.cornerRadius = 14
        toast.layer.shadowColor = UIColor.black.cgColor
        toast.layer.shadowOpacity = 0.18
        toast.layer.shadowRadius = 10
        toast.layer.shadowOffset = CGSize(width: 0, height: 3)

        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.text = message
        label.textColor = .label
        label.font = .preferredFont(forTextStyle: .body)
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 6

        let close = UIButton(type: .system)
        close.translatesAutoresizingMaskIntoConstraints = false
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.accessibilityLabel = localized("關閉")
        close.accessibilityIdentifier = "source.toast.close"
        close.addAction(UIAction { [weak toast] _ in
            Task { @MainActor in
                guard let toast else { return }
                hide(toast)
            }
        }, for: .touchUpInside)

        toast.addSubview(label)
        toast.addSubview(close)
        window.addSubview(toast)
        NSLayoutConstraint.activate([
            toast.centerXAnchor.constraint(equalTo: window.safeAreaLayoutGuide.centerXAnchor),
            toast.topAnchor.constraint(equalTo: window.safeAreaLayoutGuide.topAnchor, constant: 12),
            toast.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            toast.leadingAnchor.constraint(greaterThanOrEqualTo: window.safeAreaLayoutGuide.leadingAnchor, constant: 16),
            toast.trailingAnchor.constraint(lessThanOrEqualTo: window.safeAreaLayoutGuide.trailingAnchor, constant: -16),
            label.leadingAnchor.constraint(equalTo: toast.leadingAnchor, constant: 16),
            label.topAnchor.constraint(equalTo: toast.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: toast.bottomAnchor, constant: -12),
            label.trailingAnchor.constraint(equalTo: close.leadingAnchor, constant: -8),
            close.trailingAnchor.constraint(equalTo: toast.trailingAnchor, constant: -4),
            close.centerYAnchor.constraint(equalTo: toast.centerYAnchor),
            close.widthAnchor.constraint(equalToConstant: 44),
            close.heightAnchor.constraint(equalToConstant: 44),
            toast.heightAnchor.constraint(greaterThanOrEqualToConstant: 48)
        ])
        currentToast = toast
        UIAccessibility.post(notification: .announcement, argument: message)
        dismissalTask = Task { @MainActor [weak toast] in
            do {
                try await Task.sleep(for: .seconds(max(0, duration)))
            } catch { return }
            guard let toast else { return }
            hide(toast)
        }
    }

    static func hide() {
        dismissalTask?.cancel()
        dismissalTask = nil
        currentToast?.removeFromSuperview()
        currentToast = nil
    }

    private static func hide(_ toast: UIView) {
        // Cancellation can race a timer already resumed on MainActor. The old timer or
        // close action must neither remove a newer toast nor dismiss a browser/sheet.
        guard currentToast === toast else { return }
        hide()
    }
}
