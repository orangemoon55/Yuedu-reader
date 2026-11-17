import SwiftUI

/// A real layout slot outside each tab's NavigationStack. An outer safeAreaInset
/// alone is not reliably forwarded through TabView/NavigationStack on iOS 17;
/// overlays then cover pushed Forms and native bottom toolbars. Constraining the
/// navigation container's proposed height reserves space for both, at every depth.
///
/// Never write additionalSafeAreaInsets here: LNPopupUI owns its player reservation,
/// and changing a covered navigation controller during sheet presentation can feed
/// another layout pass back into the bar measurement. The parent safe area (player,
/// keyboard and home indicator) is consumed once, by this stack's layout.
struct FloatingRootTabBarContainer<Bar: View>: ViewModifier {
    let isPresented: Bool
    @ViewBuilder var bar: () -> Bar

    func body(content: Content) -> some View {
        VStack(spacing: 0) {
            // Keep this identity in every state: hiding the bar must not rebuild a
            // NavigationStack or change any tab's path, search field, or presenter.
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if isPresented {
                bar()
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview("Pushed content and native toolbar above the floating bar") {
    NavigationStack {
        List(0..<30, id: \.self) { row in
            NavigationLink("Row \(row)") {
                Form { Text("Details") }
                    .toolbar {
                        ToolbarItem(placement: .bottomBar) { Button("Action") {} }
                    }
            }
        }
    }
    .modifier(FloatingRootTabBarContainer(isPresented: true) {
        FloatingRootTabBar(tabs: [.explore, .bookshelf, .settings, .search], selection: .constant(.explore))
            .padding(.top, FloatingRootTabBarLayout.topSpacing)
            .padding(.bottom, FloatingRootTabBarLayout.bottomSpacing)
    })
}
