> Update (2026-10-27): The legacy iPad implementation described below has
> changed. On iPadOS < 26, MainWindow now owns a full-canvas NavigationStack
> with independent sidebar and playback overlays. Every destination reserves
> leading and bottom safe areas; grid width excludes the sidebar clearance.
> Legacy iPad no longer uses NavigationSplitView, the secondary-column fixed
> frame, or UIKit split background/separator patches. The iPadOS 26 native
> split path and iPhone navigation remain unchanged. Historical descriptions
> of tiled legacy split columns below are superseded by this note.

# iOS / iPadOS 当前差异清单

整理日期：2026-10-27。依据本地工作区源码，基准提交 `8004869`，包含整理时已有的未提交适配修改；不代表已发布 IPA 或设备上已安装版本的实际状态。本次为静态梳理，未执行构建、真机自动化或运行时验证。

## 1. 支持范围与判断方式

- iPhone 与 iPad 共用 `CodaIOS` 应用、`IOSMainWindow` 入口及 `CodaCore`，最低系统要求均为 16.0。
- 设备差异主要通过 `UIDevice.current.userInterfaceIdiom` 判断；系统差异主要通过 `#available(iOS …)` 判断。这些 iOS 可用性判断也用于 iPadOS。
- 播放器只有一套当前界面。竖向与横向布局是同一页面的响应式适配，没有供用户切换的经典、沉浸、简洁或黑胶模式。
- 部分新效果同时受编译器版本限制：原生 iPhone 26 标签栏与 `compatGlass` 的新玻璃效果要求 Swift 编译器 ≥ 6.2。

依据包括[共享构建配置](../../Sources/iOS&iPadOS/Config/Shared.xcconfig)、[根 Swift 包](../../Package.swift)、[iOS 工程配置](../../ios/project.yml)和[应用入口](../../Sources/iOS&iPadOS/CodaIOSApp.swift)。

## 2. iPhone 与 iPad 的设备差异

| 项目 | iPhone | iPad |
| --- | --- | --- |
| 主导航 | 推荐、精选、搜索、我的四个底部标签，各自维护导航路径 | 侧栏 + 详情列，共享详情导航路径；侧栏直接提供账户、下载、收藏、云盘及歌单等入口 |
| 侧栏 | 不使用 | 当前固定显示两栏，隐藏侧栏切换按钮并禁用手势收起；主界面向子树传入 `.regular` 尺寸类别 |
| 设置入口 | “我的”页面齿轮打开设置 sheet | 侧栏齿轮进入设置；26 与旧系统的齿轮承载位置不同 |
| 搜索框 | 使用系统 `.searchable` | 详情内容顶部内嵌搜索框 |
| 常驻播放条 | 与底部标签栏组合，26 使用系统底部附件 | 独立悬浮在详情列底部，不占用侧栏；包括“未在播放”的占位状态 |
| 页面底部避让 | 26 依赖系统底部附件；旧系统显式预留自定义底栏空间 | 每个目的页面预留播放条安全区，滚动内容另保留少量呼吸间距 |
| 详情页顶部导航 | 保留手机导航容器的系统行为 | 当前隐藏系统导航栏，已推入的目的页面增加内容区“返回”行 |
| 歌曲列表 | 通常为单列紧凑歌曲行 | 常规尺寸类别且详情内容宽度 ≥ 700 pt 时，两列；不足时单列 |
| 歌单、专辑、歌手、每日推荐等页头 | 使用手机专用页头 | 使用平板页头；内部仍按实际可用宽度调整封面、排布与间距 |
| 详情封面背景 | 启用该效果的页面使用封面取色和模糊背景 | `DetailArtworkBackground` 不启用封面背景，使用普通页面背景；与主窗口环境背景开关是两件事 |
| 账户/“我的” | 手机专用页面；收藏专辑、歌手等入口在个人页面组织 | 平板账户页面；部分收藏和资料库入口由侧栏承担 |
| 私人漫游 | 封面上限 240 pt，较矮页面收紧间距及按钮尺寸 | 封面上限 300 pt，默认间距较大 |
| 存储空间与关于 | 直接内嵌在设置表单中 | 直接内嵌在设置表单中 |
| 屏幕方向声明 | 竖屏、左横屏、右横屏 | 另允许倒置竖屏 |

侧栏固定常驻、强制 `.regular` 是当前工作区的真实实现。因此，不能仅凭代码中仍保留的 `.compact` 判断，就认为 iPad 窄窗口一定切换成手机导航；列表列数和部分页头仍会按内容宽度收缩。

依据：[IOSMainWindow](../../Sources/Coda/Features/IOSMainWindow.swift)、[MainWindow](../../Sources/Coda/Features/MainWindow.swift)、[SidebarView](../../Sources/Coda/Features/SidebarView.swift)、[Navigation](../../Sources/Coda/Features/Navigation.swift)、[导航栏处理](../../Sources/Coda/Features/Shared/AppNavigationBarBackground.swift)、[列表与页头布局](../../Sources/Coda/Features/Shared/TrackListScrollView.swift)、[搜索](../../Sources/Coda/Features/Pages/SearchView.swift)、[设置](../../Sources/Coda/Features/Pages/SettingsView.swift)、[封面背景](../../Sources/Coda/Features/Detail/DetailArtworkBackground.swift)、[漫游](../../Sources/Coda/Features/Pages/FMView.swift)。

## 3. 系统版本差异矩阵

表中“18 至 26 以下”指代码的可用性区间，不表示每一个整数版本号都有实际系统发布。

| 系统范围 | iPhone 主导航与播放条 | iPad 主导航与播放条 | 全屏播放器呈现（两端） | 歌词滚动与视觉兼容 |
| --- | --- | --- | --- | --- |
| 16.x | 自定义玻璃底栏 + 独立搜索按钮；播放条随底栏状态重排 | 兼容侧栏外观 + 详情列独立播放条 | 手机使用底部滑入叠层；平板使用专门的覆盖层与退场处理；手柄区域识别自定义下拉关闭 | 用拖动手势与滚动偏移判断手动浏览；没有 `geometryGroup`、`scrollClipDisabled`；控件动画用 timing curve |
| 17.x | 与 16 相同的底栏结构 | 与 16 相同的兼容侧栏结构 | 与 16 相同的呈现分支 | 增加歌词 `geometryGroup`、兼容封装中的 `scrollClipDisabled`；播放器控件显隐使用 `.smooth` |
| ≥18 且 <26 | 仍使用自定义底栏 | 仍使用兼容侧栏 | 两端统一为 `fullScreenCover` + 从播放条来源缩放的系统 zoom 转场，系统负责交互式关闭 | 使用 `onScrollPhaseChange` 判断手动滚动；隐藏工具栏背景改用新 API |
| ≥26 | 编译器 ≥6.2 时使用原生 `TabView`、搜索角色标签和 `tabViewBottomAccessory`；随滚动收起/展开 | 使用原生侧栏外观；播放条仍是详情列独立浮层 | 沿用 ≥18 的系统 zoom 呈现 | 沿用 ≥18 的滚动识别；兼容玻璃封装在编译器 ≥6.2 时使用 `glassEffect` |

补充说明：

- **26 的导航形态在两端不同**：iPad 不走 iPhone 的 `iOS26TabInterface`，升级到 26 也不会改成手机底部标签栏。
- **iPhone 旧底栏也有收起行为**：`LegacyTabScrollObserver` 驱动自定义底栏，切换标签、导航路径改变或出现键盘时展开。26 改由系统控制，并通过主滚动视图注册与反向滚动补偿改善恢复展开。
- **26 原生附件仅在有当前曲目时挂载**；iPad 底部播放条则保留未播放占位。
- **16.4 检查当前没有独立效果**：`systemNowPlayingPresentation` 内虽有 `#available(iOS 16.4, *)`，但当前只由 ≥18 的 zoom 根容器调用，因此 16.4–17 不会因此启用该透明系统呈现。
- 现有扫描未发现专门针对 16.6、26.7、27 或具体补丁版本的独立运行时分支。26.7 会命中 ≥26 条件；未来版本是否正常仍需实际验证。

依据：[入口与转场](../../Sources/Coda/Features/IOSMainWindow.swift)、[旧底栏滚动观察](../../Sources/Coda/Features/Shared/LegacyTabScrollObserver.swift)、[主滚动容器](../../Sources/Coda/Features/Shared/ScenePreservingScrollView.swift)、[歌词滚动识别](../../Sources/Coda/Features/Player/LyricsScrollTracking.swift)、[歌词绘制](../../Sources/Coda/Features/Player/LyricText.swift)、[兼容修饰器](../../Sources/Coda/DesignSystem/Theme.swift)。

## 4. 播放器内部的响应式差异

| 条件 | 当前行为 |
| --- | --- |
| 页面高度 > 宽度 | 两端使用同一竖向布局：顶部歌曲信息，中间歌词/评论/队列/添加歌单面板，底部控制区 |
| 页面高度 ≤ 宽度 | 使用横向双列：左侧封面及播放控制，右侧内容面板；手机横屏也走这一布局 |
| 竖向页面宽度 < 600 pt | 左右内边距 24 pt，顶部封面 52 pt，信息布局更紧凑 |
| 竖向页面宽度 ≥ 600 pt | 左右内边距 48 pt，顶部封面 72 pt；内容宽度上限 680 pt |
| 竖向 iPhone / iPad | 顶部内容 padding 分别为 34 / 64 pt；属于安全区之内的内容间距，不能直接当作距物理屏幕顶端的距离 |
| 横向页面高度 < 600 pt | 缩小顶部与横向边距、列间距、播放控制及音量行高度 |
| 横向控制区宽度 | iPad 将控制区对齐封面宽度；iPhone 使用预留左列宽度 |
| 歌词面板播放中且无交互 | 竖向控制区有自动隐藏逻辑；无障碍朗读或正在交互等状态会阻止隐藏。两端共用，并非设备专属模式 |
| 顶部关闭手柄 | 手机宽 60 pt，平板宽 44 pt；旧系统平板使用整宽顶部拖动区域，避免与歌词滚动争抢手势 |
| 键盘 | 平板播放器忽略底部键盘安全区变化，防止整体封面和控制区被压缩；手机未采用这一特殊处理 |
| 深色内容 | 两端播放器内容均注入深色环境；手机另设 `.preferredColorScheme(.dark)`，平板不设置该偏好，以免影响下方浏览页面 |

歌词、评论、队列与添加歌单复用同一内容面板实现；设备/方向变化主要调整排布、尺寸和呈现机制。

依据：[NowPlayingView](../../Sources/Coda/Features/Player/NowPlayingView.swift)、[NowPlayingPresentation](../../Sources/Coda/Features/Player/NowPlayingPresentation.swift)。

## 5. 播放功能与需要留意的实现差异

- iPhone 与 iPad 共用 `PlayerServiceIOS`。音源、队列、歌词、下载、后台音频及同步等主要功能没有按上述系统版本另设产品版本。
- 两端当前播放器都使用 `IOSSystemVolumeSlider` 调整系统音量，但初始化引擎音量存在设备分支：iPad 固定为 `1`；iPhone 恢复 `player.volume`，没有保存值时为 `0.8`。这意味着相同系统音量下，两端可能存在额外增益差异；这里只记录代码行为，未实测响度。
- AutoMix 设置为 macOS 范围，并不是升级 iPhone/iPad 系统版本即可获得的功能。
- CarPlay 是否写入能力配置取决于可选构建覆盖文件和授权配置，不应把它归为 16/17/18/26 自动开启的功能。本清单不据此推断设备实际支持情况。

依据：[iOS 播放服务](../../Sources/Coda/Core/Player/PlayerServiceIOS.swift)、[播放器音量控件](../../Sources/Coda/Features/Player/NowPlayingView.swift)、[设置](../../Sources/Coda/Features/Pages/SettingsView.swift)、[Package](../../Package.swift)、[可选能力覆盖](../../Sources/iOS&iPadOS/Config/Shared.xcconfig)。

## 6. 系统版本号与应用版本号不能混用

| 版本来源 | 当前仓库情况 | 解读 |
| --- | --- | --- |
| 系统版本 | 代码以 16 / 17 / 18 / 26 为主要边界 | 决定系统 API、呈现与兼容路径 |
| 本地默认应用版本 | `MARKETING_VERSION = 0.1.0`、`CURRENT_PROJECT_VERSION = 1` | 是共享配置默认值，不足以判断当前源码等于早期 0.1.0，也不证明设备安装的是该版本 |
| 仓库更新日志 | 最上方为 `0.3.21 - 2026-10-19` | 是仓库内的发布记录，不是本次在线确认的最新发行状态 |
| 发布 IPA 版本 | CI 用 `$VERSION` / `$BUILD_NUMBER` 覆盖构建参数 | 实际包版本应以构建产物 Info.plist 或安装应用为准；iPhone/iPad 共用同一 IPA |

更新日志中与本次梳理相关的历史节点：

- **0.3.6**：引入手机播放器及 26 原生底部附件；当时还记载了播放器模式切换。该模式描述属于历史记录，当前应以唯一播放器界面约定及源码为准。
- **0.3.7**：修复 16/17 播放页被缩成迷你条大小的问题，改为底部滑入；≥18 保留 zoom。
- **0.3.8**：修复从推荐卡片进入详情后侧栏切换失效的导航问题。
- **0.3.10**：修复 26 无播放时出现空附件块的问题。
- **0.3.15**：记录 iPad 设置/搜索入口与横屏播放器布局修复。当前入口位置与布局仍需按现有源码判断。
- **0.3.21**：记录 iOS 与 macOS 离线下载功能；iPad 与 iPhone 共用移动端实现。

这些节点来自更新日志，未逐个检出历史提交复测，不能代替完整的历史版本行为对比。

依据：[Shared.xcconfig](../../Sources/iOS&iPadOS/Config/Shared.xcconfig)、[发布工作流](../../.github/workflows/release.yml)、[CHANGELOG](../../CHANGELOG.md)。

## 7. 已发现的文档/兼容边界

1. `ios/CLAUDE.md` 的模板文字称最低 iOS 18，`ios/README.md` 也强调 18+，与实际构建配置和 Package 的最低 16.0 不一致。判断支持范围应优先看构建配置。
2. 历史更新日志中的播放器模式开关、侧栏入口位置等内容不能直接作为当前使用说明。
3. 编译器 <6.2 时，26 上的手机会回退到自定义底栏，但 `PlayerClearanceSpacer` 仅按系统 ≥26 判断避让方式，未同步判断编译器条件。这是静态发现的潜在布局不一致，未验证是否在实际使用的工具链中触发。
4. iPad 保留窄布局条件，但主界面固定 `.regular` 并要求侧栏常驻。极窄窗口的最终可用性仍需单独验证，不能宣称已完整覆盖所有多任务窗口尺寸。
5. 旋转、前后台和滚动位置的兼容代码大量针对 iPadOS 16 的行为编写，但其中一些应用于全部 iPad 系统。注释说明问题来源，不等于代码只在 16 执行。

按项目约定记录的设备环境是 iPhone iOS 26.7、iPad iPadOS 16.6；本次未重新检测连接、系统版本或已安装应用。二者的外观差异同时包含设备差异与系统版本差异，不能只归因于“手机/平板”。
