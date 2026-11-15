import SwiftUI

struct ReaderSettingsNavigationHost<Content: View>: View {
    let usesParent: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        if usesParent {
            content()
        } else {
            NavigationStack { content() }
        }
    }
}
