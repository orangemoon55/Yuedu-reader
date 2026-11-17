import SwiftUI

struct ReaderQuickPageTurnChip: View {
    let option: ReaderQuickPageTurnOption
    let title: String
    let selected: Bool
    let action: () -> Void

    private var fill: Color { selected ? DSColor.readerMenuSelection : DSColor.neutralControlFill }
    private var ink: AnyShapeStyle {
        selected ? AnyShapeStyle(DSColor.readerMenuOnSelection) : AnyShapeStyle(DSColor.readerMenuText)
    }
    private var border: Color { selected ? .clear : DSColor.readerMenuSeparator }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: option.iconName)
                .font(DSFont.readerMenu(.subheadline).weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundStyle(ink)
                .padding(.horizontal, DSSpacing.md)
                .frame(minHeight: DSLayout.readerQuickPanelTopControlHeight)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("reader.pageTurnStyle.\(option.rawValue)")
    }
}
