# 界面间距与字体标准

实施日期：2026-10-29。定义入口：`Sources/Coda/DesignSystem/Theme.swift`。

## 间距

统一以 pt 为单位，普通内容采用 4pt 网格。按用途引用 token，不在页面中重新定义近似值。

| token | 值 | 用途 |
| --- | ---: | --- |
| Spacing.micro | 2 | 徽标内部微间距 |
| Spacing.tight | 4 | 紧密关联文字、标题与副标题 |
| Spacing.small | 8 | 图文与同组信息 |
| Spacing.control | 12 | 同组控件、歌曲封面到文字、详情操作按钮之间 |
| Spacing.component | 16 | 卡片之间、标题到内容、面板内留白 |
| Spacing.group | 24 | 复合组件内部的大间距，独立于页面区块节奏 |
| Spacing.phonePage | 20 | 手机页面边距 |
| Spacing.page | 24 | Mac / iPad 页面边距 |
| Spacing.section | 20 | 常规内容区块 |
| Spacing.largeSection | 24 | 大区块 |
| Spacing.discoverySection | 32 | 首页推荐一级区块 |

页面边距通过 `Theme.Layout.contentInset` 获取：iPhone 为 20，iPad / Mac 为 24。不要在普通页面根据窄屏状态另外退回 16。

歌曲行内留白为 `Layout.trackRowHorizontalInset`（12）。列表外侧用 `Layout.trackListInset`（页面边距减去行内留白），保证标题、封面和搜索框的最终左右边界对齐。纵向与横向歌曲面板、加载骨架使用同一计算。

## 字体角色

| Typography token | iPhone / iPad | Mac |
| --- | --- | --- |
| pageTitle | largeTitle bold | 28 bold |
| sectionTitle | title2 semibold | 22 semibold |
| detailTitle | title2 bold | 22 bold |
| cardTitle | headline | 15 semibold |
| body | body | 13 regular |
| trackTitle | body medium | 13 medium |
| secondary | subheadline | 12 regular |
| caption | footnote | 11 regular |
| badge | caption2 medium | 10 medium |

iOS 使用系统文字样式响应 Dynamic Type；时间和数字列在角色上叠加 `.monospacedDigit()`。图标字号独立于文字，不按数字大小自动归入文字角色。

封面卡片图片到标题为 8，标题到副标题为 4；歌手卡片头像到名称为 8。两种卡片共用 cardTitle。封面栏目的基准高度已增加文字空间，放大字体时仅增长文字空间，不同步放大封面。

## 组件尺寸与规则

- 普通按钮和搜索框基准高度：44；内容增加时允许长高。
- 详情页主要动作基准高度：56；同组间距 12。
- 歌曲行基准高度：64；封面 48；标题与歌手间距 4。已有按 body 缩放的行高与封面机制保留。
- 页面普通区块间距：20；大区块：24；首页一级推荐区块：32。
- 空态/错误态：图标到文字组 16，标题到说明 8，说明到操作 24。
- 原生 Form / List / 菜单 / 警告框继续使用系统容器行为；自定义说明文字和内部内容引用 Typography / Spacing。

本轮收紧仅调整独立内容区块之间的节奏；水平页面边距、卡片网格间距、封面与信息间距、列表分栏和字号保留。分栏间隔通过 `Layout.dividedColumnSpacing`（32）、错误态外留白通过 `Layout.emptyStateInset`（40）独立定义。

## 保留的专用尺寸

这些尺寸承担明确的系统或内容职责，不属于普通页面间距：

- 分隔线 0.5 / 1、连续列表行间隔 1、无间隔容器 0。
- 浮动播放器高度 64、水平外边距 16、底部 10；页面避让继续根据实际 chrome 计算。
- iOS 系统 accessory 内联迷你播放器的专用字号与宽高适配。
- 播放器竖屏/宽屏可用尺寸公式、歌词叠层、负 padding 和光学补偿。
- 主歌词、注音、桌面歌词的独立字号及行距公式。
- 图标、徽标、调试数据、系统窗口和 CarPlay 模板的专用尺寸。

播放器仍只有当前这一套界面，横竖屏和设备尺寸仅作响应式适配。

## 迁移范围与验证

已接入：共享歌曲行与加载骨架、卡片/网格/栏目、详情头部与操作按钮、首页/推荐/精选/搜索、个人资料与收藏、下载/云盘/最近播放、登录、设置/存储/同步、自定义队列与评论、收藏到歌单内容，以及播放器普通控件组与元信息。

保留迁移前已有的收藏到歌单共享内容修改。提取工具与最新逐项清单位于 `docs/ui-layout-audit/`；`docs/archive/ui-spacing-typography-audit.md` 的人工表格保留为迁移前基线。

本次运行桌面 Swift 测试：ContentLayoutTests、SceneViewportSizeTests、NavigationDestinationTests、PlaylistArtworkTests，共 13 项通过。包含长卡片标题是否超出栏目高度、窄内容栏错误说明是否正常换行的实际 SwiftUI 布局检查。Mac 与 iOS 设备构建均通过；安装情况见本次交付说明。没有运行真机自动化或启动真机应用。
