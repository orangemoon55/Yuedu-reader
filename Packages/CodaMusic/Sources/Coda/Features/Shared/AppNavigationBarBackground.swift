import SwiftUI

/// The active page supplies the same color to its system bar and window safe areas.
struct AppPageBackgroundKey: PreferenceKey {
    static var defaultValue: Color?
    static func reduce(value: inout Color?, nextValue: () -> Color?) {
        value = nextValue() ?? value
    }
}

private struct AppMainTitleBoundsKey: PreferenceKey {
    static var defaultValue: Anchor<CGRect>?
    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = nextValue() ?? value
    }
}

private struct AppMainTitleHiddenKey: PreferenceKey {
    static var defaultValue: Bool?
    static func reduce(value: inout Bool?, nextValue: () -> Bool?) {
        value = nextValue() ?? value
    }
}

private struct AppMainTitleHiddenEnvironmentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var appMainTitleHidden: Bool {
        get { self[AppMainTitleHiddenEnvironmentKey.self] }
        set { self[AppMainTitleHiddenEnvironmentKey.self] = newValue }
    }
}

extension View {
    /// Every main tab shares title sizing and the same native toolbar host.
    func appRootNavigationTitle(_ title: String) -> some View {
        modifier(AppRootNavigationTitle(title: title))
    }

    /// Mark the title itself, rather than the cover or the entire header, so
    /// wrapping, Dynamic Type and different header layouts share one boundary.
    func appMainTitle() -> some View {
        anchorPreference(key: AppMainTitleBoundsKey.self, value: .bounds) { $0 }
    }

    @ViewBuilder
    func appNavigationBarBackground() -> some View {
        modifier(AppNavigationBarBackground())
    }
}

private struct AppRootNavigationTitle: ViewModifier {
    let title: String
    #if os(macOS)
    @ObservedObject private var player = PlayerChromeState.shared
    #endif
    @Environment(\.compactWindowLayout) private var compactWindowLayout

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            #else
            .navigationTitle(compactWindowLayout ? "" : title)
            .toolbar {
                // AppKit's editor-style title moves leading when actions appear.
                // Use the standard principal item for every compact root tab.
                if compactWindowLayout && !player.showNowPlaying {
                    ToolbarItem(placement: .principal) {
                        Text(title)
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            #endif
    }
}

private struct AppNavigationBarBackground: ViewModifier {
    @State private var mainTitleHidden: Bool?
    @State private var pageBackground: Color?
    var phoneLayout = PhonePageLayout()
    #if os(macOS)
    @ObservedObject private var player = PlayerChromeState.shared
    #endif
    func body(content: Content) -> some View {
        titleTracking(content)
            #if os(iOS)
            .toolbarRole(.navigationStack)
            .toolbar((phoneLayout.isEnabled || (ReadccHostBridge.isEmbedded && UIDevice.current.userInterfaceIdiom == .pad)) ? .visible : .hidden, for: .navigationBar)
            .modifier(PhoneNavigationGlass(backgroundColor: pageBackground))
            #else
            // MainWindowConfigurator controls NSToolbar visibility. Hiding the
            // SwiftUI window toolbar also removes the native window buttons
            // from a hidden-titlebar window on current macOS releases.
            .toolbar {
                if phoneLayout.isEnabled && player.showNowPlaying {
                    ToolbarItem(placement: .principal) {
                        Color.clear
                            .frame(width: 1, height: 1)
                            .accessibilityHidden(true)
                    }
                }
            }
            #endif
            .onPreferenceChange(AppPageBackgroundKey.self) { pageBackground = $0 }
    }

    private func titleTracking(_ content: Content) -> some View {
        content
            .environment(\.appMainTitleHidden, mainTitleHidden ?? false)
            .backgroundPreferenceValue(AppMainTitleBoundsKey.self) { anchor in
                GeometryReader { viewport in
                    Color.clear.preference(key: AppMainTitleHiddenKey.self,
                        value: anchor.map { viewport[$0].maxY <= viewport.safeAreaInsets.top })
                }
            }
            .onPreferenceChange(AppMainTitleHiddenKey.self) { mainTitleHidden = $0 }
            // A retained parent page must not consume a pushed page's title.
            .transformPreference(AppMainTitleBoundsKey.self) { $0 = nil }
            .transformPreference(AppMainTitleHiddenKey.self) { $0 = nil }
    }
}

#if os(iOS)
/// Decorate the system bar on older releases; UIKit still owns layout,
/// titles, buttons, scroll-edge transitions and the back gesture.
private struct PhoneNavigationGlass: ViewModifier {
    let backgroundColor: Color?
    var phoneLayout = PhonePageLayout()
    @ViewBuilder
    func body(content: Content) -> some View {
        if phoneLayout.isEnabled {
            if #available(iOS 26.0, *) { content }
            else { content.background(LegacyPhoneNavigationGlass(backgroundColor: backgroundColor)) }
        } else { content }
    }
}

/// Style the existing navigation bar, including its status-bar extension, so
/// large titles and pushed pages keep UIKit's sizing and back gestures.
private struct LegacyPhoneNavigationGlass: UIViewControllerRepresentable {
    let backgroundColor: Color?
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func makeUIViewController(context: Context) -> NavigationGlassController {
        NavigationGlassController()
    }

    func updateUIViewController(_ controller: NavigationGlassController, context: Context) {
        controller.pageBackground = backgroundColor.map { UIColor($0) }
        controller.dark = colorScheme == .dark
        controller.reduceTransparency = reduceTransparency
        controller.applyAppearance()
    }
}

private final class NavigationGlassController: UIViewController {
    var pageBackground: UIColor?
    var dark = false
    var reduceTransparency = false

    override func loadView() {
        view = UIView()
        view.isUserInteractionEnabled = false
        view.accessibilityElementsHidden = true
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyAppearance()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        applyAppearance()
    }

    func applyAppearance() {
        // Updates can arrive while a retained tab is off screen. Its next
        // appearance will apply its own environment without recoloring another tab.
        guard isViewLoaded, view.window != nil,
              let bar = navigationController?.navigationBar else { return }
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        if reduceTransparency {
            appearance.backgroundColor = pageBackground ?? .systemBackground
        } else {
            appearance.backgroundEffect = UIBlurEffect(style: dark
                ? .systemUltraThinMaterialDark : .systemUltraThinMaterialLight)
            appearance.backgroundColor = (dark ? UIColor.black : .white)
                .withAlphaComponent(GlassSurfaceStyle.faceOpacity(dark: dark))
            appearance.backgroundImage = faceHighlight()
            appearance.shadowColor = UIColor.white.withAlphaComponent(
                GlassSurfaceStyle.highlightOpacity(dark: dark) * 0.35)
        }
        bar.standardAppearance = appearance
        // At the scroll edge, match the page without a material tint or seam.
        let scrollEdge = UINavigationBarAppearance()
        scrollEdge.configureWithOpaqueBackground()
        scrollEdge.backgroundColor = pageBackground ?? .systemBackground
        scrollEdge.shadowColor = .clear
        bar.scrollEdgeAppearance = scrollEdge
        bar.compactAppearance = appearance
        bar.compactScrollEdgeAppearance = scrollEdge
    }

    private func faceHighlight() -> UIImage {
        let size = CGSize(width: 2, height: 128)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
            let colors = [UIColor.white.withAlphaComponent(dark ? 0.07 : 0.18).cgColor,
                          UIColor.white.withAlphaComponent(0.01).cgColor,
                          UIColor.black.withAlphaComponent(dark ? 0.06 : 0.02).cgColor]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                         colors: colors as CFArray, locations: [0, 0.5, 1]) {
                renderer.cgContext.drawLinearGradient(gradient, start: .zero,
                    end: CGPoint(x: 0, y: size.height), options: [])
            }
        }.resizableImage(withCapInsets: .zero, resizingMode: .stretch)
    }
}

#endif
