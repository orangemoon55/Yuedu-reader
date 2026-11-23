import SwiftUI
import UIKit

// Reader controls are UI, not a sample of the publication or the imported interface
// font. Keep semantic sizing/Bold Text, but explicitly request the system typeface.
extension DSFont {
    @MainActor
    static func readerMenu(_ style: GlobalAppTypography.Style) -> Font {
        GlobalAppTypography.font(style, postScriptName: nil)
    }
}

// Local design tokens: system foregrounds must be paired with system surfaces.
// DSColor.textPrimary can come from an imported theme, while neutralControlFill
// cannot; mixing those two made the quick panel unreadable in some theme packs.
extension DSColor {
    static var readerMenuBackground: Color { Color(uiColor: .systemBackground) }
    static var readerMenuText: Color { Color(uiColor: .label) }
    static var readerMenuControlFill: Color { Color(uiColor: .secondarySystemBackground) }
    static var readerMenuAccent: Color { Color(uiColor: .systemBlue) }
    static var readerMenuSelectionFill: Color { readerMenuAccent.opacity(0.10) }
    static var readerMenuSecondaryText: Color { Color(uiColor: .secondaryLabel) }
    static var readerMenuSeparator: Color { Color(uiColor: .separator) }
    static var readerMenuSelection: Color { Color(uiColor: .label) }
    static var readerMenuOnSelection: Color { Color(uiColor: .systemBackground) }
}

/// Menu surfaces never sample the page behind them, including at 100% interface
/// transparency. This also satisfies Reduce Transparency without a second path.
/// The custom colour is retained, but a translucent colour is composited onto the
/// reader's opaque ground rather than onto live text/header/footer pixels.
enum ReaderMenuColors {
    static func opaque(_ color: UIColor, over background: UIColor, traits: UITraitCollection) -> UIColor {
        let front = components(color.resolvedColor(with: traits))
        let back = components(background.resolvedColor(with: traits))
        return UIColor(
            red: front.0 * front.3 + back.0 * (1 - front.3),
            green: front.1 * front.3 + back.1 * (1 - front.3),
            blue: front.2 * front.3 + back.2 * (1 - front.3),
            alpha: 1
        )
    }

    /// Preserve readable custom ink. A theme with matching text/fill or transparent
    /// ink cannot label controls: choose the higher-contrast system monochrome ink.
    /// Unlike the reading text colour, menu legibility is not a publication setting.
    static func legible(_ ink: UIColor, on fill: UIColor, traits: UITraitCollection) -> UIColor {
        let resolved = opaque(ink, over: fill, traits: traits)
        let minimum: CGFloat = traits.accessibilityContrast == .high ? 7 : 4.5
        if contrast(resolved, fill) >= minimum { return resolved }
        return contrast(.black, fill) > contrast(.white, fill) ? .black : .white
    }

    static func contrast(_ first: UIColor, _ second: UIColor) -> CGFloat {
        let a = luminance(first), b = luminance(second)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    private static func luminance(_ color: UIColor) -> CGFloat {
        let rgb = components(color)
        func linear(_ value: CGFloat) -> CGFloat {
            value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(rgb.0) + 0.7152 * linear(rgb.1) + 0.0722 * linear(rgb.2)
    }

    private static func components(_ color: UIColor) -> (CGFloat, CGFloat, CGFloat, CGFloat) {
        var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 1
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return (min(max(red, 0), 1), min(max(green, 0), 1), min(max(blue, 0), 1), min(max(alpha, 0), 1))
    }
}

extension View {
    /// Use only on reader menu chrome, not publication or preview content.
    func readerMenuSurface<S: Shape>(in shape: S, fill: Color) -> some View {
        background(fill, in: shape)
    }
}

#Preview("Reader menu · system UI") {
    VStack(spacing: DSSpacing.lg) {
        ReaderQuickThemeActionTile(
            action: ReaderQuickThemeAction(id: .display, titleKey: "顯示設定", systemImage: "textformat.size"),
            perform: {}
        )
        ReaderQuickPageTurnChip(option: .slide, title: localized("Slide"), selected: true, action: {})
    }
    .font(DSFont.readerMenu(.body))
    .padding(DSSpacing.xl)
    .background(DSColor.readerMenuBackground)
}
