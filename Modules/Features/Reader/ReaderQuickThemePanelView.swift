import SwiftUI
import UIKit

enum ReaderQuickPageTurnOption: String, CaseIterable, Identifiable, Hashable {
    case slide
    case cover
    case curl
    case ripple
    case fastFade
    case scroll

    var id: String { rawValue }

    var titleKey: String {
        switch self {
        case .slide: return "Slide"
        case .cover: return "覆蓋翻頁"
        case .curl: return "仿真翻書"
        case .ripple: return "波纹"
        case .fastFade: return "Fast Fade"
        case .scroll: return "Scroll"
        }
    }

    var iconName: String {
        switch self {
        case .slide: return "arrow.left.square"
        case .cover: return "square.on.square"
        case .curl: return "doc"
        case .ripple: return "water.waves"
        case .fastFade: return "bolt.square"
        case .scroll: return "doc.plaintext"
        }
    }
}

/// Which saved-background page the quick panel has pushed.
enum ReaderBackgroundEditorRoute: Hashable {
    case new
    case edit(UUID)

    var backgroundID: UUID? {
        if case .edit(let id) = self { return id }
        return nil
    }
}

struct ReaderQuickThemePanelView: View {
    @Binding var fontSize: CGFloat
    @Binding var readerTheme: ReaderTheme
    let pageTurnOption: ReaderQuickPageTurnOption
    let isVerticalWritingMode: Bool
    var usesPublicationFontDefault = false
    var readerWindowCanHoldSpread = false
    var readerCapabilities: ReaderCapabilities = .reflowableText
    var allowsUserSelectedReaderFont = false
    var allowsVerticalWritingMode = false
    var hasParagraphReviews = false
    let onSelectPageTurnOption: (ReaderQuickPageTurnOption) -> Void
    var onSelectRoute: ((ReaderQuickPanelRoute) -> Void)? = nil

    @Bindable private var settings = GlobalSettings.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var backgroundTileWidth = DSLayout.readerQuickPanelBackgroundTileWidth
    @ScaledMetric(relativeTo: .caption) private var backgroundTileHeight = DSLayout.readerQuickPanelReadingBackgroundTileHeight
    /// The saved-background page pushed in this panel's own navigation.
    @State private var backgroundEditor: ReaderBackgroundEditorRoute?
    @State var panelNavigation = ReaderQuickPanelNavigation()
    /// Measured height of the panel's own content, so the sheet is exactly as tall
    /// as what it holds. A fixed detent left a band of dead space under the last
    /// row whenever the content came out shorter than the constant.
    @State private var contentHeight = DSLayout.readerQuickPanelSheetHeight
    @State private var bottomSafeAreaInset: CGFloat = 0

    private let minFontSize = GlobalSettings.readerFontSizeRange.lowerBound
    private let maxFontSize = GlobalSettings.readerFontSizeRange.upperBound

    var body: some View {
        NavigationStack {
            // Scrolls rather than clips. The panel is no longer a fixed 508pt of
            // which 214 went to a background pager that only ever had one page, so
            // its height follows its content — and at the largest Dynamic Type
            // sizes that content is taller than any detent.
            ScrollView {
                VStack(alignment: .leading, spacing: DSSpacing.lg) {
                    brightnessSlider
                    (dynamicTypeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(spacing: DSSpacing.md))
                        : AnyLayout(HStackLayout(spacing: DSSpacing.md))) {
                        fontSizeStepper
                        fontChoiceMenu
                    }
                    readingBackgroundRow
                    pageTurnStyleRow
                        .padding(.bottom, DSSpacing.xs)
                    quickActionGrid
                }
                .padding(.horizontal, DSSpacing.xl)
                .padding(.top, DSSpacing.xl)
                .padding(.bottom, DSSpacing.xl)
                .background(
                    GeometryReader { proxy in
                        Color.clear.preference(
                            key: ReaderQuickPanelContentHeightKey.self,
                            value: proxy.size.height
                        )
                    }
                )
            }
            .softScrollEdges()
            .disabled(panelNavigation.isHandingOff)
            .onPreferenceChange(ReaderQuickPanelContentHeightKey.self) { height in
                guard let next = ReaderQuickPanelHeightPolicy.measurement(
                    height, replacing: contentHeight, isRoot: canMeasureRoot, minimum: 1
                ) else { return }
                contentHeight = next
            }
            .scrollBounceBehavior(.basedOnSize)
            // This panel supplies its own bottom padding. Let the scroll viewport
            // use the whole sheet instead of reserving another home-indicator band.
            .ignoresSafeArea(.container, edges: .bottom)
            .frame(maxWidth: DSLayout.readableCompactWidth, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .top)
            .background(DSColor.readerMenuBackground.ignoresSafeArea())
            // No title bar and no close button: the panel is a short sheet the
            // reader flicks away, and a navigation chrome on top of it ate height
            // the controls could use.
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(item: $panelNavigation.settingsDestination) { route in
                ReaderQuickThemeSettingsDestination(
                    route: route,
                    fontSize: $fontSize,
                    theme: $readerTheme,
                    initialSection: settingsSection(for: route),
                    readerWindowCanHoldSpread: readerWindowCanHoldSpread,
                    capabilities: readerCapabilities,
                    allowsUserSelectedReaderFont: allowsUserSelectedReaderFont,
                    usesPublicationFontDefault: usesPublicationFontDefault,
                    isVerticalWritingMode: isVerticalWritingMode,
                    allowsVerticalWritingMode: allowsVerticalWritingMode,
                    hasParagraphReviews: hasParagraphReviews,
                    onSelectRoute: { selectTool($0) }
                )
            }
            .navigationDestination(item: $backgroundEditor) { route in
                ReaderCustomBackgroundEditorView(
                    original: route.backgroundID.flatMap(settings.readerCustomBackground(id:)),
                    onSave: { saved in
                        // A new one is made to be worn; an edit leaves what is worn alone,
                        // and the reader repaints if it was this one.
                        if route == .new {
                            wear(saved)
                        }
                        backgroundEditor = nil
                    },
                    onDelete: { backgroundEditor = nil },
                    onRequestPaywall: { selectTool(.paywall($0)) }
                )
            }
        }
        .font(DSFont.readerMenu(.body))
        .foregroundStyle(DSColor.readerMenuText)
        .tint(DSColor.readerMenuText)
        .background(DSColor.readerMenuBackground)
        .environment(\.colorScheme, readerTheme.isDark ? .dark : .light)
        .presentationBackground {
            DSColor.readerMenuBackground
                .environment(\.colorScheme, readerTheme.isDark ? .dark : .light)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: ReaderQuickPanelSafeAreaBottomKey.self,
                    value: proxy.safeAreaInsets.bottom
                )
            }
        }
        .onPreferenceChange(ReaderQuickPanelSafeAreaBottomKey.self) { inset in
            guard let next = ReaderQuickPanelHeightPolicy.measurement(
                inset, replacing: bottomSafeAreaInset, isRoot: canMeasureRoot
            ) else { return }
            bottomSafeAreaInset = next
        }
        .onAppear { panelNavigation.appeared() }
        // The grabber is the only way out now that the title bar is gone, so the
        // sheet must stay draggable and the indicator visible.
        // A height detent excludes the bottom safe area, which UIKit adds back.
        // Our measurement already includes the panel's complete bottom padding.
        // The saved-background page is a whole form, not a row of controls: the panel
        // opens to full height while it is up, and goes back to fitting its content.
        .presentationDetents(backgroundEditor == nil && panelNavigation.settingsDestination == nil
            ? [.height(max(DSLayout.minimumTapTarget, contentHeight - bottomSafeAreaInset))]
            : [.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - 字級 + 翻頁

    /// 小 A ── 現在的字級 ── 大 A, in one capsule.
    ///
    /// The size used to be reported by a row of dots under this control that
    /// faded out after 1.8 seconds — it was gone by the time anyone looked for it,
    /// and its appearing and disappearing made the panel change height. The number
    /// now sits between the two buttons that change it and never moves.
    ///
    /// Both ends keep `.buttonRepeatBehavior(.enabled)`, so press-and-hold keeps
    /// stepping.
    ///
    /// VoiceOver reads the capsule as one adjustable 字體大小 valued at the size, which a
    /// swipe up or down moves a point. It was two buttons, 縮小字體 and 放大字體, with the
    /// number hidden: nothing read the size, before a press or after it.
    private var fontSizeStepper: some View {
        HStack(spacing: 0) {
            fontSizeStepButton(-1, textFont: DSFont.readerMenu(.body).weight(.semibold))

            Text("\(Int(fontSize))")
                .font(DSFont.readerMenu(.title3).weight(.medium).monospacedDigit())
                .foregroundStyle(DSColor.readerMenuText)
                .frame(minWidth: DSSpacing.xxl)

            fontSizeStepButton(1, textFont: DSFont.readerMenu(.title2).weight(.semibold))
        }
        .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
        .background(DSColor.neutralControlFill, in: Capsule())
        .shadow(color: DSColor.shadow, radius: 6, y: 1)
        .accessibilityStepper(
            localized(ReadingSettingsScopeItem.fontSize.titleKey),
            valueText: String(format: localized("ReaderOverlay.Format.Points"), Int(fontSize)),
            onIncrement: { adjustFontSize(1) },
            onDecrement: { adjustFontSize(-1) }
        )
    }

    private var fontChoiceMenu: some View {
        Menu {
            Button {
                settings.selectedReaderFontPostScript = nil
            } label: {
                Label(
                    localized(bookUsesPublicationFont ? "書籍預設字體" : "系統字體"),
                    systemImage: settings.selectedReaderFontPostScript == nil ? "checkmark" : "textformat"
                )
            }
            if !settings.userFonts.isEmpty {
                Divider()
                ForEach(settings.userFonts, id: \.id) { font in
                    Button {
                        settings.selectedReaderFontPostScript = font.postScriptName
                    } label: {
                        Label(
                            font.displayName,
                            systemImage: settings.selectedReaderFontPostScript == font.postScriptName ? "checkmark" : "textformat"
                        )
                    }
                }
            }
        } label: {
            HStack(spacing: DSSpacing.xs) {
                Text(selectedFontName)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DSFont.readerMenu(.footnote))
                    .accessibilityHidden(true)
            }
            .font(DSFont.readerMenu(.subheadline))
            .foregroundStyle(DSColor.readerMenuText)
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
            .padding(.horizontal, DSSpacing.md)
            .background(DSColor.neutralControlFill, in: Capsule())
            .overlay(Capsule().strokeBorder(DSColor.readerMenuSeparator, lineWidth: 1))
        }
        .accessibilityLabel(localized("字體"))
        .accessibilityValue(selectedFontName)
    }

    private var bookUsesPublicationFont: Bool { usesPublicationFontDefault }

    private var selectedFontName: String {
        if let selected = settings.selectedReaderFontPostScript,
           let font = settings.userFonts.first(where: { $0.postScriptName == selected }) {
            return font.displayName
        }
        return localized(bookUsesPublicationFont ? "書籍預設字體" : "系統字體")
    }

    private var pageTurnStyleRow: some View {
        VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(localized("翻頁"))
                .font(DSFont.readerMenu(.footnote))
                .foregroundStyle(DSColor.readerMenuSecondaryText)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.sm) {
                    ForEach(ReaderQuickPageTurnOption.allCases) { option in
                        ReaderQuickPageTurnChip(
                            option: option,
                            title: localized(pageTurnTitleKey(for: option)),
                            selected: pageTurnOption == option,
                            action: { onSelectPageTurnOption(option) }
                        )
                    }
                }
                .padding(.vertical, DSSpacing.xs)
            }
            .scrollClipDisabled()
        }
    }

    /// One half of the A / A stepper. `.buttonRepeatBehavior(.enabled)` makes
    /// press-and-hold keep stepping, matching Apple Books.
    private func fontSizeStepButton(_ delta: CGFloat, textFont: Font) -> some View {
        Button {
            adjustFontSize(delta)
        } label: {
            Text("A")
                .font(textFont)
                .foregroundStyle(DSColor.readerMenuText)
                .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuickPanelSegmentButtonStyle())
        .buttonRepeatBehavior(.enabled)
    }

    // MARK: - Brightness

    private var brightnessSlider: some View {
        HStack(spacing: DSSpacing.md) {
            Image(systemName: "sun.min.fill")
                .font(DSFont.readerMenu(.body))
                .accessibilityHidden(true)
            Slider(
                value: Binding(
                    get: { CGFloat(settings.readerBrightness) },
                    // `ReaderView` puts it on the screen the reader is on.
                    set: { value in
                        settings.followSystemBrightness = false
                        settings.readerBrightness = Double(value)
                    }
                ),
                in: 0.05...1.0
            )
            .tint(DSColor.readerMenuText)
            .accessibilityLabel(localized("亮度"))
            .accessibilityValue("\(Int((settings.readerBrightness * 100).rounded()))%")
            Image(systemName: "sun.max.fill")
                .font(DSFont.readerMenu(.body))
                .accessibilityHidden(true)
        }
        .frame(minHeight: DSLayout.minimumTapTarget)
        .foregroundStyle(DSColor.readerMenuText)
    }

    // MARK: - Reading backgrounds

    /// One scrolling row, not the 3×2 paged grid this replaced: the four built-in
    /// backgrounds, then every saved one, each by name, then 自定義 to make another.
    private var readingBackgroundRow: some View {
        let resolution = settings.readerBackgroundResolution(mode: settings.readerMode, wornTheme: readerTheme)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            Text(localized("閱讀背景"))
                .font(DSFont.readerMenu(.footnote))
                .foregroundStyle(DSColor.readerMenuSecondaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DSSpacing.md) {
                    ForEach(ReaderTheme.allCases, id: \.self) { background in
                        readingBackgroundButton(background, resolution: resolution)
                            .frame(width: backgroundTileWidth)
                    }
                    ForEach(settings.readerCustomBackgrounds) { background in
                        savedBackgroundButton(background, resolution: resolution)
                            .frame(width: backgroundTileWidth)
                    }
                    newBackgroundButton
                        .frame(width: backgroundTileWidth)
                }
                .padding(.vertical, DSSpacing.xs)
                .padding(.horizontal, 2)
            }
        }
    }

    /// Whether the reader's dark mode keeps to the device's appearance, where the two
    /// picks of 綁定閱讀主題 are worn. Off to start with; switching the reader against
    /// the device by hand turns it back off, since the two cannot both hold.
    private var followSystemAppearanceToggle: some View {
        Toggle(
            localized("跟隨裝置深淺色"),
            isOn: Binding(
                get: { settings.readerFollowSystemTheme },
                set: { applyFollowSystemAppearance($0) }
            )
        )
        .font(DSFont.readerMenu(.body))
        .foregroundStyle(DSColor.readerMenuText)
    }

    private func readingBackgroundButton(
        _ background: ReaderTheme,
        resolution: ReaderBackgroundResolution
    ) -> some View {
        // While the page is painted by 跟隨外觀主題 or by a saved background — a dark one
        // sits on 黑色 — no built-in one is the one in effect.
        let selected = !resolution.paintsWithAppearanceTheme
            && resolution.customBackground == nil
            && resolution.theme == background
        return Button {
            settings.appearanceBindReaderTheme = false
            settings.setReaderDarkMode(background.isDark, deviceIsDark: colorScheme == .dark)
            // 黑色 is the reader's dark mode; the saved background stays the light mode's
            // and comes back with it. A light built-in one takes its place there.
            if !background.isDark {
                settings.readerCustomBackgroundID = nil
            }
            background.persist()
            readerTheme = background
        } label: {
            ReaderQuickPanelBackgroundTile(
                fill: background.previewBackgroundColor,
                image: nil,
                title: background.localizedTitle,
                titleColor: background.previewTextColor,
                selected: selected
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(background.localizedTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func savedBackgroundButton(
        _ background: ReaderCustomBackground,
        resolution: ReaderBackgroundResolution
    ) -> some View {
        let selected = resolution.customBackground?.id == background.id
        return Button {
            wear(background)
        } label: {
            ReaderQuickPanelBackgroundTile(
                fill: Color(uiColor: AppearanceThemePreset.hex(background.colorHex)),
                image: background.imageFileName.flatMap(ReaderCustomBackgroundStorageManager.shared.thumbnail(fileName:)),
                title: background.name,
                titleColor: Color(uiColor: AppearanceThemePreset.hex(background.resolvedTextColorHex)),
                selected: selected
            )
        }
        .buttonStyle(.plain)
        // Plain buttons only, as on the theme grid: the delete confirmation is a submenu
        // because a modal raised from a context-menu action can be dropped on iOS 17
        // (Technotes/iOS17MenuModalPresentation.md).
        .contextMenu {
            Button {
                backgroundEditor = .edit(background.id)
            } label: {
                Label(localized("編輯"), systemImage: "slider.horizontal.3")
            }
            Menu {
                Button(role: .destructive) {
                    settings.deleteReaderCustomBackground(id: background.id)
                } label: {
                    Label(String(format: localized("刪除「%@」"), background.name), systemImage: "trash")
                }
            } label: {
                Label(localized("刪除"), systemImage: "trash")
            }
        }
        .accessibilityLabel(background.name)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityAction(named: localized("編輯")) {
            backgroundEditor = .edit(background.id)
        }
    }

    private var newBackgroundButton: some View {
        Button {
            backgroundEditor = .new
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                    .fill(DSColor.neutralControlFill)
                VStack(spacing: DSSpacing.xs) {
                    Image(systemName: "plus")
                        .font(DSFont.readerMenu(.title2).weight(.semibold))
                        .accessibilityHidden(true)
                    Text(localized("自定義"))
                        .font(DSFont.readerMenu(.subheadline))
                }
                .foregroundStyle(DSColor.readerMenuText)
            }
            .frame(minHeight: backgroundTileHeight)
            .overlay(
                RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                    .stroke(DSColor.readerMenuSeparator, lineWidth: 1)
            )
            .shadow(color: DSColor.shadow, radius: 6, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(localized("自定義"))
    }

    // MARK: - 快捷動作

    /// The space the background pager gave back.
    ///
    /// 自動閱讀 comes first — that is where every reader that ships this feature
    /// puts it, and until now this app had no entry for it at all: the controller
    /// and its panel were both complete, but nothing ever set `showAutoReadPanel`.
    private var quickActionGrid: some View {
        let actions = [
            ReaderQuickThemeAction(id: .display, titleKey: "顯示設定", systemImage: "textformat.size"),
            ReaderQuickThemeAction(id: .spacing, titleKey: "間距", systemImage: "line.3.horizontal"),
            ReaderQuickThemeAction(id: .readingAloud, titleKey: "朗讀", systemImage: "speaker.wave.2"),
            ReaderQuickThemeAction(id: .autoRead, titleKey: "自動閱讀", systemImage: "play.fill"),
            ReaderQuickThemeAction(id: .commentBubble, titleKey: "氣泡設定", systemImage: "bubble.left.and.bubble.right"),
            ReaderQuickThemeAction(id: .chapterTitleStyle, titleKey: "章節標題樣式", systemImage: "textformat"),
            ReaderQuickThemeAction(id: .headerFooter, titleKey: "頁首頁尾", systemImage: "rectangle.bottomthird.inset.filled"),
            ReaderQuickThemeAction(id: .settings, titleKey: "更多設定", systemImage: "ellipsis")
        ]
        return LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 1 : (dynamicTypeSize >= .xxxLarge ? 2 : 4)), spacing: DSSpacing.sm) {
            ForEach(actions) { action in
                ReaderQuickThemeActionTile(action: action) { selectTool(action.id) }
            }
        }
    }

    // MARK: - Actions

    private var canMeasureRoot: Bool {
        !panelNavigation.isHandingOff && backgroundEditor == nil && panelNavigation.settingsDestination == nil
    }

    private func selectTool(_ route: ReaderQuickPanelRoute) {
        panelNavigation.select(route) { selected in
            // Record the request before dismissing. The reader's onDismiss is
            // the only place allowed to present the next sheet on iOS 17.
            if let onSelectRoute {
                onSelectRoute(selected)
            } else {
                dismiss()
            }
        }
    }

    private func settingsSection(for route: ReaderQuickPanelRoute) -> ReaderSettingsInitialSection {
        switch route {
        case .display: .text
        case .spacing: .spacing
        case .headerFooter: .headerFooter
        case .decoration, .commentBubble: .decoration
        case .chapterTitleStyle: .chapterTitleStyle
        default: .all
        }
    }

    private func adjustFontSize(_ delta: CGFloat) {
        fontSize = GlobalSettings.clampedReaderFontSize((fontSize + delta).rounded())
    }

    /// Turning it on hands the reader's mode to the device; turning it off keeps whatever
    /// is on screen. The reader puts the background of the mode in place.
    private func applyFollowSystemAppearance(_ isOn: Bool) {
        settings.setReaderFollowsDevice(isOn, deviceIsDark: colorScheme == .dark)
    }

    /// A saved background, worn as the reader's own pick: the light mode's background.
    private func wear(_ background: ReaderCustomBackground) {
        readerTheme = settings.wearReaderCustomBackground(
            background,
            over: readerTheme,
            deviceIsDark: colorScheme == .dark
        )
    }

    private func pageTurnTitleKey(for option: ReaderQuickPageTurnOption) -> String {
        option == .scroll && isVerticalWritingMode ? "右往左" : option.titleKey
    }


}

/// One background's tile: its colour or picture, its name, and the selection ring.
/// Built-in and saved ones alike carry the name — only the saved ones did at first,
/// which left the built-in half of the row unnamed (2026-09-29).
///
/// The tile owns its size. Its picture used to be framed by `maxWidth: .infinity`
/// alone, and a flexible frame never shrinks a child wider than the proposal: a
/// scaled-to-fill picture whose aspect is wider than the tile's (74×82, so any
/// landscape picture and even a square one) came back wider than the tile, the
/// whole `ZStack` grew to match, and the row's `.frame(width:)` only centred the
/// result. The star badge then sat over the next tile (feedback #12, iPad).
/// Internal, not private, so a test can measure it.
struct ReaderQuickPanelBackgroundTile: View {
    let fill: Color
    let image: UIImage?
    let title: String
    let titleColor: Color
    let selected: Bool

    @ScaledMetric(relativeTo: .caption) private var width = DSLayout.readerQuickPanelBackgroundTileWidth
    @ScaledMetric(relativeTo: .caption) private var height = DSLayout.readerQuickPanelReadingBackgroundTileHeight

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .fill(fill)

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: width, height: height)
                    .clipped()
                    .accessibilityHidden(true)
                    .allowsHitTesting(false)
            }

            Text(title)
                .font(DSFont.readerMenu(.caption))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .foregroundStyle(DSColor.readerMenuText)
                .padding(.horizontal, DSSpacing.xs)
                .padding(.vertical, DSSpacing.xxs)
                .background(DSColor.readerMenuBackground, in: RoundedRectangle(cornerRadius: DSRadius.sm))
                .padding(.horizontal, DSSpacing.sm)
                .padding(.bottom, DSSpacing.sm)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .accessibilityHidden(true)

            if selected {
                Image(systemName: "asterisk")
                    .font(DSFont.readerMenu(.subheadline).weight(.semibold))
                    .foregroundStyle(titleColor.opacity(0.6))
                    .padding(.top, DSSpacing.sm)
                    .padding(.trailing, DSSpacing.md)
                    .accessibilityHidden(true)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DSRadius.xxl, style: .continuous)
                .stroke(
                    selected ? DSColor.readerMenuText : DSColor.readerMenuSeparator,
                    lineWidth: selected ? 3 : 1
                )
        )
        .shadow(color: DSColor.shadow, radius: 6, y: 1)
    }
}

/// Full-width quick-panel action button: darkens and gently compresses while
/// pressed, then springs back on release.
private struct QuickPanelActionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Filled with the accent while auto-read is running, so the panel says what
    /// state the reader is in without a second row of text.
    var isProminent = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DSFont.readerMenu(.headline))
            .foregroundStyle(isProminent ? AnyShapeStyle(DSColor.textOnAccent) : AnyShapeStyle(DSColor.readerMenuText))
            .frame(maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelControlHeight)
            .background(
                isProminent
                    ? DSColor.accent.opacity(configuration.isPressed ? 0.8 : 1)
                    : (configuration.isPressed ? DSColor.neutralControlPressedFill : DSColor.neutralControlFill),
                in: Capsule()
            )
            .shadow(color: DSColor.shadow, radius: 6, y: 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .animation(DSAnimation.fast, value: configuration.isPressed)
    }
}

/// Segment sharing one capsule with its neighbor in the A / A control. While
/// pressed, an inset darker capsule appears behind the content; on release it
/// shrinks and fades back out, echoing the Apple Books quick panel.
private struct QuickPanelSegmentButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Capsule()
                    .fill(DSColor.neutralControlPressedFill)
                    .padding(DSSpacing.xs)
                    .opacity(configuration.isPressed ? 1 : 0)
                    .scaleEffect(configuration.isPressed || reduceMotion ? 1 : 0.85)
            )
            .animation(
                configuration.isPressed ? DSAnimation.fast : DSAnimation.standard,
                value: configuration.isPressed
            )
    }
}

#Preview() {
    ReaderQuickThemePanelView(
        fontSize: .constant(18),
        readerTheme: .constant(.white),
        pageTurnOption: .curl,
        isVerticalWritingMode: false,
        onSelectPageTurnOption: { _ in },
        onSelectRoute: { _ in }
    )
}

/// A selected tile wearing a 16:9 picture between two plain ones: the badge must stay
/// inside its own tile and the neighbours must not be overlapped (feedback #12).
#Preview("Background tile, landscape picture") {
    let landscape = UIGraphicsImageRenderer(size: CGSize(width: 320, height: 180)).image { context in
        // Drawn away from any view, where `UIColor(DSColor.accent)` is iOS 17's light blue
        // in dark too; `tintColor` resolves to the system accent here (see `DSUIColor`).
        UIColor.tintColor.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 320, height: 180))
        DSUIColor.textPrimary.setFill()
        context.fill(CGRect(x: 0, y: 120, width: 320, height: 60))
    }
    return HStack(spacing: DSSpacing.md) {
        ReaderQuickPanelBackgroundTile(
            fill: DSColor.neutralControlFill, image: nil, title: "Plain",
            titleColor: DSColor.readerMenuText, selected: false
        )
        ReaderQuickPanelBackgroundTile(
            fill: DSColor.neutralControlFill, image: landscape, title: "Landscape",
            titleColor: DSColor.readerMenuText, selected: true
        )
        ReaderQuickPanelBackgroundTile(
            fill: DSColor.neutralControlFill, image: nil, title: "Plain",
            titleColor: DSColor.readerMenuText, selected: false
        )
    }
    .padding(DSSpacing.xl)
}
