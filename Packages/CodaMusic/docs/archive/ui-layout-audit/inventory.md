# 全界面间距与字号：逐项源码清单

日期：2026-10-29。入口总览：[审计报告](../ui-spacing-typography-audit.md)。

本表是静态候选清单：包括所有编译分支、共享组件、加载/空态和调试界面；不等于每项都在当前设备可见。单位为 pt（比例、行数、压缩系数除外）。系统默认间距、原生 Form/List/菜单和继承字体无法仅凭源码得到最终数值。尺寸约束与字号分列；Image 的 font 表示符号尺寸，不能直接当正文。多层 padding 需结合父级计算，frame 不是间距。最近声明仅为导航提示。

扫描文件数：257；有候选项文件数：73；候选记录数：2002。

## 文件索引

| 文件 | 候选记录 |
| --- | ---: |
| [Sources/Kumone/Core/PlatformCompatibility.swift](#platformcompatibility) | 8 |
| [Sources/Kumone/DesignSystem/ArtworkPalette.swift](#artworkpalette) | 3 |
| [Sources/Kumone/DesignSystem/ButtonStyles.swift](#buttonstyles) | 9 |
| [Sources/Kumone/DesignSystem/Cards.swift](#cards) | 49 |
| [Sources/Kumone/DesignSystem/Components.swift](#components) | 64 |
| [Sources/Kumone/DesignSystem/RubyText.swift](#rubytext) | 22 |
| [Sources/Kumone/DesignSystem/StorageCapacityBar.swift](#storagecapacitybar) | 13 |
| [Sources/Kumone/DesignSystem/Theme.swift](#theme) | 37 |
| [Sources/Kumone/Features/Detail/AlbumDetailView.swift](#albumdetailview) | 8 |
| [Sources/Kumone/Features/Detail/ArtistDetailView.swift](#artistdetailview) | 14 |
| [Sources/Kumone/Features/Detail/MeloXArtworkBackground.swift](#meloxartworkbackground) | 7 |
| [Sources/Kumone/Features/Detail/MeloXPlaylistDetailHero.swift](#meloxplaylistdetailhero) | 57 |
| [Sources/Kumone/Features/Detail/PlaylistDetailView.swift](#playlistdetailview) | 34 |
| [Sources/Kumone/Features/Detail/PlaylistSearchField.swift](#playlistsearchfield) | 2 |
| [Sources/Kumone/Features/Explore/ExploreView.swift](#exploreview) | 28 |
| [Sources/Kumone/Features/GlassTabBar.swift](#glasstabbar) | 15 |
| [Sources/Kumone/Features/Home/HomeBrowseView.swift](#homebrowseview) | 7 |
| [Sources/Kumone/Features/Home/HomeCoverShelf.swift](#homecovershelf) | 3 |
| [Sources/Kumone/Features/Home/HomeDiscoverySections.swift](#homediscoverysections) | 15 |
| [Sources/Kumone/Features/Home/HomeRecommendationPageView.swift](#homerecommendationpageview) | 5 |
| [Sources/Kumone/Features/Home/HomeSongRecommendationLists.swift](#homesongrecommendationlists) | 16 |
| [Sources/Kumone/Features/Home/HomeView.swift](#homeview) | 111 |
| [Sources/Kumone/Features/IOSMainWindow.swift](#iosmainwindow) | 70 |
| [Sources/Kumone/Features/MainWindow.swift](#mainwindow) | 39 |
| [Sources/Kumone/Features/Navigation.swift](#navigation) | 26 |
| [Sources/Kumone/Features/Pages/AutoMixSettingsSection.swift](#automixsettingssection) | 6 |
| [Sources/Kumone/Features/Pages/CollectionsView.swift](#collectionsview) | 12 |
| [Sources/Kumone/Features/Pages/DailySongsView.swift](#dailysongsview) | 4 |
| [Sources/Kumone/Features/Pages/DownloadedMusicView.swift](#downloadedmusicview) | 55 |
| [Sources/Kumone/Features/Pages/FMView.swift](#fmview) | 35 |
| [Sources/Kumone/Features/Pages/IOSUpdater.swift](#iosupdater) | 28 |
| [Sources/Kumone/Features/Pages/LibraryPages.swift](#librarypages) | 28 |
| [Sources/Kumone/Features/Pages/LoginSheet.swift](#loginsheet) | 59 |
| [Sources/Kumone/Features/Pages/SearchView.swift](#searchview) | 37 |
| [Sources/Kumone/Features/Pages/SettingsView.swift](#settingsview) | 10 |
| [Sources/Kumone/Features/Pages/ShortcutSettingsView.swift](#shortcutsettingsview) | 11 |
| [Sources/Kumone/Features/Pages/StemModelsSettingsSection.swift](#stemmodelssettingssection) | 5 |
| [Sources/Kumone/Features/Pages/StorageSpaceView.swift](#storagespaceview) | 27 |
| [Sources/Kumone/Features/Player/AppleMusicLyricsColumn.swift](#applemusiclyricscolumn) | 25 |
| [Sources/Kumone/Features/Player/AutoMixDebugPanel.swift](#automixdebugpanel) | 60 |
| [Sources/Kumone/Features/Player/DesktopLyrics.swift](#desktoplyrics) | 7 |
| [Sources/Kumone/Features/Player/IOSPlaybackQueueView.swift](#iosplaybackqueueview) | 43 |
| [Sources/Kumone/Features/Player/IOSSystemVolumeSlider.swift](#iossystemvolumeslider) | 3 |
| [Sources/Kumone/Features/Player/KaraokeGlyphRenderer.swift](#karaokeglyphrenderer) | 13 |
| [Sources/Kumone/Features/Player/KaraokeLyricLine.swift](#karaokelyricline) | 6 |
| [Sources/Kumone/Features/Player/LyricText.swift](#lyrictext) | 5 |
| [Sources/Kumone/Features/Player/NowPlayingAddToPlaylistColumn.swift](#nowplayingaddtoplaylistcolumn) | 35 |
| [Sources/Kumone/Features/Player/NowPlayingFluidBackground.swift](#nowplayingfluidbackground) | 4 |
| [Sources/Kumone/Features/Player/NowPlayingPresentation.swift](#nowplayingpresentation) | 16 |
| [Sources/Kumone/Features/Player/NowPlayingQualityControl.swift](#nowplayingqualitycontrol) | 7 |
| [Sources/Kumone/Features/Player/NowPlayingTrackDestinationLinks.swift](#nowplayingtrackdestinationlinks) | 4 |
| [Sources/Kumone/Features/Player/NowPlayingView.swift](#nowplayingview) | 159 |
| [Sources/Kumone/Features/Player/Panels.swift](#panels) | 57 |
| [Sources/Kumone/Features/Player/PlayerBar.swift](#playerbar) | 67 |
| [Sources/Kumone/Features/Player/RoutePickerButton.swift](#routepickerbutton) | 53 |
| [Sources/Kumone/Features/Player/SongCommentsColumn.swift](#songcommentscolumn) | 54 |
| [Sources/Kumone/Features/Shared/AppNavigationBarBackground.swift](#appnavigationbarbackground) | 3 |
| [Sources/Kumone/Features/Shared/DownloadProgressIcon.swift](#downloadprogressicon) | 11 |
| [Sources/Kumone/Features/Shared/MainColumnGeometry.swift](#maincolumngeometry) | 8 |
| [Sources/Kumone/Features/Shared/MainWindowAmbientBackground.swift](#mainwindowambientbackground) | 9 |
| [Sources/Kumone/Features/Shared/PanelRefresh.swift](#panelrefresh) | 4 |
| [Sources/Kumone/Features/Shared/PlaylistArtwork.swift](#playlistartwork) | 1 |
| [Sources/Kumone/Features/Shared/ProfileDetailLayout.swift](#profiledetaillayout) | 24 |
| [Sources/Kumone/Features/Shared/TrackDownloadButton.swift](#trackdownloadbutton) | 2 |
| [Sources/Kumone/Features/Shared/TrackList.swift](#tracklist) | 81 |
| [Sources/Kumone/Features/Shared/TrackListScrollView.swift](#tracklistscrollview) | 126 |
| [Sources/Kumone/Features/Shared/TrackTable.swift](#tracktable) | 16 |
| [Sources/Kumone/Features/SidebarView.swift](#sidebarview) | 80 |
| [Sources/Kumone/Features/Sync/PlaybackHandoffBanner.swift](#playbackhandoffbanner) | 15 |
| [Sources/Kumone/Features/Sync/PlaybackHandoffList.swift](#playbackhandofflist) | 13 |
| [Sources/Kumone/Features/Sync/SyncSettingsSection.swift](#syncsettingssection) | 5 |
| [Sources/Kumone/Features/Sync/SyncedLoginButtons.swift](#syncedloginbuttons) | 2 |
| [Sources/Kumone/KumoneApp.swift](#kumoneapp) | 5 |

## PlatformCompatibility

源码：`Sources/Kumone/Core/PlatformCompatibility.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [20](../../../Sources/Coda/Core/PlatformCompatibility.swift#L20) | 自定义组件/原生构造尺寸参数 | `NSImage(size: NSSize(width: diameter, height: diameter))` | #if os(macOS) |
| [20](../../../Sources/Coda/Core/PlatformCompatibility.swift#L20) | 自定义组件/原生构造尺寸参数 | `NSSize(width: diameter, height: diameter)` | #if os(macOS) |
| [22](../../../Sources/Coda/Core/PlatformCompatibility.swift#L22) | 自定义组件/原生构造尺寸参数 | `NSRect(x: 0, y: 0, width: diameter, height: diameter)` | #if os(macOS) |
| [39](../../../Sources/Coda/Core/PlatformCompatibility.swift#L39) | 自定义组件/原生构造尺寸参数 | `NSRect(origin: .zero, size: size)` | #if os(macOS) |
| [78](../../../Sources/Coda/Core/PlatformCompatibility.swift#L78) | 自定义组件/原生构造尺寸参数 | `CGSize(width: diameter, height: diameter)` | #if os(macOS) / #elseif os(iOS) |
| [78](../../../Sources/Coda/Core/PlatformCompatibility.swift#L78) | 尺寸/字体/间距声明或原生字体 | `let size = CGSize(width: diameter, height: diameter)` | #if os(macOS) / #elseif os(iOS) |
| [79](../../../Sources/Coda/Core/PlatformCompatibility.swift#L79) | 自定义组件/原生构造尺寸参数 | `UIGraphicsImageRenderer(size: size)` | #if os(macOS) / #elseif os(iOS) |
| [81](../../../Sources/Coda/Core/PlatformCompatibility.swift#L81) | 自定义组件/原生构造尺寸参数 | `CGRect(origin: .zero, size: size)` | #if os(macOS) / #elseif os(iOS) |

## ArtworkPalette

源码：`Sources/Kumone/DesignSystem/ArtworkPalette.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [32](../../../Sources/Coda/DesignSystem/ArtworkPalette.swift#L32) | 尺寸/字体/间距声明或原生字体 | `let size = 10` | 共享/运行时分支见源码 |
| [40](../../../Sources/Coda/DesignSystem/ArtworkPalette.swift#L40) | 自定义组件/原生构造尺寸参数 | `CGContext( data: &rawData, width: size, height: size, bitsPerComponent: bitsPerComponent, bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: bitmapInfo )` | 共享/运行时分支见源码 |
| [50](../../../Sources/Coda/DesignSystem/ArtworkPalette.swift#L50) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: size, height: size)` | 共享/运行时分支见源码 |

## ButtonStyles

源码：`Sources/Kumone/DesignSystem/ButtonStyles.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [6](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L6) | 尺寸/字体/间距声明或原生字体 | `var hoverScale: CGFloat = 1.02` | 共享/运行时分支见源码 |
| [7](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L7) | 尺寸/字体/间距声明或原生字体 | `var pressScale: CGFloat = 0.98` | 共享/运行时分支见源码 |
| [67](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L67) | 尺寸/字体/间距声明或原生字体 | `var pressScale: CGFloat = 0.9` | 共享/运行时分支见源码 |
| [88](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L88) | 字号/字体 | `.font(Theme.Typography.secondary.weight(isSelected ? .semibold : .medium))` | #if os(macOS) |
| [89](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L89) | 内边距 | `.padding(.horizontal, Theme.Spacing.control)` | #if os(macOS) |
| [90](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L90) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | #if os(macOS) |
| [105](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L105) | 字号/字体 | `.font(Theme.Typography.secondary.weight(isSelected ? .semibold : .medium))` | #if os(macOS) / #else |
| [106](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L106) | 内边距 | `.padding(.horizontal, Theme.Spacing.control)` | #if os(macOS) / #else |
| [107](../../../Sources/Coda/DesignSystem/ButtonStyles.swift#L107) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | #if os(macOS) / #else |

## Cards

源码：`Sources/Kumone/DesignSystem/Cards.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [10](../../../Sources/Coda/DesignSystem/Cards.swift#L10) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = Theme.Layout.cardSize` | 共享/运行时分支见源码 |
| [18](../../../Sources/Coda/DesignSystem/Cards.swift#L18) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [19](../../../Sources/Coda/DesignSystem/Cards.swift#L19) | 容器布局/默认间距 | `ZStack(alignment: .bottomLeading)` | 共享/运行时分支见源码 |
| [21](../../../Sources/Coda/DesignSystem/Cards.swift#L21) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [29](../../../Sources/Coda/DesignSystem/Cards.swift#L29) | 内边距 | `.padding(Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [30](../../../Sources/Coda/DesignSystem/Cards.swift#L30) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)` | 共享/运行时分支见源码 |
| [34](../../../Sources/Coda/DesignSystem/Cards.swift#L34) | 内边距 | `.padding(Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [37](../../../Sources/Coda/DesignSystem/Cards.swift#L37) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [39](../../../Sources/Coda/DesignSystem/Cards.swift#L39) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [41](../../../Sources/Coda/DesignSystem/Cards.swift#L41) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [47](../../../Sources/Coda/DesignSystem/Cards.swift#L47) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/DesignSystem/Cards.swift#L53) | 尺寸约束 | `.frame(width: size, alignment: .leading)` | 共享/运行时分支见源码 |
| [65](../../../Sources/Coda/DesignSystem/Cards.swift#L65) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 128` | 共享/运行时分支见源码 |
| [70](../../../Sources/Coda/DesignSystem/Cards.swift#L70) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [72](../../../Sources/Coda/DesignSystem/Cards.swift#L72) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [76](../../../Sources/Coda/DesignSystem/Cards.swift#L76) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [80](../../../Sources/Coda/DesignSystem/Cards.swift#L80) | 尺寸约束 | `.frame(width: size + 12)` | 共享/运行时分支见源码 |
| [94](../../../Sources/Coda/DesignSystem/Cards.swift#L94) | 尺寸/字体/间距声明或原生字体 | `var spacing: CGFloat = Theme.Spacing.component` | 共享/运行时分支见源码 |
| [106](../../../Sources/Coda/DesignSystem/Cards.swift#L106) | 尺寸/字体/间距声明或原生字体 | `var rowHeight: CGFloat?` | 共享/运行时分支见源码 |
| [108](../../../Sources/Coda/DesignSystem/Cards.swift#L108) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var textScale: CGFloat = 1` | 共享/运行时分支见源码 |
| [111](../../../Sources/Coda/DesignSystem/Cards.swift#L111) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [113](../../../Sources/Coda/DesignSystem/Cards.swift#L113) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [121](../../../Sources/Coda/DesignSystem/Cards.swift#L121) | 尺寸/字体/间距声明或原生字体 | `private var edgeInset: some View { Color.clear.frame(width: max(0, Theme.Layout.contentInset - spacing), height: 1) }` | 共享/运行时分支见源码 |
| [122](../../../Sources/Coda/DesignSystem/Cards.swift#L122) | 尺寸约束 | `.frame(width: max(0, Theme.Layout.contentInset - spacing), height: 1)` | 共享/运行时分支见源码 |
| [127](../../../Sources/Coda/DesignSystem/Cards.swift#L127) | 尺寸/字体/间距声明或原生字体 | `if let rowHeight { LazyHStack(alignment: .top, spacing: spacing) { edgeInset content() edgeInset } // Scale the text allowance without enlarging the artwork itself. .frame(height: rowHeight + 96 * max(0, textScale - 1)) }` | 共享/运行时分支见源码 |
| [128](../../../Sources/Coda/DesignSystem/Cards.swift#L128) | 容器布局/默认间距 | `LazyHStack(alignment: .top, spacing: spacing)` | 共享/运行时分支见源码 |
| [134](../../../Sources/Coda/DesignSystem/Cards.swift#L134) | 尺寸约束 | `.frame(height: rowHeight + 96 * max(0, textScale - 1))` | 共享/运行时分支见源码 |
| [136](../../../Sources/Coda/DesignSystem/Cards.swift#L136) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: spacing)` | 共享/运行时分支见源码 |
| [151](../../../Sources/Coda/DesignSystem/Cards.swift#L151) | 尺寸/字体/间距声明或原生字体 | `var flexibleCardWidth: Bool { get { self[FlexibleCardWidthKey.self] } set { self[FlexibleCardWidthKey.self] = newValue } }` | 共享/运行时分支见源码 |
| [158](../../../Sources/Coda/DesignSystem/Cards.swift#L158) | 尺寸/字体/间距声明或原生字体 | `var minWidth: CGFloat = Theme.Layout.cardSize` | 共享/运行时分支见源码 |
| [162](../../../Sources/Coda/DesignSystem/Cards.swift#L162) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var horizontalSizeClass` | #if os(iOS) |
| [170](../../../Sources/Coda/DesignSystem/Cards.swift#L170) | 容器布局/默认间距 | `GridItem(.flexible(), spacing: Theme.Spacing.component, alignment: .top)` | 共享/运行时分支见源码 |
| [171](../../../Sources/Coda/DesignSystem/Cards.swift#L171) | 容器布局/默认间距 | `GridItem(.flexible(), spacing: Theme.Spacing.component, alignment: .top)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/DesignSystem/Cards.swift#L172) | 容器布局/默认间距 | `GridItem(.adaptive(minimum: minWidth, maximum: minWidth + 40), spacing: Theme.Spacing.component, alignment: .top)` | 共享/运行时分支见源码 |
| [177](../../../Sources/Coda/DesignSystem/Cards.swift#L177) | 容器布局/默认间距 | `LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [191](../../../Sources/Coda/DesignSystem/Cards.swift#L191) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [193](../../../Sources/Coda/DesignSystem/Cards.swift#L193) | 字号/字体 | `.font(.system(size: 40))` | 共享/运行时分支见源码 |
| [195](../../../Sources/Coda/DesignSystem/Cards.swift#L195) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [196](../../../Sources/Coda/DesignSystem/Cards.swift#L196) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [198](../../../Sources/Coda/DesignSystem/Cards.swift#L198) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [205](../../../Sources/Coda/DesignSystem/Cards.swift#L205) | 内边距 | `.padding(.top, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [207](../../../Sources/Coda/DesignSystem/Cards.swift#L207) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [208](../../../Sources/Coda/DesignSystem/Cards.swift#L208) | 内边距 | `.padding(Theme.Layout.emptyStateInset)` | 共享/运行时分支见源码 |
| [218](../../../Sources/Coda/DesignSystem/Cards.swift#L218) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [220](../../../Sources/Coda/DesignSystem/Cards.swift#L220) | 字号/字体 | `.font(.system(size: 40))` | 共享/运行时分支见源码 |
| [222](../../../Sources/Coda/DesignSystem/Cards.swift#L222) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [224](../../../Sources/Coda/DesignSystem/Cards.swift#L224) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [227](../../../Sources/Coda/DesignSystem/Cards.swift#L227) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [232](../../../Sources/Coda/DesignSystem/Cards.swift#L232) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |

## Components

源码：`Sources/Kumone/DesignSystem/Components.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [11](../../../Sources/Coda/DesignSystem/Components.swift#L11) | 字号/字体 | `.font(.system(size: 13, weight: .semibold))` | 共享/运行时分支见源码 |
| [34](../../../Sources/Coda/DesignSystem/Components.swift#L34) | 尺寸约束 | `.frame(width: geo.size.width * 0.6)` | 共享/运行时分支见源码 |
| [44](../../../Sources/Coda/DesignSystem/Components.swift#L44) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = Theme.Layout.cardSize` | 共享/运行时分支见源码 |
| [47](../../../Sources/Coda/DesignSystem/Components.swift#L47) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [48](../../../Sources/Coda/DesignSystem/Components.swift#L48) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [49](../../../Sources/Coda/DesignSystem/Components.swift#L49) | 尺寸约束 | `.frame(width: size * 0.8, height: 12)` | 共享/运行时分支见源码 |
| [50](../../../Sources/Coda/DesignSystem/Components.swift#L50) | 尺寸约束 | `.frame(width: size * 0.5, height: 10)` | 共享/运行时分支见源码 |
| [57](../../../Sources/Coda/DesignSystem/Components.swift#L57) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [58](../../../Sources/Coda/DesignSystem/Components.swift#L58) | 尺寸约束 | `.frame(width: 120, height: 20)` | 共享/运行时分支见源码 |
| [60](../../../Sources/Coda/DesignSystem/Components.swift#L60) | 尺寸/字体/间距声明或原生字体 | `let cardSize = Theme.Layout.fittedShelfCardSize(availableWidth: geometry.size.width, leadingInset: 0)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/DesignSystem/Components.swift#L62) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [64](../../../Sources/Coda/DesignSystem/Components.swift#L64) | 自定义组件/原生构造尺寸参数 | `SkeletonCardView(size: cardSize)` | 共享/运行时分支见源码 |
| [69](../../../Sources/Coda/DesignSystem/Components.swift#L69) | 尺寸约束 | `.frame(height: Theme.Layout.coverShelfHeight)` | 共享/运行时分支见源码 |
| [127](../../../Sources/Coda/DesignSystem/Components.swift#L127) | 容器布局/默认间距 | `HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [130](../../../Sources/Coda/DesignSystem/Components.swift#L130) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [132](../../../Sources/Coda/DesignSystem/Components.swift#L132) | 字号/字体 | `.font(Theme.Typography.sectionTitle.weight(.semibold))` | 共享/运行时分支见源码 |
| [144](../../../Sources/Coda/DesignSystem/Components.swift#L144) | 字号/字体 | `.font(Theme.Typography.sectionTitle.weight(.semibold))` | 共享/运行时分支见源码 |
| [148](../../../Sources/Coda/DesignSystem/Components.swift#L148) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [151](../../../Sources/Coda/DesignSystem/Components.swift#L151) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [162](../../../Sources/Coda/DesignSystem/Components.swift#L162) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [164](../../../Sources/Coda/DesignSystem/Components.swift#L164) | 字号/字体 | `.font(.system(size: 8, weight: .bold))` | 共享/运行时分支见源码 |
| [166](../../../Sources/Coda/DesignSystem/Components.swift#L166) | 字号/字体 | `.font(Theme.Typography.badge.weight(.semibold))` | 共享/运行时分支见源码 |
| [169](../../../Sources/Coda/DesignSystem/Components.swift#L169) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/DesignSystem/Components.swift#L170) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [179](../../../Sources/Coda/DesignSystem/Components.swift#L179) | 字号/字体 | `.font(Theme.Typography.badge.weight(.bold))` | 共享/运行时分支见源码 |
| [181](../../../Sources/Coda/DesignSystem/Components.swift#L181) | 内边距 | `.padding(.horizontal, Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [182](../../../Sources/Coda/DesignSystem/Components.swift#L182) | 内边距 | `.padding(.vertical, Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [195](../../../Sources/Coda/DesignSystem/Components.swift#L195) | 字号/字体 | `.font(Theme.Typography.badge.weight(.semibold))` | 共享/运行时分支见源码 |
| [197](../../../Sources/Coda/DesignSystem/Components.swift#L197) | 内边距 | `.padding(.horizontal, Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [198](../../../Sources/Coda/DesignSystem/Components.swift#L198) | 内边距 | `.padding(.vertical, Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [210](../../../Sources/Coda/DesignSystem/Components.swift#L210) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 40` | 共享/运行时分支见源码 |
| [217](../../../Sources/Coda/DesignSystem/Components.swift#L217) | 字号/字体 | `.font(.system(size: size * 0.38, weight: .bold))` | #if os(macOS) |
| [219](../../../Sources/Coda/DesignSystem/Components.swift#L219) | 尺寸约束 | `.frame(width: size, height: size)` | #if os(macOS) |
| [247](../../../Sources/Coda/DesignSystem/Components.swift#L247) | 尺寸/字体/间距声明或原生字体 | `var fontSize: CGFloat = 13` | 共享/运行时分支见源码 |
| [248](../../../Sources/Coda/DesignSystem/Components.swift#L248) | 尺寸/字体/间距声明或原生字体 | `var fontWeight: PlatformFont.Weight = .medium` | 共享/运行时分支见源码 |
| [251](../../../Sources/Coda/DesignSystem/Components.swift#L251) | 自定义组件/原生构造尺寸参数 | `Representable(text: text, fontSize: fontSize, weight: fontWeight)` | 共享/运行时分支见源码 |
| [257](../../../Sources/Coda/DesignSystem/Components.swift#L257) | 尺寸/字体/间距声明或原生字体 | `private static let gap: CGFloat = 32` | 共享/运行时分支见源码 |
| [270](../../../Sources/Coda/DesignSystem/Components.swift#L270) | 尺寸/字体/间距声明或原生字体 | `private var fontSize: CGFloat` | 共享/运行时分支见源码 |
| [272](../../../Sources/Coda/DesignSystem/Components.swift#L272) | 尺寸/字体/间距声明或原生字体 | `private var textWidth: CGFloat = 0` | 共享/运行时分支见源码 |
| [286](../../../Sources/Coda/DesignSystem/Components.swift#L286) | 尺寸/字体/间距声明或原生字体 | `self.fontSize = fontSize` | 共享/运行时分支见源码 |
| [312](../../../Sources/Coda/DesignSystem/Components.swift#L312) | 尺寸/字体/间距声明或原生字体 | `self.fontSize = fontSize` | 共享/运行时分支见源码 |
| [318](../../../Sources/Coda/DesignSystem/Components.swift#L318) | 尺寸/字体/间距声明或原生字体 | `private var font: PlatformFont { .systemFont(ofSize: fontSize, weight: weight) }` | 共享/运行时分支见源码 |
| [329](../../../Sources/Coda/DesignSystem/Components.swift#L329) | 尺寸/字体/间距声明或原生字体 | `let font = self.font` | 共享/运行时分支见源码 |
| [334](../../../Sources/Coda/DesignSystem/Components.swift#L334) | 尺寸/字体/间距声明或原生字体 | `textLayer.fontSize = fontSize` | 共享/运行时分支见源码 |
| [356](../../../Sources/Coda/DesignSystem/Components.swift#L356) | 尺寸/字体/间距声明或原生字体 | `let scale = window?.backingScaleFactor ?? 2` | #if os(macOS) |
| [376](../../../Sources/Coda/DesignSystem/Components.swift#L376) | 尺寸/字体/间距声明或原生字体 | `let scale = window?.screen.scale ?? 2` | #if os(macOS) / #else |
| [389](../../../Sources/Coda/DesignSystem/Components.swift#L389) | 尺寸/字体/间距声明或原生字体 | `let lineHeight = ceil(font.ascender - font.descender)` | 共享/运行时分支见源码 |
| [391](../../../Sources/Coda/DesignSystem/Components.swift#L391) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: y, width: textWidth, height: lineHeight)` | 共享/运行时分支见源码 |
| [392](../../../Sources/Coda/DesignSystem/Components.swift#L392) | 自定义组件/原生构造尺寸参数 | `CGRect(x: textWidth + Self.gap, y: y, width: textWidth, height: lineHeight)` | 共享/运行时分支见源码 |
| [395](../../../Sources/Coda/DesignSystem/Components.swift#L395) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: textWidth * 2 + Self.gap, height: bounds.height)` | 共享/运行时分支见源码 |
| [437](../../../Sources/Coda/DesignSystem/Components.swift#L437) | 尺寸/字体/间距声明或原生字体 | `let fontSize: CGFloat` | 共享/运行时分支见源码 |
| [442](../../../Sources/Coda/DesignSystem/Components.swift#L442) | 自定义组件/原生构造尺寸参数 | `MarqueeTextView(text: text, fontSize: fontSize, weight: weight)` | #if os(macOS) |
| [449](../../../Sources/Coda/DesignSystem/Components.swift#L449) | 自定义组件/原生构造尺寸参数 | `MarqueeTextView(text: text, fontSize: fontSize, weight: weight)` | #if os(macOS) / #else |
| [462](../../../Sources/Coda/DesignSystem/Components.swift#L462) | 尺寸/字体/间距声明或原生字体 | `static let trackHeight: CGFloat = 5` | 共享/运行时分支见源码 |
| [488](../../../Sources/Coda/DesignSystem/Components.swift#L488) | 容器布局/默认间距 | `ZStack(alignment: horizontal ? .leading : .bottom)` | 共享/运行时分支见源码 |
| [491](../../../Sources/Coda/DesignSystem/Components.swift#L491) | 尺寸约束 | `.frame(width: horizontal ? length : thickness, height: horizontal ? thickness : length)` | 共享/运行时分支见源码 |
| [495](../../../Sources/Coda/DesignSystem/Components.swift#L495) | 尺寸约束 | `.frame(width: horizontal ? filledLength : thickness, height: horizontal ? thickness : filledLength)` | 共享/运行时分支见源码 |
| [500](../../../Sources/Coda/DesignSystem/Components.swift#L500) | 尺寸约束 | `.frame(width: thumbDiameter, height: thumbDiameter)` | 共享/运行时分支见源码 |
| [508](../../../Sources/Coda/DesignSystem/Components.swift#L508) | 尺寸约束 | `.frame(width: geometry.size.width, height: geometry.size.height)` | 共享/运行时分支见源码 |
| [541](../../../Sources/Coda/DesignSystem/Components.swift#L541) | 自定义组件/原生构造尺寸参数 | `PlayerSliderMouseInput( onChanged: { point in guard let fraction = fraction(at: point, size: geometry.size) else { return } acceptedGesture = true isDragging = true onChanged(fraction) }, onEnded: { point in if acceptedGesture, let fraction = fraction(at: point, size: geometry.size) { onEnded(fraction) } acceptedGesture = false isDragging = false }, onCancelled: { if acceptedGesture { onCancelled() } acceptedGesture = false isDragging = false } )` | #if os(macOS) |
| [567](../../../Sources/Coda/DesignSystem/Components.swift#L567) | 自定义组件/原生构造尺寸参数 | `CGRect(origin: .zero, size: geometry.size)` | #if os(macOS) / #else |
| [670](../../../Sources/Coda/DesignSystem/Components.swift#L670) | 尺寸/字体/间距声明或原生字体 | `let size: CGFloat` | 共享/运行时分支见源码 |
| [683](../../../Sources/Coda/DesignSystem/Components.swift#L683) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [700](../../../Sources/Coda/DesignSystem/Components.swift#L700) | 尺寸约束 | `.frame(width: 24, height: 24)` | 共享/运行时分支见源码 |

## RubyText

源码：`Sources/Kumone/DesignSystem/RubyText.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [7](../../../Sources/Coda/DesignSystem/RubyText.swift#L7) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat` | 共享/运行时分支见源码 |
| [11](../../../Sources/Coda/DesignSystem/RubyText.swift#L11) | 尺寸/字体/间距声明或原生字体 | `var rubyScale: CGFloat` | 共享/运行时分支见源码 |
| [22](../../../Sources/Coda/DesignSystem/RubyText.swift#L22) | 尺寸/字体/间距声明或原生字体 | `let baseFont = font(style.size, style.weight, style.rounded)` | 共享/运行时分支见源码 |
| [23](../../../Sources/Coda/DesignSystem/RubyText.swift#L23) | 尺寸/字体/间距声明或原生字体 | `let rubyFont = font(style.size * style.rubyScale, .medium, style.rounded)` | 共享/运行时分支见源码 |
| [38](../../../Sources/Coda/DesignSystem/RubyText.swift#L38) | 尺寸/字体/间距声明或原生字体 | `let output = NSMutableAttributedString()` | 共享/运行时分支见源码 |
| [76](../../../Sources/Coda/DesignSystem/RubyText.swift#L76) | 尺寸/字体/间距声明或原生字体 | `output.append(NSAttributedString(string: segment.text, attributes: attributes))` | 共享/运行时分支见源码 |
| [87](../../../Sources/Coda/DesignSystem/RubyText.swift#L87) | 尺寸/字体/间距声明或原生字体 | `let piece = NSMutableAttributedString(string: text, attributes: attributes)` | 共享/运行时分支见源码 |
| [104](../../../Sources/Coda/DesignSystem/RubyText.swift#L104) | 尺寸/字体/间距声明或原生字体 | `let base = PlatformFont.systemFont(ofSize: size, weight: weight)` | 共享/运行时分支见源码 |
| [107](../../../Sources/Coda/DesignSystem/RubyText.swift#L107) | 自定义组件/原生构造尺寸参数 | `PlatformFont(descriptor: descriptor, size: size)` | #if os(macOS) |
| [109](../../../Sources/Coda/DesignSystem/RubyText.swift#L109) | 自定义组件/原生构造尺寸参数 | `PlatformFont(descriptor: descriptor, size: size)` | #if os(macOS) / #else |
| [117](../../../Sources/Coda/DesignSystem/RubyText.swift#L117) | 自定义组件/原生构造尺寸参数 | `CTFramesetterSuggestFrameSizeWithConstraints( framesetter, CFRangeMake(0, 0), nil, CGSize(width: width, height: .greatestFiniteMagnitude), nil )` | 共享/运行时分支见源码 |
| [119](../../../Sources/Coda/DesignSystem/RubyText.swift#L119) | 自定义组件/原生构造尺寸参数 | `CGSize(width: width, height: .greatestFiniteMagnitude)` | 共享/运行时分支见源码 |
| [131](../../../Sources/Coda/DesignSystem/RubyText.swift#L131) | 自定义组件/原生构造尺寸参数 | `CTFramesetterSuggestFrameSizeWithConstraints( framesetter, CFRangeMake(0, 0), nil, CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil )` | 共享/运行时分支见源码 |
| [133](../../../Sources/Coda/DesignSystem/RubyText.swift#L133) | 自定义组件/原生构造尺寸参数 | `CGSize(width: rect.width, height: .greatestFiniteMagnitude)` | 共享/运行时分支见源码 |
| [135](../../../Sources/Coda/DesignSystem/RubyText.swift#L135) | 尺寸/字体/间距声明或原生字体 | `let height = max(rect.height, ceil(fitted.height))` | 共享/运行时分支见源码 |
| [136](../../../Sources/Coda/DesignSystem/RubyText.swift#L136) | 自定义组件/原生构造尺寸参数 | `CGRect(x: rect.minX, y: rect.maxY - height, width: rect.width, height: height)` | 共享/运行时分支见源码 |
| [152](../../../Sources/Coda/DesignSystem/RubyText.swift#L152) | 尺寸/字体/间距声明或原生字体 | `private var size: CGFloat` | 共享/运行时分支见源码 |
| [156](../../../Sources/Coda/DesignSystem/RubyText.swift#L156) | 尺寸/字体/间距声明或原生字体 | `private var rubyScale: CGFloat` | 共享/运行时分支见源码 |
| [197](../../../Sources/Coda/DesignSystem/RubyText.swift#L197) | 自定义组件/原生构造尺寸参数 | `Style( size: size, weight: weight.platform, color: PlatformColor(color), rubyColor: PlatformColor(rubyColor), rubyScale: rubyScale, alignment: alignment, rounded: rounded )` | 共享/运行时分支见源码 |
| [218](../../../Sources/Coda/DesignSystem/RubyText.swift#L218) | 自定义组件/原生构造尺寸参数 | `CGRect(origin: .zero, size: canvasSize)` | 共享/运行时分支见源码 |
| [247](../../../Sources/Coda/DesignSystem/RubyText.swift#L247) | 自定义组件/原生构造尺寸参数 | `CGSize(width: ceil(fitted.width), height: ceil(fitted.height))` | 共享/运行时分支见源码 |
| [250](../../../Sources/Coda/DesignSystem/RubyText.swift#L250) | 自定义组件/原生构造尺寸参数 | `CGSize(width: proposed, height: ceil(fitted.height))` | 共享/运行时分支见源码 |

## StorageCapacityBar

源码：`Sources/Kumone/DesignSystem/StorageCapacityBar.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [8](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L8) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var height: CGFloat = 18` | 共享/运行时分支见源码 |
| [11](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L11) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [13](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L13) | 自定义组件/原生构造尺寸参数 | `SegmentedStorageProgressStyle(fractions: capacity.fractions(appBytes: appBytes), height: height)` | 共享/运行时分支见源码 |
| [17](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L17) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [18](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L18) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [20](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L20) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [32](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L32) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [33](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L33) | 尺寸约束 | `.frame(width: 7, height: 7)` | 共享/运行时分支见源码 |
| [43](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L43) | 尺寸/字体/间距声明或原生字体 | `let height: CGFloat` | 共享/运行时分支见源码 |
| [48](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L48) | 容器布局/默认间距 | `HStack(spacing: 0)` | 共享/运行时分支见源码 |
| [51](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L51) | 尺寸约束 | `.frame(width: geometry.size.width * fractions[index])` | 共享/运行时分支见源码 |
| [54](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L54) | 尺寸约束 | `.frame(width: min(1, geometry.size.width * fractions[index] / 2))` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/DesignSystem/StorageCapacityBar.swift#L62) | 尺寸约束 | `.frame(height: height)` | 共享/运行时分支见源码 |

## Theme

源码：`Sources/Kumone/DesignSystem/Theme.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [95](../../../Sources/Coda/DesignSystem/Theme.swift#L95) | 尺寸/字体/间距声明或原生字体 | `static var contentInset: CGFloat { #if os(iOS) UIDevice.current.userInterfaceIdiom == .phone ? Spacing.phonePage : Spacing.page #else Spacing.page #endif }` | 共享/运行时分支见源码 |
| [102](../../../Sources/Coda/DesignSystem/Theme.swift#L102) | 尺寸/字体/间距声明或原生字体 | `static let dividedColumnSpacing: CGFloat = 32` | 共享/运行时分支见源码 |
| [103](../../../Sources/Coda/DesignSystem/Theme.swift#L103) | 尺寸/字体/间距声明或原生字体 | `static let emptyStateInset: CGFloat = 40` | 共享/运行时分支见源码 |
| [104](../../../Sources/Coda/DesignSystem/Theme.swift#L104) | 尺寸/字体/间距声明或原生字体 | `static let controlHeight: CGFloat = 44` | 共享/运行时分支见源码 |
| [105](../../../Sources/Coda/DesignSystem/Theme.swift#L105) | 尺寸/字体/间距声明或原生字体 | `static let detailActionHeight: CGFloat = 56` | 共享/运行时分支见源码 |
| [106](../../../Sources/Coda/DesignSystem/Theme.swift#L106) | 尺寸/字体/间距声明或原生字体 | `static let trackRowHeight: CGFloat = 64` | 共享/运行时分支见源码 |
| [107](../../../Sources/Coda/DesignSystem/Theme.swift#L107) | 尺寸/字体/间距声明或原生字体 | `static let trackArtworkSize: CGFloat = 48` | 共享/运行时分支见源码 |
| [108](../../../Sources/Coda/DesignSystem/Theme.swift#L108) | 尺寸/字体/间距声明或原生字体 | `static let trackRowHorizontalInset = Spacing.control` | 共享/运行时分支见源码 |
| [110](../../../Sources/Coda/DesignSystem/Theme.swift#L110) | 尺寸/字体/间距声明或原生字体 | `static var trackListInset: CGFloat { contentInset - trackRowHorizontalInset }` | 共享/运行时分支见源码 |
| [111](../../../Sources/Coda/DesignSystem/Theme.swift#L111) | 尺寸/字体/间距声明或原生字体 | `static let cardSize: CGFloat = 160` | 共享/运行时分支见源码 |
| [113](../../../Sources/Coda/DesignSystem/Theme.swift#L113) | 尺寸/字体/间距声明或原生字体 | `let usableWidth = availableWidth - leadingInset - spacing` | 共享/运行时分支见源码 |
| [120](../../../Sources/Coda/DesignSystem/Theme.swift#L120) | 尺寸/字体/间距声明或原生字体 | `static let coverShelfHeight: CGFloat = cardSize + 96` | 共享/运行时分支见源码 |
| [122](../../../Sources/Coda/DesignSystem/Theme.swift#L122) | 尺寸/字体/间距声明或原生字体 | `static let artistShelfHeight: CGFloat = 196` | 共享/运行时分支见源码 |
| [123](../../../Sources/Coda/DesignSystem/Theme.swift#L123) | 尺寸/字体/间距声明或原生字体 | `static let sidebarWidth: CGFloat = 332` | 共享/运行时分支见源码 |
| [124](../../../Sources/Coda/DesignSystem/Theme.swift#L124) | 尺寸/字体/间距声明或原生字体 | `static let playerBarHeight: CGFloat = 64` | 共享/运行时分支见源码 |
| [125](../../../Sources/Coda/DesignSystem/Theme.swift#L125) | 尺寸/字体/间距声明或原生字体 | `static let playerBarHorizontalMargin: CGFloat = 16` | 共享/运行时分支见源码 |
| [126](../../../Sources/Coda/DesignSystem/Theme.swift#L126) | 尺寸/字体/间距声明或原生字体 | `static let playerBarProgressMinimumWidth: CGFloat = 720` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/DesignSystem/Theme.swift#L129) | 尺寸/字体/间距声明或原生字体 | `static let playerBarBottomMargin: CGFloat = 10` | 共享/运行时分支见源码 |
| [131](../../../Sources/Coda/DesignSystem/Theme.swift#L131) | 尺寸/字体/间距声明或原生字体 | `static var playerChromeClearance: CGFloat { playerBarHeight + playerBarBottomMargin }` | 共享/运行时分支见源码 |
| [133](../../../Sources/Coda/DesignSystem/Theme.swift#L133) | 尺寸/字体/间距声明或原生字体 | `static let scrollBreathingMargin: CGFloat = 8` | 共享/运行时分支见源码 |
| [137](../../../Sources/Coda/DesignSystem/Theme.swift#L137) | 尺寸/字体/间距声明或原生字体 | `static let iPadPlayerBarHeight = playerBarHeight` | #if os(iOS) |
| [138](../../../Sources/Coda/DesignSystem/Theme.swift#L138) | 尺寸/字体/间距声明或原生字体 | `static let iPadPlayerBarHorizontalMargin = playerBarHorizontalMargin` | #if os(iOS) |
| [139](../../../Sources/Coda/DesignSystem/Theme.swift#L139) | 尺寸/字体/间距声明或原生字体 | `static let iPadPlayerBarBottomMargin = playerBarBottomMargin` | #if os(iOS) |
| [141](../../../Sources/Coda/DesignSystem/Theme.swift#L141) | 尺寸/字体/间距声明或原生字体 | `static var iPadPlayerChromeClearance: CGFloat { iPadPlayerBarHeight + iPadPlayerBarBottomMargin }` | #if os(iOS) |
| [147](../../../Sources/Coda/DesignSystem/Theme.swift#L147) | 尺寸/字体/间距声明或原生字体 | `static let tabBarHeight: CGFloat = 64` | #if os(iOS) |
| [149](../../../Sources/Coda/DesignSystem/Theme.swift#L149) | 尺寸/字体/间距声明或原生字体 | `static let miniPlayerHeight: CGFloat = 52` | #if os(iOS) |
| [151](../../../Sources/Coda/DesignSystem/Theme.swift#L151) | 尺寸/字体/间距声明或原生字体 | `static let barSpacing: CGFloat = 8` | #if os(iOS) |
| [153](../../../Sources/Coda/DesignSystem/Theme.swift#L153) | 尺寸/字体/间距声明或原生字体 | `static let bottomMargin: CGFloat = 6` | #if os(iOS) |
| [155](../../../Sources/Coda/DesignSystem/Theme.swift#L155) | 尺寸/字体/间距声明或原生字体 | `static let extraPadding: CGFloat = 12` | #if os(iOS) |
| [158](../../../Sources/Coda/DesignSystem/Theme.swift#L158) | 尺寸/字体/间距声明或原生字体 | `static var tabBarClearance: CGFloat { tabBarHeight + bottomMargin + extraPadding }` | #if os(iOS) |
| [163](../../../Sources/Coda/DesignSystem/Theme.swift#L163) | 尺寸/字体/间距声明或原生字体 | `static var fullChromeClearance: CGFloat { miniPlayerHeight + barSpacing + tabBarHeight + bottomMargin + extraPadding }` | #if os(iOS) |
| [168](../../../Sources/Coda/DesignSystem/Theme.swift#L168) | 尺寸/字体/间距声明或原生字体 | `static let minWindowWidth: CGFloat = 1280` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/DesignSystem/Theme.swift#L170) | 尺寸/字体/间距声明或原生字体 | `static let splitDividerWidth: CGFloat = 8` | 共享/运行时分支见源码 |
| [178](../../../Sources/Coda/DesignSystem/Theme.swift#L178) | 尺寸/字体/间距声明或原生字体 | `static var minWindowWidthSidebarCollapsed: CGFloat { minWindowWidth - sidebarWidth - splitDividerWidth }` | 共享/运行时分支见源码 |
| [181](../../../Sources/Coda/DesignSystem/Theme.swift#L181) | 尺寸/字体/间距声明或原生字体 | `static let minWindowHeight: CGFloat = 640` | 共享/运行时分支见源码 |
| [182](../../../Sources/Coda/DesignSystem/Theme.swift#L182) | 尺寸/字体/间距声明或原生字体 | `static let defaultWindowWidth: CGFloat = 1200` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/DesignSystem/Theme.swift#L183) | 尺寸/字体/间距声明或原生字体 | `static let defaultWindowHeight: CGFloat = 780` | 共享/运行时分支见源码 |

## AlbumDetailView

源码：`Sources/Kumone/Features/Detail/AlbumDetailView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [22](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L22) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var horizontalSizeClass` | 共享/运行时分支见源码 |
| [66](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L66) | 安全区插入 | `.safeAreaInset(edge: .top)` | 共享/运行时分支见源码 |
| [84](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L84) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [94](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L94) | 尺寸约束 | `.frame(minHeight: 400)` | 共享/运行时分支见源码 |
| [103](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L103) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [106](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L106) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [107](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L107) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [209](../../../Sources/Coda/Features/Detail/AlbumDetailView.swift#L209) | 内边距 | `.padding(Theme.Spacing.phonePage)` | 共享/运行时分支见源码 |

## ArtistDetailView

源码：`Sources/Kumone/Features/Detail/ArtistDetailView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [46](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L46) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [51](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L51) | 尺寸约束 | `.frame(width: 100, height: 22)` | 共享/运行时分支见源码 |
| [52](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L52) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [58](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L58) | 尺寸约束 | `.frame(minHeight: 400)` | 共享/运行时分支见源码 |
| [68](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L68) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [77](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L77) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [86](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L86) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [106](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L106) | 安全区插入 | `.safeAreaInset(edge: .top)` | 共享/运行时分支见源码 |
| [184](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L184) | 自定义组件/原生构造尺寸参数 | `MeloXPlaylistPrimaryActions( isSaved: isFollowed, canSave: account.isLoggedIn && !isLoadingFollow, canPlay: !hotSongs.isEmpty, isSaving: isUpdatingFollow, onToggleSaved: toggleFollow, onPlayAll: { player.play(tracks: hotSongs, source: .artist(artistID), context: .artist(id: artistID, name: artist.name)) }, saveAccessibilityLabel: isFollowed ? String(localized: "取消关注歌手") : String(localized: "关注歌手"), saveAccessibilityIdentifier: "artistFollow", horizontalPadding: horizontalPadding )` | 共享/运行时分支见源码 |
| [272](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L272) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [292](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L292) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [304](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L304) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 44)` | 共享/运行时分支见源码 |
| [307](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L307) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [310](../../../Sources/Coda/Features/Detail/ArtistDetailView.swift#L310) | 内边距 | `.padding(.top, Theme.Spacing.component)` | 共享/运行时分支见源码 |

## MeloXArtworkBackground

源码：`Sources/Kumone/Features/Detail/MeloXArtworkBackground.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [73](../../../Sources/Coda/Features/Detail/MeloXArtworkBackground.swift#L73) | 尺寸/字体/间距声明或原生字体 | `let scale = CIFilter.lanczosScaleTransform()` | #if os(iOS) |
| [85](../../../Sources/Coda/Features/Detail/MeloXArtworkBackground.swift#L85) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: 1, height: 1)` | #if os(iOS) |
| [136](../../../Sources/Coda/Features/Detail/MeloXArtworkBackground.swift#L136) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [148](../../../Sources/Coda/Features/Detail/MeloXArtworkBackground.swift#L148) | 尺寸约束 | `.frame(width: geometry.size.width, height: geometry.size.height)` | #if os(iOS) |
| [186](../../../Sources/Coda/Features/Detail/MeloXArtworkBackground.swift#L186) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [191](../../../Sources/Coda/Features/Detail/MeloXArtworkBackground.swift#L191) | 尺寸约束 | `.frame(width: size.width, height: size.height)` | #if os(iOS) |
| [199](../../../Sources/Coda/Features/Detail/MeloXArtworkBackground.swift#L199) | 尺寸约束 | `.frame(width: size.width, height: size.height)` | #if os(iOS) |

## MeloXPlaylistDetailHero

源码：`Sources/Kumone/Features/Detail/MeloXPlaylistDetailHero.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [35](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L35) | 容器布局/默认间距 | `VStack(spacing: 0)` | 共享/运行时分支见源码 |
| [41](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L41) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [42](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L42) | 内边距 | `.padding(.top, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [60](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L60) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L62) | 字号/字体 | `.font(.title3)` | 共享/运行时分支见源码 |
| [66](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L66) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [67](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L67) | 尺寸约束 | `.frame(minHeight: Theme.Layout.controlHeight)` | 共享/运行时分支见源码 |
| [86](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L86) | 尺寸/字体/间距声明或原生字体 | `@State private var availableWidth: CGFloat = 320` | 共享/运行时分支见源码 |
| [87](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L87) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .title2) private var titleLineHeight: CGFloat = 26` | 共享/运行时分支见源码 |
| [88](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L88) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .title3) private var subtitleLineHeight: CGFloat = 24` | 共享/运行时分支见源码 |
| [89](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L89) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .subheadline) private var metadataLineHeight: CGFloat = 18` | 共享/运行时分支见源码 |
| [103](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L103) | 容器布局/默认间距 | `VStack(spacing: 0)` | 共享/运行时分支见源码 |
| [111](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L111) | 尺寸约束 | `.frame(width: min(availableWidth - 48, 220), height: titleLineHeight)` | 共享/运行时分支见源码 |
| [114](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L114) | 字号/字体 | `.font(Theme.Typography.detailTitle)` | 共享/运行时分支见源码 |
| [120](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L120) | 内边距 | `.padding(.top, Theme.Spacing.page)` | 共享/运行时分支见源码 |
| [121](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L121) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [123](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L123) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [136](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L136) | 尺寸约束 | `.frame(width: 24, height: 24)` | 共享/运行时分支见源码 |
| [141](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L141) | 尺寸约束 | `.frame(width: 112, height: subtitleLineHeight)` | 共享/运行时分支见源码 |
| [144](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L144) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [148](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L148) | 内边距 | `.padding(.top, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [149](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L149) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [153](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L153) | 尺寸约束 | `.frame(width: 180, height: metadataLineHeight)` | 共享/运行时分支见源码 |
| [156](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L156) | 字号/字体 | `.font(Theme.Typography.secondary.weight(.medium))` | 共享/运行时分支见源码 |
| [159](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L159) | 文字压缩下限 | `.minimumScaleFactor(0.8)` | 共享/运行时分支见源码 |
| [162](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L162) | 内边距 | `.padding(.top, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [163](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L163) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [166](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L166) | 内边距 | `.padding(.top, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [168](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L168) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [169](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L169) | 内边距 | `.padding(.top, Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L170) | 内边距 | `.padding(.bottom, Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [181](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L181) | 尺寸/字体/间距声明或原生字体 | `let size = min(availableWidth * 0.68, 300)` | 共享/运行时分支见源码 |
| [190](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L190) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [219](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L219) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [220](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L220) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [223](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L223) | 尺寸约束 | `.frame(width: 24, height: 24)` | 共享/运行时分支见源码 |
| [228](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L228) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [232](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L232) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [243](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L243) | 尺寸/字体/间距声明或原生字体 | `static let height = Theme.Layout.detailActionHeight` | 共享/运行时分支见源码 |
| [260](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L260) | 尺寸/字体/间距声明或原生字体 | `var horizontalPadding: CGFloat? = nil` | 共享/运行时分支见源码 |
| [266](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L266) | 容器布局/默认间距 | `HStack(alignment: .bottom, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [276](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L276) | 字号/字体 | `.font(.title2.weight(.semibold))` | 共享/运行时分支见源码 |
| [277](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L277) | 尺寸约束 | `.frame(width: MeloXPlaylistActionMetrics.height, height: MeloXPlaylistActionMetrics.height)` | 共享/运行时分支见源码 |
| [294](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L294) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [295](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L295) | 尺寸约束 | `.frame(minWidth: 116, maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [296](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L296) | 尺寸约束 | `.frame(height: MeloXPlaylistActionMetrics.height)` | 共享/运行时分支见源码 |
| [306](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L306) | 尺寸约束 | `.frame(maxWidth: 328)` | 共享/运行时分支见源码 |
| [307](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L307) | 内边距 | `.padding(.horizontal, horizontalPadding ?? (usesWideDetailHeader ? 0 : Theme.Layout.contentInset))` | 共享/运行时分支见源码 |
| [316](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L316) | 字号/字体 | `.font(.title2.weight(.semibold))` | 共享/运行时分支见源码 |
| [317](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L317) | 尺寸约束 | `.frame(width: MeloXPlaylistActionMetrics.height, height: MeloXPlaylistActionMetrics.height)` | 共享/运行时分支见源码 |
| [338](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L338) | 容器布局/默认间距 | `HStack(alignment: .bottom, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [339](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L339) | 尺寸约束 | `.frame(width: 56, height: 56)` | 共享/运行时分支见源码 |
| [340](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L340) | 尺寸约束 | `.frame(minWidth: 116, maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [340](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L340) | 尺寸约束 | `.frame(height: 56)` | 共享/运行时分支见源码 |
| [341](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L341) | 尺寸约束 | `.frame(width: 56, height: 56)` | 共享/运行时分支见源码 |
| [343](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L343) | 尺寸约束 | `.frame(maxWidth: 328)` | 共享/运行时分支见源码 |
| [344](../../../Sources/Coda/Features/Detail/MeloXPlaylistDetailHero.swift#L344) | 内边距 | `.padding(.horizontal, usesWideDetailHeader ? 0 : Theme.Layout.contentInset)` | 共享/运行时分支见源码 |

## PlaylistDetailView

源码：`Sources/Kumone/Features/Detail/PlaylistDetailView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [10](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L10) | 尺寸/字体/间距声明或原生字体 | `var spacing: CGFloat` | 共享/运行时分支见源码 |
| [14](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L14) | 尺寸/字体/间距声明或原生字体 | `let gap = min(spacing, width / CGFloat(max(1, subviews.count * 4)))` | 共享/运行时分支见源码 |
| [19](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L19) | 尺寸/字体/间距声明或原生字体 | `let iconWidth = min(44, usable / CGFloat(subviews.count))` | 共享/运行时分支见源码 |
| [20](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L20) | 尺寸/字体/间距声明或原生字体 | `let flexibleWidth = flexibleCount > 0` | 共享/运行时分支见源码 |
| [24](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L24) | 尺寸/字体/间距声明或原生字体 | `let itemWidth = icon ? iconWidth : flexibleWidth` | 共享/运行时分支见源码 |
| [26](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L26) | 自定义组件/原生构造尺寸参数 | `CGRect(x: x, y: 0, width: itemWidth, height: 44)` | 共享/运行时分支见源码 |
| [31](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L31) | 尺寸/字体/间距声明或原生字体 | `let idealWidth = subviews.reduce(CGFloat.zero) { $0 + $1.sizeThatFits(.unspecified).width }` | 共享/运行时分支见源码 |
| [33](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L33) | 自定义组件/原生构造尺寸参数 | `CGSize(width: max(1, proposal.width ?? idealWidth), height: subviews.isEmpty ? 0 : 44)` | 共享/运行时分支见源码 |
| [56](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L56) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var horizontalSizeClass` | 共享/运行时分支见源码 |
| [153](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L153) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L183) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.tight)` | #if os(iOS) |
| [191](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L191) | 内边距 | `.padding(.trailing, Theme.Spacing.small)` | #if os(iOS) |
| [193](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L193) | 尺寸约束 | `.frame(height: 52)` | #if os(iOS) |
| [194](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L194) | 内边距 | `.padding(.horizontal, isCompact ? 8 : Theme.Layout.contentInset - 8)` | #if os(iOS) |
| [195](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L195) | 内边距 | `.padding(.top, Theme.Spacing.small)` | #if os(iOS) |
| [200](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L200) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [203](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L203) | 容器布局/默认间距 | `Spacer()` | #if os(iOS) |
| [207](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L207) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) |
| [209](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L209) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | #if os(iOS) |
| [214](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L214) | 尺寸约束 | `.frame(minHeight: 180)` | #if os(iOS) |
| [241](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L241) | 尺寸约束 | `.frame(minHeight: 400)` | 共享/运行时分支见源码 |
| [244](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L244) | 尺寸约束 | `.frame(minHeight: 400)` | 共享/运行时分支见源码 |
| [256](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L256) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [257](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L257) | 内边距 | `.padding(.vertical, Theme.Spacing.largeSection)` | 共享/运行时分支见源码 |
| [260](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L260) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [262](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L262) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [267](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L267) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | #if os(iOS) |
| [269](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L269) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) |
| [271](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L271) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [277](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L277) | 尺寸约束 | `.frame(maxWidth: .infinity)` | #if os(iOS) |
| [278](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L278) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | #if os(iOS) |
| [297](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L297) | 自定义组件/原生构造尺寸参数 | `MeloXPlaylistPrimaryActions( isSaved: detail.subscribed \|\| isOwnPlaylist, canSave: account.isLoggedIn && !isOwnPlaylist, canPlay: !playable.isEmpty, isSaving: isSubscribing, onToggleSaved: { toggleSubscribe(detail) }, onPlayAll: { player.play(tracks: playable, source: .playlist(playlistID), context: .playlist(id: playlistID, name: detail.name)) }, horizontalPadding: horizontalPadding )` | 共享/运行时分支见源码 |
| [338](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L338) | 内边距 | `.padding(Theme.Spacing.page)` | 共享/运行时分支见源码 |
| [339](../../../Sources/Coda/Features/Detail/PlaylistDetailView.swift#L339) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |

## PlaylistSearchField

源码：`Sources/Kumone/Features/Detail/PlaylistSearchField.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [144](../../../Sources/Coda/Features/Detail/PlaylistSearchField.swift#L144) | 容器布局/默认间距 | `TextField(placeholder, text: $text)` | #if os(macOS) |
| [146](../../../Sources/Coda/Features/Detail/PlaylistSearchField.swift#L146) | 字号/字体 | `.font(Theme.Typography.body)` | #if os(macOS) |

## ExploreView

源码：`Sources/Kumone/Features/Explore/ExploreView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [117](../../../Sources/Coda/Features/Explore/ExploreView.swift#L117) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [119](../../../Sources/Coda/Features/Explore/ExploreView.swift#L119) | 页面顶部留白 | `.pageHeaderTopPadding(8)` | 共享/运行时分支见源码 |
| [127](../../../Sources/Coda/Features/Explore/ExploreView.swift#L127) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [144](../../../Sources/Coda/Features/Explore/ExploreView.swift#L144) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [147](../../../Sources/Coda/Features/Explore/ExploreView.swift#L147) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [148](../../../Sources/Coda/Features/Explore/ExploreView.swift#L148) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [150](../../../Sources/Coda/Features/Explore/ExploreView.swift#L150) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [152](../../../Sources/Coda/Features/Explore/ExploreView.swift#L152) | 内边距 | `.padding(.vertical, Theme.Spacing.phonePage)` | 共享/运行时分支见源码 |
| [155](../../../Sources/Coda/Features/Explore/ExploreView.swift#L155) | 尺寸约束 | `.frame(height: 1)` | 共享/运行时分支见源码 |
| [171](../../../Sources/Coda/Features/Explore/ExploreView.swift#L171) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/Features/Explore/ExploreView.swift#L172) | 尺寸约束 | `.frame(width: Theme.Layout.contentInset - 8)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/Features/Explore/ExploreView.swift#L172) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [181](../../../Sources/Coda/Features/Explore/ExploreView.swift#L181) | 尺寸约束 | `.frame(width: Theme.Layout.contentInset - 8)` | 共享/运行时分支见源码 |
| [181](../../../Sources/Coda/Features/Explore/ExploreView.swift#L181) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/Features/Explore/ExploreView.swift#L183) | 内边距 | `.padding(.vertical, Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [207](../../../Sources/Coda/Features/Explore/ExploreView.swift#L207) | 容器布局/默认间距 | `LazyVGrid( columns: [GridItem(.adaptive(minimum: 300, maximum: 420), spacing: Theme.Spacing.group)], alignment: .leading, spacing: Theme.Spacing.section )` | 共享/运行时分支见源码 |
| [208](../../../Sources/Coda/Features/Explore/ExploreView.swift#L208) | 容器布局/默认间距 | `GridItem(.adaptive(minimum: 300, maximum: 420), spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [213](../../../Sources/Coda/Features/Explore/ExploreView.swift#L213) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [215](../../../Sources/Coda/Features/Explore/ExploreView.swift#L215) | 尺寸约束 | `.frame(width: 110, height: 110)` | 共享/运行时分支见源码 |
| [217](../../../Sources/Coda/Features/Explore/ExploreView.swift#L217) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [219](../../../Sources/Coda/Features/Explore/ExploreView.swift#L219) | 字号/字体 | `.font(Theme.Typography.secondary.weight(.semibold))` | 共享/运行时分支见源码 |
| [223](../../../Sources/Coda/Features/Explore/ExploreView.swift#L223) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [225](../../../Sources/Coda/Features/Explore/ExploreView.swift#L225) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [228](../../../Sources/Coda/Features/Explore/ExploreView.swift#L228) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [234](../../../Sources/Coda/Features/Explore/ExploreView.swift#L234) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [236](../../../Sources/Coda/Features/Explore/ExploreView.swift#L236) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [252](../../../Sources/Coda/Features/Explore/ExploreView.swift#L252) | 容器布局/默认间距 | `VStack(spacing: 0)` | 共享/运行时分支见源码 |
| [254](../../../Sources/Coda/Features/Explore/ExploreView.swift#L254) | 内边距 | `.padding(Theme.Layout.contentInset)` | 共享/运行时分支见源码 |

## GlassTabBar

源码：`Sources/Kumone/Features/GlassTabBar.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [17](../../../Sources/Coda/Features/GlassTabBar.swift#L17) | 尺寸/字体/间距声明或原生字体 | `var expandedWidth: CGFloat` | #if os(iOS) |
| [28](../../../Sources/Coda/Features/GlassTabBar.swift#L28) | 尺寸/字体/间距声明或原生字体 | `private let innerInset: CGFloat = 4` | #if os(iOS) |
| [29](../../../Sources/Coda/Features/GlassTabBar.swift#L29) | 尺寸/字体/间距声明或原生字体 | `private let contentHeight: CGFloat = 56` | #if os(iOS) |
| [46](../../../Sources/Coda/Features/GlassTabBar.swift#L46) | 容器布局/默认间距 | `ZStack(alignment: .leading)` | #if os(iOS) |
| [48](../../../Sources/Coda/Features/GlassTabBar.swift#L48) | 尺寸约束 | `.frame(width: cellW - 8, height: contentHeight)` | #if os(iOS) |
| [65](../../../Sources/Coda/Features/GlassTabBar.swift#L65) | 尺寸约束 | `.frame(width: cellW, height: contentHeight)` | #if os(iOS) |
| [81](../../../Sources/Coda/Features/GlassTabBar.swift#L81) | 尺寸约束 | `.frame(height: contentHeight)` | #if os(iOS) |
| [82](../../../Sources/Coda/Features/GlassTabBar.swift#L82) | 内边距 | `.padding(innerInset)` | #if os(iOS) |
| [88](../../../Sources/Coda/Features/GlassTabBar.swift#L88) | 容器布局/默认间距 | `VStack(spacing: 3)` | #if os(iOS) |
| [90](../../../Sources/Coda/Features/GlassTabBar.swift#L90) | 字号/字体 | `.font(.system(size: 23, weight: .semibold))` | #if os(iOS) |
| [95](../../../Sources/Coda/Features/GlassTabBar.swift#L95) | 字号/字体 | `.font(.system(size: 10, weight: .semibold))` | #if os(iOS) |
| [102](../../../Sources/Coda/Features/GlassTabBar.swift#L102) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | #if os(iOS) |
| [158](../../../Sources/Coda/Features/GlassTabBar.swift#L158) | 字号/字体 | `.font(.system(size: 23, weight: .semibold))` | #if os(iOS) |
| [160](../../../Sources/Coda/Features/GlassTabBar.swift#L160) | 尺寸约束 | `.frame(width: 64, height: 64)` | #if os(iOS) |
| [163](../../../Sources/Coda/Features/GlassTabBar.swift#L163) | 内边距 | `.padding(4)` | #if os(iOS) |

## HomeBrowseView

源码：`Sources/Kumone/Features/Home/HomeBrowseView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [27](../../../Sources/Coda/Features/Home/HomeBrowseView.swift#L27) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [48](../../../Sources/Coda/Features/Home/HomeBrowseView.swift#L48) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Home/HomeBrowseView.swift#L53) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Home/HomeBrowseView.swift#L62) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [65](../../../Sources/Coda/Features/Home/HomeBrowseView.swift#L65) | 尺寸约束 | `.frame(minHeight: 44)` | 共享/运行时分支见源码 |
| [70](../../../Sources/Coda/Features/Home/HomeBrowseView.swift#L70) | 尺寸约束 | `.frame(minHeight: 44)` | 共享/运行时分支见源码 |
| [76](../../../Sources/Coda/Features/Home/HomeBrowseView.swift#L76) | 内边距 | `.padding(.top, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |

## HomeCoverShelf

源码：`Sources/Kumone/Features/Home/HomeCoverShelf.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [12](../../../Sources/Coda/Features/Home/HomeCoverShelf.swift#L12) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [16](../../../Sources/Coda/Features/Home/HomeCoverShelf.swift#L16) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [24](../../../Sources/Coda/Features/Home/HomeCoverShelf.swift#L24) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |

## HomeDiscoverySections

源码：`Sources/Kumone/Features/Home/HomeDiscoverySections.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [5](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L5) | 尺寸/字体/间距声明或原生字体 | `let shelfWidth: CGFloat` | 共享/运行时分支见源码 |
| [11](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L11) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 0)` | 共享/运行时分支见源码 |
| [15](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L15) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: HomeLayout.headerHeight, alignment: .leading)` | 共享/运行时分支见源码 |
| [16](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L16) | 内边距 | `.padding(.bottom, HomeLayout.headerSpacing)` | 共享/运行时分支见源码 |
| [17](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L17) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [22](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L22) | 自定义组件/原生构造尺寸参数 | `MusicLibraryLoadingView(rowsPerColumn: 3, scrollsHorizontally: true, showsHorizontalPanel: false, horizontalInset: Theme.Layout.trackListInset)` | 共享/运行时分支见源码 |
| [28](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L28) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 120)` | 共享/运行时分支见源码 |
| [32](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L32) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [38](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L38) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [39](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L39) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 64)` | 共享/运行时分支见源码 |
| [52](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L52) | 尺寸约束 | `.frame(height: 0.5)` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L53) | 内边距 | `.padding(.bottom, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [54](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L54) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [55](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L55) | 自定义组件/原生构造尺寸参数 | `MusicTrackPanel(tracks: Array(songs.prefix(36)), scrollsHorizontally: true, horizontalRowLimit: 3, horizontalInset: Theme.Layout.trackListInset, showsHorizontalPanel: false, showsRowSeparators: false)` | 共享/运行时分支见源码 |
| [61](../../../Sources/Coda/Features/Home/HomeDiscoverySections.swift#L61) | 自定义组件/原生构造尺寸参数 | `CoverCardBody( coverURL: playlist.coverURL?.resizedImageURL(384), playlistID: playlist.id, title: playlist.name, subtitle: playlist.copywriter ?? playlist.creator?.nickname, size: Theme.Layout.fittedShelfCardSize( availableWidth: shelfWidth, leadingInset: Theme.Layout.contentInset) )` | 共享/运行时分支见源码 |

## HomeRecommendationPageView

源码：`Sources/Kumone/Features/Home/HomeRecommendationPageView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [53](../../../Sources/Coda/Features/Home/HomeRecommendationPageView.swift#L53) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [76](../../../Sources/Coda/Features/Home/HomeRecommendationPageView.swift#L76) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [82](../../../Sources/Coda/Features/Home/HomeRecommendationPageView.swift#L82) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 240)` | 共享/运行时分支见源码 |
| [86](../../../Sources/Coda/Features/Home/HomeRecommendationPageView.swift#L86) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [87](../../../Sources/Coda/Features/Home/HomeRecommendationPageView.swift#L87) | 内边距 | `.padding(.top, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |

## HomeSongRecommendationLists

源码：`Sources/Kumone/Features/Home/HomeSongRecommendationLists.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [140](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L140) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing)` | 共享/运行时分支见源码 |
| [161](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L161) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 0)` | 共享/运行时分支见源码 |
| [165](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L165) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: HomeLayout.headerHeight, alignment: .leading)` | 共享/运行时分支见源码 |
| [166](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L166) | 内边距 | `.padding(.bottom, HomeLayout.headerSpacing)` | 共享/运行时分支见源码 |
| [167](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L167) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L170) | 尺寸约束 | `.frame(height: 0.5)` | 共享/运行时分支见源码 |
| [171](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L171) | 内边距 | `.padding(.bottom, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L172) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [174](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L174) | 自定义组件/原生构造尺寸参数 | `MusicTrackPanel(tracks: tracks, scrollsHorizontally: true, horizontalRowLimit: 3, horizontalInset: Theme.Layout.trackListInset, showsHorizontalPanel: false, showsRowSeparators: false)` | 共享/运行时分支见源码 |
| [178](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L178) | 自定义组件/原生构造尺寸参数 | `MusicLibraryLoadingView(rowsPerColumn: 3, scrollsHorizontally: true, showsHorizontalPanel: false, horizontalInset: Theme.Layout.trackListInset)` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L183) | 内边距 | `.padding(Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [184](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L184) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [187](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L187) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .topLeading)` | 共享/运行时分支见源码 |
| [193](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L193) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [195](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L195) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [203](../../../Sources/Coda/Features/Home/HomeSongRecommendationLists.swift#L203) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 216)` | 共享/运行时分支见源码 |

## HomeView

源码：`Sources/Kumone/Features/Home/HomeView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [5](../../../Sources/Coda/Features/Home/HomeView.swift#L5) | 尺寸/字体/间距声明或原生字体 | `static let sectionSpacing = Theme.Spacing.discoverySection` | 共享/运行时分支见源码 |
| [6](../../../Sources/Coda/Features/Home/HomeView.swift#L6) | 尺寸/字体/间距声明或原生字体 | `static let headerSpacing = Theme.Spacing.component` | 共享/运行时分支见源码 |
| [7](../../../Sources/Coda/Features/Home/HomeView.swift#L7) | 尺寸/字体/间距声明或原生字体 | `static let headerHeight: CGFloat = 44` | 共享/运行时分支见源码 |
| [182](../../../Sources/Coda/Features/Home/HomeView.swift#L182) | 尺寸/字体/间距声明或原生字体 | `@State private var shelfWidth: CGFloat = 0` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/Features/Home/HomeView.swift#L183) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var chartRowHeight: CGFloat = 64` | 共享/运行时分支见源码 |
| [185](../../../Sources/Coda/Features/Home/HomeView.swift#L185) | 尺寸/字体/间距声明或原生字体 | `private var toplistHeight: CGFloat { 64 + 8 + 0.5 + 6 + chartRowHeight * 10 }` | 共享/运行时分支见源码 |
| [203](../../../Sources/Coda/Features/Home/HomeView.swift#L203) | 安全区插入 | `.safeAreaInset(edge: .top)` | 共享/运行时分支见源码 |
| [217](../../../Sources/Coda/Features/Home/HomeView.swift#L217) | 尺寸约束 | `.frame(minHeight: 400)` | 共享/运行时分支见源码 |
| [235](../../../Sources/Coda/Features/Home/HomeView.swift#L235) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: HomeLayout.sectionSpacing)` | 共享/运行时分支见源码 |
| [237](../../../Sources/Coda/Features/Home/HomeView.swift#L237) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [239](../../../Sources/Coda/Features/Home/HomeView.swift#L239) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [242](../../../Sources/Coda/Features/Home/HomeView.swift#L242) | 尺寸约束 | `.frame(width: FeatureCard.width, height: FeatureCard.height)` | 共享/运行时分支见源码 |
| [247](../../../Sources/Coda/Features/Home/HomeView.swift#L247) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [249](../../../Sources/Coda/Features/Home/HomeView.swift#L249) | 尺寸约束 | `.frame(height: FeatureCard.height * 2 + 16)` | 共享/运行时分支见源码 |
| [250](../../../Sources/Coda/Features/Home/HomeView.swift#L250) | 页面顶部留白 | `.pageHeaderTopPadding(8)` | 共享/运行时分支见源码 |
| [256](../../../Sources/Coda/Features/Home/HomeView.swift#L256) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 0)` | 共享/运行时分支见源码 |
| [257](../../../Sources/Coda/Features/Home/HomeView.swift#L257) | 尺寸约束 | `.frame(width: 220, height: 22)` | 共享/运行时分支见源码 |
| [258](../../../Sources/Coda/Features/Home/HomeView.swift#L258) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: HomeLayout.headerHeight, alignment: .leading)` | 共享/运行时分支见源码 |
| [259](../../../Sources/Coda/Features/Home/HomeView.swift#L259) | 内边距 | `.padding(.bottom, HomeLayout.headerSpacing)` | 共享/运行时分支见源码 |
| [260](../../../Sources/Coda/Features/Home/HomeView.swift#L260) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [261](../../../Sources/Coda/Features/Home/HomeView.swift#L261) | 尺寸约束 | `.frame(height: 0.5)` | 共享/运行时分支见源码 |
| [262](../../../Sources/Coda/Features/Home/HomeView.swift#L262) | 内边距 | `.padding(.bottom, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [263](../../../Sources/Coda/Features/Home/HomeView.swift#L263) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [264](../../../Sources/Coda/Features/Home/HomeView.swift#L264) | 自定义组件/原生构造尺寸参数 | `MusicLibraryLoadingView(rowsPerColumn: 3, scrollsHorizontally: true, showsHorizontalPanel: false, horizontalInset: Theme.Layout.trackListInset)` | 共享/运行时分支见源码 |
| [270](../../../Sources/Coda/Features/Home/HomeView.swift#L270) | 页面顶部留白 | `.pageHeaderTopPadding(Theme.Layout.contentInset - 8)` | 共享/运行时分支见源码 |
| [271](../../../Sources/Coda/Features/Home/HomeView.swift#L271) | 内边距 | `.padding(.bottom, Theme.Layout.contentInset - 8)` | 共享/运行时分支见源码 |
| [272](../../../Sources/Coda/Features/Home/HomeView.swift#L272) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [276](../../../Sources/Coda/Features/Home/HomeView.swift#L276) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: HomeLayout.sectionSpacing)` | 共享/运行时分支见源码 |
| [278](../../../Sources/Coda/Features/Home/HomeView.swift#L278) | 页面顶部留白 | `.pageHeaderTopPadding(8)` | 共享/运行时分支见源码 |
| [287](../../../Sources/Coda/Features/Home/HomeView.swift#L287) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: HomeLayout.headerSpacing)` | 共享/运行时分支见源码 |
| [289](../../../Sources/Coda/Features/Home/HomeView.swift#L289) | 尺寸约束 | `.frame(minHeight: HomeLayout.headerHeight)` | 共享/运行时分支见源码 |
| [290](../../../Sources/Coda/Features/Home/HomeView.swift#L290) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [299](../../../Sources/Coda/Features/Home/HomeView.swift#L299) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: HomeLayout.headerSpacing)` | 共享/运行时分支见源码 |
| [301](../../../Sources/Coda/Features/Home/HomeView.swift#L301) | 尺寸约束 | `.frame(minHeight: HomeLayout.headerHeight)` | 共享/运行时分支见源码 |
| [302](../../../Sources/Coda/Features/Home/HomeView.swift#L302) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [304](../../../Sources/Coda/Features/Home/HomeView.swift#L304) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [309](../../../Sources/Coda/Features/Home/HomeView.swift#L309) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [317](../../../Sources/Coda/Features/Home/HomeView.swift#L317) | 页面顶部留白 | `.pageHeaderTopPadding(Theme.Layout.contentInset - 8)` | 共享/运行时分支见源码 |
| [318](../../../Sources/Coda/Features/Home/HomeView.swift#L318) | 内边距 | `.padding(.bottom, Theme.Layout.contentInset - 8)` | 共享/运行时分支见源码 |
| [319](../../../Sources/Coda/Features/Home/HomeView.swift#L319) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [326](../../../Sources/Coda/Features/Home/HomeView.swift#L326) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: HomeLayout.headerSpacing)` | 共享/运行时分支见源码 |
| [328](../../../Sources/Coda/Features/Home/HomeView.swift#L328) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [329](../../../Sources/Coda/Features/Home/HomeView.swift#L329) | 字号/字体 | `.font(Theme.Typography.sectionTitle.bold())` | 共享/运行时分支见源码 |
| [333](../../../Sources/Coda/Features/Home/HomeView.swift#L333) | 尺寸约束 | `.frame(minHeight: HomeLayout.headerHeight)` | 共享/运行时分支见源码 |
| [338](../../../Sources/Coda/Features/Home/HomeView.swift#L338) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [341](../../../Sources/Coda/Features/Home/HomeView.swift#L341) | 尺寸/字体/间距声明或原生字体 | `let width = max(360, (geometry.size.width - 2 * Theme.Layout.contentInset - 32) / 3)` | 共享/运行时分支见源码 |
| [343](../../../Sources/Coda/Features/Home/HomeView.swift#L343) | 容器布局/默认间距 | `LazyHStack(alignment: .top, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [359](../../../Sources/Coda/Features/Home/HomeView.swift#L359) | 尺寸约束 | `.frame(width: width)` | 共享/运行时分支见源码 |
| [363](../../../Sources/Coda/Features/Home/HomeView.swift#L363) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [366](../../../Sources/Coda/Features/Home/HomeView.swift#L366) | 尺寸约束 | `.frame(height: toplistHeight)` | 共享/运行时分支见源码 |
| [378](../../../Sources/Coda/Features/Home/HomeView.swift#L378) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [379](../../../Sources/Coda/Features/Home/HomeView.swift#L379) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [419](../../../Sources/Coda/Features/Home/HomeView.swift#L419) | 尺寸约束 | `.frame(height: FeatureCard.height)` | 共享/运行时分支见源码 |
| [421](../../../Sources/Coda/Features/Home/HomeView.swift#L421) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [426](../../../Sources/Coda/Features/Home/HomeView.swift#L426) | 尺寸约束 | `.frame(height: FeatureCard.height)` | 共享/运行时分支见源码 |
| [428](../../../Sources/Coda/Features/Home/HomeView.swift#L428) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [430](../../../Sources/Coda/Features/Home/HomeView.swift#L430) | 尺寸约束 | `.frame(height: FeatureCard.height * 2 + 16)` | 共享/运行时分支见源码 |
| [475](../../../Sources/Coda/Features/Home/HomeView.swift#L475) | 自定义组件/原生构造尺寸参数 | `CoverCardBody( coverURL: album.picUrl?.resizedImageURL(384), title: album.name, subtitle: album.artistName, size: size )` | 共享/运行时分支见源码 |
| [494](../../../Sources/Coda/Features/Home/HomeView.swift#L494) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [496](../../../Sources/Coda/Features/Home/HomeView.swift#L496) | 尺寸约束 | `.frame(width: 128, height: 128)` | 共享/运行时分支见源码 |
| [500](../../../Sources/Coda/Features/Home/HomeView.swift#L500) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [504](../../../Sources/Coda/Features/Home/HomeView.swift#L504) | 尺寸约束 | `.frame(width: 140)` | 共享/运行时分支见源码 |
| [526](../../../Sources/Coda/Features/Home/HomeView.swift#L526) | 尺寸/字体/间距声明或原生字体 | `static let width: CGFloat = 178` | 共享/运行时分支见源码 |
| [528](../../../Sources/Coda/Features/Home/HomeView.swift#L528) | 尺寸/字体/间距声明或原生字体 | `static let height: CGFloat = width` | 共享/运行时分支见源码 |
| [541](../../../Sources/Coda/Features/Home/HomeView.swift#L541) | 容器布局/默认间距 | `ZStack(alignment: .bottomLeading)` | 共享/运行时分支见源码 |
| [544](../../../Sources/Coda/Features/Home/HomeView.swift#L544) | 尺寸约束 | `.frame(width: Self.width, height: Self.height)` | 共享/运行时分支见源码 |
| [554](../../../Sources/Coda/Features/Home/HomeView.swift#L554) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [557](../../../Sources/Coda/Features/Home/HomeView.swift#L557) | 字号/字体 | `.font(Theme.Typography.secondary.weight(.medium))` | 共享/运行时分支见源码 |
| [561](../../../Sources/Coda/Features/Home/HomeView.swift#L561) | 字号/字体 | `.font(.system(size: 21, weight: .semibold))` | 共享/运行时分支见源码 |
| [563](../../../Sources/Coda/Features/Home/HomeView.swift#L563) | 尺寸约束 | `.frame(width: 46, height: 46)` | 共享/运行时分支见源码 |
| [566](../../../Sources/Coda/Features/Home/HomeView.swift#L566) | 容器布局/默认间距 | `Spacer(minLength: 12)` | 共享/运行时分支见源码 |
| [568](../../../Sources/Coda/Features/Home/HomeView.swift#L568) | 字号/字体 | `.font(Theme.Typography.sectionTitle.weight(.bold))` | 共享/运行时分支见源码 |
| [573](../../../Sources/Coda/Features/Home/HomeView.swift#L573) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [577](../../../Sources/Coda/Features/Home/HomeView.swift#L577) | 内边距 | `.padding(Theme.Spacing.phonePage)` | 共享/运行时分支见源码 |
| [579](../../../Sources/Coda/Features/Home/HomeView.swift#L579) | 尺寸约束 | `.frame(width: Self.width, height: Self.height)` | 共享/运行时分支见源码 |
| [596](../../../Sources/Coda/Features/Home/HomeView.swift#L596) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = Theme.Layout.cardSize` | 共享/运行时分支见源码 |
| [600](../../../Sources/Coda/Features/Home/HomeView.swift#L600) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.flexibleCardWidth) private var flexibleWidth` | 共享/运行时分支见源码 |
| [603](../../../Sources/Coda/Features/Home/HomeView.swift#L603) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [613](../../../Sources/Coda/Features/Home/HomeView.swift#L613) | 内边距 | `.padding(Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [619](../../../Sources/Coda/Features/Home/HomeView.swift#L619) | 内边距 | `.padding(Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [624](../../../Sources/Coda/Features/Home/HomeView.swift#L624) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [628](../../../Sources/Coda/Features/Home/HomeView.swift#L628) | 尺寸约束 | `.frame(maxWidth: flexibleWidth ? .infinity : size, alignment: .leading)` | 共享/运行时分支见源码 |
| [631](../../../Sources/Coda/Features/Home/HomeView.swift#L631) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [634](../../../Sources/Coda/Features/Home/HomeView.swift#L634) | 尺寸约束 | `.frame(maxWidth: flexibleWidth ? .infinity : size, alignment: .leading)` | 共享/运行时分支见源码 |
| [637](../../../Sources/Coda/Features/Home/HomeView.swift#L637) | 尺寸约束 | `.frame(maxWidth: flexibleWidth ? .infinity : size, alignment: .leading)` | 共享/运行时分支见源码 |
| [649](../../../Sources/Coda/Features/Home/HomeView.swift#L649) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [652](../../../Sources/Coda/Features/Home/HomeView.swift#L652) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [661](../../../Sources/Coda/Features/Home/HomeView.swift#L661) | 尺寸/字体/间距声明或原生字体 | `let reservedHeight: CGFloat` | 共享/运行时分支见源码 |
| [671](../../../Sources/Coda/Features/Home/HomeView.swift#L671) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 0)` | 共享/运行时分支见源码 |
| [673](../../../Sources/Coda/Features/Home/HomeView.swift#L673) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [675](../../../Sources/Coda/Features/Home/HomeView.swift#L675) | 尺寸约束 | `.frame(width: 48, height: 48)` | 共享/运行时分支见源码 |
| [678](../../../Sources/Coda/Features/Home/HomeView.swift#L678) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [680](../../../Sources/Coda/Features/Home/HomeView.swift#L680) | 字号/字体 | `.font(Theme.Typography.cardTitle.weight(.semibold))` | 共享/运行时分支见源码 |
| [684](../../../Sources/Coda/Features/Home/HomeView.swift#L684) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [689](../../../Sources/Coda/Features/Home/HomeView.swift#L689) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [691](../../../Sources/Coda/Features/Home/HomeView.swift#L691) | 尺寸约束 | `.frame(width: TrackRow.chartRankColumnWidth)` | 共享/运行时分支见源码 |
| [692](../../../Sources/Coda/Features/Home/HomeView.swift#L692) | 内边距 | `.padding(.trailing, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [694](../../../Sources/Coda/Features/Home/HomeView.swift#L694) | 内边距 | `.padding(.leading, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [696](../../../Sources/Coda/Features/Home/HomeView.swift#L696) | 尺寸约束 | `.frame(minHeight: 64)` | 共享/运行时分支见源码 |
| [700](../../../Sources/Coda/Features/Home/HomeView.swift#L700) | 内边距 | `.padding(.bottom, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [703](../../../Sources/Coda/Features/Home/HomeView.swift#L703) | 尺寸约束 | `.frame(height: 0.5)` | 共享/运行时分支见源码 |
| [704](../../../Sources/Coda/Features/Home/HomeView.swift#L704) | 内边距 | `.padding(.leading, Theme.Spacing.phonePage)` | 共享/运行时分支见源码 |
| [705](../../../Sources/Coda/Features/Home/HomeView.swift#L705) | 内边距 | `.padding(.trailing, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [706](../../../Sources/Coda/Features/Home/HomeView.swift#L706) | 内边距 | `.padding(.bottom, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [708](../../../Sources/Coda/Features/Home/HomeView.swift#L708) | 容器布局/默认间距 | `LazyVStack(spacing: 0)` | 共享/运行时分支见源码 |
| [722](../../../Sources/Coda/Features/Home/HomeView.swift#L722) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [724](../../../Sources/Coda/Features/Home/HomeView.swift#L724) | 尺寸约束 | `.frame(minHeight: 44)` | 共享/运行时分支见源码 |
| [726](../../../Sources/Coda/Features/Home/HomeView.swift#L726) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: reservedHeight - 78.5)` | 共享/运行时分支见源码 |
| [730](../../../Sources/Coda/Features/Home/HomeView.swift#L730) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: reservedHeight - 78.5)` | 共享/运行时分支见源码 |
| [733](../../../Sources/Coda/Features/Home/HomeView.swift#L733) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: reservedHeight - 78.5)` | 共享/运行时分支见源码 |
| [736](../../../Sources/Coda/Features/Home/HomeView.swift#L736) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: reservedHeight, alignment: .topLeading)` | 共享/运行时分支见源码 |

## IOSMainWindow

源码：`Sources/Kumone/Features/IOSMainWindow.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [31](../../../Sources/Coda/Features/IOSMainWindow.swift#L31) | 尺寸/字体/间距声明或原生字体 | `var legacyIPadSystemInsets: EdgeInsets { get { self[LegacyIPadSystemInsetsKey.self] } set { self[LegacyIPadSystemInsetsKey.self] = newValue } }` | #if os(iOS) |
| [60](../../../Sources/Coda/Features/IOSMainWindow.swift#L60) | 尺寸/字体/间距声明或原生字体 | `@State private var lastActiveSystemInsets: EdgeInsets?` | #if os(iOS) |
| [67](../../../Sources/Coda/Features/IOSMainWindow.swift#L67) | 尺寸/字体/间距声明或原生字体 | `let insets = scenePhase == .active ? viewport.safeAreaInsets` | #if os(iOS) |
| [108](../../../Sources/Coda/Features/IOSMainWindow.swift#L108) | 尺寸/字体/间距声明或原生字体 | `let ownsContainerInsets = insideNavigation \|\| controller is UINavigationController` | #if os(iOS) |
| [277](../../../Sources/Coda/Features/IOSMainWindow.swift#L277) | 尺寸/字体/间距声明或原生字体 | `guard let hosting, let size = view.window?.bounds.size,` | #if os(iOS) |
| [465](../../../Sources/Coda/Features/IOSMainWindow.swift#L465) | 容器布局/默认间距 | `VStack(spacing: 8)` | #if os(iOS) |
| [474](../../../Sources/Coda/Features/IOSMainWindow.swift#L474) | 内边距 | `.padding(.top, 8)` | #if os(iOS) |
| [640](../../../Sources/Coda/Features/IOSMainWindow.swift#L640) | 容器布局/默认间距 | `ZStack(alignment: .bottom)` | #if os(iOS) |
| [641](../../../Sources/Coda/Features/IOSMainWindow.swift#L641) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [649](../../../Sources/Coda/Features/IOSMainWindow.swift#L649) | 内边距 | `.padding(.bottom, 6)` | #if os(iOS) |
| [679](../../../Sources/Coda/Features/IOSMainWindow.swift#L679) | 尺寸/字体/间距声明或原生字体 | `let width = proxy.size.width` | #if os(iOS) |
| [680](../../../Sources/Coda/Features/IOSMainWindow.swift#L680) | 尺寸/字体/间距声明或原生字体 | `let expandedNavigationWidth = max(64, width - 76)` | #if os(iOS) |
| [681](../../../Sources/Coda/Features/IOSMainWindow.swift#L681) | 尺寸/字体/间距声明或原生字体 | `let navigationWidth: CGFloat = legacyBarCollapsed ? 64 : expandedNavigationWidth` | #if os(iOS) |
| [682](../../../Sources/Coda/Features/IOSMainWindow.swift#L682) | 尺寸/字体/间距声明或原生字体 | `let playerWidth = legacyBarCollapsed ? max(0, width - 152) : width` | #if os(iOS) |
| [684](../../../Sources/Coda/Features/IOSMainWindow.swift#L684) | 容器布局/默认间距 | `ZStack(alignment: .bottomLeading)` | #if os(iOS) |
| [694](../../../Sources/Coda/Features/IOSMainWindow.swift#L694) | 尺寸约束 | `.frame(width: navigationWidth, height: 64)` | #if os(iOS) |
| [698](../../../Sources/Coda/Features/IOSMainWindow.swift#L698) | 尺寸约束 | `.frame(width: playerWidth, height: 52)` | #if os(iOS) |
| [706](../../../Sources/Coda/Features/IOSMainWindow.swift#L706) | 尺寸约束 | `.frame(width: width, height: proxy.size.height, alignment: .bottomLeading)` | #if os(iOS) |
| [708](../../../Sources/Coda/Features/IOSMainWindow.swift#L708) | 尺寸约束 | `.frame(height: legacyBarCollapsed \|\| !player.hasCurrentTrack ? 64 : 124)` | #if os(iOS) |
| [709](../../../Sources/Coda/Features/IOSMainWindow.swift#L709) | 内边距 | `.padding(.horizontal, 12)` | #if os(iOS) |
| [899](../../../Sources/Coda/Features/IOSMainWindow.swift#L899) | 容器布局/默认间距 | `HStack(spacing: 4)` | #if os(iOS) |
| [908](../../../Sources/Coda/Features/IOSMainWindow.swift#L908) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "backward.fill", label: "上一首", size: 14, width: 44, tint: PlayerControlAppearance.barTint, height: 44, disabled: player.isFMMode, action: player.previous)` | #if os(iOS) |
| [914](../../../Sources/Coda/Features/IOSMainWindow.swift#L914) | 自定义组件/原生构造尺寸参数 | `PlayerPlayPauseButton(isPlaying: player.isPlaying, isBuffering: player.isBuffering, size: 15, width: 44, tint: PlayerControlAppearance.barTint, height: 44, action: player.togglePlayPause)` | #if os(iOS) |
| [918](../../../Sources/Coda/Features/IOSMainWindow.swift#L918) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "forward.fill", label: "下一首", size: 14, width: 44, tint: PlayerControlAppearance.barTint, height: 44, action: player.next)` | #if os(iOS) |
| [923](../../../Sources/Coda/Features/IOSMainWindow.swift#L923) | 内边距 | `.padding(.leading, 12)` | #if os(iOS) |
| [924](../../../Sources/Coda/Features/IOSMainWindow.swift#L924) | 内边距 | `.padding(.trailing, 6)` | #if os(iOS) |
| [925](../../../Sources/Coda/Features/IOSMainWindow.swift#L925) | 内边距 | `.padding(.vertical, 4)` | #if os(iOS) |
| [926](../../../Sources/Coda/Features/IOSMainWindow.swift#L926) | 尺寸约束 | `.frame(maxWidth: .infinity)` | #if os(iOS) |
| [930](../../../Sources/Coda/Features/IOSMainWindow.swift#L930) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: 8)` | #if os(iOS) |
| [932](../../../Sources/Coda/Features/IOSMainWindow.swift#L932) | 尺寸约束 | `.frame( width: artworkSize, height: artworkSize )` | #if os(iOS) |
| [939](../../../Sources/Coda/Features/IOSMainWindow.swift#L939) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: metadataSpacing)` | #if os(iOS) |
| [941](../../../Sources/Coda/Features/IOSMainWindow.swift#L941) | 字号/字体 | `.font(titleFont)` | #if os(iOS) |
| [946](../../../Sources/Coda/Features/IOSMainWindow.swift#L946) | 字号/字体 | `.font(artistFont)` | #if os(iOS) |
| [950](../../../Sources/Coda/Features/IOSMainWindow.swift#L950) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .topLeading)` | #if os(iOS) |
| [953](../../../Sources/Coda/Features/IOSMainWindow.swift#L953) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | #if os(iOS) |
| [956](../../../Sources/Coda/Features/IOSMainWindow.swift#L956) | 尺寸/字体/间距声明或原生字体 | `private var artworkSize: CGFloat { presentation.isInline ? 28 : 32 }` | #if os(iOS) |
| [960](../../../Sources/Coda/Features/IOSMainWindow.swift#L960) | 尺寸/字体/间距声明或原生字体 | `private var titleFont: Font { .system(size: presentation.isInline ? 10 : 13, weight: .semibold) }` | #if os(iOS) |
| [964](../../../Sources/Coda/Features/IOSMainWindow.swift#L964) | 尺寸/字体/间距声明或原生字体 | `private var artistFont: Font { .system(size: presentation.isInline ? 8 : 10) }` | #if os(iOS) |
| [968](../../../Sources/Coda/Features/IOSMainWindow.swift#L968) | 尺寸/字体/间距声明或原生字体 | `private var metadataSpacing: CGFloat { presentation.isInline ? 2 : 3 }` | #if os(iOS) |
| [1072](../../../Sources/Coda/Features/IOSMainWindow.swift#L1072) | 容器布局/默认间距 | `TextField("歌单名称", text: $newPlaylistName)` | #if os(iOS) |
| [1110](../../../Sources/Coda/Features/IOSMainWindow.swift#L1110) | 容器布局/默认间距 | `VStack(spacing: 16)` | #if os(iOS) |
| [1117](../../../Sources/Coda/Features/IOSMainWindow.swift#L1117) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [1121](../../../Sources/Coda/Features/IOSMainWindow.swift#L1121) | 容器布局/默认间距 | `Spacer()` | #if os(iOS) |
| [1124](../../../Sources/Coda/Features/IOSMainWindow.swift#L1124) | 字号/字体 | `.font(.system(size: 13, weight: .semibold))` | #if os(iOS) |
| [1125](../../../Sources/Coda/Features/IOSMainWindow.swift#L1125) | 尺寸约束 | `.frame(width: 44, height: 44)` | #if os(iOS) |
| [1129](../../../Sources/Coda/Features/IOSMainWindow.swift#L1129) | 内边距 | `.padding(.horizontal, 16)` | #if os(iOS) |
| [1134](../../../Sources/Coda/Features/IOSMainWindow.swift#L1134) | 内边距 | `.padding(.horizontal, 16)` | #if os(iOS) |
| [1140](../../../Sources/Coda/Features/IOSMainWindow.swift#L1140) | 内边距 | `.padding(.horizontal, 16)` | #if os(iOS) |
| [1154](../../../Sources/Coda/Features/IOSMainWindow.swift#L1154) | 内边距 | `.padding(.horizontal, 16)` | #if os(iOS) |
| [1193](../../../Sources/Coda/Features/IOSMainWindow.swift#L1193) | 容器布局/默认间距 | `List { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [1199](../../../Sources/Coda/Features/IOSMainWindow.swift#L1199) | 列表内边距 | `.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 16, trailing: 0))` | #if os(iOS) |
| [1205](../../../Sources/Coda/Features/IOSMainWindow.swift#L1205) | 容器布局/默认间距 | `HStack(spacing: 12)` | #if os(iOS) |
| [1207](../../../Sources/Coda/Features/IOSMainWindow.swift#L1207) | 字号/字体 | `.font(.system(size: 32))` | #if os(iOS) |
| [1209](../../../Sources/Coda/Features/IOSMainWindow.swift#L1209) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 2)` | #if os(iOS) |
| [1211](../../../Sources/Coda/Features/IOSMainWindow.swift#L1211) | 字号/字体 | `.font(.headline)` | #if os(iOS) |
| [1214](../../../Sources/Coda/Features/IOSMainWindow.swift#L1214) | 字号/字体 | `.font(.caption)` | #if os(iOS) |
| [1218](../../../Sources/Coda/Features/IOSMainWindow.swift#L1218) | 内边距 | `.padding(.vertical, 6)` | #if os(iOS) |
| [1221](../../../Sources/Coda/Features/IOSMainWindow.swift#L1221) | 字号/字体 | `.font(.system(size: 16, weight: .semibold))` | #if os(iOS) |
| [1243](../../../Sources/Coda/Features/IOSMainWindow.swift#L1243) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [1247](../../../Sources/Coda/Features/IOSMainWindow.swift#L1247) | 容器布局/默认间距 | `Spacer()` | #if os(iOS) |
| [1252](../../../Sources/Coda/Features/IOSMainWindow.swift#L1252) | 字号/字体 | `.font(.system(size: 13, weight: .semibold))` | #if os(iOS) |
| [1315](../../../Sources/Coda/Features/IOSMainWindow.swift#L1315) | 内边距 | `.padding(.vertical, 8)` | #if os(iOS) |
| [1316](../../../Sources/Coda/Features/IOSMainWindow.swift#L1316) | 列表内边距 | `.listRowInsets(EdgeInsets())` | #if os(iOS) |
| [1331](../../../Sources/Coda/Features/IOSMainWindow.swift#L1331) | 内边距 | `.padding(.vertical, 8)` | #if os(iOS) |
| [1332](../../../Sources/Coda/Features/IOSMainWindow.swift#L1332) | 列表内边距 | `.listRowInsets(EdgeInsets())` | #if os(iOS) |
| [1342](../../../Sources/Coda/Features/IOSMainWindow.swift#L1342) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 6)` | #if os(iOS) |
| [1344](../../../Sources/Coda/Features/IOSMainWindow.swift#L1344) | 容器布局/默认间距 | `HStack(spacing: 8)` | #if os(iOS) |
| [1345](../../../Sources/Coda/Features/IOSMainWindow.swift#L1345) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 4)` | #if os(iOS) |
| [1361](../../../Sources/Coda/Features/IOSMainWindow.swift#L1361) | 字号/字体 | `.font(.caption)` | #if os(iOS) |
| [1364](../../../Sources/Coda/Features/IOSMainWindow.swift#L1364) | 字号/字体 | `.font(.system(size: 13))` | #if os(iOS) |

## MainWindow

源码：`Sources/Kumone/Features/MainWindow.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [11](../../../Sources/Coda/Features/MainWindow.swift#L11) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.legacyIPadSystemInsets) private var legacySystemInsets` | #if os(iOS) |
| [14](../../../Sources/Coda/Features/MainWindow.swift#L14) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var horizontalSizeClass` | #if os(iOS) |
| [18](../../../Sources/Coda/Features/MainWindow.swift#L18) | 尺寸/字体/间距声明或原生字体 | `@State private var activeSizeClass: UserInterfaceSizeClass?` | #if os(iOS) |
| [20](../../../Sources/Coda/Features/MainWindow.swift#L20) | 尺寸/字体/间距声明或原生字体 | `@State private var viewportSize = SceneViewportSize()` | #if os(iOS) |
| [65](../../../Sources/Coda/Features/MainWindow.swift#L65) | 尺寸/字体/间距声明或原生字体 | `let size = viewportSize.resolved(viewport.size, active: scenePhase == .active)` | #if os(iOS) |
| [71](../../../Sources/Coda/Features/MainWindow.swift#L71) | 尺寸约束 | `.frame(width: size.width, height: size.height)` | #if os(iOS) |
| [194](../../../Sources/Coda/Features/MainWindow.swift#L194) | 内边距 | `.padding(.top, 12)` | 共享/运行时分支见源码 |
| [211](../../../Sources/Coda/Features/MainWindow.swift#L211) | 容器布局/默认间距 | `ZStack(alignment: .bottom)` | #if os(iOS) |
| [225](../../../Sources/Coda/Features/MainWindow.swift#L225) | 尺寸/字体/间距声明或原生字体 | `let sidebarWidth = min(Theme.Layout.sidebarWidth, viewport.size.width * 0.32)` | #if os(macOS) |
| [226](../../../Sources/Coda/Features/MainWindow.swift#L226) | 尺寸/字体/间距声明或原生字体 | `let leadingClearance = sidebarWidth + 20` | #if os(macOS) |
| [227](../../../Sources/Coda/Features/MainWindow.swift#L227) | 自定义组件/原生构造尺寸参数 | `Layout(frame: CGRect( x: leadingClearance, y: 0, width: max(0, viewport.size.width - leadingClearance), height: viewport.size.height))` | #if os(macOS) |
| [227](../../../Sources/Coda/Features/MainWindow.swift#L227) | 自定义组件/原生构造尺寸参数 | `CGRect( x: leadingClearance, y: 0, width: max(0, viewport.size.width - leadingClearance), height: viewport.size.height)` | #if os(macOS) |
| [231](../../../Sources/Coda/Features/MainWindow.swift#L231) | 容器布局/默认间距 | `ZStack(alignment: .leading)` | #if os(macOS) |
| [233](../../../Sources/Coda/Features/MainWindow.swift#L233) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | #if os(macOS) |
| [248](../../../Sources/Coda/Features/MainWindow.swift#L248) | 尺寸约束 | `.frame(width: sidebarWidth)` | #if os(macOS) |
| [250](../../../Sources/Coda/Features/MainWindow.swift#L250) | 内边距 | `.padding(.leading, 10)` | #if os(macOS) |
| [251](../../../Sources/Coda/Features/MainWindow.swift#L251) | 内边距 | `.padding(.top, 38)` | #if os(macOS) |
| [252](../../../Sources/Coda/Features/MainWindow.swift#L252) | 内边距 | `.padding(.bottom, 10)` | #if os(macOS) |
| [268](../../../Sources/Coda/Features/MainWindow.swift#L268) | 尺寸/字体/间距声明或原生字体 | `let sidebarWidth = min(Theme.Layout.sidebarWidth, max(180, viewport.size.width * 0.32))` | #if os(iOS) |
| [269](../../../Sources/Coda/Features/MainWindow.swift#L269) | 尺寸/字体/间距声明或原生字体 | `let leadingClearance = sidebarWidth + 20` | #if os(iOS) |
| [270](../../../Sources/Coda/Features/MainWindow.swift#L270) | 自定义组件/原生构造尺寸参数 | `Layout(frame: CGRect( x: leadingClearance, y: 0, width: max(0, viewport.size.width - leadingClearance), height: viewport.size.height))` | #if os(iOS) |
| [270](../../../Sources/Coda/Features/MainWindow.swift#L270) | 自定义组件/原生构造尺寸参数 | `CGRect( x: leadingClearance, y: 0, width: max(0, viewport.size.width - leadingClearance), height: viewport.size.height)` | #if os(iOS) |
| [274](../../../Sources/Coda/Features/MainWindow.swift#L274) | 容器布局/默认间距 | `ZStack(alignment: .leading)` | #if os(iOS) |
| [276](../../../Sources/Coda/Features/MainWindow.swift#L276) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | #if os(iOS) |
| [293](../../../Sources/Coda/Features/MainWindow.swift#L293) | 尺寸约束 | `.frame(width: sidebarWidth)` | #if os(iOS) |
| [294](../../../Sources/Coda/Features/MainWindow.swift#L294) | 内边距 | `.padding(.top, legacySystemInsets.top + 10)` | #if os(iOS) |
| [295](../../../Sources/Coda/Features/MainWindow.swift#L295) | 内边距 | `.padding(.bottom, legacySystemInsets.bottom + legacyKeyboardOverlap + 10)` | #if os(iOS) |
| [296](../../../Sources/Coda/Features/MainWindow.swift#L296) | 内边距 | `.padding(.leading, 10)` | #if os(iOS) |
| [300](../../../Sources/Coda/Features/MainWindow.swift#L300) | 内边距 | `.padding(.bottom, legacySystemInsets.bottom + legacyKeyboardOverlap)` | #if os(iOS) |
| [344](../../../Sources/Coda/Features/MainWindow.swift#L344) | 导航列宽 | `.navigationSplitViewColumnWidth(min: 300, ideal: 332, max: 360)` | #if os(iOS) |
| [541](../../../Sources/Coda/Features/MainWindow.swift#L541) | 尺寸/字体/间距声明或原生字体 | `let titlebarHeight = window.frame.height - window.contentLayoutRect.height` | #if os(macOS) |
| [543](../../../Sources/Coda/Features/MainWindow.swift#L543) | 自定义组件/原生构造尺寸参数 | `NSRect( x: frameView.bounds.minX, y: frameView.isFlipped ? frameView.bounds.minY : frameView.bounds.maxY - titlebarHeight, width: frameView.bounds.width, height: titlebarHeight )` | #if os(macOS) |
| [693](../../../Sources/Coda/Features/MainWindow.swift#L693) | 字号/字体 | `.font(.system(size: 12.5, weight: .medium))` | 共享/运行时分支见源码 |
| [694](../../../Sources/Coda/Features/MainWindow.swift#L694) | 内边距 | `.padding(.horizontal, 16)` | 共享/运行时分支见源码 |
| [695](../../../Sources/Coda/Features/MainWindow.swift#L695) | 内边距 | `.padding(.vertical, 9)` | 共享/运行时分支见源码 |
| [751](../../../Sources/Coda/Features/MainWindow.swift#L751) | 容器布局/默认间距 | `VStack(spacing: 16)` | 共享/运行时分支见源码 |
| [753](../../../Sources/Coda/Features/MainWindow.swift#L753) | 字号/字体 | `.font(.system(size: 48))` | 共享/运行时分支见源码 |
| [756](../../../Sources/Coda/Features/MainWindow.swift#L756) | 字号/字体 | `.font(.headline)` | 共享/运行时分支见源码 |
| [761](../../../Sources/Coda/Features/MainWindow.swift#L761) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |

## Navigation

源码：`Sources/Kumone/Features/Navigation.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [55](../../../Sources/Coda/Features/Navigation.swift#L55) | 内边距 | `.padding(.top, 12)` | 共享/运行时分支见源码 |
| [56](../../../Sources/Coda/Features/Navigation.swift#L56) | 内边距 | `.padding(.bottom, Theme.Layout.playerChromeClearance + 10)` | 共享/运行时分支见源码 |
| [57](../../../Sources/Coda/Features/Navigation.swift#L57) | 内边距 | `.padding(.trailing, 16)` | 共享/运行时分支见源码 |
| [69](../../../Sources/Coda/Features/Navigation.swift#L69) | 尺寸约束 | `.frame(width: geometry.layout.width)` | #if os(macOS) |
| [165](../../../Sources/Coda/Features/Navigation.swift#L165) | 安全区插入 | `.safeAreaInset(edge: .top, alignment: .leading, spacing: 12)` | #if os(iOS) / #else |
| [167](../../../Sources/Coda/Features/Navigation.swift#L167) | 内边距 | `.padding(.leading, 20)` | #if os(iOS) / #else |
| [255](../../../Sources/Coda/Features/Navigation.swift#L255) | 内边距 | `.padding(.leading, 20)` | #if os(iOS) |
| [295](../../../Sources/Coda/Features/Navigation.swift#L295) | 尺寸/字体/间距声明或原生字体 | `let defaultPadding: CGFloat` | #if os(iOS) |
| [299](../../../Sources/Coda/Features/Navigation.swift#L299) | 内边距 | `.padding(.top, UIDevice.current.userInterfaceIdiom == .pad && chrome == .legacy ? 0 : defaultPadding)` | #if os(iOS) |
| [310](../../../Sources/Coda/Features/Navigation.swift#L310) | 内边距 | `.padding(.bottom, Theme.Layout.iPadPlayerChromeClearance)` | #if os(iOS) |
| [312](../../../Sources/Coda/Features/Navigation.swift#L312) | 安全区插入 | `.safeAreaInset(edge: .bottom, spacing: 0)` | #if os(iOS) |
| [313](../../../Sources/Coda/Features/Navigation.swift#L313) | 尺寸约束 | `.frame(height: Theme.Layout.iPadPlayerChromeClearance)` | #if os(iOS) |
| [324](../../../Sources/Coda/Features/Navigation.swift#L324) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.legacyIPadSystemInsets) private var systemInsets` | #if os(iOS) |
| [334](../../../Sources/Coda/Features/Navigation.swift#L334) | 内边距 | `.padding(.top, systemInsets.top + 10)` | #if os(iOS) |
| [335](../../../Sources/Coda/Features/Navigation.swift#L335) | 内边距 | `.padding(.bottom, systemInsets.bottom + keyboardOverlap)` | #if os(iOS) |
| [336](../../../Sources/Coda/Features/Navigation.swift#L336) | 内边距 | `.padding(.leading, geometry.layout.leadingInset)` | #if os(iOS) |
| [351](../../../Sources/Coda/Features/Navigation.swift#L351) | 字号/字体 | `.font(.body.weight(.semibold))` | #if os(iOS) |
| [352](../../../Sources/Coda/Features/Navigation.swift#L352) | 尺寸约束 | `.frame(width: 44, height: 44)` | #if os(iOS) |
| [373](../../../Sources/Coda/Features/Navigation.swift#L373) | 尺寸约束 | `.frame(height: Theme.Layout.scrollBreathingMargin)` | #if os(iOS) |
| [377](../../../Sources/Coda/Features/Navigation.swift#L377) | 尺寸约束 | `.frame(height: Theme.Layout.scrollBreathingMargin)` | #if os(iOS) |
| [381](../../../Sources/Coda/Features/Navigation.swift#L381) | 尺寸约束 | `.frame( height: player.hasCurrentTrack ? Theme.Layout.FloatingChrome.fullChromeClearance : Theme.Layout.FloatingChrome.tabBarClearance )` | #if os(iOS) |
| [388](../../../Sources/Coda/Features/Navigation.swift#L388) | 尺寸约束 | `.frame( height: Theme.Layout.playerChromeClearance + Theme.Layout.scrollBreathingMargin )` | #if os(iOS) / #else |
| [415](../../../Sources/Coda/Features/Navigation.swift#L415) | 内边距 | `.padding(.leading, geometry.layout.leadingInset)` | #if os(macOS) |
| [416](../../../Sources/Coda/Features/Navigation.swift#L416) | 内边距 | `.padding(.top, 38)` | #if os(macOS) |
| [433](../../../Sources/Coda/Features/Navigation.swift#L433) | 字号/字体 | `.font(.body.weight(.semibold))` | #if os(macOS) |
| [434](../../../Sources/Coda/Features/Navigation.swift#L434) | 尺寸约束 | `.frame(width: 36, height: 36)` | #if os(macOS) |

## AutoMixSettingsSection

源码：`Sources/Kumone/Features/Pages/AutoMixSettingsSection.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [11](../../../Sources/Coda/Features/Pages/AutoMixSettingsSection.swift#L11) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(macOS) |
| [16](../../../Sources/Coda/Features/Pages/AutoMixSettingsSection.swift#L16) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | #if os(macOS) |
| [19](../../../Sources/Coda/Features/Pages/AutoMixSettingsSection.swift#L19) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(macOS) |
| [44](../../../Sources/Coda/Features/Pages/AutoMixSettingsSection.swift#L44) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | #if os(macOS) |
| [47](../../../Sources/Coda/Features/Pages/AutoMixSettingsSection.swift#L47) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(macOS) |
| [56](../../../Sources/Coda/Features/Pages/AutoMixSettingsSection.swift#L56) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(macOS) |

## CollectionsView

源码：`Sources/Kumone/Features/Pages/CollectionsView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [20](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L20) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [27](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L27) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [30](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L30) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [39](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L39) | 尺寸约束 | `.frame(maxWidth: 240)` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L53) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [68](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L68) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [73](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L73) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [84](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L84) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [138](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L138) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [146](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L146) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 300)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L172) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [175](../../../Sources/Coda/Features/Pages/CollectionsView.swift#L175) | 内边距 | `.padding(.top, Theme.Spacing.component)` | 共享/运行时分支见源码 |

## DailySongsView

源码：`Sources/Kumone/Features/Pages/DailySongsView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [32](../../../Sources/Coda/Features/Pages/DailySongsView.swift#L32) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: usesMeloXHeader ? 16 : 20)` | 共享/运行时分支见源码 |
| [50](../../../Sources/Coda/Features/Pages/DailySongsView.swift#L50) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [54](../../../Sources/Coda/Features/Pages/DailySongsView.swift#L54) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [88](../../../Sources/Coda/Features/Pages/DailySongsView.swift#L88) | 安全区插入 | `.safeAreaInset(edge: .top)` | 共享/运行时分支见源码 |

## DownloadedMusicView

源码：`Sources/Kumone/Features/Pages/DownloadedMusicView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [32](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L32) | 自定义组件/原生构造尺寸参数 | `TrackListScrollView(trackIDs: visible.map(\.id), spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [33](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L33) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [55](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L55) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [59](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L59) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [115](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L115) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [117](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L117) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [120](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L120) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [136](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L136) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [139](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L139) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [140](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L140) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [160](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L160) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [162](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L162) | 容器布局/默认间距 | `Spacer(minLength: 12)` | 共享/运行时分支见源码 |
| [165](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L165) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [169](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L169) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [175](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L175) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [177](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L177) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [178](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L178) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L183) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [190](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L190) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [212](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L212) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [216](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L216) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [217](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L217) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [237](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L237) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [238](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L238) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [240](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L240) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [241](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L241) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [261](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L261) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [262](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L262) | 尺寸约束 | `.frame(width: 30, height: 30)` | 共享/运行时分支见源码 |
| [272](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L272) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [273](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L273) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [277](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L277) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [279](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L279) | 容器布局/默认间距 | `LazyVStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [284](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L284) | 内边距 | `.padding(.horizontal, Theme.Layout.trackListInset)` | 共享/运行时分支见源码 |
| [302](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L302) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [303](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L303) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [303](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L303) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [316](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L316) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var artworkSize: CGFloat = 42` | 共享/运行时分支见源码 |
| [322](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L322) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [324](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L324) | 尺寸约束 | `.frame(width: artworkSize, height: artworkSize)` | 共享/运行时分支见源码 |
| [326](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L326) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [327](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L327) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [328](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L328) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [329](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L329) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [330](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L330) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [332](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L332) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [351](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L351) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [353](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L353) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [358](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L358) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [361](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L361) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [365](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L365) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [374](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L374) | 字号/字体 | `.font(.callout.weight(.medium))` | 共享/运行时分支见源码 |
| [376](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L376) | 尺寸约束 | `.frame(width: 28, height: 28)` | #if os(macOS) |
| [378](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L378) | 尺寸约束 | `.frame(width: 44, height: 44)` | #if os(macOS) / #else |
| [498](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L498) | 自定义组件/原生构造尺寸参数 | `DownloadButtonIcon(isActive: isActive \|\| isSubmitting, isComplete: isComplete && !canResume && !isActive, progress: fraction, size: compact ? 21 : 19, symbolSize: compact ? 16 : 14, completedSymbol: "checkmark")` | 共享/运行时分支见源码 |
| [502](../../../Sources/Coda/Features/Pages/DownloadedMusicView.swift#L502) | 尺寸约束 | `.frame(width: compact ? 38 : 34, height: compact ? 38 : 34)` | 共享/运行时分支见源码 |

## FMView

源码：`Sources/Kumone/Features/Pages/FMView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [19](../../../Sources/Coda/Features/Pages/FMView.swift#L19) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [38](../../../Sources/Coda/Features/Pages/FMView.swift#L38) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Pages/FMView.swift#L62) | 尺寸/字体/间距声明或原生字体 | `let spacing: CGFloat = isPhone && geo.size.height < 520 ? Theme.Spacing.control : Theme.Spacing.section` | 共享/运行时分支见源码 |
| [64](../../../Sources/Coda/Features/Pages/FMView.swift#L64) | 容器布局/默认间距 | `VStack(spacing: spacing)` | 共享/运行时分支见源码 |
| [65](../../../Sources/Coda/Features/Pages/FMView.swift#L65) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [67](../../../Sources/Coda/Features/Pages/FMView.swift#L67) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [70](../../../Sources/Coda/Features/Pages/FMView.swift#L70) | 尺寸约束 | `.frame(width: coverDimension, height: coverDimension)` | 共享/运行时分支见源码 |
| [76](../../../Sources/Coda/Features/Pages/FMView.swift#L76) | 尺寸约束 | `.frame(width: coverDimension, height: coverDimension)` | 共享/运行时分支见源码 |
| [79](../../../Sources/Coda/Features/Pages/FMView.swift#L79) | 字号/字体 | `.font( .system( size: max(32, coverDimension * 0.25), weight: .light ) )` | 共享/运行时分支见源码 |
| [92](../../../Sources/Coda/Features/Pages/FMView.swift#L92) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [93](../../../Sources/Coda/Features/Pages/FMView.swift#L93) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [95](../../../Sources/Coda/Features/Pages/FMView.swift#L95) | 字号/字体 | `.font(isPhone && geo.size.height < 520 ? Theme.Typography.cardTitle : Theme.Typography.detailTitle)` | 共享/运行时分支见源码 |
| [102](../../../Sources/Coda/Features/Pages/FMView.swift#L102) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [106](../../../Sources/Coda/Features/Pages/FMView.swift#L106) | 尺寸约束 | `.frame(maxWidth: 420)` | 共享/运行时分支见源码 |
| [115](../../../Sources/Coda/Features/Pages/FMView.swift#L115) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [117](../../../Sources/Coda/Features/Pages/FMView.swift#L117) | 内边距 | `.padding(.horizontal, Theme.Spacing.page)` | 共享/运行时分支见源码 |
| [118](../../../Sources/Coda/Features/Pages/FMView.swift#L118) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [125](../../../Sources/Coda/Features/Pages/FMView.swift#L125) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [126](../../../Sources/Coda/Features/Pages/FMView.swift#L126) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [128](../../../Sources/Coda/Features/Pages/FMView.swift#L128) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/Features/Pages/FMView.swift#L129) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [134](../../../Sources/Coda/Features/Pages/FMView.swift#L134) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [139](../../../Sources/Coda/Features/Pages/FMView.swift#L139) | 字号/字体 | `.font(.system(size: 17, weight: .medium))` | 共享/运行时分支见源码 |
| [141](../../../Sources/Coda/Features/Pages/FMView.swift#L141) | 尺寸约束 | `.frame(width: 48, height: 48)` | 共享/运行时分支见源码 |
| [150](../../../Sources/Coda/Features/Pages/FMView.swift#L150) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [153](../../../Sources/Coda/Features/Pages/FMView.swift#L153) | 尺寸约束 | `.frame(width: 64, height: 64)` | 共享/运行时分支见源码 |
| [156](../../../Sources/Coda/Features/Pages/FMView.swift#L156) | 字号/字体 | `.font(.system(size: 24, weight: .bold))` | 共享/运行时分支见源码 |
| [167](../../../Sources/Coda/Features/Pages/FMView.swift#L167) | 字号/字体 | `.font(.system(size: 17, weight: .medium))` | 共享/运行时分支见源码 |
| [169](../../../Sources/Coda/Features/Pages/FMView.swift#L169) | 尺寸约束 | `.frame(width: 48, height: 48)` | 共享/运行时分支见源码 |
| [176](../../../Sources/Coda/Features/Pages/FMView.swift#L176) | 自定义组件/原生构造尺寸参数 | `LikeButton(trackID: track.id, size: 16)` | 共享/运行时分支见源码 |
| [177](../../../Sources/Coda/Features/Pages/FMView.swift#L177) | 尺寸约束 | `.frame(width: 48, height: 48)` | 共享/运行时分支见源码 |
| [184](../../../Sources/Coda/Features/Pages/FMView.swift#L184) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [186](../../../Sources/Coda/Features/Pages/FMView.swift#L186) | 字号/字体 | `.font(.system(size: 52, weight: .light))` | 共享/运行时分支见源码 |
| [189](../../../Sources/Coda/Features/Pages/FMView.swift#L189) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [191](../../../Sources/Coda/Features/Pages/FMView.swift#L191) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |

## IOSUpdater

源码：`Sources/Kumone/Features/Pages/IOSUpdater.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [143](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L143) | 自定义组件/原生构造尺寸参数 | `CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)` | #if os(iOS) |
| [198](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L198) | 容器布局/默认间距 | `VStack(spacing: 22)` | #if os(iOS) |
| [206](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L206) | 字号/字体 | `.font(.system(size: 44))` | #if os(iOS) |
| [207](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L207) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | #if os(iOS) |
| [212](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L212) | 字号/字体 | `.font(.system(size: 44))` | #if os(iOS) |
| [213](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L213) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.tight)` | #if os(iOS) |
| [214](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L214) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | #if os(iOS) |
| [216](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L216) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [219](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L219) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [224](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L224) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | #if os(iOS) |
| [231](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L231) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | #if os(iOS) |
| [235](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L235) | 字号/字体 | `.font(.system(size: 40))` | #if os(iOS) |
| [236](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L236) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | #if os(iOS) |
| [238](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L238) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [245](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L245) | 字号/字体 | `.font(.system(size: 44))` | #if os(iOS) |
| [246](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L246) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | #if os(iOS) |
| [247](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L247) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [252](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L252) | 字号/字体 | `.font(.system(size: 40))` | #if os(iOS) |
| [253](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L253) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) |
| [261](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L261) | 内边距 | `.padding(Theme.Spacing.largeSection)` | #if os(iOS) |
| [262](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L262) | 尺寸约束 | `.frame(maxWidth: .infinity)` | #if os(iOS) |
| [269](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L269) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | #if os(iOS) |
| [270](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L270) | 尺寸约束 | `.frame(maxWidth: .infinity)` | #if os(iOS) |
| [270](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L270) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | #if os(iOS) |
| [281](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L281) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) |
| [294](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L294) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [304](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L304) | 字号/字体 | `.font(Theme.Typography.sectionTitle.bold())` | #if os(iOS) |
| [307](../../../Sources/Coda/Features/Pages/IOSUpdater.swift#L307) | 尺寸约束 | `.frame(width: 96, height: 96)` | #if os(iOS) |

## LibraryPages

源码：`Sources/Kumone/Features/Pages/LibraryPages.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [23](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L23) | 自定义组件/原生构造尺寸参数 | `TrackListScrollView(trackIDs: displayedRecords.map { $0.song.id }, style: .compact, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [24](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L24) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [33](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L33) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [34](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L34) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [40](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L40) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [42](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L42) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [43](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L43) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [49](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L49) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [50](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L50) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [57](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L57) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L62) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 300)` | 共享/运行时分支见源码 |
| [65](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L65) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [80](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L80) | 安全区插入 | `.safeAreaInset(edge: .top)` | 共享/运行时分支见源码 |
| [112](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L112) | 尺寸/字体/间距声明或原生字体 | `private var sizeInfo: String? { guard let size = resource.value?.size, let max = resource.value?.maxSize, max > 0 else { return nil } let used = String(format: "%.1f", Double(size) / 1_073_741_824) let total = String(format: "%.0f", Double(max) / 1_073_741_824) return String(localized: "已使用 \(used) GB / \(total) GB") }` | 共享/运行时分支见源码 |
| [113](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L113) | 尺寸/字体/间距声明或原生字体 | `guard let size = resource.value?.size, let max = resource.value?.maxSize, max > 0 else { return nil }` | 共享/运行时分支见源码 |
| [126](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L126) | 自定义组件/原生构造尺寸参数 | `TrackListScrollView(trackIDs: displayed.map(\.id), style: .compact, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [127](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L127) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [136](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L136) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [137](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L137) | 尺寸/字体/间距声明或原生字体 | `if let sizeInfo { Text(sizeInfo) .font(Theme.Typography.caption) .foregroundStyle(.secondary) }` | 共享/运行时分支见源码 |
| [139](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L139) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [142](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L142) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [147](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L147) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [149](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L149) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [150](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L150) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [156](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L156) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [157](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L157) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [168](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L168) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [185](../../../Sources/Coda/Features/Pages/LibraryPages.swift#L185) | 安全区插入 | `.safeAreaInset(edge: .top)` | 共享/运行时分支见源码 |

## LoginSheet

源码：`Sources/Kumone/Features/Pages/LoginSheet.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [42](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L42) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [43](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L43) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [45](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L45) | 字号/字体 | `.font(Theme.Typography.sectionTitle)` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L53) | 尺寸约束 | `.frame(width: 220)` | 共享/运行时分支见源码 |
| [54](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L54) | 内边距 | `.padding(.top, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [56](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L56) | 内边距 | `.padding(.top, Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L62) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [75](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L75) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [77](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L77) | 内边距 | `.padding(.bottom, Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [79](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L79) | 尺寸约束 | `.frame(width: 320)` | 共享/运行时分支见源码 |
| [81](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L81) | 内边距 | `.padding(.top, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [103](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L103) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [105](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L105) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [108](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L108) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [111](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L111) | 尺寸约束 | `.frame(width: 208, height: 208)` | 共享/运行时分支见源码 |
| [118](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L118) | 尺寸约束 | `.frame(width: 180, height: 180)` | 共享/运行时分支见源码 |
| [125](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L125) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L129) | 字号/字体 | `.font(.system(size: 34))` | 共享/运行时分支见源码 |
| [132](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L132) | 字号/字体 | `.font(Theme.Typography.caption.weight(.medium))` | 共享/运行时分支见源码 |
| [141](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L141) | 字号/字体 | `.font(.system(size: 34))` | 共享/运行时分支见源码 |
| [144](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L144) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [146](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L146) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [152](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L152) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [173](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L173) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [178](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L178) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [181](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L181) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | #if os(iOS) |
| [259](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L259) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [260](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L260) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [262](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L262) | 字号/字体 | `.font(.system(size: 11))` | 共享/运行时分支见源码 |
| [264](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L264) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [268](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L268) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [269](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L269) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [270](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L270) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [272](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L272) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [274](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L274) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [275](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L275) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [277](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L277) | 字号/字体 | `.font(.system(size: 15))` | 共享/运行时分支见源码 |
| [277](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L277) | 尺寸约束 | `.frame(width: 20)` | 共享/运行时分支见源码 |
| [278](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L278) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [279](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L279) | 尺寸约束 | `.frame(width: 1, height: 20)` | 共享/运行时分支见源码 |
| [280](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L280) | 容器布局/默认间距 | `TextField("手机号", text: $phone)` | 共享/运行时分支见源码 |
| [281](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L281) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [288](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L288) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [289](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L289) | 容器布局/默认间距 | `TextField("验证码", text: $code)` | 共享/运行时分支见源码 |
| [290](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L290) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [306](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L306) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [313](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L313) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [317](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L317) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [318](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L318) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [331](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L331) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [332](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L332) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: Theme.Layout.controlHeight)` | 共享/运行时分支见源码 |
| [339](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L339) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [339](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L339) | 内边距 | `.padding(.top, Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [341](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L341) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [392](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L392) | 尺寸/字体/间距声明或原生字体 | `let scaled = output.transformed(by: CGAffineTransform(scaleX: 12, y: 12))` | 共享/运行时分支见源码 |
| [396](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L396) | 自定义组件/原生构造尺寸参数 | `NSImage(cgImage: cgImage, size: NSSize(width: 180, height: 180))` | #if os(macOS) |
| [396](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L396) | 自定义组件/原生构造尺寸参数 | `NSSize(width: 180, height: 180)` | #if os(macOS) |
| [406](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L406) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [406](../../../Sources/Coda/Features/Pages/LoginSheet.swift#L406) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | 共享/运行时分支见源码 |

## SearchView

源码：`Sources/Kumone/Features/Pages/SearchView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [156](../../../Sources/Coda/Features/Pages/SearchView.swift#L156) | 容器布局/默认间距 | `VStack(spacing: 0)` | #if os(iOS) / #else |
| [158](../../../Sources/Coda/Features/Pages/SearchView.swift#L158) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | #if os(iOS) / #else |
| [159](../../../Sources/Coda/Features/Pages/SearchView.swift#L159) | 页面顶部留白 | `.pageHeaderTopPadding(8)` | #if os(iOS) / #else |
| [160](../../../Sources/Coda/Features/Pages/SearchView.swift#L160) | 内边距 | `.padding(.bottom, Theme.Spacing.component)` | #if os(iOS) / #else |
| [167](../../../Sources/Coda/Features/Pages/SearchView.swift#L167) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/Features/Pages/SearchView.swift#L170) | 容器布局/默认间距 | `TextField("搜索歌曲、歌手、专辑、歌单", text: $searchText)` | 共享/运行时分支见源码 |
| [185](../../../Sources/Coda/Features/Pages/SearchView.swift#L185) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [191](../../../Sources/Coda/Features/Pages/SearchView.swift#L191) | 内边距 | `.padding(.leading, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [192](../../../Sources/Coda/Features/Pages/SearchView.swift#L192) | 内边距 | `.padding(.trailing, searchText.isEmpty ? 16 : 4)` | 共享/运行时分支见源码 |
| [193](../../../Sources/Coda/Features/Pages/SearchView.swift#L193) | 尺寸约束 | `.frame(minHeight: 48)` | 共享/运行时分支见源码 |
| [214](../../../Sources/Coda/Features/Pages/SearchView.swift#L214) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.section)` | #if os(macOS) |
| [217](../../../Sources/Coda/Features/Pages/SearchView.swift#L217) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 300)` | #if os(macOS) |
| [222](../../../Sources/Coda/Features/Pages/SearchView.swift#L222) | 内边距 | `.padding(.horizontal, Theme.Layout.trackListInset)` | #if os(macOS) |
| [236](../../../Sources/Coda/Features/Pages/SearchView.swift#L236) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [240](../../../Sources/Coda/Features/Pages/SearchView.swift#L240) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | #if os(iOS) |
| [241](../../../Sources/Coda/Features/Pages/SearchView.swift#L241) | 页面顶部留白 | `.pageHeaderTopPadding(8)` | #if os(iOS) |
| [249](../../../Sources/Coda/Features/Pages/SearchView.swift#L249) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 300)` | 共享/运行时分支见源码 |
| [269](../../../Sources/Coda/Features/Pages/SearchView.swift#L269) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [270](../../../Sources/Coda/Features/Pages/SearchView.swift#L270) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [274](../../../Sources/Coda/Features/Pages/SearchView.swift#L274) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [276](../../../Sources/Coda/Features/Pages/SearchView.swift#L276) | 字号/字体 | `.font(.system(size: 48, weight: .light))` | 共享/运行时分支见源码 |
| [278](../../../Sources/Coda/Features/Pages/SearchView.swift#L278) | 内边距 | `.padding(.top, 60)` | 共享/运行时分支见源码 |
| [280](../../../Sources/Coda/Features/Pages/SearchView.swift#L280) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [283](../../../Sources/Coda/Features/Pages/SearchView.swift#L283) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [286](../../../Sources/Coda/Features/Pages/SearchView.swift#L286) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [287](../../../Sources/Coda/Features/Pages/SearchView.swift#L287) | 内边距 | `.padding(.horizontal, Theme.Spacing.component * 2)` | 共享/运行时分支见源码 |
| [306](../../../Sources/Coda/Features/Pages/SearchView.swift#L306) | 内边距 | `.padding(.horizontal, Theme.Layout.trackListInset)` | #if os(iOS) / #else |
| [315](../../../Sources/Coda/Features/Pages/SearchView.swift#L315) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [319](../../../Sources/Coda/Features/Pages/SearchView.swift#L319) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [340](../../../Sources/Coda/Features/Pages/SearchView.swift#L340) | 尺寸约束 | `.frame(minHeight: 300)` | 共享/运行时分支见源码 |
| [348](../../../Sources/Coda/Features/Pages/SearchView.swift#L348) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [353](../../../Sources/Coda/Features/Pages/SearchView.swift#L353) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [358](../../../Sources/Coda/Features/Pages/SearchView.swift#L358) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [367](../../../Sources/Coda/Features/Pages/SearchView.swift#L367) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [369](../../../Sources/Coda/Features/Pages/SearchView.swift#L369) | 尺寸约束 | `.frame(width: 128, height: 128)` | 共享/运行时分支见源码 |
| [372](../../../Sources/Coda/Features/Pages/SearchView.swift#L372) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [376](../../../Sources/Coda/Features/Pages/SearchView.swift#L376) | 尺寸约束 | `.frame(width: 140)` | 共享/运行时分支见源码 |

## SettingsView

源码：`Sources/Kumone/Features/Pages/SettingsView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [36](../../../Sources/Coda/Features/Pages/SettingsView.swift#L36) | 尺寸约束 | `.frame(width: 520, height: 620)` | #if os(macOS) |
| [45](../../../Sources/Coda/Features/Pages/SettingsView.swift#L45) | 容器布局/默认间距 | `Form { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [49](../../../Sources/Coda/Features/Pages/SettingsView.swift#L49) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [83](../../../Sources/Coda/Features/Pages/SettingsView.swift#L83) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(macOS) |
| [119](../../../Sources/Coda/Features/Pages/SettingsView.swift#L119) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [132](../../../Sources/Coda/Features/Pages/SettingsView.swift#L132) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [136](../../../Sources/Coda/Features/Pages/SettingsView.swift#L136) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [159](../../../Sources/Coda/Features/Pages/SettingsView.swift#L159) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | #if os(macOS) |
| [160](../../../Sources/Coda/Features/Pages/SettingsView.swift#L160) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | #if os(macOS) |
| [199](../../../Sources/Coda/Features/Pages/SettingsView.swift#L199) | 内边距 | `.padding(.top, Theme.Spacing.control)` | #if os(macOS) |

## ShortcutSettingsView

源码：`Sources/Kumone/Features/Pages/ShortcutSettingsView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [15](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L15) | 容器布局/默认间距 | `VStack(spacing: 0)` | #if os(macOS) |
| [28](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L28) | 内边距 | `.padding()` | #if os(macOS) |
| [30](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L30) | 容器布局/默认间距 | `Form { … } // 无显式参数，使用系统/上下文默认值` | #if os(macOS) |
| [72](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L72) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(macOS) |
| [74](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L74) | 容器布局/默认间距 | `Spacer()` | #if os(macOS) |
| [80](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L80) | 字号/字体 | `.font(Theme.Typography.body.monospaced())` | #if os(macOS) |
| [81](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L81) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | #if os(macOS) |
| [82](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L82) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | #if os(macOS) |
| [83](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L83) | 尺寸约束 | `.frame(minWidth: 80)` | #if os(macOS) |
| [108](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L108) | 尺寸约束 | `.frame(width: 0, height: 0)` | #if os(macOS) |
| [111](../../../Sources/Coda/Features/Pages/ShortcutSettingsView.swift#L111) | 内边距 | `.padding(.vertical, Theme.Spacing.micro)` | #if os(macOS) |

## StemModelsSettingsSection

源码：`Sources/Kumone/Features/Pages/StemModelsSettingsSection.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [25](../../../Sources/Coda/Features/Pages/StemModelsSettingsSection.swift#L25) | 容器布局/默认间距 | `HStack(alignment: .firstTextBaseline)` | #if os(macOS) |
| [26](../../../Sources/Coda/Features/Pages/StemModelsSettingsSection.swift#L26) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.micro)` | #if os(macOS) |
| [29](../../../Sources/Coda/Features/Pages/StemModelsSettingsSection.swift#L29) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(macOS) |
| [34](../../../Sources/Coda/Features/Pages/StemModelsSettingsSection.swift#L34) | 尺寸约束 | `.frame(maxWidth: 200)` | #if os(macOS) |
| [37](../../../Sources/Coda/Features/Pages/StemModelsSettingsSection.swift#L37) | 容器布局/默认间距 | `Spacer()` | #if os(macOS) |

## StorageSpaceView

源码：`Sources/Kumone/Features/Pages/StorageSpaceView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [14](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L14) | 容器布局/默认间距 | `Form { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [16](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L16) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [19](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L19) | 容器布局/默认间距 | `HStack(alignment: .firstTextBaseline)` | 共享/运行时分支见源码 |
| [20](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L20) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [21](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L21) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [24](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L24) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [25](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L25) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [31](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L31) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [36](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L36) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [42](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L42) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [49](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L49) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [51](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L51) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [57](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L57) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [59](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L59) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [87](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L87) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [89](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L89) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [95](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L95) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [97](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L97) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [102](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L102) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [104](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L104) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [116](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L116) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [118](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L118) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [126](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L126) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [128](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L128) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [132](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L132) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [173](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L173) | 尺寸/字体/间距声明或原生字体 | `var sizes = [500, 1_000, 2_000, 5_000, 10_000]` | #if os(iOS) |
| [196](../../../Sources/Coda/Features/Pages/StorageSpaceView.swift#L196) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |

## AppleMusicLyricsColumn

源码：`Sources/Kumone/Features/Player/AppleMusicLyricsColumn.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [8](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L8) | 尺寸/字体/间距声明或原生字体 | `let bottomOverlayHeight: CGFloat` | #if os(iOS) |
| [65](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L65) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: rowSpacing(width: viewport.size.width))` | 共享/运行时分支见源码 |
| [66](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L66) | 尺寸约束 | `.frame(height: viewport.size.height * anchor.y)` | 共享/运行时分支见源码 |
| [68](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L68) | 自定义组件/原生构造尺寸参数 | `AppleMusicLyricRow( line: line, isActive: cursor.activeIndices.contains(index), distance: index - (activeIndex ?? 0), isBrowsing: isUserScrolling, followOffset: followOffset, motionResponse: motionResponse, fontSize: primaryFontSize(width: viewport.size.width) )` | 共享/运行时分支见源码 |
| [85](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L85) | 尺寸约束 | `.frame(in: .named("appleMusicLyricContent"))` | 共享/运行时分支见源码 |
| [92](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L92) | 尺寸约束 | `.frame(height: viewport.size.height * (1 - anchor.y))` | 共享/运行时分支见源码 |
| [94](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L94) | 内边距 | `.padding(.horizontal, 28)` | 共享/运行时分支见源码 |
| [100](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L100) | 尺寸约束 | `.frame(in: .named("appleMusicLyricViewport"))` | 共享/运行时分支见源码 |
| [128](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L128) | 尺寸约束 | `.frame(height: lyricsInterface.bottomOverlayHeight)` | #if os(iOS) |
| [257](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L257) | 尺寸/字体/间距声明或原生字体 | `private var lastViewportSize = CGSize.zero` | #if os(iOS) |
| [301](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L301) | 尺寸/字体/间距声明或原生字体 | `let insets = scroll.adjustedContentInset` | #if os(iOS) |
| [345](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L345) | 尺寸/字体/间距声明或原生字体 | `let fontSize: CGFloat` | 共享/运行时分支见源码 |
| [363](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L363) | 尺寸/字体/间距声明或原生字体 | `private var deselectedScale: CGFloat { #if os(iOS) return 0.98 #else return 0.94 #endif }` | 共享/运行时分支见源码 |
| [371](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L371) | 尺寸/字体/间距声明或原生字体 | `private var annotationFont: Font { #if os(iOS) let style: UIFont.TextStyle = settings.lyricsAnnotation == .romaji && line.romaji != nil ? .callout : .title3 return .system(size: UIFont.preferredFont(forTextStyle: style).pointSize, weight: .bold) #else return .system(size: fontSize * 0.55, weight: .semibold) #endif }` | 共享/运行时分支见源码 |
| [375](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L375) | 尺寸/字体/间距声明或原生字体 | `return .system(size: UIFont.preferredFont(forTextStyle: style).pointSize, weight: .bold)` | #if os(iOS) |
| [389](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L389) | 字号/字体 | `.font(annotationFont)` | 共享/运行时分支见源码 |
| [392](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L392) | 内边距 | `.padding(.bottom, 5)` | #if os(iOS) |
| [399](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L399) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: annotationSpacing)` | 共享/运行时分支见源码 |
| [403](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L403) | 自定义组件/原生构造尺寸参数 | `LyricMainText( line: line, isActive: isActive, size: fontSize, weight: .bold, verbatim: settings.verbatimLyrics, inactiveOpacity: 1 )` | 共享/运行时分支见源码 |
| [409](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L409) | 字号/字体 | `.font(annotationFont)` | 共享/运行时分支见源码 |
| [411](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L411) | 内边距 | `.padding(.top, 7)` | #if os(iOS) |
| [412](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L412) | 内边距 | `.padding(.bottom, 4)` | #if os(iOS) |
| [420](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L420) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: minimumRowHeight, alignment: .leading)` | 共享/运行时分支见源码 |
| [444](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L444) | 尺寸/字体/间距声明或原生字体 | `private var annotationSpacing: CGFloat { #if os(iOS) return 0 // Supplemental layers own MeloX's 5 / 7 point gaps. #else return 8 #endif }` | 共享/运行时分支见源码 |
| [452](../../../Sources/Coda/Features/Player/AppleMusicLyricsColumn.swift#L452) | 尺寸/字体/间距声明或原生字体 | `private var minimumRowHeight: CGFloat { #if os(iOS) return 0 #else return 44 #endif }` | 共享/运行时分支见源码 |

## AutoMixDebugPanel

源码：`Sources/Kumone/Features/Player/AutoMixDebugPanel.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [39](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L39) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 0)` | #if os(macOS) && DEBUG |
| [41](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L41) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 14)` | #if os(macOS) && DEBUG |
| [50](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L50) | 内边距 | `.padding(14)` | #if os(macOS) && DEBUG |
| [51](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L51) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | #if os(macOS) && DEBUG |
| [54](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L54) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(macOS) && DEBUG |
| [58](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L58) | 容器布局/默认间距 | `Spacer()` | #if os(macOS) && DEBUG |
| [62](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L62) | 内边距 | `.padding(.horizontal, 14)` | #if os(macOS) && DEBUG |
| [63](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L63) | 内边距 | `.padding(.vertical, 8)` | #if os(macOS) && DEBUG |
| [65](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L65) | 字号/字体 | `.font(.system(size: 11, design: .monospaced))` | #if os(macOS) && DEBUG |
| [69](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L69) | 尺寸约束 | `.frame(minWidth: 560, minHeight: 460)` | #if os(macOS) && DEBUG |
| [100](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L100) | 容器布局/默认间距 | `HStack(alignment: .firstTextBaseline, spacing: 8)` | #if os(macOS) && DEBUG |
| [103](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L103) | 尺寸约束 | `.frame(width: 76, alignment: .leading)` | #if os(macOS) && DEBUG |
| [110](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L110) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [177](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L177) | 字号/字体 | `.font(.caption2)` | #if os(macOS) && DEBUG |
| [183](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L183) | 字号/字体 | `.font(.system(size: 9, design: .monospaced))` | #if os(macOS) && DEBUG |
| [186](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L186) | 内边距 | `.padding(.top, 2)` | #if os(macOS) && DEBUG |
| [193](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L193) | 容器布局/默认间距 | `HStack(spacing: 6)` | #if os(macOS) && DEBUG |
| [194](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L194) | 尺寸约束 | `.frame(width: 128, alignment: .leading)` | #if os(macOS) && DEBUG |
| [195](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L195) | 尺寸约束 | `.frame(width: 92, alignment: .leading)` | #if os(macOS) && DEBUG |
| [197](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L197) | 尺寸约束 | `.frame(width: 34, alignment: .trailing)` | #if os(macOS) && DEBUG |
| [199](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L199) | 尺寸约束 | `.frame(width: 44, alignment: .trailing)` | #if os(macOS) && DEBUG |
| [200](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L200) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [202](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L202) | 字号/字体 | `.font(.system(size: 9, weight: .semibold, design: .monospaced))` | #if os(macOS) && DEBUG |
| [207](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L207) | 容器布局/默认间距 | `HStack(spacing: 6)` | #if os(macOS) && DEBUG |
| [210](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L210) | 尺寸约束 | `.frame(width: 128, alignment: .leading)` | #if os(macOS) && DEBUG |
| [211](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L211) | 尺寸约束 | `.frame(width: 92, alignment: .leading)` | #if os(macOS) && DEBUG |
| [215](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L215) | 尺寸约束 | `.frame(width: 34, alignment: .trailing)` | #if os(macOS) && DEBUG |
| [218](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L218) | 尺寸约束 | `.frame(width: 44, alignment: .trailing)` | #if os(macOS) && DEBUG |
| [219](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L219) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [221](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L221) | 字号/字体 | `.font(.system(size: 10, weight: c.chosen ? .bold : .regular, design: .monospaced))` | #if os(macOS) && DEBUG |
| [289](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L289) | 容器布局/默认间距 | `HStack(spacing: 4)` | #if os(macOS) && DEBUG |
| [292](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L292) | 字号/字体 | `.font(.system(size: 9, weight: .bold, design: .monospaced))` | #if os(macOS) && DEBUG |
| [293](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L293) | 内边距 | `.padding(.horizontal, 5)` | #if os(macOS) && DEBUG |
| [294](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L294) | 内边距 | `.padding(.vertical, 2)` | #if os(macOS) && DEBUG |
| [298](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L298) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [300](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L300) | 内边距 | `.padding(.bottom, 2)` | #if os(macOS) && DEBUG |
| [363](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L363) | 内边距 | `.padding(.vertical, 3)` | #if os(macOS) && DEBUG |
| [365](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L365) | 内边距 | `.padding(.vertical, 3)` | #if os(macOS) && DEBUG |
| [367](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L367) | 内边距 | `.padding(.vertical, 3)` | #if os(macOS) && DEBUG |
| [414](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L414) | 容器布局/默认间距 | `HStack(spacing: 8)` | #if os(macOS) && DEBUG |
| [441](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L441) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [449](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L449) | 容器布局/默认间距 | `HStack(spacing: 8)` | #if os(macOS) && DEBUG |
| [462](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L462) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [479](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L479) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 3)` | #if os(macOS) && DEBUG |
| [480](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L480) | 容器布局/默认间距 | `HStack(spacing: 8)` | #if os(macOS) && DEBUG |
| [484](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L484) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [492](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L492) | 容器布局/默认间距 | `TextField(text: $markNote)` | #if os(macOS) && DEBUG |
| [496](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L496) | 字号/字体 | `.font(.system(size: 11, design: .monospaced))` | #if os(macOS) && DEBUG |
| [517](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L517) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 2)` | #if os(macOS) && DEBUG |
| [546](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L546) | 内边距 | `.padding(.vertical, 3)` | #if os(macOS) && DEBUG |
| [560](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L560) | 容器布局/默认间距 | `HStack(spacing: 8)` | #if os(macOS) && DEBUG |
| [569](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L569) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [608](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L608) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 3)` | #if os(macOS) && DEBUG |
| [610](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L610) | 字号/字体 | `.font(.system(size: 10, weight: .semibold, design: .monospaced))` | #if os(macOS) && DEBUG |
| [614](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L614) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | #if os(macOS) && DEBUG |
| [615](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L615) | 内边距 | `.padding(8)` | #if os(macOS) && DEBUG |
| [632](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L632) | 容器布局/默认间距 | `HStack(alignment: .firstTextBaseline, spacing: 8)` | #if os(macOS) && DEBUG |
| [635](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L635) | 尺寸约束 | `.frame(width: 76, alignment: .leading)` | #if os(macOS) && DEBUG |
| [639](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L639) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(macOS) && DEBUG |
| [647](../../../Sources/Coda/Features/Player/AutoMixDebugPanel.swift#L647) | 字号/字体 | `.font(.caption2)` | #if os(macOS) && DEBUG |

## DesktopLyrics

源码：`Sources/Kumone/Features/Player/DesktopLyrics.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [105](../../../Sources/Coda/Features/Player/DesktopLyrics.swift#L105) | 自定义组件/原生构造尺寸参数 | `CGSize(width: 0, height: value.translation.height)` | #if os(macOS) |
| [143](../../../Sources/Coda/Features/Player/DesktopLyrics.swift#L143) | 容器布局/默认间距 | `VStack(spacing: 5)` | #if os(macOS) |
| [146](../../../Sources/Coda/Features/Player/DesktopLyrics.swift#L146) | 字号/字体 | `.font(.system(size: 15, weight: .semibold, design: .rounded))` | #if os(macOS) |
| [151](../../../Sources/Coda/Features/Player/DesktopLyrics.swift#L151) | 容器布局/默认间距 | `LyricText( line: line, size: 26, weight: .bold, color: .white, alignment: .center, rounded: true )` | #if os(macOS) |
| [163](../../../Sources/Coda/Features/Player/DesktopLyrics.swift#L163) | 字号/字体 | `.font(.system(size: 16, weight: .semibold, design: .rounded))` | #if os(macOS) |
| [171](../../../Sources/Coda/Features/Player/DesktopLyrics.swift#L171) | 内边距 | `.padding(.horizontal, 26)` | #if os(macOS) |
| [172](../../../Sources/Coda/Features/Player/DesktopLyrics.swift#L172) | 内边距 | `.padding(.vertical, 10)` | #if os(macOS) |

## IOSPlaybackQueueView

源码：`Sources/Kumone/Features/Player/IOSPlaybackQueueView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [10](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L10) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [11](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L11) | 容器布局/默认间距 | `HStack(alignment: .center, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [12](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L12) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [14](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L14) | 字号/字体 | `.font(Theme.Typography.sectionTitle.weight(.bold))` | 共享/运行时分支见源码 |
| [16](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L16) | 字号/字体 | `.font(Theme.Typography.secondary.weight(.medium))` | 共享/运行时分支见源码 |
| [19](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L19) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [21](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L21) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [23](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L23) | 容器布局/默认间距 | `List { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [26](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L26) | 列表内边距 | `.listRowInsets(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))` | 共享/运行时分支见源码 |
| [39](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L39) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [41](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L41) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 140)` | 共享/运行时分支见源码 |
| [64](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L64) | 内边距 | `.padding(.horizontal, Theme.Layout.trackListInset)` | 共享/运行时分支见源码 |
| [65](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L65) | 内边距 | `.padding(.top, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [90](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L90) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [92](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L92) | 尺寸约束 | `.frame(width: 48, height: 48)` | 共享/运行时分支见源码 |
| [94](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L94) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [96](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L96) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [99](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L99) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [103](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L103) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [151](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L151) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: Theme.Spacing.micro)` | #if os(iOS) |
| [153](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L153) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | #if os(iOS) |
| [154](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L154) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | #if os(iOS) |
| [161](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L161) | 内边距 | `.padding(.top, Theme.Spacing.control)` | #if os(iOS) |
| [170](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L170) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | #if os(iOS) |
| [172](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L172) | 字号/字体 | `.font(.system(size: 28, weight: .light))` | #if os(iOS) |
| [174](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L174) | 字号/字体 | `.font(.subheadline.weight(.semibold))` | #if os(iOS) |
| [177](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L177) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 240)` | #if os(iOS) |
| [180](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L180) | 内边距 | `.padding(Theme.Spacing.control)` | #if os(iOS) |
| [187](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L187) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [196](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L196) | 内边距 | `.padding(.top, Theme.Spacing.small)` | #if os(iOS) |
| [202](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L202) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) |
| [223](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L223) | 字号/字体 | `.font(Theme.Typography.caption.weight(.semibold))` | #if os(iOS) |
| [225](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L225) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | #if os(iOS) |
| [226](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L226) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | #if os(iOS) |
| [243](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L243) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | #if os(iOS) |
| [245](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L245) | 尺寸约束 | `.frame(width: 36, height: 36)` | #if os(iOS) |
| [248](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L248) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.micro)` | #if os(iOS) |
| [250](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L250) | 字号/字体 | `.font(Theme.Typography.caption.weight(.medium))` | #if os(iOS) |
| [254](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L254) | 字号/字体 | `.font(Theme.Typography.caption)` | #if os(iOS) |
| [259](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L259) | 容器布局/默认间距 | `Spacer(minLength: 0)` | #if os(iOS) |
| [265](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L265) | 字号/字体 | `.font(Theme.Typography.caption.monospacedDigit())` | #if os(iOS) |
| [269](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L269) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | #if os(iOS) |
| [270](../../../Sources/Coda/Features/Player/IOSPlaybackQueueView.swift#L270) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | #if os(iOS) |

## IOSSystemVolumeSlider

源码：`Sources/Kumone/Features/Player/IOSSystemVolumeSlider.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [16](../../../Sources/Coda/Features/Player/IOSSystemVolumeSlider.swift#L16) | 尺寸约束 | `.frame(width: 1, height: 1)` | #if os(iOS) |
| [36](../../../Sources/Coda/Features/Player/IOSSystemVolumeSlider.swift#L36) | 自定义组件/原生构造尺寸参数 | `MPVolumeView(frame: CGRect(x: 0, y: 0, width: 100, height: 44))` | #if os(iOS) |
| [36](../../../Sources/Coda/Features/Player/IOSSystemVolumeSlider.swift#L36) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: 100, height: 44)` | #if os(iOS) |

## KaraokeGlyphRenderer

源码：`Sources/Kumone/Features/Player/KaraokeGlyphRenderer.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [18](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L18) | 尺寸/字体/间距声明或原生字体 | `private var size: CGFloat = 0` | 共享/运行时分支见源码 |
| [69](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L69) | 尺寸/字体/间距声明或原生字体 | `let scale = 1 + CGFloat(emphasis) * 0.075` | 共享/运行时分支见源码 |
| [72](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L72) | 自定义组件/原生构造尺寸参数 | `CGRect(x: -tile.rect.width / 2, y: -tile.rect.height / 2, width: tile.rect.width, height: tile.rect.height)` | 共享/运行时分支见源码 |
| [101](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L101) | 尺寸/字体/间距声明或原生字体 | `let scale: CGFloat = 2` | 共享/运行时分支见源码 |
| [103](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L103) | 尺寸/字体/间距声明或原生字体 | `let height = max(bounds.height, ceil(fitted.height))` | 共享/运行时分支见源码 |
| [104](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L104) | 尺寸/字体/间距声明或原生字体 | `let width = bounds.width` | 共享/运行时分支见源码 |
| [106](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L106) | 自定义组件/原生构造尺寸参数 | `CGContext(data: nil, width: Int(ceil(width * scale)), height: Int(ceil(height * scale)), bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)` | 共享/运行时分支见源码 |
| [112](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L112) | 自定义组件/原生构造尺寸参数 | `CTFramesetterCreateFrame(framesetter, CFRangeMake(0, 0), CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil), nil)` | 共享/运行时分支见源码 |
| [113](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L113) | 自定义组件/原生构造尺寸参数 | `CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)` | 共享/运行时分支见源码 |
| [113](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L113) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: width, height: height)` | 共享/运行时分支见源码 |
| [142](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L142) | 自定义组件/原生构造尺寸参数 | `CGRect(x: left, y: floor((height - top) * scale), width: right - left, height: ceil((top - bottom) * scale))` | 共享/运行时分支见源码 |
| [149](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L149) | 自定义组件/原生构造尺寸参数 | `Tile(image: piece, rect: CGRect(x: bounds.minX + crop.minX / scale, y: bounds.maxY - crop.maxY / scale, width: crop.width / scale, height: crop.height / scale), timings: times)` | 共享/运行时分支见源码 |
| [150](../../../Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift#L150) | 自定义组件/原生构造尺寸参数 | `CGRect(x: bounds.minX + crop.minX / scale, y: bounds.maxY - crop.maxY / scale, width: crop.width / scale, height: crop.height / scale)` | 共享/运行时分支见源码 |

## KaraokeLyricLine

源码：`Sources/Kumone/Features/Player/KaraokeLyricLine.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [10](../../../Sources/Coda/Features/Player/KaraokeLyricLine.swift#L10) | 尺寸/字体/间距声明或原生字体 | `let size: CGFloat` | 共享/运行时分支见源码 |
| [78](../../../Sources/Coda/Features/Player/KaraokeLyricLine.swift#L78) | 自定义组件/原生构造尺寸参数 | `Style( size: size, weight: weight.platform, color: color, rubyColor: color.withAlphaComponent(color.cgColor.alpha * 0.72), rubyScale: 0.5, alignment: alignment, rounded: rounded )` | 共享/运行时分支见源码 |
| [118](../../../Sources/Coda/Features/Player/KaraokeLyricLine.swift#L118) | 自定义组件/原生构造尺寸参数 | `CGSize(width: ceil(fitted.width), height: ceil(fitted.height))` | 共享/运行时分支见源码 |
| [121](../../../Sources/Coda/Features/Player/KaraokeLyricLine.swift#L121) | 自定义组件/原生构造尺寸参数 | `CGSize(width: proposed, height: ceil(fitted.height))` | 共享/运行时分支见源码 |
| [174](../../../Sources/Coda/Features/Player/KaraokeLyricLine.swift#L174) | 自定义组件/原生构造尺寸参数 | `CGSize(width: fitted.width + 16, height: fitted.height + 16)` | #if os(macOS) |
| [279](../../../Sources/Coda/Features/Player/KaraokeLyricLine.swift#L279) | 自定义组件/原生构造尺寸参数 | `CGSize(width: fitted.width + 16, height: fitted.height + 16)` | #if os(macOS) / #else |

## LyricText

源码：`Sources/Kumone/Features/Player/LyricText.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [13](../../../Sources/Coda/Features/Player/LyricText.swift#L13) | 尺寸/字体/间距声明或原生字体 | `let size: CGFloat` | 共享/运行时分支见源码 |
| [25](../../../Sources/Coda/Features/Player/LyricText.swift#L25) | 容器布局/默认间距 | `RubyText( segments: furigana, size: size, weight: weight, color: color, rubyColor: color.opacity(0.72), alignment: alignment, rounded: rounded, alphas: alphas )` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Player/LyricText.swift#L53) | 容器布局/默认间距 | `RubyText( segments: [RubySegment(line.text)], size: size, weight: weight, color: color.opacity(0.28), alignment: alignment, rounded: rounded )` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Player/LyricText.swift#L62) | 容器布局/默认间距 | `RubyText( segments: [RubySegment(line.text)], size: size, weight: weight, color: color, alignment: alignment, rounded: rounded, alphas: alphas.map { max(0, ($0 - 0.28) / 0.72) } )` | 共享/运行时分支见源码 |
| [81](../../../Sources/Coda/Features/Player/LyricText.swift#L81) | 字号/字体 | `.font(.system(size: size, weight: weight, design: rounded ? .rounded : .default))` | 共享/运行时分支见源码 |

## NowPlayingAddToPlaylistColumn

源码：`Sources/Kumone/Features/Player/NowPlayingAddToPlaylistColumn.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [38](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L38) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [39](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L39) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [41](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L41) | 字号/字体 | `.font(Theme.Typography.sectionTitle.weight(.bold))` | 共享/运行时分支见源码 |
| [42](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L42) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [48](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L48) | 尺寸约束 | `.frame(width: 36, height: 36)` | 共享/运行时分支见源码 |
| [51](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L51) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [59](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L59) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [61](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L61) | 容器布局/默认间距 | `TextField("搜索歌单", text: $query)` | 共享/运行时分支见源码 |
| [72](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L72) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [77](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L77) | 容器布局/默认间距 | `LazyVStack(spacing: 0)` | 共享/运行时分支见源码 |
| [87](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L87) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 100)` | 共享/运行时分支见源码 |
| [97](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L97) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [98](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L98) | 内边距 | `.padding(.top, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [99](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L99) | 内边距 | `.padding(.bottom, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [107](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L107) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [114](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L114) | 字号/字体 | `.font(.system(size: 25, weight: .medium))` | 共享/运行时分支见源码 |
| [115](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L115) | 尺寸约束 | `.frame(width: 48, height: 48)` | 共享/运行时分支见源码 |
| [122](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L122) | 容器布局/默认间距 | `TextField("歌单名称", text: $newName)` | 共享/运行时分支见源码 |
| [125](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L125) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [132](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L132) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [141](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L141) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [147](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L147) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [158](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L158) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [159](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L159) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)` | 共享/运行时分支见源码 |
| [166](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L166) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [184](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L184) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [198](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L198) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [200](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L200) | 尺寸约束 | `.frame(width: 48, height: 48)` | 共享/运行时分支见源码 |
| [202](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L202) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [203](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L203) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [205](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L205) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [208](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L208) | 容器布局/默认间距 | `Spacer(minLength: 4)` | 共享/运行时分支见源码 |
| [211](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L211) | 字号/字体 | `.font(.system(size: 25, weight: .regular))` | 共享/运行时分支见源码 |
| [213](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L213) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [216](../../../Sources/Coda/Features/Player/NowPlayingAddToPlaylistColumn.swift#L216) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | 共享/运行时分支见源码 |

## NowPlayingFluidBackground

源码：`Sources/Kumone/Features/Player/NowPlayingFluidBackground.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [125](../../../Sources/Coda/Features/Player/NowPlayingFluidBackground.swift#L125) | 尺寸/字体/间距声明或原生字体 | `var size: SIMD2<Float>` | 共享/运行时分支见源码 |
| [497](../../../Sources/Coda/Features/Player/NowPlayingFluidBackground.swift#L497) | 自定义组件/原生构造尺寸参数 | `CGSize(width: max(1, (bounds.width * fit).rounded()), height: max(1, (bounds.height * fit).rounded()))` | 共享/运行时分支见源码 |
| [497](../../../Sources/Coda/Features/Player/NowPlayingFluidBackground.swift#L497) | 尺寸/字体/间距声明或原生字体 | `let size = CGSize(width: max(1, (bounds.width * fit).rounded()),` | 共享/运行时分支见源码 |
| [562](../../../Sources/Coda/Features/Player/NowPlayingFluidBackground.swift#L562) | 自定义组件/原生构造尺寸参数 | `Uniforms(size: SIMD2(Float(bounds.width), Float(bounds.height)), time: Float(motion.time), pulse: Float(motion.pulse), energy: Float(motion.energy), darkness: dark, blend: Float(blend * blend * (3 - 2 * blend)), contrast: increasedContrast ? 1 : 0, melody: Float(motion.melody), detail: Float(motion.detail), melodyPulse: Float(motion.melodyPulse))` | 共享/运行时分支见源码 |

## NowPlayingPresentation

源码：`Sources/Kumone/Features/Player/NowPlayingPresentation.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [10](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L10) | 尺寸/字体/间距声明或原生字体 | `static let dynamicIslandSafeAreaClearance: CGFloat = 12` | #if os(iOS) |
| [11](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L11) | 尺寸/字体/间距声明或原生字体 | `static let indicatorTopSpacing: CGFloat = 8` | #if os(iOS) |
| [12](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L12) | 尺寸/字体/间距声明或原生字体 | `static let indicatorToHeaderSpacing: CGFloat = 21` | #if os(iOS) |
| [13](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L13) | 尺寸/字体/间距声明或原生字体 | `static let indicatorWidth: CGFloat = 60` | #if os(iOS) |
| [14](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L14) | 尺寸/字体/间距声明或原生字体 | `static let indicatorHeight: CGFloat = 5` | #if os(iOS) |
| [15](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L15) | 尺寸/字体/间距声明或原生字体 | `static let indicatorHitWidth: CGFloat = 180` | #if os(iOS) |
| [16](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L16) | 尺寸/字体/间距声明或原生字体 | `static let indicatorHitHeight: CGFloat = 82` | #if os(iOS) |
| [17](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L17) | 尺寸/字体/间距声明或原生字体 | `static let controlsRevealHitHeight: CGFloat = 132` | #if os(iOS) |
| [19](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L19) | 尺寸/字体/间距声明或原生字体 | `static let controlsTransitionScale: CGFloat = 0.97` | #if os(iOS) |
| [60](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L60) | 尺寸/字体/间距声明或原生字体 | `static var dynamicIslandToIndicatorSpacing: CGFloat { dynamicIslandSafeAreaClearance + indicatorTopSpacing }` | #if os(iOS) |
| [135](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L135) | 容器布局/默认间距 | `ZStack(alignment: .top)` | #if os(iOS) |
| [144](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L144) | 尺寸约束 | `.frame(width: isPad ? proxy.size.width : NowPlayingPresentationMetrics.indicatorHitWidth, height: isPad \|\| proxy.size.height > proxy.size.width ? 44 : NowPlayingPresentationMetrics.indicatorHitHeight, alignment: .top)` | #if os(iOS) |
| [148](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L148) | 内边距 | `.padding(.top, isPad ? 12 : 0)` | #if os(iOS) |
| [153](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L153) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | #if os(iOS) |
| [161](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L161) | 尺寸约束 | `.frame(width: UIDevice.current.userInterfaceIdiom == .pad ? 44 : NowPlayingPresentationMetrics.indicatorWidth, height: NowPlayingPresentationMetrics.indicatorHeight)` | #if os(iOS) |
| [163](../../../Sources/Coda/Features/Player/NowPlayingPresentation.swift#L163) | 内边距 | `.padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 1 : NowPlayingPresentationMetrics.indicatorTopSpacing)` | #if os(iOS) |

## NowPlayingQualityControl

源码：`Sources/Kumone/Features/Player/NowPlayingQualityControl.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [50](../../../Sources/Coda/Features/Player/NowPlayingQualityControl.swift#L50) | 容器布局/默认间距 | `HStack(spacing: 4)` | 共享/运行时分支见源码 |
| [57](../../../Sources/Coda/Features/Player/NowPlayingQualityControl.swift#L57) | 尺寸约束 | `.frame(width: 15, height: 11)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Player/NowPlayingQualityControl.swift#L62) | 字号/字体 | `.font(.system(size: 10.5, weight: .medium))` | 共享/运行时分支见源码 |
| [64](../../../Sources/Coda/Features/Player/NowPlayingQualityControl.swift#L64) | 内边距 | `.padding(.horizontal, 7)` | 共享/运行时分支见源码 |
| [65](../../../Sources/Coda/Features/Player/NowPlayingQualityControl.swift#L65) | 尺寸约束 | `.frame(height: 21)` | 共享/运行时分支见源码 |
| [70](../../../Sources/Coda/Features/Player/NowPlayingQualityControl.swift#L70) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 24)` | 共享/运行时分支见源码 |
| [128](../../../Sources/Coda/Features/Player/NowPlayingQualityControl.swift#L128) | 尺寸/字体/间距声明或原生字体 | `let width = rect.width * 0.72` | 共享/运行时分支见源码 |

## NowPlayingTrackDestinationLinks

源码：`Sources/Kumone/Features/Player/NowPlayingTrackDestinationLinks.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [6](../../../Sources/Coda/Features/Player/NowPlayingTrackDestinationLinks.swift#L6) | 尺寸/字体/间距声明或原生字体 | `let font: Font` | 共享/运行时分支见源码 |
| [15](../../../Sources/Coda/Features/Player/NowPlayingTrackDestinationLinks.swift#L15) | 容器布局/默认间距 | `HStack(spacing: 0)` | 共享/运行时分支见源码 |
| [28](../../../Sources/Coda/Features/Player/NowPlayingTrackDestinationLinks.swift#L28) | 内边距 | `.padding(.vertical, 3)` | 共享/运行时分支见源码 |
| [36](../../../Sources/Coda/Features/Player/NowPlayingTrackDestinationLinks.swift#L36) | 字号/字体 | `.font(font)` | 共享/运行时分支见源码 |

## NowPlayingView

源码：`Sources/Kumone/Features/Player/NowPlayingView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [21](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L21) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .title3) private var iPadMetadataHeight: CGFloat = 56` | 共享/运行时分支见源码 |
| [26](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L26) | 尺寸/字体/间距声明或原生字体 | `@State private var portraitControlsHeight: CGFloat = 320` | #if os(iOS) |
| [41](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L41) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [68](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L68) | 尺寸约束 | `.frame(width: geo.size.width)` | 共享/运行时分支见源码 |
| [77](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L77) | 内边距 | `.padding(.top, 12)` | #if os(macOS) |
| [78](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L78) | 内边距 | `.padding(.leading, 91)` | #if os(macOS) |
| [81](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L81) | 内边距 | `.padding(.top, 20)` | #if os(macOS) / #else |
| [82](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L82) | 内边距 | `.padding(.leading, 20)` | #if os(macOS) / #else |
| [94](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L94) | 字号/字体 | `.font(.system(size: 14, weight: .semibold))` | 共享/运行时分支见源码 |
| [96](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L96) | 尺寸约束 | `.frame(width: 36, height: 36)` | 共享/运行时分支见源码 |
| [100](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L100) | 内边距 | `.padding(.top, 20)` | 共享/运行时分支见源码 |
| [101](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L101) | 内边距 | `.padding(.trailing, 20)` | 共享/运行时分支见源码 |
| [199](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L199) | 字号/字体 | `.font(.system(size: glyphSize, weight: .semibold))` | 共享/运行时分支见源码 |
| [201](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L201) | 尺寸约束 | `.frame(width: diameter, height: diameter)` | 共享/运行时分支见源码 |
| [281](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L281) | 尺寸/字体/间距声明或原生字体 | `let inset: CGFloat = isNarrow ? 24 : min(72, size.width * 0.06)` | #if os(iOS) |
| [282](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L282) | 尺寸/字体/间距声明或原生字体 | `let width = max(0, min(size.width - inset * 2, 960))` | #if os(iOS) |
| [283](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L283) | 尺寸/字体/间距声明或原生字体 | `let coverSize: CGFloat = isNarrow ? 52 : 72` | #if os(iOS) |
| [285](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L285) | 容器布局/默认间距 | `VStack(spacing: isNarrow ? Theme.Spacing.small : Theme.Spacing.component)` | #if os(iOS) |
| [286](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L286) | 容器布局/默认间距 | `HStack(spacing: isNarrow ? Theme.Spacing.control : Theme.Spacing.component)` | #if os(iOS) |
| [295](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L295) | 尺寸约束 | `.frame(maxWidth: .infinity)` | #if os(iOS) |
| [297](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L297) | 尺寸约束 | `.frame(minHeight: max(coverSize, iPadMetadataHeight))` | #if os(iOS) |
| [309](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L309) | 内边距 | `.padding(.bottom, usesPortraitLyricsInterface ? 0 : portraitControlsHeight)` | #if os(iOS) |
| [310](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L310) | 内边距 | `.padding(.horizontal, -16)` | #if os(iOS) |
| [341](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L341) | 尺寸约束 | `.frame(width: width)` | #if os(iOS) |
| [342](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L342) | 内边距 | `.padding(.top, UIDevice.current.userInterfaceIdiom == .pad ? 64 : 34)` | #if os(iOS) |
| [343](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L343) | 内边距 | `.padding(.bottom, 3)` | #if os(iOS) |
| [344](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L344) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | #if os(iOS) |
| [374](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L374) | 容器布局/默认间距 | `VStack(spacing: 0)` | #if os(iOS) |
| [376](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L376) | 自定义组件/原生构造尺寸参数 | `NowPlayingScrubber(showsRemainingTime: true, rowHeight: 52)` | #if os(iOS) |
| [378](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L378) | 内边距 | `.padding(.bottom, 19)` | #if os(iOS) |
| [380](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L380) | 自定义组件/原生构造尺寸参数 | `PlayerTransportControls(width: width)` | #if os(iOS) |
| [381](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L381) | 尺寸约束 | `.frame(height: 82)` | #if os(iOS) |
| [383](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L383) | 内边距 | `.padding(.bottom, 31)` | #if os(iOS) |
| [387](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L387) | 内边距 | `.padding(.bottom, 3)` | #if os(iOS) |
| [449](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L449) | 容器布局/默认间距 | `HStack(spacing: 0)` | #if os(iOS) |
| [452](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L452) | 容器布局/默认间距 | `Spacer(minLength: 12)` | #if os(iOS) |
| [453](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L453) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | #if os(iOS) |
| [473](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L473) | 尺寸约束 | `.frame(height: 50)` | #if os(iOS) |
| [479](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L479) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [496](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L496) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [498](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L498) | 字号/字体 | `.font(.system(size: 32, weight: .light))` | 共享/运行时分支见源码 |
| [500](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L500) | 字号/字体 | `.font(.subheadline)` | 共享/运行时分支见源码 |
| [505](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L505) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [513](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L513) | 尺寸/字体/间距声明或原生字体 | `let contentWidth = min(size.width, 1920)` | 共享/运行时分支见源码 |
| [514](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L514) | 尺寸/字体/间距声明或原生字体 | `let horizontalInset: CGFloat = shortViewport ? 24 : min(96, max(32, contentWidth * 0.04))` | 共享/运行时分支见源码 |
| [516](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L516) | 尺寸/字体/间距声明或原生字体 | `let topInset: CGFloat = shortViewport ? 48 : 56` | #if os(macOS) |
| [518](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L518) | 尺寸/字体/间距声明或原生字体 | `let topInset: CGFloat = shortViewport ? 16 : 56` | #if os(macOS) / #else |
| [520](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L520) | 尺寸/字体/间距声明或原生字体 | `let bottomInset: CGFloat = shortViewport ? 3 : 16` | 共享/运行时分支见源码 |
| [521](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L521) | 尺寸/字体/间距声明或原生字体 | `let columnSpacing: CGFloat = shortViewport ? 24 : min(88, max(32, contentWidth * 0.04))` | 共享/运行时分支见源码 |
| [522](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L522) | 尺寸/字体/间距声明或原生字体 | `let controlSpacing: CGFloat = shortViewport ? Theme.Spacing.tight : Theme.Spacing.small` | 共享/运行时分支见源码 |
| [523](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L523) | 尺寸/字体/间距声明或原生字体 | `let artworkSpacing: CGFloat = shortViewport ? Theme.Spacing.control : Theme.Spacing.group` | 共享/运行时分支见源码 |
| [524](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L524) | 尺寸/字体/间距声明或原生字体 | `let transportHeight: CGFloat = shortViewport ? 52 : 64` | 共享/运行时分支见源码 |
| [525](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L525) | 尺寸/字体/间距声明或原生字体 | `let volumeHeight: CGFloat = shortViewport ? 36 : 44` | 共享/运行时分支见源码 |
| [526](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L526) | 尺寸/字体/间距声明或原生字体 | `let availableWidth = max(0, contentWidth - horizontalInset * 2 - columnSpacing)` | 共享/运行时分支见源码 |
| [527](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L527) | 尺寸/字体/间距声明或原生字体 | `let columnWidth = availableWidth * 0.42` | 共享/运行时分支见源码 |
| [528](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L528) | 尺寸/字体/间距声明或原生字体 | `let reservedHeight = topInset + bottomInset + 44 + 8 + artworkSpacing` | 共享/运行时分支见源码 |
| [530](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L530) | 尺寸/字体/间距声明或原生字体 | `let coverSize = max(0, min(columnWidth, size.height - reservedHeight))` | 共享/运行时分支见源码 |
| [534](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L534) | 尺寸/字体/间距声明或原生字体 | `let controlsWidth = UIDevice.current.userInterfaceIdiom == .pad ? coverSize : columnWidth` | #if os(iOS) |
| [536](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L536) | 尺寸/字体/间距声明或原生字体 | `let controlsWidth = max(min(240, columnWidth), coverSize)` | #if os(iOS) / #else |
| [538](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L538) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [539](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L539) | 容器布局/默认间距 | `HStack(spacing: columnSpacing)` | 共享/运行时分支见源码 |
| [546](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L546) | 尺寸约束 | `.frame(maxWidth: 960)` | 共享/运行时分支见源码 |
| [547](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L547) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [549](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L549) | 尺寸约束 | `.frame(maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [551](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L551) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [552](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L552) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [554](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L554) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [559](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L559) | 尺寸约束 | `.frame(width: controlsWidth)` | 共享/运行时分支见源码 |
| [560](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L560) | 尺寸约束 | `.frame(width: columnWidth)` | 共享/运行时分支见源码 |
| [561](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L561) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [564](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L564) | 尺寸约束 | `.frame(height: 44)` | 共享/运行时分支见源码 |
| [566](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L566) | 内边距 | `.padding(.horizontal, horizontalInset)` | 共享/运行时分支见源码 |
| [567](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L567) | 内边距 | `.padding(.top, topInset)` | 共享/运行时分支见源码 |
| [568](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L568) | 内边距 | `.padding(.bottom, bottomInset)` | 共享/运行时分支见源码 |
| [569](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L569) | 尺寸约束 | `.frame(width: contentWidth)` | 共享/运行时分支见源码 |
| [570](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L570) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [574](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L574) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [610](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L610) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [656](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L656) | 尺寸约束 | `.frame(width: 28, height: 20)` | 共享/运行时分支见源码 |
| [659](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L659) | 字号/字体 | `.font(.system(size: 20, weight: .medium))` | 共享/运行时分支见源码 |
| [663](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L663) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [667](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L667) | 内边距 | `.padding(3)` | 共享/运行时分支见源码 |
| [685](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L685) | 容器布局/默认间距 | `VStack(spacing: 0)` | 共享/运行时分支见源码 |
| [686](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L686) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [688](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L688) | 内边距 | `.padding(.bottom, artworkSpacing)` | 共享/运行时分支见源码 |
| [689](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L689) | 容器布局/默认间距 | `VStack(spacing: controlSpacing)` | 共享/运行时分支见源码 |
| [691](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L691) | 尺寸约束 | `.frame(height: iPadMetadataHeight)` | 共享/运行时分支见源码 |
| [692](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L692) | 自定义组件/原生构造尺寸参数 | `NowPlayingScrubber(showsRemainingTime: true, rowHeight: 52)` | 共享/运行时分支见源码 |
| [693](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L693) | 尺寸约束 | `.frame(height: 44)` | 共享/运行时分支见源码 |
| [694](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L694) | 自定义组件/原生构造尺寸参数 | `PlayerTransportControls(width: controlsWidth ?? coverSize, height: transportHeight)` | 共享/运行时分支见源码 |
| [695](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L695) | 尺寸约束 | `.frame(height: transportHeight)` | 共享/运行时分支见源码 |
| [697](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L697) | 尺寸约束 | `.frame(height: volumeHeight)` | 共享/运行时分支见源码 |
| [703](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L703) | 尺寸约束 | `.frame(width: controlsWidth ?? coverSize)` | 共享/运行时分支见源码 |
| [704](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L704) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [706](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L706) | 尺寸约束 | `.frame(width: columnWidth)` | 共享/运行时分支见源码 |
| [710](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L710) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [711](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L711) | 字号/字体 | `.font(.system(size: 13))` | 共享/运行时分支见源码 |
| [713](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L713) | 尺寸约束 | `.frame(height: rowHeight)` | #if os(iOS) |
| [718](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L718) | 尺寸约束 | `.frame(height: rowHeight)` | #if os(iOS) / #else |
| [720](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L720) | 字号/字体 | `.font(.system(size: 15))` | 共享/运行时分支见源码 |
| [723](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L723) | 尺寸约束 | `.frame(height: rowHeight)` | 共享/运行时分支见源码 |
| [731](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L731) | 尺寸/字体/间距声明或原生字体 | `let width = max(0, min(size.width - 64, 420))` | 共享/运行时分支见源码 |
| [733](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L733) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [735](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L735) | 尺寸约束 | `.frame(maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [738](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L738) | 尺寸约束 | `.frame(maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [743](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L743) | 自定义组件/原生构造尺寸参数 | `NowPlayingScrubber(showsRemainingTime: true, rowHeight: 52)` | 共享/运行时分支见源码 |
| [744](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L744) | 自定义组件/原生构造尺寸参数 | `PlayerTransportControls(width: width)` | 共享/运行时分支见源码 |
| [746](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L746) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [748](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L748) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [753](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L753) | 尺寸约束 | `.frame(width: width)` | 共享/运行时分支见源码 |
| [754](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L754) | 内边距 | `.padding(.top, 64)` | 共享/运行时分支见源码 |
| [755](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L755) | 内边距 | `.padding(.bottom, 16)` | 共享/运行时分支见源码 |
| [756](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L756) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [779](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L779) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [784](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L784) | 字号/字体 | `.font(.system(size: 48, weight: .light))` | 共享/运行时分支见源码 |
| [794](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L794) | 自定义组件/原生构造尺寸参数 | `PlayerArtworkFrame(size: size, style: .detail)` | 共享/运行时分支见源码 |
| [809](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L809) | 容器布局/默认间距 | `VStack(spacing: 10)` | 共享/运行时分支见源码 |
| [811](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L811) | 字号/字体 | `.font(.system(size: 36, weight: .light))` | 共享/运行时分支见源码 |
| [814](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L814) | 字号/字体 | `.font(.system(size: 15))` | 共享/运行时分支见源码 |
| [817](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L817) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [821](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L821) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [823](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L823) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [840](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L840) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [857](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L857) | 尺寸/字体/间距声明或原生字体 | `let size: CGFloat` | 共享/运行时分支见源码 |
| [867](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L867) | 容器布局/默认间距 | `LyricText( line: line, size: size, weight: weight, color: .white.opacity(isActive ? 1 : (verbatim ? min(inactiveOpacity, 0.25) : inactiveOpacity)) )` | 共享/运行时分支见源码 |
| [874](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L874) | 自定义组件/原生构造尺寸参数 | `ActiveKaraokeLyricText(line: line, words: words, size: size, weight: weight)` | 共享/运行时分支见源码 |
| [905](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L905) | 尺寸/字体/间距声明或原生字体 | `let size: CGFloat` | 共享/运行时分支见源码 |
| [925](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L925) | 自定义组件/原生构造尺寸参数 | `KaraokeLyricLine( line: line, words: words, size: size, weight: weight, playing: player.isPlaying && windowVisibility.isVisible && allowsAnimation )` | 共享/运行时分支见源码 |
| [929](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L929) | 内边距 | `.padding(-8)` | 共享/运行时分支见源码 |
| [952](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L952) | 内边距 | `.padding(.horizontal, 48)` | 共享/运行时分支见源码 |
| [955](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L955) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [957](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L957) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [962](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L962) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [964](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L964) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [989](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L989) | 容器布局/默认间距 | `VStack(alignment: alignment, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [990](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L990) | 容器布局/默认间距 | `HStack(spacing: 6)` | 共享/运行时分支见源码 |
| [992](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L992) | 字号/字体 | `.font(largeMetadata ? Theme.Typography.cardTitle : Theme.Typography.trackTitle)` | 共享/运行时分支见源码 |
| [1019](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1019) | 尺寸约束 | `.frame(width: 22, height: 22)` | 共享/运行时分支见源码 |
| [1021](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1021) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [1034](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1034) | 自定义组件/原生构造尺寸参数 | `PlayerHeartIcon(liked: liked, size: 22, tint: .white)` | 共享/运行时分支见源码 |
| [1035](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1035) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [1082](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1082) | 字号/字体 | `.font(.system(size: 22, weight: .medium))` | 共享/运行时分支见源码 |
| [1084](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1084) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [1089](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1089) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [1168](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1168) | 字号/字体 | `.font(.system(size: 12))` | 共享/运行时分支见源码 |
| [1174](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1174) | 尺寸约束 | `.frame(width: 20, height: 20)` | 共享/运行时分支见源码 |
| [1185](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1185) | 尺寸/字体/间距声明或原生字体 | `var rowHeight: CGFloat = 44` | 共享/运行时分支见源码 |
| [1210](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1210) | 容器布局/默认间距 | `VStack(spacing: 5)` | 共享/运行时分支见源码 |
| [1237](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1237) | 尺寸约束 | `.frame(height: 24)` | 共享/运行时分支见源码 |
| [1243](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1243) | 尺寸约束 | `.frame(width: geo.size.width, height: geo.size.height)` | 共享/运行时分支见源码 |
| [1251](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1251) | 尺寸约束 | `.frame(height: rowHeight)` | 共享/运行时分支见源码 |
| [1256](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1256) | 尺寸约束 | `.frame(width: 148, height: 24)` | 共享/运行时分支见源码 |
| [1272](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1272) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [1275](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1275) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [1283](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1283) | 字号/字体 | `.font(Theme.Typography.caption.monospacedDigit())` | 共享/运行时分支见源码 |
| [1326](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1326) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [1331](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1331) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [1344](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1344) | 字号/字体 | `.font(.system(size: emphasized ? 17 : 14, weight: emphasized ? .bold : .medium))` | 共享/运行时分支见源码 |
| [1348](../../../Sources/Coda/Features/Player/NowPlayingView.swift#L1348) | 内边距 | `.padding(.horizontal, 28)` | 共享/运行时分支见源码 |

## Panels

源码：`Sources/Kumone/Features/Player/Panels.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [14](../../../Sources/Coda/Features/Player/Panels.swift#L14) | 容器布局/默认间距 | `VStack(spacing: 0)` | 共享/运行时分支见源码 |
| [19](../../../Sources/Coda/Features/Player/Panels.swift#L19) | 尺寸约束 | `.frame(width: 320)` | 共享/运行时分支见源码 |
| [20](../../../Sources/Coda/Features/Player/Panels.swift#L20) | 尺寸约束 | `.frame(maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [30](../../../Sources/Coda/Features/Player/Panels.swift#L30) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [31](../../../Sources/Coda/Features/Player/Panels.swift#L31) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [33](../../../Sources/Coda/Features/Player/Panels.swift#L33) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [36](../../../Sources/Coda/Features/Player/Panels.swift#L36) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [40](../../../Sources/Coda/Features/Player/Panels.swift#L40) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [45](../../../Sources/Coda/Features/Player/Panels.swift#L45) | 字号/字体 | `.font(.system(size: 11, weight: .semibold))` | 共享/运行时分支见源码 |
| [47](../../../Sources/Coda/Features/Player/Panels.swift#L47) | 尺寸约束 | `.frame(width: 22, height: 22)` | 共享/运行时分支见源码 |
| [52](../../../Sources/Coda/Features/Player/Panels.swift#L52) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Player/Panels.swift#L53) | 内边距 | `.padding(.vertical, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [61](../../../Sources/Coda/Features/Player/Panels.swift#L61) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Player/Panels.swift#L62) | 尺寸约束 | `.frame(height: 120)` | 共享/运行时分支见源码 |
| [67](../../../Sources/Coda/Features/Player/Panels.swift#L67) | 尺寸约束 | `.frame(height: 160)` | 共享/运行时分支见源码 |
| [69](../../../Sources/Coda/Features/Player/Panels.swift#L69) | 内边距 | `.padding(.horizontal, Theme.Spacing.page)` | 共享/运行时分支见源码 |
| [97](../../../Sources/Coda/Features/Player/Panels.swift#L97) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [100](../../../Sources/Coda/Features/Player/Panels.swift#L100) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [103](../../../Sources/Coda/Features/Player/Panels.swift#L103) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [127](../../../Sources/Coda/Features/Player/Panels.swift#L127) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [130](../../../Sources/Coda/Features/Player/Panels.swift#L130) | 字号/字体 | `.font(.system(size: isActive ? 12 : 11))` | 共享/运行时分支见源码 |
| [133](../../../Sources/Coda/Features/Player/Panels.swift#L133) | 容器布局/默认间距 | `LyricText( line: line, size: isActive ? 16 : 14, weight: isActive ? .bold : .medium, // Core Text needs a resolved colour, so the hierarchical // styles the other rows use are spelled out here. color: isActive ? .primary : .secondary )` | 共享/运行时分支见源码 |
| [143](../../../Sources/Coda/Features/Player/Panels.swift#L143) | 字号/字体 | `.font(.system(size: isActive ? 13 : 12))` | 共享/运行时分支见源码 |
| [148](../../../Sources/Coda/Features/Player/Panels.swift#L148) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [165](../../../Sources/Coda/Features/Player/Panels.swift#L165) | 容器布局/默认间距 | `VStack(spacing: 0)` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/Features/Player/Panels.swift#L170) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/Features/Player/Panels.swift#L172) | 内边距 | `.padding(.bottom, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [178](../../../Sources/Coda/Features/Player/Panels.swift#L178) | 内边距 | `.padding(.top, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [185](../../../Sources/Coda/Features/Player/Panels.swift#L185) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [189](../../../Sources/Coda/Features/Player/Panels.swift#L189) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [194](../../../Sources/Coda/Features/Player/Panels.swift#L194) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [198](../../../Sources/Coda/Features/Player/Panels.swift#L198) | 尺寸约束 | `.frame(width: 340)` | 共享/运行时分支见源码 |
| [199](../../../Sources/Coda/Features/Player/Panels.swift#L199) | 尺寸约束 | `.frame(maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [209](../../../Sources/Coda/Features/Player/Panels.swift#L209) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [211](../../../Sources/Coda/Features/Player/Panels.swift#L211) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [213](../../../Sources/Coda/Features/Player/Panels.swift#L213) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [215](../../../Sources/Coda/Features/Player/Panels.swift#L215) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [220](../../../Sources/Coda/Features/Player/Panels.swift#L220) | 字号/字体 | `.font(.system(size: 11, weight: .semibold))` | 共享/运行时分支见源码 |
| [222](../../../Sources/Coda/Features/Player/Panels.swift#L222) | 尺寸约束 | `.frame(width: 22, height: 22)` | 共享/运行时分支见源码 |
| [227](../../../Sources/Coda/Features/Player/Panels.swift#L227) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [228](../../../Sources/Coda/Features/Player/Panels.swift#L228) | 内边距 | `.padding(.vertical, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [233](../../../Sources/Coda/Features/Player/Panels.swift#L233) | 字号/字体 | `.font(Theme.Typography.caption.weight(.semibold))` | 共享/运行时分支见源码 |
| [235](../../../Sources/Coda/Features/Player/Panels.swift#L235) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [236](../../../Sources/Coda/Features/Player/Panels.swift#L236) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [249](../../../Sources/Coda/Features/Player/Panels.swift#L249) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [255](../../../Sources/Coda/Features/Player/Panels.swift#L255) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [257](../../../Sources/Coda/Features/Player/Panels.swift#L257) | 尺寸约束 | `.frame(width: 36, height: 36)` | 共享/运行时分支见源码 |
| [259](../../../Sources/Coda/Features/Player/Panels.swift#L259) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [261](../../../Sources/Coda/Features/Player/Panels.swift#L261) | 字号/字体 | `.font(Theme.Typography.caption.weight(.medium))` | 共享/运行时分支见源码 |
| [265](../../../Sources/Coda/Features/Player/Panels.swift#L265) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [269](../../../Sources/Coda/Features/Player/Panels.swift#L269) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [279](../../../Sources/Coda/Features/Player/Panels.swift#L279) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [288](../../../Sources/Coda/Features/Player/Panels.swift#L288) | 字号/字体 | `.font(.system(size: 9, weight: .semibold))` | 共享/运行时分支见源码 |
| [296](../../../Sources/Coda/Features/Player/Panels.swift#L296) | 字号/字体 | `.font(Theme.Typography.caption.monospacedDigit())` | 共享/运行时分支见源码 |
| [300](../../../Sources/Coda/Features/Player/Panels.swift#L300) | 尺寸约束 | `.frame(width: 32)` | 共享/运行时分支见源码 |
| [302](../../../Sources/Coda/Features/Player/Panels.swift#L302) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [303](../../../Sources/Coda/Features/Player/Panels.swift#L303) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | 共享/运行时分支见源码 |

## PlayerBar

源码：`Sources/Kumone/Features/Player/PlayerBar.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [9](../../../Sources/Coda/Features/Player/PlayerBar.swift#L9) | 内边距 | `.padding(.horizontal, Theme.Layout.playerBarHorizontalMargin)` | #if os(macOS) |
| [10](../../../Sources/Coda/Features/Player/PlayerBar.swift#L10) | 内边距 | `.padding(.bottom, Theme.Layout.playerBarBottomMargin)` | #if os(macOS) |
| [29](../../../Sources/Coda/Features/Player/PlayerBar.swift#L29) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [31](../../../Sources/Coda/Features/Player/PlayerBar.swift#L31) | 尺寸约束 | `.frame(maxWidth: showsProgress ? 180 : .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [34](../../../Sources/Coda/Features/Player/PlayerBar.swift#L34) | 尺寸约束 | `.frame(minWidth: 140, maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [41](../../../Sources/Coda/Features/Player/PlayerBar.swift#L41) | 内边距 | `.padding(.horizontal, 16)` | 共享/运行时分支见源码 |
| [42](../../../Sources/Coda/Features/Player/PlayerBar.swift#L42) | 尺寸约束 | `.frame(width: proxy.size.width, height: Theme.Layout.playerBarHeight)` | 共享/运行时分支见源码 |
| [44](../../../Sources/Coda/Features/Player/PlayerBar.swift#L44) | 尺寸约束 | `.frame(height: Theme.Layout.playerBarHeight)` | 共享/运行时分支见源码 |
| [61](../../../Sources/Coda/Features/Player/PlayerBar.swift#L61) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [63](../../../Sources/Coda/Features/Player/PlayerBar.swift#L63) | 自定义组件/原生构造尺寸参数 | `PlayerArtworkFrame(size: 40, style: .dock)` | 共享/运行时分支见源码 |
| [64](../../../Sources/Coda/Features/Player/PlayerBar.swift#L64) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 3)` | 共享/运行时分支见源码 |
| [66](../../../Sources/Coda/Features/Player/PlayerBar.swift#L66) | 字号/字体 | `.font(Theme.Typography.trackTitle)` | 共享/运行时分支见源码 |
| [67](../../../Sources/Coda/Features/Player/PlayerBar.swift#L67) | 尺寸约束 | `.frame(height: 18)` | 共享/运行时分支见源码 |
| [71](../../../Sources/Coda/Features/Player/PlayerBar.swift#L71) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [72](../../../Sources/Coda/Features/Player/PlayerBar.swift#L72) | 尺寸约束 | `.frame(height: 16)` | 共享/运行时分支见源码 |
| [76](../../../Sources/Coda/Features/Player/PlayerBar.swift#L76) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [86](../../../Sources/Coda/Features/Player/PlayerBar.swift#L86) | 容器布局/默认间距 | `HStack(spacing: 0)` | 共享/运行时分支见源码 |
| [88](../../../Sources/Coda/Features/Player/PlayerBar.swift#L88) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "backward.fill", label: "上一首", size: 24, width: 44, tint: .primary, height: 44, disabled: player.isFMMode, action: player.previous)` | 共享/运行时分支见源码 |
| [91](../../../Sources/Coda/Features/Player/PlayerBar.swift#L91) | 自定义组件/原生构造尺寸参数 | `PlayerPlayPauseButton(isPlaying: player.isPlaying, isBuffering: player.isBuffering, size: 26, width: 44, tint: .primary, height: 44, action: player.togglePlayPause)` | 共享/运行时分支见源码 |
| [95](../../../Sources/Coda/Features/Player/PlayerBar.swift#L95) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "forward.fill", label: "下一首", size: 24, width: 44, tint: .primary, height: 44, action: player.next)` | 共享/运行时分支见源码 |
| [100](../../../Sources/Coda/Features/Player/PlayerBar.swift#L100) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "quote.bubble", label: "歌词", size: 19, width: 44, tint: .primary, height: 44, active: player.activePanel == .lyrics)` | #if os(macOS) |
| [105](../../../Sources/Coda/Features/Player/PlayerBar.swift#L105) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "inset.filled.bottomthird.square", label: "桌面歌词", size: 19, width: 44, tint: .primary, height: 44, active: settings.showDesktopLyrics)` | #if os(macOS) |
| [110](../../../Sources/Coda/Features/Player/PlayerBar.swift#L110) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "list.bullet", label: "播放列表", size: 19, width: 44, tint: .primary, height: 44, active: player.activePanel == .queue, disabled: player.isFMMode)` | #if os(macOS) |
| [122](../../../Sources/Coda/Features/Player/PlayerBar.swift#L122) | 字号/字体 | `.font(.system(size: 22, weight: .medium))` | 共享/运行时分支见源码 |
| [123](../../../Sources/Coda/Features/Player/PlayerBar.swift#L123) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [137](../../../Sources/Coda/Features/Player/PlayerBar.swift#L137) | 自定义组件/原生构造尺寸参数 | `PlayerHeartIcon(liked: liked, size: 22)` | 共享/运行时分支见源码 |
| [138](../../../Sources/Coda/Features/Player/PlayerBar.swift#L138) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [186](../../../Sources/Coda/Features/Player/PlayerBar.swift#L186) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 14` | 共享/运行时分支见源码 |
| [198](../../../Sources/Coda/Features/Player/PlayerBar.swift#L198) | 自定义组件/原生构造尺寸参数 | `PlayerHeartIcon(liked: icon == "heart.fill", size: size)` | 共享/运行时分支见源码 |
| [201](../../../Sources/Coda/Features/Player/PlayerBar.swift#L201) | 字号/字体 | `.font(.system(size: size, weight: .medium))` | 共享/运行时分支见源码 |
| [205](../../../Sources/Coda/Features/Player/PlayerBar.swift#L205) | 尺寸约束 | `.frame(width: 26, height: 26)` | 共享/运行时分支见源码 |
| [230](../../../Sources/Coda/Features/Player/PlayerBar.swift#L230) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 22` | 共享/运行时分支见源码 |
| [242](../../../Sources/Coda/Features/Player/PlayerBar.swift#L242) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [252](../../../Sources/Coda/Features/Player/PlayerBar.swift#L252) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 13` | 共享/运行时分支见源码 |
| [258](../../../Sources/Coda/Features/Player/PlayerBar.swift#L258) | 自定义组件/原生构造尺寸参数 | `PlayerIconButton( icon: liked ? "heart.fill" : "heart", size: size, isActive: liked )` | 共享/运行时分支见源码 |
| [276](../../../Sources/Coda/Features/Player/PlayerBar.swift#L276) | 尺寸约束 | `.frame(maxWidth: 460)` | 共享/运行时分支见源码 |
| [283](../../../Sources/Coda/Features/Player/PlayerBar.swift#L283) | 尺寸/字体/间距声明或原生字体 | `var controlWidth: CGFloat = 26` | 共享/运行时分支见源码 |
| [290](../../../Sources/Coda/Features/Player/PlayerBar.swift#L290) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: volumeIcon, label: "音量", size: 19, width: 44, tint: .primary, height: 44)` | 共享/运行时分支见源码 |
| [295](../../../Sources/Coda/Features/Player/PlayerBar.swift#L295) | 自定义组件/原生构造尺寸参数 | `PlayerIconButton(icon: volumeIcon, size: 13)` | 共享/运行时分支见源码 |
| [300](../../../Sources/Coda/Features/Player/PlayerBar.swift#L300) | 内边距 | `.padding(.vertical, 12)` | 共享/运行时分支见源码 |
| [301](../../../Sources/Coda/Features/Player/PlayerBar.swift#L301) | 内边距 | `.padding(.horizontal, 10)` | 共享/运行时分支见源码 |
| [326](../../../Sources/Coda/Features/Player/PlayerBar.swift#L326) | 尺寸约束 | `.frame(width: 22, height: 110)` | 共享/运行时分支见源码 |
| [346](../../../Sources/Coda/Features/Player/PlayerBar.swift#L346) | 内边距 | `.padding(.horizontal, Theme.Layout.iPadPlayerBarHorizontalMargin)` | #if os(iOS) |
| [347](../../../Sources/Coda/Features/Player/PlayerBar.swift#L347) | 内边距 | `.padding(.bottom, Theme.Layout.iPadPlayerBarBottomMargin)` | #if os(iOS) |
| [348](../../../Sources/Coda/Features/Player/PlayerBar.swift#L348) | 尺寸约束 | `.frame(width: geometry.layout.width)` | #if os(iOS) |
| [349](../../../Sources/Coda/Features/Player/PlayerBar.swift#L349) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .trailing)` | #if os(iOS) |
| [381](../../../Sources/Coda/Features/Player/PlayerBar.swift#L381) | 尺寸/字体/间距声明或原生字体 | `let width: CGFloat` | 共享/运行时分支见源码 |
| [382](../../../Sources/Coda/Features/Player/PlayerBar.swift#L382) | 尺寸/字体/间距声明或原生字体 | `var height: CGFloat = 64` | 共享/运行时分支见源码 |
| [384](../../../Sources/Coda/Features/Player/PlayerBar.swift#L384) | 尺寸/字体/间距声明或原生字体 | `private var glyphScale: CGFloat { min(1, width / 280) }` | 共享/运行时分支见源码 |
| [411](../../../Sources/Coda/Features/Player/PlayerBar.swift#L411) | 容器布局/默认间距 | `HStack(spacing: 0)` | 共享/运行时分支见源码 |
| [412](../../../Sources/Coda/Features/Player/PlayerBar.swift#L412) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton( icon: player.isFMMode ? "trash" : orderIcon, label: player.isFMMode ? "不喜欢" : "随机播放", size: 17 * glyphScale, width: width / 5, height: height, active: !player.isFMMode && orderActive )` | 共享/运行时分支见源码 |
| [420](../../../Sources/Coda/Features/Player/PlayerBar.swift#L420) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "backward.fill", label: "上一首", size: 28 * glyphScale, width: width / 5, height: height, disabled: player.isFMMode, action: player.previous)` | 共享/运行时分支见源码 |
| [422](../../../Sources/Coda/Features/Player/PlayerBar.swift#L422) | 自定义组件/原生构造尺寸参数 | `PlayerPlayPauseButton(isPlaying: player.isPlaying, isBuffering: player.isBuffering, size: 40 * glyphScale, width: width / 5, height: height, action: player.togglePlayPause)` | 共享/运行时分支见源码 |
| [426](../../../Sources/Coda/Features/Player/PlayerBar.swift#L426) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: "forward.fill", label: "下一首", size: 28 * glyphScale, width: width / 5, height: height, action: player.next)` | 共享/运行时分支见源码 |
| [428](../../../Sources/Coda/Features/Player/PlayerBar.swift#L428) | 自定义组件/原生构造尺寸参数 | `PlayerTransportButton(icon: player.repeatMode == .one ? "repeat.1" : "repeat", label: "循环模式", size: 17 * glyphScale, width: width / 5, height: height, active: player.repeatMode != .off, disabled: player.isFMMode, action: player.cycleRepeatMode)` | 共享/运行时分支见源码 |
| [445](../../../Sources/Coda/Features/Player/PlayerBar.swift#L445) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 28` | 共享/运行时分支见源码 |
| [446](../../../Sources/Coda/Features/Player/PlayerBar.swift#L446) | 尺寸/字体/间距声明或原生字体 | `let width: CGFloat` | 共享/运行时分支见源码 |
| [448](../../../Sources/Coda/Features/Player/PlayerBar.swift#L448) | 尺寸/字体/间距声明或原生字体 | `var height: CGFloat = 64` | 共享/运行时分支见源码 |
| [456](../../../Sources/Coda/Features/Player/PlayerBar.swift#L456) | 字号/字体 | `.font(.system(size: size, weight: .semibold))` | 共享/运行时分支见源码 |
| [458](../../../Sources/Coda/Features/Player/PlayerBar.swift#L458) | 尺寸约束 | `.frame(width: width, height: height)` | 共享/运行时分支见源码 |
| [463](../../../Sources/Coda/Features/Player/PlayerBar.swift#L463) | 尺寸约束 | `.frame(width: 34, height: 30)` | 共享/运行时分支见源码 |
| [479](../../../Sources/Coda/Features/Player/PlayerBar.swift#L479) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 40` | 共享/运行时分支见源码 |
| [480](../../../Sources/Coda/Features/Player/PlayerBar.swift#L480) | 尺寸/字体/间距声明或原生字体 | `let width: CGFloat` | 共享/运行时分支见源码 |
| [482](../../../Sources/Coda/Features/Player/PlayerBar.swift#L482) | 尺寸/字体/间距声明或原生字体 | `var height: CGFloat = 64` | 共享/运行时分支见源码 |
| [487](../../../Sources/Coda/Features/Player/PlayerBar.swift#L487) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [492](../../../Sources/Coda/Features/Player/PlayerBar.swift#L492) | 字号/字体 | `.font(.system(size: size, weight: .semibold))` | 共享/运行时分支见源码 |
| [496](../../../Sources/Coda/Features/Player/PlayerBar.swift#L496) | 尺寸约束 | `.frame(width: width, height: height)` | 共享/运行时分支见源码 |

## RoutePickerButton

源码：`Sources/Kumone/Features/Player/RoutePickerButton.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [14](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L14) | 尺寸/字体/间距声明或原生字体 | `var glyphSize: CGFloat = 15` | 共享/运行时分支见源码 |
| [30](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L30) | 自定义组件/原生构造尺寸参数 | `OutputDevicePicker( diameter: diameter, glyphSize: glyphSize, tint: tint, background: background)` | #if os(macOS) |
| [33](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L33) | 自定义组件/原生构造尺寸参数 | `RoutePickerRepresentable( tint: PlatformColor(tint), glyphSize: glyphSize, request: request )` | #if os(macOS) / #else |
| [36](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L36) | 尺寸约束 | `.frame(width: diameter, height: diameter)` | #if os(macOS) / #else |
| [56](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L56) | 容器布局/默认间距 | `HStack(spacing: 8)` | #if os(iOS) |
| [58](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L58) | 尺寸约束 | `.frame(width: 24)` | #if os(iOS) |
| [59](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L59) | 字号/字体 | `.font(.system(size: 19, weight: .medium))` | #if os(iOS) |
| [64](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L64) | 字号/字体 | `.font(.system(size: 13, weight: .medium))` | #if os(iOS) |
| [70](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L70) | 内边距 | `.padding(.horizontal, showsName ? 8 : 0)` | #if os(iOS) |
| [71](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L71) | 尺寸约束 | `.frame(minWidth: 44, maxWidth: showsName ? nil : 44, minHeight: 44)` | #if os(iOS) |
| [176](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L176) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: min(44, bounds.width), height: bounds.height)` | #if os(iOS) |
| [248](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L248) | 尺寸/字体/间距声明或原生字体 | `let glyphSize: CGFloat` | #if os(iOS) |
| [311](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L311) | 尺寸/字体/间距声明或原生字体 | `var glyphSize: CGFloat = 15` | #if os(iOS) / #elseif os(macOS) |
| [325](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L325) | 字号/字体 | `.font(.system(size: glyphSize, weight: .medium))` | #if os(iOS) / #elseif os(macOS) |
| [327](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L327) | 尺寸约束 | `.frame(width: diameter, height: diameter)` | #if os(iOS) / #elseif os(macOS) |
| [332](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L332) | 尺寸约束 | `.frame(width: diameter, height: diameter)` | #if os(iOS) / #elseif os(macOS) |
| [388](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L388) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 0)` | #if os(iOS) / #elseif os(macOS) |
| [390](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L390) | 字号/字体 | `.font(.system(size: 13, weight: .semibold))` | #if os(iOS) / #elseif os(macOS) |
| [391](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L391) | 内边距 | `.padding(.horizontal, 14)` | #if os(iOS) / #elseif os(macOS) |
| [392](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L392) | 内边距 | `.padding(.top, 12)` | #if os(iOS) / #elseif os(macOS) |
| [393](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L393) | 内边距 | `.padding(.bottom, 6)` | #if os(iOS) / #elseif os(macOS) |
| [415](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L415) | 字号/字体 | `.font(.system(size: 11))` | #if os(iOS) / #elseif os(macOS) |
| [418](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L418) | 内边距 | `.padding(.horizontal, 14)` | #if os(iOS) / #elseif os(macOS) |
| [419](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L419) | 内边距 | `.padding(.vertical, 4)` | #if os(iOS) / #elseif os(macOS) |
| [424](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L424) | 内边距 | `.padding(.horizontal, 14)` | #if os(iOS) / #elseif os(macOS) |
| [425](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L425) | 内边距 | `.padding(.vertical, 6)` | #if os(iOS) / #elseif os(macOS) |
| [429](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L429) | 内边距 | `.padding(.bottom, 6)` | #if os(iOS) / #elseif os(macOS) |
| [430](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L430) | 尺寸约束 | `.frame(width: 290)` | #if os(iOS) / #elseif os(macOS) |
| [450](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L450) | 字号/字体 | `.font(.system(size: 11, weight: .semibold))` | #if os(iOS) / #elseif os(macOS) |
| [452](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L452) | 内边距 | `.padding(.horizontal, 14)` | #if os(iOS) / #elseif os(macOS) |
| [453](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L453) | 内边距 | `.padding(.top, 8)` | #if os(iOS) / #elseif os(macOS) |
| [454](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L454) | 内边距 | `.padding(.bottom, 2)` | #if os(iOS) / #elseif os(macOS) |
| [464](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L464) | 容器布局/默认间距 | `HStack(spacing: 10)` | #if os(iOS) / #elseif os(macOS) |
| [465](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L465) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) / #elseif os(macOS) |
| [470](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L470) | 字号/字体 | `.font(.system(size: 12, weight: .medium))` | #if os(iOS) / #elseif os(macOS) |
| [474](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L474) | 尺寸约束 | `.frame(width: 26, height: 26)` | #if os(iOS) / #elseif os(macOS) |
| [476](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L476) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 1)` | #if os(iOS) / #elseif os(macOS) |
| [478](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L478) | 字号/字体 | `.font(.system(size: 13))` | #if os(iOS) / #elseif os(macOS) |
| [482](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L482) | 字号/字体 | `.font(.system(size: 11))` | #if os(iOS) / #elseif os(macOS) |
| [488](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L488) | 容器布局/默认间距 | `Spacer(minLength: 8)` | #if os(iOS) / #elseif os(macOS) |
| [492](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L492) | 字号/字体 | `.font(.system(size: 11, weight: .semibold))` | #if os(iOS) / #elseif os(macOS) |
| [504](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L504) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(iOS) / #elseif os(macOS) |
| [506](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L506) | 字号/字体 | `.font(.system(size: 13))` | #if os(iOS) / #elseif os(macOS) |
| [507](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L507) | 容器布局/默认间距 | `Spacer()` | #if os(iOS) / #elseif os(macOS) |
| [597](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L597) | 内边距 | `.padding(.horizontal, 8)` | #if os(iOS) / #elseif os(macOS) |
| [598](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L598) | 内边距 | `.padding(.vertical, 5)` | #if os(iOS) / #elseif os(macOS) |
| [606](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L606) | 内边距 | `.padding(.horizontal, 6)` | #if os(iOS) / #elseif os(macOS) |
| [675](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L675) | 容器布局/默认间距 | `HStack(spacing: 8)` | #if os(macOS) |
| [677](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L677) | 尺寸约束 | `.frame(width: 24)` | #if os(macOS) |
| [678](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L678) | 字号/字体 | `.font(.system(size: 19, weight: .medium))` | #if os(macOS) |
| [682](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L682) | 字号/字体 | `.font(.system(size: 13, weight: .medium))` | #if os(macOS) |
| [688](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L688) | 内边距 | `.padding(.horizontal, showsName ? 8 : 0)` | #if os(macOS) |
| [689](../../../Sources/Coda/Features/Player/RoutePickerButton.swift#L689) | 尺寸约束 | `.frame(minWidth: 44, maxWidth: showsName ? nil : 44, minHeight: 44)` | #if os(macOS) |

## SongCommentsColumn

源码：`Sources/Kumone/Features/Player/SongCommentsColumn.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [21](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L21) | 内边距 | `.padding(.bottom, SongCommentsKeyboardLayout.bottomInset( column: geometry.frame(in: .global), keyboard: keyboardFrame, window: keyboardWindow ))` | 共享/运行时分支见源码 |
| [22](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L22) | 尺寸约束 | `.frame(in: .global)` | 共享/运行时分支见源码 |
| [58](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L58) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [59](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L59) | 容器布局/默认间距 | `HStack(alignment: .center, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [61](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L61) | 字号/字体 | `.font(Theme.Typography.sectionTitle.weight(.bold))` | 共享/运行时分支见源码 |
| [64](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L64) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [73](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L73) | 尺寸约束 | `.frame(width: 164)` | 共享/运行时分支见源码 |
| [78](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L78) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | 共享/运行时分支见源码 |
| [82](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L82) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [83](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L83) | 内边距 | `.padding(.top, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [84](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L84) | 内边距 | `.padding(.bottom, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [109](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L109) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [113](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L113) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 140)` | 共享/运行时分支见源码 |
| [115](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L115) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [124](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L124) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 140)` | 共享/运行时分支见源码 |
| [127](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L127) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L129) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 140)` | 共享/运行时分支见源码 |
| [133](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L133) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [134](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L134) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [137](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L137) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [143](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L143) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [145](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L145) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [154](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L154) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 44)` | 共享/运行时分支见源码 |
| [158](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L158) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [167](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L167) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [169](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L169) | 尺寸约束 | `.frame(width: 34, height: 34)` | 共享/运行时分支见源码 |
| [171](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L171) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L172) | 容器布局/默认间距 | `HStack(alignment: .top)` | 共享/运行时分支见源码 |
| [173](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L173) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [175](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L175) | 字号/字体 | `.font(Theme.Typography.secondary.weight(.semibold))` | 共享/运行时分支见源码 |
| [178](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L178) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [181](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L181) | 容器布局/默认间距 | `Spacer(minLength: 4)` | 共享/运行时分支见源码 |
| [186](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L186) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [187](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L187) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [189](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L189) | 字号/字体 | `.font(.system(size: 14))` | 共享/运行时分支见源码 |
| [192](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L192) | 尺寸约束 | `.frame(minWidth: 44, minHeight: 34)` | 共享/运行时分支见源码 |
| [200](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L200) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [207](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L207) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [209](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L209) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [210](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L210) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [218](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L218) | 字号/字体 | `.font(.system(size: 12, weight: .medium))` | 共享/运行时分支见源码 |
| [240](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L240) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | 共享/运行时分支见源码 |
| [241](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L241) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 48)` | 共享/运行时分支见源码 |
| [246](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L246) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [248](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L248) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [250](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L250) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [253](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L253) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [257](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L257) | 尺寸约束 | `.frame(width: 32, height: 32)` | 共享/运行时分支见源码 |
| [262](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L262) | 容器布局/默认间距 | `HStack(alignment: .bottom, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [263](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L263) | 容器布局/默认间距 | `TextField("写下你的感受…", text: $model.draft, axis: .vertical)` | 共享/运行时分支见源码 |
| [264](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L264) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [268](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L268) | 内边距 | `.padding(Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [280](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L280) | 字号/字体 | `.font(.system(size: 17, weight: .bold))` | 共享/运行时分支见源码 |
| [282](../../../Sources/Coda/Features/Player/SongCommentsColumn.swift#L282) | 尺寸约束 | `.frame(width: 42, height: 42)` | 共享/运行时分支见源码 |

## AppNavigationBarBackground

源码：`Sources/Kumone/Features/Shared/AppNavigationBarBackground.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [138](../../../Sources/Coda/Features/Shared/AppNavigationBarBackground.swift#L138) | 自定义组件/原生构造尺寸参数 | `CGSize(width: 2, height: 128)` | #if os(iOS) |
| [138](../../../Sources/Coda/Features/Shared/AppNavigationBarBackground.swift#L138) | 尺寸/字体/间距声明或原生字体 | `let size = CGSize(width: 2, height: 128)` | #if os(iOS) |
| [141](../../../Sources/Coda/Features/Shared/AppNavigationBarBackground.swift#L141) | 自定义组件/原生构造尺寸参数 | `UIGraphicsImageRenderer(size: size, format: format)` | #if os(iOS) |

## DownloadProgressIcon

源码：`Sources/Kumone/Features/Shared/DownloadProgressIcon.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [5](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L5) | 尺寸/字体/间距声明或原生字体 | `var size: CGFloat = 18` | 共享/运行时分支见源码 |
| [9](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L9) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [21](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L21) | 字号/字体 | `.font(.system(size: size * 0.4, weight: .semibold))` | 共享/运行时分支见源码 |
| [23](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L23) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |
| [34](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L34) | 尺寸/字体/间距声明或原生字体 | `let size: CGFloat` | 共享/运行时分支见源码 |
| [35](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L35) | 尺寸/字体/间距声明或原生字体 | `let symbolSize: CGFloat` | 共享/运行时分支见源码 |
| [52](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L52) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [55](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L55) | 字号/字体 | `.font(.system(size: symbolSize, weight: .medium))` | 共享/运行时分支见源码 |
| [58](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L58) | 自定义组件/原生构造尺寸参数 | `DownloadProgressIcon(progress: isComplete ? 1 : progress, size: size)` | 共享/运行时分支见源码 |
| [62](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L62) | 字号/字体 | `.font(.system(size: symbolSize, weight: .medium))` | 共享/运行时分支见源码 |
| [65](../../../Sources/Coda/Features/Shared/DownloadProgressIcon.swift#L65) | 尺寸约束 | `.frame(width: size, height: size)` | 共享/运行时分支见源码 |

## MainColumnGeometry

源码：`Sources/Kumone/Features/Shared/MainColumnGeometry.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [9](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L9) | 尺寸/字体/间距声明或原生字体 | `var width: CGFloat = 0` | 共享/运行时分支见源码 |
| [10](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L10) | 尺寸/字体/间距声明或原生字体 | `var leadingInset: CGFloat = 0` | 共享/运行时分支见源码 |
| [30](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L30) | 尺寸/字体/间距声明或原生字体 | `private(set) var lastActiveSize: CGSize?` | 共享/运行时分支见源码 |
| [122](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L122) | 尺寸/字体/间距声明或原生字体 | `private var lastWindowSize: CGSize?` | #if os(iOS) |
| [214](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L214) | 尺寸/字体/间距声明或原生字体 | `let windowSize = window.bounds.size` | #if os(iOS) |
| [215](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L215) | 尺寸/字体/间距声明或原生字体 | `let scale = window.screen.scale` | #if os(iOS) |
| [216](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L216) | 自定义组件/原生构造尺寸参数 | `CGRect(x: (visible.minX * scale).rounded() / scale, y: visible.minY, width: (visible.width * scale).rounded() / scale, height: visible.height)` | #if os(iOS) |
| [232](../../../Sources/Coda/Features/Shared/MainColumnGeometry.swift#L232) | 尺寸/字体/间距声明或原生字体 | `let changesWidth = next.width != self.geometry?.layout.width` | #if os(iOS) |

## MainWindowAmbientBackground

源码：`Sources/Kumone/Features/Shared/MainWindowAmbientBackground.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [30](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L30) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [67](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L67) | 尺寸约束 | `.frame(width: geometry.layout.width)` | 共享/运行时分支见源码 |
| [88](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L88) | 尺寸/字体/间距声明或原生字体 | `var mainColumnLeadingInset: CGFloat = 0` | #if os(macOS) |
| [107](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L107) | 尺寸/字体/间距声明或原生字体 | `private var hadFullSizeContentView = false` | #if os(macOS) |
| [161](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L161) | 尺寸/字体/间距声明或原生字体 | `let fullSize = extendsContentIntoTitlebar \|\| hadFullSizeContentView` | #if os(macOS) |
| [204](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L204) | 尺寸/字体/间距声明或原生字体 | `let leadingInset = max(configuration.mainColumnLeadingInset, 0)` | #if os(macOS) |
| [205](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L205) | 尺寸/字体/间距声明或原生字体 | `let width = max(contentView.bounds.width - leadingInset, 0)` | #if os(macOS) |
| [211](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L211) | 尺寸/字体/间距声明或原生字体 | `let titlebarHeight = contentView.bounds.height - window.contentLayoutRect.height` | #if os(macOS) |
| [219](../../../Sources/Coda/Features/Shared/MainWindowAmbientBackground.swift#L219) | 自定义组件/原生构造尺寸参数 | `CGRect( x: contentView.bounds.maxX - width, y: y, width: width, height: titlebarHeight )` | #if os(macOS) |

## PanelRefresh

源码：`Sources/Kumone/Features/Shared/PanelRefresh.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [186](../../../Sources/Coda/Features/Shared/PanelRefresh.swift#L186) | 容器布局/默认间距 | `HStack(spacing: 12)` | 共享/运行时分支见源码 |
| [188](../../../Sources/Coda/Features/Shared/PanelRefresh.swift#L188) | 字号/字体 | `.font(.caption)` | 共享/运行时分支见源码 |
| [190](../../../Sources/Coda/Features/Shared/PanelRefresh.swift#L190) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [193](../../../Sources/Coda/Features/Shared/PanelRefresh.swift#L193) | 内边距 | `.padding(12)` | 共享/运行时分支见源码 |

## PlaylistArtwork

源码：`Sources/Kumone/Features/Shared/PlaylistArtwork.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [34](../../../Sources/Coda/Features/Shared/PlaylistArtwork.swift#L34) | 尺寸/字体/间距声明或原生字体 | `var pixelSize: Int = 384` | 共享/运行时分支见源码 |

## ProfileDetailLayout

源码：`Sources/Kumone/Features/Shared/ProfileDetailLayout.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [5](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L5) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var sizeClass` | 共享/运行时分支见源码 |
| [15](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L15) | 尺寸/字体/间距声明或原生字体 | `var contentInset: CGFloat { Theme.Layout.contentInset }` | 共享/运行时分支见源码 |
| [16](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L16) | 尺寸/字体/间距声明或原生字体 | `var sectionSpacing: CGFloat { Theme.Spacing.section }` | 共享/运行时分支见源码 |
| [35](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L35) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: layout.sectionSpacing)` | 共享/运行时分支见源码 |
| [71](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L71) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) |
| [81](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L81) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | #if os(iOS) / #else |
| [82](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L82) | 容器布局/默认间距 | `HStack(alignment: .center, spacing: Theme.Spacing.component)` | #if os(iOS) / #else |
| [89](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L89) | 容器布局/默认间距 | `HStack(alignment: .center, spacing: Theme.Spacing.group)` | #if os(iOS) / #else |
| [91](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L91) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | #if os(iOS) / #else |
| [93](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L93) | 容器布局/默认间距 | `Spacer(minLength: 6)` | #if os(iOS) / #else |
| [96](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L96) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | #if os(iOS) / #else |
| [100](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L100) | 内边距 | `.padding(.horizontal, layout.contentInset)` | #if os(iOS) / #else |
| [101](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L101) | 内边距 | `.padding(.top, layout.isCompact ? 12 : 16)` | #if os(iOS) / #else |
| [107](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L107) | 尺寸约束 | `.frame(width: layout.isCompact ? 100 : 180, height: layout.isCompact ? 100 : 180)` | 共享/运行时分支见源码 |
| [115](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L115) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: layout.isCompact ? 5 : 8)` | 共享/运行时分支见源码 |
| [118](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L118) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [123](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L123) | 字号/字体 | `.font(Theme.Typography.pageTitle)` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L129) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [143](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L143) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [146](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L146) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [161](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L161) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [163](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L163) | 尺寸约束 | `.frame(width: layout.isCompact ? 80 : 100, height: layout.isCompact ? 80 : 100)` | 共享/运行时分支见源码 |
| [166](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L166) | 字号/字体 | `.font(Theme.Typography.cardTitle)` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/Features/Shared/ProfileDetailLayout.swift#L170) | 尺寸约束 | `.frame(width: layout.isCompact ? 80 : 100)` | 共享/运行时分支见源码 |

## TrackDownloadButton

源码：`Sources/Kumone/Features/Shared/TrackDownloadButton.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [41](../../../Sources/Coda/Features/Shared/TrackDownloadButton.swift#L41) | 尺寸约束 | `.frame(width: 24, height: 24)` | 共享/运行时分支见源码 |
| [125](../../../Sources/Coda/Features/Shared/TrackDownloadButton.swift#L125) | 自定义组件/原生构造尺寸参数 | `DownloadButtonIcon(isActive: isActive, isComplete: isComplete, progress: showsFraction ? progress.fraction : nil, size: 16, symbolSize: 12, completedSymbol: "arrow.down.circle.fill")` | 共享/运行时分支见源码 |

## TrackList

源码：`Sources/Kumone/Features/Shared/TrackList.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [14](../../../Sources/Coda/Features/Shared/TrackList.swift#L14) | 尺寸/字体/间距声明或原生字体 | `var desktopRowHeight: CGFloat { Theme.Layout.trackRowHeight }` | 共享/运行时分支见源码 |
| [54](../../../Sources/Coda/Features/Shared/TrackList.swift#L54) | 尺寸/字体/间距声明或原生字体 | `static let chartRankColumnWidth: CGFloat = 52` | 共享/运行时分支见源码 |
| [81](../../../Sources/Coda/Features/Shared/TrackList.swift#L81) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var compactArtworkSize: CGFloat = Theme.Layout.trackArtworkSize` | 共享/运行时分支见源码 |
| [82](../../../Sources/Coda/Features/Shared/TrackList.swift#L82) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var compactRowHeight: CGFloat = Theme.Layout.trackRowHeight` | 共享/运行时分支见源码 |
| [83](../../../Sources/Coda/Features/Shared/TrackList.swift#L83) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var compactAlbumRowHeight: CGFloat = 50` | 共享/运行时分支见源码 |
| [144](../../../Sources/Coda/Features/Shared/TrackList.swift#L144) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [153](../../../Sources/Coda/Features/Shared/TrackList.swift#L153) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [159](../../../Sources/Coda/Features/Shared/TrackList.swift#L159) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [166](../../../Sources/Coda/Features/Shared/TrackList.swift#L166) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [174](../../../Sources/Coda/Features/Shared/TrackList.swift#L174) | 字号/字体 | `.font(.system(size: 12))` | 共享/运行时分支见源码 |
| [180](../../../Sources/Coda/Features/Shared/TrackList.swift#L180) | 尺寸约束 | `.frame(maxWidth: 220, alignment: .leading)` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/Features/Shared/TrackList.swift#L183) | 字号/字体 | `.font(.system(size: 12))` | 共享/运行时分支见源码 |
| [186](../../../Sources/Coda/Features/Shared/TrackList.swift#L186) | 尺寸约束 | `.frame(maxWidth: 220, alignment: .leading)` | 共享/运行时分支见源码 |
| [192](../../../Sources/Coda/Features/Shared/TrackList.swift#L192) | 字号/字体 | `.font(.system(size: 10, weight: .medium))` | 共享/运行时分支见源码 |
| [194](../../../Sources/Coda/Features/Shared/TrackList.swift#L194) | 内边距 | `.padding(.horizontal, 5)` | 共享/运行时分支见源码 |
| [195](../../../Sources/Coda/Features/Shared/TrackList.swift#L195) | 内边距 | `.padding(.vertical, 2)` | 共享/运行时分支见源码 |
| [201](../../../Sources/Coda/Features/Shared/TrackList.swift#L201) | 字号/字体 | `.font(Theme.Typography.caption.monospacedDigit())` | 共享/运行时分支见源码 |
| [207](../../../Sources/Coda/Features/Shared/TrackList.swift#L207) | 内边距 | `.padding(.leading, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [210](../../../Sources/Coda/Features/Shared/TrackList.swift#L210) | 内边距 | `.padding(.horizontal, Theme.Layout.trackRowHorizontalInset)` | 共享/运行时分支见源码 |
| [211](../../../Sources/Coda/Features/Shared/TrackList.swift#L211) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [213](../../../Sources/Coda/Features/Shared/TrackList.swift#L213) | 尺寸约束 | `.frame(height: rowHeight)` | 共享/运行时分支见源码 |
| [273](../../../Sources/Coda/Features/Shared/TrackList.swift#L273) | 尺寸约束 | `.frame(width: compactArtworkSize, height: compactArtworkSize)` | 共享/运行时分支见源码 |
| [278](../../../Sources/Coda/Features/Shared/TrackList.swift#L278) | 尺寸约束 | `.frame(width: style == .likedMusic ? 48 : 42, height: style == .likedMusic ? 48 : 42)` | 共享/运行时分支见源码 |
| [287](../../../Sources/Coda/Features/Shared/TrackList.swift#L287) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) |
| [294](../../../Sources/Coda/Features/Shared/TrackList.swift#L294) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) / #else |
| [298](../../../Sources/Coda/Features/Shared/TrackList.swift#L298) | 容器布局/默认间距 | `HStack(spacing: 0)` | #if os(iOS) / #else |
| [312](../../../Sources/Coda/Features/Shared/TrackList.swift#L312) | 字号/字体 | `.font(Theme.Typography.secondary)` | #if os(iOS) / #else |
| [319](../../../Sources/Coda/Features/Shared/TrackList.swift#L319) | 尺寸/字体/间距声明或原生字体 | `private var rowHeight: CGFloat { if isCompact { return compactRowHeight } if style == .likedMusic { return 64 } if style == .albumTrack { return isCompact ? compactAlbumRowHeight : style.desktopRowHeight } return isCompact ? compactRowHeight : style.desktopRowHeight }` | 共享/运行时分支见源码 |
| [330](../../../Sources/Coda/Features/Shared/TrackList.swift#L330) | 容器布局/默认间距 | `ZStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [336](../../../Sources/Coda/Features/Shared/TrackList.swift#L336) | 字号/字体 | `.font(.system(size: 11, weight: .semibold))` | 共享/运行时分支见源码 |
| [342](../../../Sources/Coda/Features/Shared/TrackList.swift#L342) | 字号/字体 | `.font(.system(size: 12).monospacedDigit())` | 共享/运行时分支见源码 |
| [346](../../../Sources/Coda/Features/Shared/TrackList.swift#L346) | 尺寸约束 | `.frame(width: 28)` | 共享/运行时分支见源码 |
| [351](../../../Sources/Coda/Features/Shared/TrackList.swift#L351) | 字号/字体 | `.font(Theme.Typography.trackTitle)` | 共享/运行时分支见源码 |
| [356](../../../Sources/Coda/Features/Shared/TrackList.swift#L356) | 字号/字体 | `.font(.system(size: 12))` | 共享/运行时分支见源码 |
| [361](../../../Sources/Coda/Features/Shared/TrackList.swift#L361) | 容器布局/默认间距 | `HStack(spacing: 8)` | 共享/运行时分支见源码 |
| [373](../../../Sources/Coda/Features/Shared/TrackList.swift#L373) | 自定义组件/原生构造尺寸参数 | `PlayerHeartIcon(liked: true, size: 18)` | 共享/运行时分支见源码 |
| [374](../../../Sources/Coda/Features/Shared/TrackList.swift#L374) | 尺寸约束 | `.frame(width: 24, height: 24)` | 共享/运行时分支见源码 |
| [383](../../../Sources/Coda/Features/Shared/TrackList.swift#L383) | 容器布局/默认间距 | `ZStack(alignment: .center)` | 共享/运行时分支见源码 |
| [389](../../../Sources/Coda/Features/Shared/TrackList.swift#L389) | 容器布局/默认间距 | `VStack(alignment: .center, spacing: 3)` | 共享/运行时分支见源码 |
| [391](../../../Sources/Coda/Features/Shared/TrackList.swift#L391) | 字号/字体 | `.font(.system(size: 13, weight: .medium).monospacedDigit())` | 共享/运行时分支见源码 |
| [397](../../../Sources/Coda/Features/Shared/TrackList.swift#L397) | 尺寸约束 | `.frame(width: Self.chartRankColumnWidth, alignment: .center)` | 共享/运行时分支见源码 |
| [400](../../../Sources/Coda/Features/Shared/TrackList.swift#L400) | 容器布局/默认间距 | `ZStack(alignment: .center)` | 共享/运行时分支见源码 |
| [402](../../../Sources/Coda/Features/Shared/TrackList.swift#L402) | 字号/字体 | `.font(Theme.Typography.caption.monospacedDigit())` | 共享/运行时分支见源码 |
| [412](../../../Sources/Coda/Features/Shared/TrackList.swift#L412) | 尺寸约束 | `.frame(width: 36, alignment: .center)` | 共享/运行时分支见源码 |
| [420](../../../Sources/Coda/Features/Shared/TrackList.swift#L420) | 容器布局/默认间距 | `HStack(spacing: 2)` | 共享/运行时分支见源码 |
| [423](../../../Sources/Coda/Features/Shared/TrackList.swift#L423) | 字号/字体 | `.font(.system(size: 7))` | 共享/运行时分支见源码 |
| [426](../../../Sources/Coda/Features/Shared/TrackList.swift#L426) | 字号/字体 | `.font(.system(size: 10).monospacedDigit())` | 共享/运行时分支见源码 |
| [433](../../../Sources/Coda/Features/Shared/TrackList.swift#L433) | 字号/字体 | `.font(.system(size: 9, weight: .semibold))` | 共享/运行时分支见源码 |
| [438](../../../Sources/Coda/Features/Shared/TrackList.swift#L438) | 容器布局/默认间距 | `HStack(spacing: 2)` | 共享/运行时分支见源码 |
| [441](../../../Sources/Coda/Features/Shared/TrackList.swift#L441) | 字号/字体 | `.font(.system(size: 7))` | 共享/运行时分支见源码 |
| [444](../../../Sources/Coda/Features/Shared/TrackList.swift#L444) | 字号/字体 | `.font(.system(size: 10).monospacedDigit())` | 共享/运行时分支见源码 |
| [451](../../../Sources/Coda/Features/Shared/TrackList.swift#L451) | 字号/字体 | `.font(.system(size: 10))` | 共享/运行时分支见源码 |
| [542](../../../Sources/Coda/Features/Shared/TrackList.swift#L542) | 尺寸约束 | `.frame(width: SpectrumBarsView.width, height: SpectrumBarsView.maxHeight)` | 共享/运行时分支见源码 |
| [571](../../../Sources/Coda/Features/Shared/TrackList.swift#L571) | 尺寸/字体/间距声明或原生字体 | `static let minHeight: CGFloat = 3` | 共享/运行时分支见源码 |
| [572](../../../Sources/Coda/Features/Shared/TrackList.swift#L572) | 尺寸/字体/间距声明或原生字体 | `static let maxHeight: CGFloat = 14` | 共享/运行时分支见源码 |
| [573](../../../Sources/Coda/Features/Shared/TrackList.swift#L573) | 尺寸/字体/间距声明或原生字体 | `static let barWidth: CGFloat = 2.5` | 共享/运行时分支见源码 |
| [574](../../../Sources/Coda/Features/Shared/TrackList.swift#L574) | 尺寸/字体/间距声明或原生字体 | `static let spacing: CGFloat = 2` | 共享/运行时分支见源码 |
| [575](../../../Sources/Coda/Features/Shared/TrackList.swift#L575) | 尺寸/字体/间距声明或原生字体 | `static let width =` | 共享/运行时分支见源码 |
| [591](../../../Sources/Coda/Features/Shared/TrackList.swift#L591) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: Self.width, height: Self.maxHeight)` | 共享/运行时分支见源码 |
| [615](../../../Sources/Coda/Features/Shared/TrackList.swift#L615) | 自定义组件/原生构造尺寸参数 | `CGRect(x: 0, y: 0, width: Self.barWidth, height: Self.maxHeight)` | 共享/运行时分支见源码 |
| [692](../../../Sources/Coda/Features/Shared/TrackList.swift#L692) | 尺寸/字体/间距声明或原生字体 | `let height = Self.minHeight + span * level` | 共享/运行时分支见源码 |
| [713](../../../Sources/Coda/Features/Shared/TrackList.swift#L713) | 尺寸/字体/间距声明或原生字体 | `let columnWidth: CGFloat` | 共享/运行时分支见源码 |
| [714](../../../Sources/Coda/Features/Shared/TrackList.swift#L714) | 尺寸/字体/间距声明或原生字体 | `let rowHeight: CGFloat` | 共享/运行时分支见源码 |
| [725](../../../Sources/Coda/Features/Shared/TrackList.swift#L725) | 尺寸/字体/间距声明或原生字体 | `private let rowSpacing: CGFloat = 1` | 共享/运行时分支见源码 |
| [761](../../../Sources/Coda/Features/Shared/TrackList.swift#L761) | 容器布局/默认间距 | `LazyHGrid(rows: Array(repeating: GridItem(.fixed(horizontalLayout.rowHeight), spacing: rowSpacing), count: max(1, horizontalLayout.rows)), alignment: .top, spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [761](../../../Sources/Coda/Features/Shared/TrackList.swift#L761) | 容器布局/默认间距 | `GridItem(.fixed(horizontalLayout.rowHeight), spacing: rowSpacing)` | 共享/运行时分支见源码 |
| [761](../../../Sources/Coda/Features/Shared/TrackList.swift#L761) | 自定义组件/原生构造尺寸参数 | `Array(repeating: GridItem(.fixed(horizontalLayout.rowHeight), spacing: rowSpacing), count: max(1, horizontalLayout.rows))` | 共享/运行时分支见源码 |
| [765](../../../Sources/Coda/Features/Shared/TrackList.swift#L765) | 尺寸约束 | `.frame(width: horizontalLayout.columnWidth)` | 共享/运行时分支见源码 |
| [772](../../../Sources/Coda/Features/Shared/TrackList.swift#L772) | 容器布局/默认间距 | `LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: showsColumnSeparator ? MusicLibraryTrackLayout.dividedColumnSpacing : Theme.Spacing.component), count: columns), alignment: .leading, spacing: rowSpacing)` | 共享/运行时分支见源码 |
| [772](../../../Sources/Coda/Features/Shared/TrackList.swift#L772) | 容器布局/默认间距 | `GridItem(.flexible(), spacing: showsColumnSeparator ? MusicLibraryTrackLayout.dividedColumnSpacing : Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [772](../../../Sources/Coda/Features/Shared/TrackList.swift#L772) | 自定义组件/原生构造尺寸参数 | `Array(repeating: GridItem(.flexible(), spacing: showsColumnSeparator ? MusicLibraryTrackLayout.dividedColumnSpacing : Theme.Spacing.component), count: columns)` | 共享/运行时分支见源码 |
| [781](../../../Sources/Coda/Features/Shared/TrackList.swift#L781) | 尺寸约束 | `.frame(width: 0.5)` | 共享/运行时分支见源码 |
| [788](../../../Sources/Coda/Features/Shared/TrackList.swift#L788) | 容器布局/默认间距 | `LazyVStack(spacing: rowSpacing)` | 共享/运行时分支见源码 |
| [826](../../../Sources/Coda/Features/Shared/TrackList.swift#L826) | 容器布局/默认间距 | `VStack(spacing: 0)` | 共享/运行时分支见源码 |
| [833](../../../Sources/Coda/Features/Shared/TrackList.swift#L833) | 容器布局/默认间距 | `HStack(spacing: 0)` | 共享/运行时分支见源码 |
| [835](../../../Sources/Coda/Features/Shared/TrackList.swift#L835) | 字号/字体 | `.font(.system(size: 20))` | 共享/运行时分支见源码 |
| [837](../../../Sources/Coda/Features/Shared/TrackList.swift#L837) | 尺寸约束 | `.frame(width: 32)` | 共享/运行时分支见源码 |
| [851](../../../Sources/Coda/Features/Shared/TrackList.swift#L851) | 自定义组件/原生构造尺寸参数 | `MusicLibrarySeparator( leadingInset: separatorLeadingInset + (selection == nil ? 0 : 32), trailingInset: Theme.Layout.trackRowHorizontalInset)` | 共享/运行时分支见源码 |
| [858](../../../Sources/Coda/Features/Shared/TrackList.swift#L858) | 尺寸/字体/间距声明或原生字体 | `private var separatorLeadingInset: CGFloat { #if os(iOS) return Theme.Layout.trackRowHorizontalInset + Theme.Layout.trackArtworkSize * UIFontMetrics(forTextStyle: .body).scaledValue(for: 1) + Theme.Spacing.control #else return 10 + 48 + 12 #endif }` | 共享/运行时分支见源码 |
| [923](../../../Sources/Coda/Features/Shared/TrackList.swift#L923) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)` | #if os(iOS) |
| [925](../../../Sources/Coda/Features/Shared/TrackList.swift#L925) | 尺寸约束 | `.frame(width: 440, height: 540)` | #if os(iOS) / #else |

## TrackListScrollView

源码：`Sources/Kumone/Features/Shared/TrackListScrollView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [8](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L8) | 尺寸/字体/间距声明或原生字体 | `var musicLibraryContentWidth: CGFloat { get { self[MusicLibraryContentWidthKey.self] } set { self[MusicLibraryContentWidthKey.self] = newValue } }` | 共享/运行时分支见源码 |
| [16](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L16) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var sizeClass` | 共享/运行时分支见源码 |
| [18](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L18) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.musicLibraryContentWidth) private var contentWidth` | 共享/运行时分支见源码 |
| [39](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L39) | 尺寸/字体/间距声明或原生字体 | `static let dividedColumnSpacing = Theme.Layout.dividedColumnSpacing` | 共享/运行时分支见源码 |
| [47](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L47) | 尺寸/字体/间距声明或原生字体 | `var leadingInset: CGFloat = 0` | 共享/运行时分支见源码 |
| [48](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L48) | 尺寸/字体/间距声明或原生字体 | `var trailingInset: CGFloat = 0` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L53) | 尺寸约束 | `.frame(height: 0.5)` | 共享/运行时分支见源码 |
| [54](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L54) | 内边距 | `.padding(.leading, leadingInset)` | 共享/运行时分支见源码 |
| [55](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L55) | 内边距 | `.padding(.trailing, trailingInset)` | 共享/运行时分支见源码 |
| [66](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L66) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.section)` | 共享/运行时分支见源码 |
| [69](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L69) | 自定义组件/原生构造尺寸参数 | `MusicLibrarySeparator(leadingInset: Theme.Layout.contentInset, trailingInset: Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [81](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L81) | 内边距 | `.padding(.vertical, enabled ? Theme.Spacing.component : 0)` | 共享/运行时分支见源码 |
| [82](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L82) | 内边距 | `.padding(.horizontal, Theme.Layout.trackListInset)` | 共享/运行时分支见源码 |
| [102](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L102) | 尺寸/字体/间距声明或原生字体 | `var horizontalInset: CGFloat = Theme.Layout.trackListInset` | 共享/运行时分支见源码 |
| [104](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L104) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var sizeClass` | 共享/运行时分支见源码 |
| [105](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L105) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var artworkSize: CGFloat = Theme.Layout.trackArtworkSize` | 共享/运行时分支见源码 |
| [106](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L106) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var rowHeight: CGFloat = Theme.Layout.trackRowHeight` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L129) | 容器布局/默认间距 | `LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: MusicLibraryTrackLayout.dividedColumnSpacing), count: layout.columns), spacing: 1)` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L129) | 容器布局/默认间距 | `GridItem(.flexible(), spacing: MusicLibraryTrackLayout.dividedColumnSpacing)` | 共享/运行时分支见源码 |
| [129](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L129) | 自定义组件/原生构造尺寸参数 | `Array(repeating: GridItem(.flexible(), spacing: MusicLibraryTrackLayout.dividedColumnSpacing), count: layout.columns)` | 共享/运行时分支见源码 |
| [142](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L142) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [144](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L144) | 尺寸约束 | `.frame(width: artworkSize, height: artworkSize)` | 共享/运行时分支见源码 |
| [145](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L145) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [146](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L146) | 尺寸约束 | `.frame(height: 20)` | 共享/运行时分支见源码 |
| [147](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L147) | 尺寸约束 | `.frame(maxWidth: 140)` | 共享/运行时分支见源码 |
| [147](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L147) | 尺寸约束 | `.frame(height: 16)` | 共享/运行时分支见源码 |
| [149](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L149) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [150](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L150) | 尺寸约束 | `.frame(width: 30, height: 10)` | 共享/运行时分支见源码 |
| [152](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L152) | 内边距 | `.padding(.horizontal, Theme.Layout.trackRowHorizontalInset)` | 共享/运行时分支见源码 |
| [153](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L153) | 尺寸约束 | `.frame(height: rowHeight)` | 共享/运行时分支见源码 |
| [158](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L158) | 尺寸/字体/间距声明或原生字体 | `let panelInset: CGFloat = showsHorizontalPanel ? Theme.Spacing.component : 0` | 共享/运行时分支见源码 |
| [162](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L162) | 尺寸/字体/间距声明或原生字体 | `let columnWidth = max(1, (available - CGFloat(columns - 1) * 24) / CGFloat(columns)` | 共享/运行时分支见源码 |
| [165](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L165) | 容器布局/默认间距 | `LazyHGrid(rows: Array(repeating: GridItem(.fixed(rowHeight), spacing: 1), count: rowsPerColumn), spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [165](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L165) | 容器布局/默认间距 | `GridItem(.fixed(rowHeight), spacing: 1)` | 共享/运行时分支见源码 |
| [165](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L165) | 自定义组件/原生构造尺寸参数 | `Array(repeating: GridItem(.fixed(rowHeight), spacing: 1), count: rowsPerColumn)` | 共享/运行时分支见源码 |
| [167](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L167) | 尺寸约束 | `.frame(width: columnWidth)` | 共享/运行时分支见源码 |
| [170](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L170) | 内边距 | `.padding(.horizontal, horizontalInset)` | 共享/运行时分支见源码 |
| [172](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L172) | 内边距 | `.padding(.vertical, panelInset)` | 共享/运行时分支见源码 |
| [174](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L174) | 尺寸约束 | `.frame(height: CGFloat(rowsPerColumn) * rowHeight + CGFloat(max(0, rowsPerColumn - 1)) + 2 * panelInset)` | 共享/运行时分支见源码 |
| [183](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L183) | 尺寸/字体/间距声明或原生字体 | `var horizontalInset: CGFloat = Theme.Layout.trackListInset` | 共享/运行时分支见源码 |
| [195](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L195) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var sizeClass` | 共享/运行时分支见源码 |
| [196](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L196) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.musicLibraryContentWidth) private var contentWidth` | 共享/运行时分支见源码 |
| [197](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L197) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var compactRowHeight: CGFloat = Theme.Layout.trackRowHeight` | 共享/运行时分支见源码 |
| [233](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L233) | 尺寸/字体/间距声明或原生字体 | `let rowHeight = compactRowHeight` | #if os(iOS) |
| [235](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L235) | 尺寸/字体/间距声明或原生字体 | `let rowHeight: CGFloat = 64` | #if os(iOS) / #else |
| [237](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L237) | 尺寸/字体/间距声明或原生字体 | `let panelInset: CGFloat = showsHorizontalPanel ? Theme.Spacing.component : 0` | 共享/运行时分支见源码 |
| [241](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L241) | 尺寸/字体/间距声明或原生字体 | `let columnWidth = max(1, (available - CGFloat(columns - 1) * 24) / CGFloat(columns)` | 共享/运行时分支见源码 |
| [247](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L247) | 内边距 | `.padding(.horizontal, horizontalInset)` | 共享/运行时分支见源码 |
| [249](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L249) | 内边距 | `.padding(.vertical, panelInset)` | 共享/运行时分支见源码 |
| [251](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L251) | 尺寸约束 | `.frame(height: CGFloat(rows) * rowHeight + CGFloat(max(0, rows - 1)) + 2 * panelInset)` | 共享/运行时分支见源码 |
| [260](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L260) | 尺寸/字体/间距声明或原生字体 | `var spacing: CGFloat = Theme.Spacing.section` | 共享/运行时分支见源码 |
| [267](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L267) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: spacing)` | 共享/运行时分支见源码 |
| [291](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L291) | 尺寸/字体/间距声明或原生字体 | `@State private var measuredWidth: CGFloat = 0` | 共享/运行时分支见源码 |
| [292](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L292) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.musicLibraryContentWidth) private var contentWidth` | 共享/运行时分支见源码 |
| [293](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L293) | 尺寸/字体/间距声明或原生字体 | `@Environment(\.horizontalSizeClass) private var sizeClass` | 共享/运行时分支见源码 |
| [297](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L297) | 尺寸/字体/间距声明或原生字体 | `private var availableWidth: CGFloat { contentWidth.isFinite && contentWidth > 0 ? contentWidth : measuredWidth }` | 共享/运行时分支见源码 |
| [300](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L300) | 尺寸/字体/间距声明或原生字体 | `private var coverSize: CGFloat { min(240, max(200, availableWidth * 0.3)) }` | 共享/运行时分支见源码 |
| [311](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L311) | 尺寸/字体/间距声明或原生字体 | `private var inset: CGFloat { Theme.Layout.contentInset }` | 共享/运行时分支见源码 |
| [312](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L312) | 尺寸/字体/间距声明或原生字体 | `private var artworkSize: CGFloat { isNarrow ? min(200, max(112, availableWidth * 0.28)) : coverSize }` | 共享/运行时分支见源码 |
| [317](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L317) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [320](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L320) | 尺寸约束 | `.frame(minHeight: Theme.Layout.controlHeight)` | 共享/运行时分支见源码 |
| [329](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L329) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [331](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L331) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [334](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L334) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [338](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L338) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [339](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L339) | 尺寸约束 | `.frame(height: isNarrow ? nil : artworkSize, alignment: .top)` | 共享/运行时分支见源码 |
| [348](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L348) | 内边距 | `.padding(.horizontal, inset)` | 共享/运行时分支见源码 |
| [349](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L349) | 页面顶部留白 | `.pageHeaderTopPadding(16)` | 共享/运行时分支见源码 |
| [350](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L350) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [365](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L365) | 容器布局/默认间距 | `HStack(alignment: .bottom, spacing: Theme.Spacing.group)` | 共享/运行时分支见源码 |
| [367](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L367) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [369](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L369) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [372](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L372) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: artworkSize, alignment: .topLeading)` | 共享/运行时分支见源码 |
| [377](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L377) | 容器布局/默认间距 | `HStack(alignment: .top, spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [407](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L407) | 尺寸约束 | `.frame(width: artworkSize, height: artworkSize)` | 共享/运行时分支见源码 |
| [415](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L415) | 尺寸约束 | `.frame(width: artworkSize, height: artworkSize)` | 共享/运行时分支见源码 |
| [420](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L420) | 字号/字体 | `.font(.system(size: 44))` | 共享/运行时分支见源码 |
| [430](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L430) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [431](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L431) | 尺寸约束 | `.frame(width: 80, height: 14)` | 共享/运行时分支见源码 |
| [432](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L432) | 尺寸约束 | `.frame(maxWidth: 220)` | 共享/运行时分支见源码 |
| [432](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L432) | 尺寸约束 | `.frame(height: 24)` | 共享/运行时分支见源码 |
| [433](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L433) | 尺寸约束 | `.frame(width: 120, height: 14)` | 共享/运行时分支见源码 |
| [441](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L441) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [443](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L443) | 字号/字体 | `.font(Theme.Typography.detailTitle)` | 共享/运行时分支见源码 |
| [444](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L444) | 文字压缩下限 | `.minimumScaleFactor(0.75)` | 共享/运行时分支见源码 |
| [456](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L456) | 字号/字体 | `.font(Theme.Typography.body)` | 共享/运行时分支见源码 |
| [460](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L460) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [466](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L466) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [467](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L467) | 内边距 | `.padding(Theme.Spacing.phonePage)` | 共享/运行时分支见源码 |
| [468](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L468) | 尺寸约束 | `.frame(maxWidth: 380, alignment: .leading)` | 共享/运行时分支见源码 |
| [470](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L470) | 尺寸约束 | `.frame(maxHeight: 400)` | 共享/运行时分支见源码 |
| [481](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L481) | 尺寸约束 | `.frame(width: 240, height: 44)` | 共享/运行时分支见源码 |
| [485](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L485) | 尺寸约束 | `.frame(maxWidth: .infinity, alignment: .leading)` | 共享/运行时分支见源码 |
| [487](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L487) | 容器布局/默认间距 | `LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.small), count: max(1, actionColumns)), spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [487](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L487) | 容器布局/默认间距 | `GridItem(.flexible(), spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [487](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L487) | 自定义组件/原生构造尺寸参数 | `Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.small), count: max(1, actionColumns))` | 共享/运行时分支见源码 |
| [492](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L492) | 自定义组件/原生构造尺寸参数 | `PlaylistActionLayout(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [495](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L495) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [551](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L551) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [554](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L554) | 尺寸约束 | `.frame(height: 14)` | 共享/运行时分支见源码 |
| [555](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L555) | 尺寸约束 | `.frame(maxWidth: 100)` | 共享/运行时分支见源码 |
| [555](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L555) | 尺寸约束 | `.frame(height: 11)` | 共享/运行时分支见源码 |
| [559](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L559) | 内边距 | `.padding(.horizontal, Theme.Layout.contentInset)` | 共享/运行时分支见源码 |
| [570](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L570) | 字号/字体 | `.font(.system(size: 22, weight: .medium))` | 共享/运行时分支见源码 |
| [571](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L571) | 尺寸约束 | `.frame(width: 44, height: 44)` | 共享/运行时分支见源码 |
| [608](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L608) | 自定义组件/原生构造尺寸参数 | `MeloXPlaylistPrimaryActions( isSaved: false, canSave: false, canPlay: !tracks.isEmpty, isSaving: false, onToggleSaved: {}, onPlayAll: play, showsSaveButton: false, horizontalPadding: horizontalPadding )` | 共享/运行时分支见源码 |
| [644](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L644) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | #if os(macOS) |
| [645](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L645) | 字号/字体 | `.font(Theme.Typography.body.weight(.medium))` | #if os(macOS) |
| [646](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L646) | 容器布局/默认间距 | `Spacer(minLength: 12)` | #if os(macOS) |
| [651](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L651) | 字号/字体 | `.font(Theme.Typography.body)` | #if os(macOS) |
| [655](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L655) | 文字压缩下限 | `.minimumScaleFactor(0.65)` | #if os(macOS) |
| [656](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L656) | 内边距 | `.padding(.horizontal, Theme.Spacing.page)` | #if os(macOS) |
| [656](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L656) | 尺寸约束 | `.frame(maxWidth: .infinity)` | #if os(macOS) |
| [656](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L656) | 尺寸约束 | `.frame(minHeight: Theme.Layout.controlHeight)` | #if os(macOS) |
| [660](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L660) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | #if os(macOS) |
| [661](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L661) | 容器布局/默认间距 | `TextField("搜索", text: $filter)` | #if os(macOS) |
| [662](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L662) | 字号/字体 | `.font(Theme.Typography.body)` | #if os(macOS) |
| [665](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L665) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | #if os(macOS) |
| [665](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L665) | 尺寸约束 | `.frame(minWidth: 64, maxWidth: .infinity)` | #if os(macOS) |
| [666](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L666) | 尺寸约束 | `.frame(maxWidth: .infinity)` | #if os(macOS) |
| [666](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L666) | 尺寸约束 | `.frame(minHeight: Theme.Layout.controlHeight)` | #if os(macOS) |
| [741](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L741) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | 共享/运行时分支见源码 |
| [742](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L742) | 文字压缩下限 | `.minimumScaleFactor(0.65)` | 共享/运行时分支见源码 |
| [744](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L744) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [745](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L745) | 尺寸约束 | `.frame(maxWidth: .infinity)` | 共享/运行时分支见源码 |
| [745](../../../Sources/Coda/Features/Shared/TrackListScrollView.swift#L745) | 尺寸约束 | `.frame(minHeight: Theme.Layout.controlHeight)` | 共享/运行时分支见源码 |

## TrackTable

源码：`Sources/Kumone/Features/Shared/TrackTable.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [11](../../../Sources/Coda/Features/Shared/TrackTable.swift#L11) | 尺寸/字体/间距声明或原生字体 | `var headerHeight: CGFloat? = nil` | #if os(macOS) |
| [12](../../../Sources/Coda/Features/Shared/TrackTable.swift#L12) | 尺寸/字体/间距声明或原生字体 | `var footerHeight: CGFloat? = nil` | #if os(macOS) |
| [13](../../../Sources/Coda/Features/Shared/TrackTable.swift#L13) | 尺寸/字体/间距声明或原生字体 | `var rowHeight: CGFloat = TrackRowStyle.full.desktopRowHeight + 1` | #if os(macOS) |
| [35](../../../Sources/Coda/Features/Shared/TrackTable.swift#L35) | 尺寸/字体/间距声明或原生字体 | `private var headerHeight: CGFloat = 1` | #if os(macOS) |
| [36](../../../Sources/Coda/Features/Shared/TrackTable.swift#L36) | 尺寸/字体/间距声明或原生字体 | `private var footerHeight: CGFloat = 1` | #if os(macOS) |
| [67](../../../Sources/Coda/Features/Shared/TrackTable.swift#L67) | 尺寸/字体/间距声明或原生字体 | `let previousRowHeight = content?.rowHeight` | #if os(macOS) |
| [70](../../../Sources/Coda/Features/Shared/TrackTable.swift#L70) | 尺寸/字体/间距声明或原生字体 | `let changedHeights = updateChrome(notifyTable: false)` | #if os(macOS) |
| [125](../../../Sources/Coda/Features/Shared/TrackTable.swift#L125) | 尺寸/字体/间距声明或原生字体 | `let width = scrollView.contentSize.width` | #if os(macOS) |
| [143](../../../Sources/Coda/Features/Shared/TrackTable.swift#L143) | 尺寸/字体/间距声明或原生字体 | `if let fixedHeight { // AppKit can resize this host directly; assigning a new SwiftUI // root for every animation frame would rebuild fixed chrome. cell.host.sizingOptions = [] cell.host.rootView = AnyView(view .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) .environment(\.self, environment)) return max(1, fixedHeight) }` | #if os(macOS) |
| [148](../../../Sources/Coda/Features/Shared/TrackTable.swift#L148) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` | #if os(macOS) |
| [153](../../../Sources/Coda/Features/Shared/TrackTable.swift#L153) | 自定义组件/原生构造尺寸参数 | `AnyView(view .frame(width: max(1, width), alignment: .topLeading) .fixedSize(horizontal: false, vertical: true) .environment(\.self, environment))` | #if os(macOS) |
| [154](../../../Sources/Coda/Features/Shared/TrackTable.swift#L154) | 尺寸约束 | `.frame(width: max(1, width), alignment: .topLeading)` | #if os(macOS) |
| [174](../../../Sources/Coda/Features/Shared/TrackTable.swift#L174) | 尺寸/字体/间距声明或原生字体 | `var onWidthChange: (() -> Void)?` | #if os(macOS) |
| [175](../../../Sources/Coda/Features/Shared/TrackTable.swift#L175) | 尺寸/字体/间距声明或原生字体 | `private var measuredWidth: CGFloat = 0` | #if os(macOS) |
| [179](../../../Sources/Coda/Features/Shared/TrackTable.swift#L179) | 尺寸/字体/间距声明或原生字体 | `let width = contentSize.width` | #if os(macOS) |
| [201](../../../Sources/Coda/Features/Shared/TrackTable.swift#L201) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)` | #if os(macOS) |

## SidebarView

源码：`Sources/Kumone/Features/SidebarView.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [51](../../../Sources/Coda/Features/SidebarView.swift#L51) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/SidebarView.swift#L53) | 容器布局/默认间距 | `Spacer()` | 共享/运行时分支见源码 |
| [58](../../../Sources/Coda/Features/SidebarView.swift#L58) | 字号/字体 | `.font(.system(size: 10, weight: .semibold))` | 共享/运行时分支见源码 |
| [59](../../../Sources/Coda/Features/SidebarView.swift#L59) | 尺寸约束 | `.frame(width: 16, height: 16)` | 共享/运行时分支见源码 |
| [66](../../../Sources/Coda/Features/SidebarView.swift#L66) | 内边距 | `.padding(.trailing, Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [105](../../../Sources/Coda/Features/SidebarView.swift#L105) | 容器布局/默认间距 | `TextField("歌单名称", text: $newPlaylistName)` | 共享/运行时分支见源码 |
| [130](../../../Sources/Coda/Features/SidebarView.swift#L130) | 容器布局/默认间距 | `VStack(spacing: 0)` | #if os(iOS) |
| [131](../../../Sources/Coda/Features/SidebarView.swift#L131) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.tight)` | #if os(iOS) |
| [132](../../../Sources/Coda/Features/SidebarView.swift#L132) | 容器布局/默认间距 | `Spacer()` | #if os(iOS) |
| [135](../../../Sources/Coda/Features/SidebarView.swift#L135) | 内边距 | `.padding(.leading, Theme.Spacing.small)` | #if os(iOS) |
| [136](../../../Sources/Coda/Features/SidebarView.swift#L136) | 内边距 | `.padding(.trailing, Theme.Spacing.small)` | #if os(iOS) |
| [137](../../../Sources/Coda/Features/SidebarView.swift#L137) | 内边距 | `.padding(.top, Theme.Spacing.small)` | #if os(iOS) |
| [156](../../../Sources/Coda/Features/SidebarView.swift#L156) | 尺寸约束 | `.frame(width: 44, height: 44)` | #if os(iOS) |
| [170](../../../Sources/Coda/Features/SidebarView.swift#L170) | 容器布局/默认间距 | `LazyVStack(alignment: .leading, spacing: Theme.Spacing.component)` | #if os(macOS) |
| [173](../../../Sources/Coda/Features/SidebarView.swift#L173) | 内边距 | `.padding(.horizontal, Theme.Spacing.control)` | #if os(macOS) |
| [174](../../../Sources/Coda/Features/SidebarView.swift#L174) | 内边距 | `.padding(.top, Theme.Spacing.small)` | #if os(macOS) |
| [175](../../../Sources/Coda/Features/SidebarView.swift#L175) | 内边距 | `.padding(.bottom, Theme.Spacing.component)` | #if os(macOS) |
| [180](../../../Sources/Coda/Features/SidebarView.swift#L180) | 容器布局/默认间距 | `LazyVStack(spacing: Theme.Spacing.section)` | #if os(macOS) / #else |
| [183](../../../Sources/Coda/Features/SidebarView.swift#L183) | 内边距 | `.padding(.top, Theme.Spacing.component)` | #if os(macOS) / #else |
| [184](../../../Sources/Coda/Features/SidebarView.swift#L184) | 内边距 | `.padding(.bottom, Theme.Spacing.component)` | #if os(macOS) / #else |
| [188](../../../Sources/Coda/Features/SidebarView.swift#L188) | 容器布局/默认间距 | `List { … } // 无显式参数，使用系统/上下文默认值` | #if os(macOS) / #else |
| [196](../../../Sources/Coda/Features/SidebarView.swift#L196) | 字号/字体 | `.font(Theme.Typography.sectionTitle.weight(.semibold))` | 共享/运行时分支见源码 |
| [285](../../../Sources/Coda/Features/SidebarView.swift#L285) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | #if os(macOS) |
| [287](../../../Sources/Coda/Features/SidebarView.swift#L287) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)` | #if os(macOS) |
| [288](../../../Sources/Coda/Features/SidebarView.swift#L288) | 容器布局/默认间距 | `VStack(spacing: 0, content: content)` | #if os(macOS) |
| [289](../../../Sources/Coda/Features/SidebarView.swift#L289) | 内边距 | `.padding(.trailing, Theme.Spacing.small)` | #if os(macOS) |
| [293](../../../Sources/Coda/Features/SidebarView.swift#L293) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.tight)` | #if os(macOS) / #else |
| [295](../../../Sources/Coda/Features/SidebarView.swift#L295) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)` | #if os(macOS) / #else |
| [296](../../../Sources/Coda/Features/SidebarView.swift#L296) | 内边距 | `.padding(.leading, Theme.Spacing.component * 2)` | #if os(macOS) / #else |
| [297](../../../Sources/Coda/Features/SidebarView.swift#L297) | 内边距 | `.padding(.trailing, Theme.Spacing.small)` | #if os(macOS) / #else |
| [298](../../../Sources/Coda/Features/SidebarView.swift#L298) | 容器布局/默认间距 | `VStack(spacing: 0, content: content)` | #if os(macOS) / #else |
| [299](../../../Sources/Coda/Features/SidebarView.swift#L299) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | #if os(macOS) / #else |
| [338](../../../Sources/Coda/Features/SidebarView.swift#L338) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var textSize: CGFloat = 17` | 共享/运行时分支见源码 |
| [339](../../../Sources/Coda/Features/SidebarView.swift#L339) | 尺寸/字体/间距声明或原生字体 | `@ScaledMetric(relativeTo: .body) private var iconSize: CGFloat = 22` | 共享/运行时分支见源码 |
| [342](../../../Sources/Coda/Features/SidebarView.swift#L342) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [344](../../../Sources/Coda/Features/SidebarView.swift#L344) | 尺寸约束 | `.frame(width: iconSize, height: iconSize)` | 共享/运行时分支见源码 |
| [347](../../../Sources/Coda/Features/SidebarView.swift#L347) | 字号/字体 | `.font(.system(size: textSize))` | 共享/运行时分支见源码 |
| [350](../../../Sources/Coda/Features/SidebarView.swift#L350) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [352](../../../Sources/Coda/Features/SidebarView.swift#L352) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [353](../../../Sources/Coda/Features/SidebarView.swift#L353) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)` | 共享/运行时分支见源码 |
| [371](../../../Sources/Coda/Features/SidebarView.swift#L371) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [376](../../../Sources/Coda/Features/SidebarView.swift#L376) | 列表内边距 | `.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6))` | 共享/运行时分支见源码 |
| [400](../../../Sources/Coda/Features/SidebarView.swift#L400) | 内边距 | `.padding(.horizontal, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [405](../../../Sources/Coda/Features/SidebarView.swift#L405) | 列表内边距 | `.listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 6))` | 共享/运行时分支见源码 |
| [450](../../../Sources/Coda/Features/SidebarView.swift#L450) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [476](../../../Sources/Coda/Features/SidebarView.swift#L476) | 内边距 | `.padding(.horizontal, layout.contentInset)` | #if os(iOS) |
| [480](../../../Sources/Coda/Features/SidebarView.swift#L480) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.section)` | #if os(iOS) / #else |
| [487](../../../Sources/Coda/Features/SidebarView.swift#L487) | 尺寸约束 | `.frame(maxWidth: .infinity, maxHeight: .infinity)` | #if os(iOS) / #else |
| [521](../../../Sources/Coda/Features/SidebarView.swift#L521) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [526](../../../Sources/Coda/Features/SidebarView.swift#L526) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [529](../../../Sources/Coda/Features/SidebarView.swift#L529) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [533](../../../Sources/Coda/Features/SidebarView.swift#L533) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [536](../../../Sources/Coda/Features/SidebarView.swift#L536) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [541](../../../Sources/Coda/Features/SidebarView.swift#L541) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [548](../../../Sources/Coda/Features/SidebarView.swift#L548) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [554](../../../Sources/Coda/Features/SidebarView.swift#L554) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.control)` | #if os(iOS) / #else |
| [557](../../../Sources/Coda/Features/SidebarView.swift#L557) | 字号/字体 | `.font(Theme.Typography.body.weight(.semibold))` | #if os(iOS) / #else |
| [559](../../../Sources/Coda/Features/SidebarView.swift#L559) | 内边距 | `.padding(.horizontal, layout.isCompact ? 0 : 18)` | #if os(iOS) / #else |
| [560](../../../Sources/Coda/Features/SidebarView.swift#L560) | 尺寸约束 | `.frame(maxWidth: layout.isCompact ? .infinity : nil)` | #if os(iOS) / #else |
| [561](../../../Sources/Coda/Features/SidebarView.swift#L561) | 内边距 | `.padding(.vertical, layout.isCompact ? 9 : 8)` | #if os(iOS) / #else |
| [577](../../../Sources/Coda/Features/SidebarView.swift#L577) | 字号/字体 | `.font(.system(size: 14, weight: .semibold))` | #if os(iOS) / #else |
| [578](../../../Sources/Coda/Features/SidebarView.swift#L578) | 尺寸约束 | `.frame(width: 38, height: 38)` | #if os(iOS) / #else |
| [663](../../../Sources/Coda/Features/SidebarView.swift#L663) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.component)` | 共享/运行时分支见源码 |
| [666](../../../Sources/Coda/Features/SidebarView.swift#L666) | 容器布局/默认间距 | `Spacer(minLength: 0)` | 共享/运行时分支见源码 |
| [669](../../../Sources/Coda/Features/SidebarView.swift#L669) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [682](../../../Sources/Coda/Features/SidebarView.swift#L682) | 尺寸约束 | `.frame(width: 180)` | 共享/运行时分支见源码 |
| [689](../../../Sources/Coda/Features/SidebarView.swift#L689) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 220)` | 共享/运行时分支见源码 |
| [692](../../../Sources/Coda/Features/SidebarView.swift#L692) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 220)` | 共享/运行时分支见源码 |
| [695](../../../Sources/Coda/Features/SidebarView.swift#L695) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 220)` | 共享/运行时分支见源码 |
| [708](../../../Sources/Coda/Features/SidebarView.swift#L708) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: layout.sectionSpacing)` | 共享/运行时分支见源码 |
| [711](../../../Sources/Coda/Features/SidebarView.swift#L711) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [714](../../../Sources/Coda/Features/SidebarView.swift#L714) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [716](../../../Sources/Coda/Features/SidebarView.swift#L716) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [717](../../../Sources/Coda/Features/SidebarView.swift#L717) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [771](../../../Sources/Coda/Features/SidebarView.swift#L771) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: layout.sectionSpacing)` | 共享/运行时分支见源码 |
| [774](../../../Sources/Coda/Features/SidebarView.swift#L774) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [778](../../../Sources/Coda/Features/SidebarView.swift#L778) | 尺寸约束 | `.frame(maxWidth: .infinity, minHeight: 100)` | 共享/运行时分支见源码 |
| [781](../../../Sources/Coda/Features/SidebarView.swift#L781) | 字号/字体 | `.font(Theme.Typography.secondary)` | 共享/运行时分支见源码 |
| [783](../../../Sources/Coda/Features/SidebarView.swift#L783) | 内边距 | `.padding(.horizontal, layout.contentInset)` | 共享/运行时分支见源码 |
| [784](../../../Sources/Coda/Features/SidebarView.swift#L784) | 内边距 | `.padding(.vertical, Theme.Spacing.control)` | 共享/运行时分支见源码 |

## PlaybackHandoffBanner

源码：`Sources/Kumone/Features/Sync/PlaybackHandoffBanner.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [23](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L23) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [25](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L25) | 字号/字体 | `.font(.system(size: 13, weight: .medium))` | 共享/运行时分支见源码 |
| [27](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L27) | 尺寸约束 | `.frame(width: 28, height: 28)` | 共享/运行时分支见源码 |
| [30](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L30) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: 1)` | 共享/运行时分支见源码 |
| [32](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L32) | 字号/字体 | `.font(Theme.Typography.caption.weight(.medium))` | 共享/运行时分支见源码 |
| [35](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L35) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [40](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L40) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [50](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L50) | 字号/字体 | `.font(Theme.Typography.caption.weight(.semibold))` | 共享/运行时分支见源码 |
| [52](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L52) | 内边距 | `.padding(.horizontal, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [53](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L53) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [69](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L69) | 字号/字体 | `.font(.system(size: 10, weight: .bold))` | 共享/运行时分支见源码 |
| [71](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L71) | 尺寸约束 | `.frame(width: 22, height: 22)` | 共享/运行时分支见源码 |
| [77](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L77) | 内边距 | `.padding(.horizontal, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [78](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L78) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [82](../../../Sources/Coda/Features/Sync/PlaybackHandoffBanner.swift#L82) | 内边距 | `.padding(.horizontal, Theme.Spacing.component)` | 共享/运行时分支见源码 |

## PlaybackHandoffList

源码：`Sources/Kumone/Features/Sync/PlaybackHandoffList.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [14](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L14) | 容器布局/默认间距 | `VStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [17](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L17) | 容器布局/默认间距 | `HStack(spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [19](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L19) | 字号/字体 | `.font(.system(size: 13, weight: .medium))` | 共享/运行时分支见源码 |
| [21](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L21) | 尺寸约束 | `.frame(width: 28, height: 28)` | 共享/运行时分支见源码 |
| [24](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L24) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.micro)` | 共享/运行时分支见源码 |
| [26](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L26) | 字号/字体 | `.font(Theme.Typography.caption.weight(.medium))` | 共享/运行时分支见源码 |
| [29](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L29) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [34](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L34) | 容器布局/默认间距 | `Spacer(minLength: 8)` | 共享/运行时分支见源码 |
| [44](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L44) | 字号/字体 | `.font(Theme.Typography.caption.weight(.semibold))` | 共享/运行时分支见源码 |
| [46](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L46) | 内边距 | `.padding(.horizontal, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [47](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L47) | 内边距 | `.padding(.vertical, Theme.Spacing.tight)` | 共享/运行时分支见源码 |
| [57](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L57) | 内边距 | `.padding(.horizontal, Theme.Spacing.control)` | 共享/运行时分支见源码 |
| [58](../../../Sources/Coda/Features/Sync/PlaybackHandoffList.swift#L58) | 内边距 | `.padding(.vertical, Theme.Spacing.small)` | 共享/运行时分支见源码 |

## SyncSettingsSection

源码：`Sources/Kumone/Features/Sync/SyncSettingsSection.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [14](../../../Sources/Coda/Features/Sync/SyncSettingsSection.swift#L14) | 容器布局/默认间距 | `VStack(alignment: .leading, spacing: Theme.Spacing.small)` | 共享/运行时分支见源码 |
| [29](../../../Sources/Coda/Features/Sync/SyncSettingsSection.swift#L29) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [46](../../../Sources/Coda/Features/Sync/SyncSettingsSection.swift#L46) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [59](../../../Sources/Coda/Features/Sync/SyncSettingsSection.swift#L59) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |
| [90](../../../Sources/Coda/Features/Sync/SyncSettingsSection.swift#L90) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |

## SyncedLoginButtons

源码：`Sources/Kumone/Features/Sync/SyncedLoginButtons.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [24](../../../Sources/Coda/Features/Sync/SyncedLoginButtons.swift#L24) | 容器布局/默认间距 | `HStack { … } // 无显式参数，使用系统/上下文默认值` | 共享/运行时分支见源码 |
| [36](../../../Sources/Coda/Features/Sync/SyncedLoginButtons.swift#L36) | 字号/字体 | `.font(Theme.Typography.caption)` | 共享/运行时分支见源码 |

## KumoneApp

源码：`Sources/Kumone/KumoneApp.swift`。

| 行 | 类型 | 当前表达式 | 编译分支 |
| ---: | --- | --- | --- |
| [26](../../../Sources/Coda/CodaApp.swift#L26) | 尺寸约束 | `.frame(minWidth: player.showNowPlaying ? Theme.Layout.minWindowWidthSidebarCollapsed : Theme.Layout.minWindowWidth, minHeight: Theme.Layout.minWindowHeight)` | #if os(macOS) |
| [31](../../../Sources/Coda/CodaApp.swift#L31) | 默认窗口尺寸 | `.defaultSize(width: Theme.Layout.defaultWindowWidth, height: Theme.Layout.defaultWindowHeight)` | #if os(macOS) |
| [34](../../../Sources/Coda/CodaApp.swift#L34) | 窗口约束 | `.windowResizability(.contentMinSize)` | #if os(macOS) |
| [106](../../../Sources/Coda/CodaApp.swift#L106) | 默认窗口尺寸 | `.defaultSize(width: 460, height: 620)` | #if os(macOS) → #if DEBUG |
| [107](../../../Sources/Coda/CodaApp.swift#L107) | 窗口约束 | `.windowResizability(.contentMinSize)` | #if os(macOS) → #if DEBUG |
