# iPhone 页面样式检查

检查日期：2026-10-26。范围：iPhone 音乐详情与相关导航页面。
方法：检查导航目的地、页面实现与共享组件调用；未启动应用、XCUITest 或真机测试 Runner。此表表示代码复用情况，不代表运行时截图验收。

最新更新：iPhone/iPad 音乐集合头部已由同一自适应组件提供；头部三个按钮统一56pt等高，歌曲行与控制栏共用 `PlayerHeartIcon`（行内红心仅显示状态，不可操作）。

统一基准：MeloXPlaylistHeader / MeloXPlaylistDetailHero、MeloXPlaylistPrimaryActions、MeloXPlaylistMoreLabel、MeloXPlaylistArtworkBackdrop，以及 MusicTrackPanel / TrackListView。

| 页面 | 检查结果 | 具体情况与代码位置 |
| --- | --- | --- |
| 歌单、我喜欢的音乐、雷达歌单 | 已复用 | PlaylistDetailView.swift：同一详情实现，搜索、封面头部、按钮、背景、透明歌曲列表。 |
| 专辑 | 本次统一 | AlbumDetailView.swift：搜索、封面头部、收藏/播放/更多、背景、纵向歌曲列表；简介、歌手跳转和下载放在更多菜单；其他专辑使用 ProfileDetailCoverShelf。 |
| 每日推荐 | 已复用 | DailySongsView.swift：歌单搜索头部、按钮和背景；没有收藏动作，因此省略左侧收藏按钮。 |
| 音乐云盘、最近播放 | 已复用 | LibraryPages.swift + MusicLibraryHeader(usesPlaylistStyle: true)：歌单搜索头部、背景、按钮和透明列表；排序放在更多菜单中。 |
| 下载、已保存的离线集合 | 已复用常规浏览状态 | DownloadedMusicView.swift：同上；批量选择时使用专门的选择/全选/移除操作栏。 |
| 歌手 | 共用视觉组件，保留内容差异 | ArtistDetailView.swift：圆形头像、DetailHero、同款按钮和背景；热门歌曲为横向列表，专辑/相似歌手为横向栏目，无歌曲搜索栏。 |
| 我的 | 共用视觉组件，保留内容差异 | IOSMainWindow.swift：圆形头像、DetailHero、同款按钮和背景；下方为歌单/专辑/歌手栏目，无歌曲搜索栏。 |
| 独立“我的收藏” | 仍为旧头部 | CollectionsView.swift：MusicLibraryHeaderLayout + 分段选择器 + 卡片网格 + 普通背景。iPhone“我的”页已移除其快捷入口，但共享导航仍注册该目的地。 |
| 新碟上架、推荐歌手 | 未使用详情页头部 | HomeBrowseView.swift：导航标题与卡片网格；歌手卡片还使用内联样式，而非 ProfileDetailArtistCardBody。 |
| 排行榜 | 未使用详情页头部 | ExploreView.swift / ToplistsView：导航标题与 ToplistGrid。 |
| 首页、精选、搜索 | 独立浏览布局 | HomeView.swift、ExploreView.swift、SearchView.swift：不使用单个音乐集合的封面头部。 |
| 漫游、播放器 | 独立播放布局 | FMView.swift、NowPlayingView.swift：不使用集合详情页布局。 |
| 下载任务、存储空间、设置、登录 | 独立工具/表单布局 | DownloadTasksView、StorageSpaceView、SettingsView、LoginSheet；无需封面与歌曲搜索头部。 |

当前专辑、歌单、歌手、每日推荐、最近播放、云盘和下载页面均接入自适应共用头部，iPad 搜索框位于头部上方、右侧按钮与封面底部对齐。macOS 保留桌面头部；独立浏览页、表单和账户快捷操作不强行套用音乐集合动作。

补充：iPad 账户侧栏实际进入 `AccountDetailsView`，已将 `ProfileDetailHeader` 接入共用响应式头部，操作栏改为56pt云盘、播放排行与更多按钮，保留账户元信息和未登录入口。
