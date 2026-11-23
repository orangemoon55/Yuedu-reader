import SwiftUI

struct AdaptiveContentContainer<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder var content: Content

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesCenteredWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        content
            .frame(maxWidth: usesCenteredWidth ? maxWidth : .infinity, alignment: .top)
            .frame(maxWidth: .infinity, alignment: .top)
    }
}

struct AdaptiveSheetContainer<Content: View>: View {
    let maxWidth: CGFloat
    @ViewBuilder var content: Content

    @Bindable private var settings = GlobalSettings.shared
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var usesCenteredWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        content
            .frame(maxWidth: usesCenteredWidth ? maxWidth : .infinity, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .presentationBackground(
                InterfaceGlassPolicy.shouldUseGlass(isEnabled: settings.interfaceFrostedGlass,
                                                    systemReduceTransparency: reduceTransparency)
                ? AnyShapeStyle(.regularMaterial) : AnyShapeStyle(DSColor.groupedBackground)
            )
    }
}
