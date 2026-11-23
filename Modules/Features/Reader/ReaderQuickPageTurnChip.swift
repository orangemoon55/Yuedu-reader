import SwiftUI

struct ReaderQuickPageTurnChip: View {
    let option: ReaderQuickPageTurnOption
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: DSSpacing.xs) {
                Image(systemName: option.iconName)
                    .font(DSFont.readerMenu(.footnote))
                    .accessibilityHidden(true)
                Text(title)
                    .font(DSFont.readerMenu(.footnote))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(selected ? DSColor.readerMenuAccent : DSColor.readerMenuText)
            .padding(.horizontal, DSSpacing.sm)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSLayout.minimumTapTarget)
            .background(selected ? DSColor.readerMenuSelectionFill : Color.clear,
                        in: RoundedRectangle(cornerRadius: DSRadius.md))
            .overlay(alignment: .topTrailing) {
                if selected {
                    Image(systemName: "checkmark")
                        .font(DSFont.readerMenu(.caption2))
                        .foregroundStyle(DSColor.readerMenuAccent)
                        .padding(DSSpacing.xxs)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("reader.pageTurnStyle.\(option.rawValue)")
    }
}
