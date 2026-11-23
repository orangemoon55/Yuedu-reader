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
                    typographyControls
                    readingBackgroundRow
                    pageTurnStyleRow
                    quickActionGrid
                }
                .padding(.horizontal, DSSpacing.lg)
                .padding(.top, DSSpacing.sm)
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
            // Compact in-content heading; pushed settings retain their own native bar.
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
        // Both the close button and the native swipe-down gesture dismiss this panel.
        // A height detent excludes the bottom safe area, which UIKit adds back.
        // Our measurement already includes the panel's complete bottom padding.
        // The saved-background page is a whole form, not a row of controls: the panel
        // opens to full height while it is up, and goes back to fitting its content.
        .presentationDetents(backgroundEditor == nil && panelNavigation.settingsDestination == nil
            ? [.height(max(DSLayout.minimumTapTarget, contentHeight - bottomSafeAreaInset))]
            : [.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Typography and light

    private var typographyControls: some View {
        VStack(spacing: DSSpacing.sm) {
            (dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: DSSpacing.sm))
                : AnyLayout(HStackLayout(spacing: DSSpacing.md))) {
                fontSizeStepper
                fontChoiceMenu
            }
        }
    }

    /// One adjustable control, retaining the current number and 44pt end buttons.
    private var fontSizeStepper: some View {
        HStack(spacing: 0) {
            fontSizeStepButton(-1, textFont: DSFont.readerMenu(.subheadline))
            Text("\(Int(fontSize))")
                .font(DSFont.readerMenu(.title3).weight(.medium).monospacedDigit())
                .foregroundStyle(DSColor.readerMenuText)
                .frame(minWidth: DSLayout.minimumTapTarget)
            fontSizeStepButton(1, textFont: DSFont.readerMenu(.title3))
        }
        .frame(minWidth: DSLayout.minimumTapTarget * 3,
               maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
        .background(DSColor.readerMenuControlFill, in: RoundedRectangle(cornerRadius: DSRadius.lg))
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
            HStack(spacing: DSSpacing.sm) {
                Image(systemName: "textformat")
                    .font(DSFont.readerMenu(.subheadline))
                    .foregroundStyle(DSColor.readerMenuSecondaryText)
                    .accessibilityHidden(true)
                Text(selectedFontName)
                    .font(DSFont.readerMenu(.subheadline))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: DSSpacing.xs)
                Image(systemName: "chevron.up.chevron.down")
                    .font(DSFont.readerMenu(.caption))
                    .foregroundStyle(DSColor.readerMenuSecondaryText)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(DSColor.readerMenuText)
            .padding(.horizontal, DSSpacing.md)
            .frame(minWidth: DSLayout.readerQuickPanelTopMenuWidth,
                   maxWidth: .infinity, minHeight: DSLayout.readerQuickPanelTopControlHeight)
            .background(DSColor.readerMenuControlFill, in: RoundedRectangle(cornerRadius: DSRadius.lg))
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
            sectionHeading("翻頁")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.xs),
                                     count: dynamicTypeSize.isAccessibilitySize ? 1 : (dynamicTypeSize >= .xxxLarge ? 2 : 3)), spacing: DSSpacing.xs) {
                ForEach(ReaderQuickPageTurnOption.allCases) { option in
                    ReaderQuickPageTurnChip(
                        option: option, title: localized(pageTurnTitleKey(for: option)),
                        selected: pageTurnOption == option,
                        action: { onSelectPageTurnOption(option) }
                    )
                }
            }
            .padding(DSSpacing.xs)
            .background(DSColor.readerMenuControlFill, in: RoundedRectangle(cornerRadius: DSRadius.lg))
        }
    }

    private func sectionHeading(_ key: String) -> some View {
        Text(localized(key))
            .font(DSFont.readerMenu(.footnote).weight(.medium))
            .foregroundStyle(DSColor.readerMenuSecondaryText)
            .accessibilityAddTraits(.isHeader)
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
        .buttonStyle(.plain)
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
            .tint(DSColor.readerMenuAccent)
            .accessibilityLabel(localized("亮度"))
            .accessibilityValue("\(Int((settings.readerBrightness * 100).rounded()))%")
            Image(systemName: "sun.max.fill")
                .font(DSFont.readerMenu(.body))
                .accessibilityHidden(true)
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(DSFont.readerMenu(.footnote))
                    .foregroundStyle(DSColor.readerMenuSecondaryText)
                    .frame(width: DSLayout.minimumTapTarget, height: DSLayout.minimumTapTarget)
                    .contentShape(Circle())
                    .accessibilityHidden(true)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(localized("關閉"))
            .accessibilityIdentifier("reader.quickPanel.close")
        }
        .frame(minHeight: DSLayout.minimumTapTarget)
        .foregroundStyle(DSColor.readerMenuText)
    }

    // MARK: - Reading backgrounds

    /// The four defaults are all visible. Extra user backgrounds have a separate
    /// rail; their arbitrary number never squeezes or clips the built-in names.
    private var readingBackgroundRow: some View {
        let resolution = settings.readerBackgroundResolution(mode: settings.readerMode, wornTheme: readerTheme)
        return VStack(alignment: .leading, spacing: DSSpacing.sm) {
            HStack {
                sectionHeading("閱讀背景")
                Spacer()
                Button { backgroundEditor = .new } label: {
                    Label(localized("自定義"), systemImage: "plus")
                        .font(DSFont.readerMenu(.footnote))
                        .labelStyle(.titleAndIcon)
                        .foregroundStyle(DSColor.readerMenuAccent)
                        .frame(minHeight: DSLayout.minimumTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reader.quickPanel.addBackground")
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: DSSpacing.md),
                                     count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: DSSpacing.md) {
                ForEach(ReaderTheme.allCases, id: \.self) { background in
                    readingBackgroundButton(background, resolution: resolution)
                }
            }
            if !settings.readerCustomBackgrounds.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(alignment: .top, spacing: DSSpacing.md) {
                        ForEach(settings.readerCustomBackgrounds) { background in
                            savedBackgroundButton(background, resolution: resolution)
                                .frame(width: DSLayout.readerQuickPanelBackgroundTileWidth)
                        }
                    }
                    .padding(.vertical, DSSpacing.xs)
                }
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
                selected: selected,
                captionSpacing: DSSpacing.sm
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(background.localizedTitle)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("reader.quickPanel.background.\(background.epubJSName)")
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

    // MARK: - Tools

    private var quickActionGrid: some View {
        VStack(spacing: 0) {
            ForEach(ReaderQuickThemeAction.rows.indices, id: \.self) { index in
                if index > 0 { Divider().padding(.horizontal, DSSpacing.md) }
                let row = ReaderQuickThemeAction.rows[index]
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(spacing: 0) {
                        ForEach(row) { action in
                            ReaderQuickThemeActionTile(action: action) { selectTool(action.id) }
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(row) { action in
                            ReaderQuickThemeActionTile(action: action) { selectTool(action.id) }
                        }
                    }
                }
            }
        }
        .background(DSColor.readerMenuControlFill, in: RoundedRectangle(cornerRadius: DSRadius.lg))
        .accessibilityIdentifier("reader.quickPanel.tools")
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

/// A colour sample above its name; text never receives a white badge over it.
/// Built-in samples stretch evenly across the panel; saved pictures stay clipped.
struct ReaderQuickPanelBackgroundTile: View {
    let fill: Color
    let image: UIImage?
    let title: String
    let titleColor: Color
    let selected: Bool
    var captionSpacing = DSSpacing.xs
    @ScaledMetric(relativeTo: .caption) private var sampleHeight = DSLayout.readerQuickPanelBackgroundSampleHeight

    var body: some View {
        VStack(spacing: captionSpacing) {
            // Size the fill first. The preview can want more room than the fixed
            // sample, so make it an overlay and clip to the sample, not the preview.
            fill
                .frame(height: sampleHeight)
                .overlay {
                    if let image {
                        GeometryReader { geometry in
                            Image(uiImage: image).resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text(localized("閱讀"))
                                .font(DSFont.readerMenu(.subheadline))
                            ForEach(0..<3) { line in
                                Capsule().fill(titleColor.opacity(line == 2 ? 0.20 : 0.32))
                                    .frame(maxWidth: line == 2 ? DSLayout.readerQuickPanelBackgroundLastLineWidth : .infinity)
                                    .frame(height: DSLayout.readerQuickPanelBackgroundLineHeight)
                            }
                        }
                        .padding(DSSpacing.sm)
                        .foregroundStyle(titleColor)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: DSRadius.lg))
                .overlay {
                    RoundedRectangle(cornerRadius: DSRadius.lg)
                        .strokeBorder(selected ? DSColor.readerMenuAccent : DSColor.readerMenuSeparator.opacity(0.3),
                                      lineWidth: selected ? 2 : 0.5)
                }
                .overlay(alignment: .topTrailing) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(DSColor.readerMenuOnSelection, DSColor.readerMenuAccent)
                            .font(DSFont.readerMenu(.caption))
                            .padding(DSSpacing.xs)
                    }
                }
                .accessibilityHidden(true)
            Text(title)
                .font(DSFont.readerMenu(.caption))
                .foregroundStyle(selected ? DSColor.readerMenuAccent : DSColor.readerMenuText)
                .multilineTextAlignment(.center)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .contentShape(Rectangle())
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
