import SwiftUI

private struct FloatingRootScrollBottomInsetKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

extension EnvironmentValues {
    /// UIKit result lists do not inherit SwiftUI contentMargins automatically.
    /// Only content insets consume this value; no navigation viewport is shortened.
    var floatingRootScrollBottomInset: CGFloat {
        get { self[FloatingRootScrollBottomInsetKey.self] }
        set { self[FloatingRootScrollBottomInsetKey.self] = newValue }
    }
}

/// The capsule is an overlay on a full-size navigation surface. Only its transparent
/// scroll-safe region is reserved: rows can pass behind it, and the last row can still
/// be scrolled clear. Never allocate a VStack slot or shorten a navigation viewport.
/// The reservation follows the actual bar height, including accessibility text.
/// Native player and home-indicator safe areas remain owned by their existing hosts.
struct FloatingRootTabBarContainer<Bar: View>: ViewModifier {
    let isPresented: Bool
    @ViewBuilder var bar: () -> Bar
    @State private var barHeight: CGFloat = 0

    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // Content margins affect scrollable content/indicators, never the
            // full-size navigation viewport. Transparent gaps keep live content.
            .contentMargins(.bottom, isPresented ? barHeight : 0, for: .scrollContent)
            .contentMargins(.bottom, isPresented ? barHeight : 0, for: .scrollIndicators)
            .environment(\.floatingRootScrollBottomInset, isPresented ? barHeight : 0)
            .overlay(alignment: .bottom) {
                if isPresented {
                    bar()
                        .fixedSize(horizontal: false, vertical: true)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                            guard height.isFinite, height > 0, abs(height - barHeight) > 0.5 else { return }
                            barHeight = height
                        }
                }
            }
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
