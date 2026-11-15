import SwiftUI

struct ReaderQuickThemeSettingsDestination: View {
    let route: ReaderQuickPanelRoute
    let fontSize: Binding<CGFloat>
    let theme: Binding<ReaderTheme>
    let initialSection: ReaderSettingsInitialSection
    let readerWindowCanHoldSpread: Bool
    let capabilities: ReaderCapabilities
    let allowsUserSelectedReaderFont: Bool
    let usesPublicationFontDefault: Bool
    let isVerticalWritingMode: Bool
    let allowsVerticalWritingMode: Bool
    let hasParagraphReviews: Bool
    let onSelectRoute: (ReaderQuickPanelRoute) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            switch route {
            case .chapterTitleStyle:
                ChapterTitleStyleSettingsView(onOpenImporter: { onSelectRoute(.styleImporter(.chapterTitleStyle)) })
                    .toolbar(.visible, for: .navigationBar)
            case .settings, .display, .spacing, .headerFooter, .decoration, .commentBubble:
                ReaderSettingsView(
                    fontSize: fontSize,
                    theme: theme,
                    readerWindowCanHoldSpread: readerWindowCanHoldSpread,
                    capabilities: capabilities,
                    allowsUserSelectedReaderFont: allowsUserSelectedReaderFont,
                    usesPublicationFontDefault: usesPublicationFontDefault,
                    isVerticalWritingMode: isVerticalWritingMode,
                    allowsVerticalWritingMode: allowsVerticalWritingMode,
                    hasParagraphReviews: hasParagraphReviews,
                    onOpenTouchZoneEditor: { onSelectRoute(.touchZoneEditor) },
                    onOpenStyleImporter: { route in onSelectRoute(.styleImporter(route)) },
                    onOpenPaywall: { feature in onSelectRoute(.paywall(feature)) },
                    initialSection: initialSection,
                    usesParentNavigation: true
                )
                .toolbar(.visible, for: .navigationBar)
            case .touchZoneEditor, .tableOfContents, .bookmarks, .readingAloud, .autoRead, .paywall, .styleImporter:
                ContentUnavailableView {
                    UnavailableLabel(localized("閱讀設定"), systemImage: "book")
                } description: {
                    Text(localized("請從閱讀頁操作此功能。"))
                } actions: {
                    Button(localized("返回閱讀")) { dismiss() }
                }
            }
        }
    }
}
