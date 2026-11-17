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
                    .font(DSFont.readerMenu(.title2).weight(.medium))
                    .accessibilityHidden(true)
                Text(localized(action.titleKey))
                    .font(DSFont.readerMenu(.caption).weight(.medium))
                    .lineLimit(nil)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundStyle(DSColor.readerMenuText)
            .padding(.vertical, DSSpacing.md)
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerModernBookCardActionHeight)
            .background {
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .fill(DSColor.neutralControlFill)
            }
            .overlay {
                RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous)
                    .strokeBorder(DSColor.readerMenuSeparator, lineWidth: 0.5)
            }
            .contentShape(RoundedRectangle(cornerRadius: DSRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(action.titleKey))
        .accessibilityIdentifier("reader.quickTool.\(String(describing: action.id))")
    }
}
