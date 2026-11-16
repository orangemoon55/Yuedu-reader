import SwiftUI

struct ReaderQuickThemeAction: Identifiable {
    let id: ReaderQuickPanelRoute
    let titleKey: String
    let systemImage: String
}

struct ReaderQuickThemeActionTile: View {
    let action: ReaderQuickThemeAction
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            VStack(spacing: DSSpacing.xs) {
                Image(systemName: action.systemImage)
                    .font(DSFont.title2.weight(.medium))
                    .accessibilityHidden(true)
                Text(localized(action.titleKey))
                    .font(DSFont.caption.weight(.medium))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DSColor.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 76)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .fill(DSColor.neutralControlFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .strokeBorder(DSColor.separator, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(action.titleKey))
        .accessibilityIdentifier("reader.quickTool.\(String(describing: action.id))")
    }
}
