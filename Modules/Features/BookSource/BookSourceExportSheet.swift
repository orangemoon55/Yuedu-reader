import SwiftUI
import UIKit

/// The menu only hands off the request. Share is a fresh tap on the already
/// presented first-level sheet, not a second modal opened by a dismissing menu.
struct BookSourceExportSheet: View {
    let request: BookSourceExportRequest

    @Environment(\.dismiss) private var dismiss
    @State private var anchor = BookSourceShareAnchor()
    @State private var isSharing = false
    @State private var shareError: String?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button(action: share) {
                        Label(localized("分享"), systemImage: "square.and.arrow.up")
                    }
                    .background(BookSourceShareAnchorView(anchor: anchor))
                    .disabled(isSharing)
                    if isSharing {
                        ProgressView()
                    }
                    if let shareError {
                        VStack(alignment: .leading) {
                            Text(localized("匯出失敗")).font(.headline)
                            Text(shareError)
                        }
                    }
                } footer: {
                    Text(request.filename).dsSectionFooter()
                }
                .interfaceSectionSurface()
            }
            .softScrollEdges()
            .navigationTitle(request.title)
            .toolbarTitleDisplayMode(.inline)
            .themedAppSurface(for: .settings)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(localized("取消")) { dismiss() }.disabled(isSharing)
                }
            }
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled(isSharing)
    }

    private func share() {
        guard !isSharing else { return }
        isSharing = true
        shareError = nil
        let snapshot = request
        Task { @MainActor in
            do {
                let file = try await Task.detached(priority: .userInitiated) {
                    try BookSourceExportFile.write(snapshot)
                }.value
                if !anchor.present(file, onCompletion: { error in
                    isSharing = false
                    shareError = error
                }) {
                    isSharing = false
                    shareError = localized("請稍後再試。")
                }
            } catch {
                isSharing = false
                shareError = error.localizedDescription
            }
        }
    }
}

/// Unlike a global scene lookup, the row gives us both the sheet's actual window
/// and an iPad source rect. Present the real file URL, not a lazy item provider.
@MainActor
final class BookSourceShareAnchor {
    weak var view: UIView?

    @discardableResult
    func present(
        _ file: BookSourceExportFile,
        onCompletion: @escaping @MainActor (String?) -> Void
    ) -> Bool {
        guard let view, let window = view.window else { return false }
        var responder = view.next
        while let candidate = responder, !(candidate is UIViewController) {
            responder = candidate.next
        }
        guard var presenter = responder as? UIViewController else { return false }
        while let parent = presenter.parent { presenter = parent }
        // Navigation/SwiftUI containment may lead to the presenting root. Follow only
        // this window's visible presented chain, and require that it still owns the tap.
        while let foreground = presenter.presentedViewController, !foreground.isBeingDismissed {
            presenter = foreground
        }
        guard presenter.viewIfLoaded?.window === window,
              view.isDescendant(of: presenter.view),
              !presenter.isBeingDismissed, !presenter.isBeingPresented,
              presenter.presentedViewController == nil,
              presenter.transitionCoordinator == nil else { return false }

        let activity = UIActivityViewController(activityItems: [file.url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = view
            popover.sourceRect = view.bounds
        }
        // Retain the file through target selection and activity completion (including
        // Save to Files), not merely until the activity controller has appeared.
        activity.completionWithItemsHandler = { _, _, _, error in
            file.remove()
            let message = error?.localizedDescription
            Task { @MainActor in onCompletion(message) }
        }
        presenter.present(activity, animated: true)
        return true
    }
}

private struct BookSourceShareAnchorView: UIViewRepresentable {
    let anchor: BookSourceShareAnchor

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        anchor.view = view
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        anchor.view = uiView
    }
}
