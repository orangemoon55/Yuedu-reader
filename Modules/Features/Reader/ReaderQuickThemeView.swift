import SwiftUI

struct ReaderQuickThemeAction: Identifiable {
    let id: ReaderQuickPanelRoute
    let titleKey: String
    let systemImage: String

    static let rows: [[ReaderQuickThemeAction]] = [
        [.init(id: .display, titleKey: "顯示設定", systemImage: "textformat.size"),
         .init(id: .spacing, titleKey: "間距", systemImage: "line.3.horizontal")],
        [.init(id: .readingAloud, titleKey: "朗讀", systemImage: "speaker.wave.2"),
         .init(id: .autoRead, titleKey: "自動閱讀", systemImage: "play")],
        [.init(id: .commentBubble, titleKey: "氣泡設定", systemImage: "bubble.left.and.bubble.right"),
         .init(id: .chapterTitleStyle, titleKey: "章節標題樣式", systemImage: "textformat")],
        [.init(id: .headerFooter, titleKey: "頁首頁尾", systemImage: "rectangle.bottomthird.inset.filled"),
         .init(id: .settings, titleKey: "更多設定", systemImage: "slider.horizontal.3")]
    ]
}

struct ReaderQuickThemeActionTile: View {
    let action: ReaderQuickThemeAction
    let perform: () -> Void

    var body: some View {
        Button(action: perform) {
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: action.systemImage)
                    .font(DSFont.readerMenu(.subheadline))
                    .foregroundStyle(DSColor.readerMenuSecondaryText)
                    .frame(width: DSLayout.readerQuickPanelToolIconWidth)
                    .accessibilityHidden(true)
                Text(localized(action.titleKey))
                    .font(DSFont.readerMenu(.subheadline))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DSSpacing.xs)
                Image(systemName: "chevron.right")
                    .font(DSFont.readerMenu(.caption2))
                    .foregroundStyle(DSColor.readerMenuSecondaryText)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DSColor.readerMenuText)
            .padding(.horizontal, DSSpacing.md)
            .padding(.vertical, DSSpacing.sm)
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelToolRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized(action.titleKey))
        .accessibilityIdentifier("reader.quickTool.\(String(describing: action.id))")
    }
}
