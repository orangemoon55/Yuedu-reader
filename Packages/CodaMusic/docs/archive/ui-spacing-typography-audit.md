# Kumone 全界面间距与字号审计（迁移前基线）

检查日期：2026-10-29。后续已实施统一标准，见 [当前标准与迁移说明](../development/ui-layout-standard.md)。本文人工表格和统计保留迁移前基线，`ui-layout-audit/` 的自动清单已按修改后的源码重新生成。目的：为后续统一间距建立当前值、使用位置和响应式例外的基线。本次未修改应用代码。

## 交付与检查范围

- [逐文件、逐项源码清单](ui-layout-audit/inventory.md)：每个候选项的表达式、行号和编译分支，涵盖布局容器、padding、字体、尺寸约束、共享组件参数和相关声明。
- [结构化明细](ui-layout-audit/occurrences.json)：保留附近源码，便于下一步按语义核对、批量迁移。
- [数值与频次统计](ui-layout-audit/summary.json)。
- [重新生成脚本](ui-layout-audit/generate.py)：项目根目录执行 `python3 docs/archive/ui-layout-audit/generate.py`；重生成逐项清单和 JSON，不覆盖本报告。

枚举 257 个应用源码 Swift 文件（不包含 vendor、测试及 StemKit 测试），重点提取 Features、DesignSystem、应用入口、Launcher、CarPlay、平台兼容和更新器中的 UI 候选项；73 个文件包含匹配结果，共 1,991 条候选记录。其中 `.font(...)` 322 处、`.padding(...)` 359 处、容器构造/默认布局 444 处、`.frame(...)` 419 处。不同类别可能描述同一组件，不能相加为独立界面数量；声明和构造参数也不能当作实际屏幕元素数。

这是源码审计，不是屏幕实测。SwiftUI 默认间距、继承字体、原生 Form/List/菜单/警告框、导航栏、CarPlay 模板等受平台控制；运行时条件、父子容器、safe area 和 Dynamic Type 会影响最终效果。系统样式保留名称，不伪装成跨平台固定字号。提取器不是 Swift AST，候选项仍需结合源码语义判断；未覆盖运行时截图、系统内部布局或不可从源码确定的最终距离。

## 现状结论

1. `Theme.Layout` 有页面边距和播放器尺寸，但没有通用 `Spacing`、`Typography` 语义 token。
2. 页面主边界存在 16、20、24、28pt；同类区块间距存在 16、20、26、40pt，且不同页面采用不同容器。
3. 固定字号、系统文字样式、`@ScaledMetric` 和视口公式混用。小数值包括 8.5、10.5、11.5、12.5；其中部分是图标/徽标，不能与正文一起收敛。
4. 多层 padding 经常共同完成对齐。例如搜索歌曲列表外侧 `24 - 10 = 14`、歌曲行内部 `10`，形成 24pt 边界；面板还可能增加 14pt。必须先确定容器层级，再统一最终边界。
5. 播放器只有当前一套界面。横竖屏、窄屏和矮窗口分支属于响应式适配，后续保留在同一布局体系中。

## 已有全局布局基准

来源：`Sources/Kumone/DesignSystem/Theme.swift`。

| 用途 | 当前值（pt） | 说明 |
| --- | --- | --- |
| 内容水平基准 | 24 | `contentInset`，部分页面覆写或加减补偿 |
| 封面卡片基准 | 160 | 横向栏目还会按可用宽度计算 |
| 横向卡片默认间隔 | 16 | `fittedShelfCardSize` / `Shelf` |
| 封面栏目 / 歌手栏目高度 | 226 / 196 | 包含图片与文字，不能作为纯间距 |
| 侧栏宽度 / 分栏分隔占位 | 332 / 8 | 结构尺寸 |
| Mac / iPad 底栏高度 | 64 | 共用基准 |
| 底栏左右外边距 / 底部外边距 | 16 / 10 | 内容避让基准 64 + 10 = 74 |
| 滚动额外余量 | 8 | `scrollBreathingMargin` |
| 旧版 iPhone 标签栏 / 迷你播放器高度 | 64 / 52 | 属于系统兼容布局 |
| 迷你播放器与标签栏间隔 | 8 | `FloatingChrome.barSpacing` |
| 旧版底栏底边距 / 内容额外余量 | 6 / 12 | 仅标签栏避让 82；双栏避让 142 |

圆角是另一种 token，当前为 4 / 6 / 8 / 12 / 20；不计入间距档位。

## 页面与组件清单

以下为人工核对的主要值。每行所有细项、字体权重、条件分支与源码位置见逐项清单中对应文件；共享组件继承的值应沿组件继续查阅。

| 页面 / 区域 | 当前主要间距（pt） | 当前主要文字 / 字号 | 源文件（均位于 Sources/Kumone） |
| --- | --- | --- | --- |
| 首页 | 区块 40；栏目标题间距 16；页面水平 24；顶部/底部 16 | 栏目标题 title2 semibold；卡片 13 medium / 11；推荐说明 subheadline | Features/Home/HomeView、HomeDiscoverySections、HomeCoverShelf、HomeSongRecommendationLists.swift |
| 新碟上架 / 推荐歌手 / 推荐专题 | 水平 24；顶部 24；网格继承 CardGrid | 歌手文字 subheadline medium；其他继承共享卡片/歌曲行 | Features/Home/HomeBrowseView、HomeRecommendationPageView.swift |
| 精选 / 排行榜 | 大区块 20；横向入口 8；榜单网格 20；榜单内部 14 / 5 / 3；卡片 padding 10 | 榜名 14 semibold；更新信息 10.5；歌曲 11 | Features/Explore/ExploreView.swift |
| 搜索 | 水平 24；歌曲外侧 14 + 行内 10；顶部 12；结果区底部 16；搜索输入左 16、右 16/4；空态顶部 60 | headline / subheadline；搜索相关 13 medium；空态符号 48（非正文） | Features/Pages/SearchView.swift |
| iPhone 歌单 / 专辑 / 每日推荐等共用详情头部 | 搜索外边距 20、顶部 8、内部水平 16；封面到标题 24；作者顶部 8；元信息顶部 7；按钮顶部 17；头部顶 26 / 底 22；文字水平 24 | 标题 title2 bold；作者 title3；元信息 subheadline medium | Features/Detail/MeloXPlaylistDetailHero.swift |
| iPad 共用音乐集合头部 | 窄/宽水平 16/28；外层区块 14；封面与信息 14/28；信息间距 6/8；标题/元信息间距还受调用组件影响 | 标题固定 18/28 bold；作者、元信息 subheadline | Features/Shared/TrackListScrollView.swift + MeloXPlaylistDetailHero.swift |
| 详情头部三个动作 | 按钮间隔 14；iPhone 外侧 24；宽布局默认 0；整组最大宽 328 | 播放 title3 bold；收藏和更多符号 title2 semibold；按钮高 56 | Features/Detail/MeloXPlaylistDetailHero.swift |
| Mac 歌单 / 专辑 / 歌手详情 | 页面边距常为 24，窄分支 16；歌单列表存在 `24 - 8` 和行内补偿；头像信息横距 28；Profile 区块 26 | 桌面 profile 标题 largeTitle bold；列表继承 TrackRow；其他文字见各页明细 | Features/Detail/PlaylistDetailView、AlbumDetailView、ArtistDetailView.swift + ProfileDetailLayout.swift |
| 我的 / 账户详情 / 歌手主页 | Profile 水平窄/宽 16/24；区块 16/26；横向卡片 16；歌手头像与名称 8 | profile 歌手卡片 12 medium；另有 ArtistCard 13 medium；iOS 主头部走共用集合头部 | Features/IOSMainWindow、SidebarView.swift + Features/Shared/ProfileDetailLayout.swift |
| 云盘 / 最近播放 / 播放排行 | 水平 24；操作区域水平 14、垂直 7；顶部 12；歌曲面板继承共用布局 | 操作文字 12 / 12.5 semibold；歌曲行继承共用字体 | Features/Pages/LibraryPages.swift + Features/SidebarView.swift |
| 下载 / 离线集合 / 下载任务 | 水平 24 或 14；任务卡片 padding 10；操作垂直 7；顶部 12 | 任务文字 11 / 11.5 / 12 / 12.5 / 13；另有 body / callout / caption | Features/Pages/DownloadedMusicView.swift |
| 我的收藏 / 收藏分区 | 水平 24；顶部 16；内容继承 CardGrid/Profile | 13 / 13 medium，以及共享卡片字体 | Features/Pages/CollectionsView.swift + Features/SidebarView.swift |
| 漫游 | 手机矮/普通区块 12/20，大屏 28；内容左右 40；信息组 6、标题组 8；控制组 26；按钮水平 28 / 垂直 12 | 歌名 18/22 bold；歌手 14；动作文字 15 semibold；图标字号单列 | Features/Pages/FMView.swift |
| Mac / iPad 浮动播放栏 | 外侧水平 16 / 底 10；内部水平 16；主组 16；封面到文字 12；歌名到歌手 3 | 歌名 15 medium；歌手 13；符号 19/22/24/26 等 | Features/Player/PlayerBar.swift |
| iPhone 迷你播放器 / 自定义标签栏 | 迷你栏常见水平 12/16、垂直 4/6/8；标签栏内部 padding 4；详见系统兼容分支 | 标签文字 10 semibold、符号 23 semibold；迷你栏内联/普通标题 10/13 semibold、歌手 8/10、文字间距 2/3 | Features/IOSMainWindow、GlassTabBar.swift |
| 全屏播放器 | 竖向、宽屏、矮窗口分别计算，见下表；含 -16 和 -8 的扩展/补偿 | 元信息 title3 semibold 或 body bold；歌手 17/14；时间 13/10.5；其他含图标字号 | Features/Player/NowPlayingView.swift |
| 歌词 / 桌面歌词 | 主歌词行间隔随字号变化；桌面歌词内容间距 5、水平 26、垂直 10 | 主歌词 iOS 36–48、Mac 26–48；桌面原文 26、上/下辅助行 15/16 semibold rounded | Features/Player/AppleMusicLyricsColumn、DesktopLyrics、LyricText、KaraokeLyricLine、KaraokeGlyphRenderer.swift |
| 播放队列 / 歌词弹出面板 | 横向 padding 8/16/20；单行垂直 4/5；面板垂直 14；部分 padding 10 | 9 / 10.5 / 11 / 12 / 12.5；活动歌词 12/11、13/12；标题 headline | Features/Player/Panels、IOSPlaybackQueueView.swift |
| 歌曲评论 / 输入区 | 外侧水平 28；顶部 14；内容 padding 10/12；垂直 12；键盘底部由遮挡计算 | 文字 11–17，标题另有 23 bold；含图标字号 | Features/Player/SongCommentsColumn.swift |
| 登录（二维码 / 手机号 / 验证码） | 主组 20、子组 6/10/12/16；顶 28；水平 24/28；字段组 10；主按钮垂直 13 | 字段 15；说明 12/12.5；小提示 11/11.5；标题 title3 semibold；占位符号 34 | Features/Pages/LoginSheet.swift |
| 设置 / 存储 / 快捷键 / 同步 / 模型 / AutoMix 设置 | 多为原生 Form/Section/List 默认间距；局部 2/4/8/12；快捷键 `.padding()` 无固定值 | body / headline / subheadline / footnote / caption；快捷键 body monospaced | Features/Pages/SettingsView、StorageSpaceView、ShortcutSettingsView、StemModelsSettingsSection、AutoMixSettingsSection.swift；Features/Sync/SyncSettingsSection.swift |
| 同步接力提示 / 接力列表 / 登录同步 | 提示水平 12/16、垂直 5/8；其他行值见明细 | 接力提示 10 bold / 11 / 12 / 13；其他为继承样式和系统样式 | Features/Sync/PlaybackHandoffBanner、PlaybackHandoffList、SyncedLoginButtons、LoginPassphraseAlert.swift |
| AutoMix 调试面板 | padding 8/14；微间距 2/3/5/8；保留调试密度语义 | 9 / 10 / 11 monospaced，caption2 | Features/Player/AutoMixDebugPanel.swift |
| 通用加载 / 空态 / 错误 / 徽标 | 空态组 12；错误外侧 40；封面骨架 8；栏目骨架 14/16；徽标 1/2/3.5/4/5/7 | 空态 headline + subheadline；符号 40；徽标 8.5 / 9 / 10 | DesignSystem/Cards、Components.swift；Features/Shared/PanelRefresh.swift |
| Mac 启动配置 / 系统更新 / CarPlay | AppKit/SwiftUI/系统模板分别提供布局，不能统一套用页面 padding | 原生继承文字、模板文字和启动器固定字体见明细 | Sources/KumoneLauncher/StemSetup.swift；Core/UpdaterManager.swift；Core/CarPlay/CarPlayTemplateFactory.swift |

## 共享歌曲行与封面卡片

| 组件 / 语义 | 当前值 |
| --- | --- |
| TrackRow 行高 | 桌面 64；compact 使用按 body 缩放的基准 64；原生表格默认行高 65（含 1pt 行间节奏） |
| TrackRow 封面 | compact 基准 48，随 body 缩放 |
| 歌曲行内部留白 | 水平 10；垂直 compact 6 / 其他 5 |
| 封面到文字 | HStack 12 |
| 歌名到辅助信息 | 普通 2；非 compact likedMusic 5 |
| 歌名 | compact 为 callout medium；其他 13 medium；likedMusic 16 semibold |
| 歌手/辅助信息 | compact 多为 footnote；桌面 11.5；likedMusic 13；特殊标签单独设置 |
| 歌曲列表 | 行距 1；普通多列间隔 20；带分隔列间隔 40；横向网格列间隔 24 |
| CoverCard | 图片到标题、标题到副标题均为 VStack spacing 8；标题 13 medium，副标题 11 |
| ArtistCard | 图片到文字 10；名字 13 medium |
| ProfileDetailArtistCardBody | 图片到文字 8；名字 12 medium；与 ArtistCard 有重复语义 |
| Shelf | 标题到滚动容器 14，滚动容器另有垂直 padding 6；卡片间 16 |
| CardGrid | compact 列距 16 / 行距 20；其他列距 20 / 行距 24 |
| SectionHeader | 标题 title2 semibold；副标题 subheadline；标题到箭头 4；外层 HStack 默认间距 |

`TrackRow` 还声明 compact album 行高基准 50，但当前 `rowHeight` 先对所有 compact 返回 64，因此该后续条件中的 compact 50 分支不会生效；不要把声明的 50 当作当前实际行高。

## 播放器与歌词的响应式数值

| 条件 / 语义 | 当前表达式或数值 |
| --- | --- |
| 竖向播放器窄屏判定 | `width < 600` |
| 竖向水平留白 | 窄屏 24；宽屏 `min(72, width × 0.06)`；内容最大宽 960 |
| 竖向区块 / 头部横向间距 | 窄屏 8 / 12；宽屏 16 / 18 |
| 竖向顶部 / 底部 | iPhone 34、iPad 64；底部 3 |
| 竖向进度到播放键 / 播放键到音量 | bottom padding 19 / 31；音量后 3 |
| 常规宽屏矮窗口判定 | `height < 600`；内容宽最多 1920 |
| 常规宽屏水平留白 | 矮窗口 24；其他 `min(96, max(32, contentWidth × 0.04))` |
| 常规宽屏列间隔 | 矮窗口 24；其他 `min(88, max(32, contentWidth × 0.04))` |
| 常规宽屏顶部 | Mac 矮/普通 48/56；iOS 矮/普通 16/56 |
| 常规宽屏底部 / 控件间距 / 封面间距 | 矮窗口 3 / 4 / 12；普通 16 / 8 / 20 |
| iOS 主歌词字号 | `min(48, max(36, 36 + (width - 600) × 0.035))` |
| Mac 主歌词字号 | `min(48, max(26, 34 + (width - 500) × 0.035))` |
| iOS 歌词行间隔 | `25 × 主字号 / 36`（约 25–33.33） |
| Mac 歌词行间隔 | `30 × 主字号 / 34`（约 22.94–42.35） |
| 歌词辅助文字 | iOS 罗马音为 callout、其他为 title3 的 UIFont preferredFont（bold）；Mac 为主字号 × 0.55 |

这些值反映当前代码意图。不能把 3、19、31、34、56、64 或负 padding 全部四舍五入到通用网格；需核对控件 frame、歌词叠层和实际可用高度。

## 数值分布

直接固定字号（仅 `.font(.system(size: 数字...))` 可直接识别的值，包含符号）：

`7, 8, 8.5, 9, 10, 10.5, 11, 11.5, 12, 12.5, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 28, 32, 34, 36, 40, 44, 48, 52`

此外还有条件字号、组件传入字号及计算字号，例如桌面歌词 26、详情标题 18/28、播放器时间 13/10.5。所有这些表达式均保留在明细中，上述序列不是全部运行时字号全集。

系统文字样式：`largeTitle, title2, title3, headline, subheadline, body, callout, footnote, caption, caption2`；还有 `.system(.body, design: .monospaced)` 等变体。不要把 iOS 默认字号直接套给 macOS，也不要忽略用户文字缩放。

直接固定 padding / 容器 spacing 值（不含声明、变量、三元表达式、组件传参）：

`-16, -8, 0, 1, 2, 3, 3.5, 4, 5, 6, 7, 8, 9, 10, 12, 13, 14, 16, 17, 18, 19, 20, 22, 24, 26, 28, 31, 32, 38, 40, 48, 60, 64, 91`

该统计不计算最终视觉距离。例如 `HomeLayout.sectionSpacing = 40`、竖屏顶部 34、宽屏顶部 56 等变量/条件值不会计入直接值频次。重复嵌套表达式可能出现于构造参数候选中，频次只用于定位散落定义，不用作视觉质量评分。

## 下一步统一方案（建议，尚未实施）

| 语义 | 建议基准 | 使用边界 |
| --- | --- | --- |
| 微间距 | 2 / 4 | 图标与徽标、同组微调；1pt 分隔节奏独立保留 |
| 同组内容 | 8 | 图文、标题与辅助信息；歌曲行等密集组件可有专用 token |
| 控件内部留白 | 12 / 16 | 按控件大小区分，不逐值机械映射 |
| 手机页面边距 | 20 | 候选值，需对比现有详情搜索与 24pt 文字边界后定稿 |
| 桌面 / iPad 内容边距 | 24 | 现有基准；28pt 头部需连封面和列表一起核对 |
| 标题到内容 | 16 | 当前 14 + 滚动容器 6 等叠加结构需按最终边界调整 |
| 常规页面区块 | 24 / 32 | 按内容分组定义；首页可保留独立 40pt 大区块语义 |
| 文字体系 | 正文、辅助、标题、徽标、图标分开定义 | iOS 优先保留系统样式和 Dynamic Type；Mac 可保留更紧凑密度；歌词独立 |

建议实施顺序：先定义 `Theme.Spacing`、页面布局和文字角色；随后统一共享歌曲行、卡片、栏目与详情头部；再迁移浏览页、工具表单与弹窗；最后核对播放器计算布局、歌词、safe area 和旧系统兼容分支。

每一步先确认「最终左右边界」「标题到内容距离」「行高与文字缩放」三项，再调整具体数字。不会新增播放器界面模式。本次只产生文档与提取脚本，因此未构建、安装、启动应用或运行真机自动化。
