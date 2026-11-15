import SwiftUI

struct ReaderQuickPageTurnChip: View {
    let option: ReaderQuickPageTurnOption
    let title: String
    let selected: Bool
    let action: () -> Void

    private var fill: Color { selected ? DSColor.accent : DSColor.neutralControlFill }
    private var ink: Color { selected ? DSColor.textOnAccent : DSColor.textPrimary }
    private var border: Color { selected ? .clear : DSColor.separator }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: option.iconName)
                .font(DSFont.subheadline.weight(.medium))
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .foregroundColor(ink)
                .padding(.horizontal, DSSpacing.md)
                .frame(minHeight: DSLayout.readerQuickPanelTopControlHeight)
                .background(fill, in: Capsule())
                .overlay(Capsule().strokeBorder(border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? AccessibilityTraits.isSelected : AccessibilityTraits())
        .accessibilityIdentifier("reader.pageTurnStyle.\(option.rawValue)")
    }
}
