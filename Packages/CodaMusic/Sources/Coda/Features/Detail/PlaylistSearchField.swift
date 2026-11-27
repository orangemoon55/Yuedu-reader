#if os(iOS)
import SwiftUI
import UIKit

/// The iPad header supplies its own trailing search icon and flexible background.
struct PlaylistInlineSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String = String(localized: "搜索")

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.placeholder = placeholder
        field.accessibilityLabel = String(localized: "搜索歌单内歌曲")
        field.accessibilityHint = String(localized: "按歌名、歌手或专辑搜索")
        field.accessibilityIdentifier = "likedSongsSearch"
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.returnKeyType = .search
        field.clearButtonMode = .whileEditing
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        if field.markedTextRange == nil, field.text != text { field.text = text }
        if isFocused && !field.isFirstResponder {
            DispatchQueue.main.async { [weak field, weak coordinator = context.coordinator] in
                guard coordinator?.parent.isFocused == true else { return }
                field?.becomeFirstResponder()
            }
        } else if !isFocused && field.isFirstResponder {
            field.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ field: UITextField, coordinator: Coordinator) {
        field.delegate = nil
        field.removeTarget(coordinator, action: #selector(Coordinator.textChanged(_:)), for: .editingChanged)
        field.resignFirstResponder()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PlaylistInlineSearchField
        init(_ parent: PlaylistInlineSearchField) { self.parent = parent }

        @objc func textChanged(_ field: UITextField) {
            guard field.markedTextRange == nil else { return }
            parent.text = field.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) { parent.isFocused = true }
        func textFieldDidEndEditing(_ textField: UITextField) { parent.isFocused = false }
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return true
        }
    }
}

struct PlaylistSearchField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool

    func makeUIView(context: Context) -> UISearchBar {
        let bar = UISearchBar()
        bar.searchBarStyle = .minimal
        bar.placeholder = String(localized: "搜索")
        bar.searchTextField.accessibilityHint = String(localized: "按歌名、歌手或专辑搜索")
        bar.searchTextField.accessibilityIdentifier = "likedSongsSearch"
        bar.autocapitalizationType = .none
        bar.autocorrectionType = .no
        bar.delegate = context.coordinator
        return bar
    }

    func updateUIView(_ bar: UISearchBar, context: Context) {
        context.coordinator.parent = self
        // Marked text belongs to the input method until the user commits it.
        if bar.searchTextField.markedTextRange == nil, bar.text != text {
            bar.text = text
        }
        if isFocused && !bar.searchTextField.isFirstResponder {
            // A newly revealed field joins the window after this update.
            DispatchQueue.main.async { [weak bar, weak coordinator = context.coordinator] in
                guard coordinator?.parent.isFocused == true else { return }
                bar?.searchTextField.becomeFirstResponder()
            }
        } else if !isFocused && bar.searchTextField.isFirstResponder {
            bar.searchTextField.resignFirstResponder()
        }
    }

    static func dismantleUIView(_ bar: UISearchBar, coordinator: Coordinator) {
        bar.delegate = nil
        bar.searchTextField.resignFirstResponder()
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UISearchBarDelegate {
        var parent: PlaylistSearchField

        init(_ parent: PlaylistSearchField) { self.parent = parent }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            guard searchBar.searchTextField.markedTextRange == nil else { return }
            parent.text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            parent.isFocused = true
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            parent.isFocused = false
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.searchTextField.resignFirstResponder()
        }
    }
}
#endif

#if os(macOS)
import SwiftUI

struct PlaylistInlineSearchField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    var placeholder: String = String(localized: "搜索")
    @FocusState private var focused: Bool

    var body: some View {
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(Theme.Typography.body)
            .focused($focused)
            .onChange(of: focused) { isFocused = $0 }
            .onChange(of: isFocused) { focused = $0 }
            .accessibilityLabel(placeholder)
            .accessibilityHint("按歌名、歌手或专辑搜索")
    }
}
#endif
