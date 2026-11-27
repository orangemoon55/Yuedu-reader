# 首页发现板块与接口

核对日期：2026-10-30。

首页顺序：功能入口和雷达 → 两组相似歌曲推荐 → 排行榜 → **推荐歌单 → 近期热播 → 分地区热门** → 新碟上架 → 推荐歌手。

## 接口映射

以下均为网易云内部接口路径，由 Coda 现有客户端执行加密、携带当前账号 Cookie；不是额外部署的第三方 API 服务。

| 用途 | 加密与路径 | 参数 | 读取数据 |
| --- | --- | --- | --- |
| 首页聚合，优先来源 | eapi `/homepage/block/page` | `refresh: Bool` | `data.blocks[].creatives[].resources[]` |
| 推荐歌单兜底 | eapi `/personalized/playlist` | `limit=30,total=true,n=1000` | `result` |
| 登录用户每日推荐歌单兜底 | eapi `/v1/discovery/recommend/resource` | 无 | `recommend`，排在通用推荐之前，按 ID 去重 |
| 近期热播兜底 | eapi `/v1/discovery/new/songs` | `areaId=0,total=true` | `data`，保留最多 100 首 |
| 分地区热门兜底 | eapi `/v1/discovery/new/songs` | 分别请求 `areaId=7/96/8/16,total=true` | 华语、欧美、日本、韩国交错合并，按歌曲 ID 去重，最多 100 首 |

`/v1/discovery/new/songs` 实际是分地区新歌源，沿用 MeloX 对热播板块的兜底策略，不代表按播放量计算的实时热度排名。服务端聚合板块可用时优先保留其内容，不把新歌接口描述为独立的热度算法。

## 模块识别与展示

- 推荐歌单：`HOMEPAGE_BLOCK_PLAYLIST_RCMD` 或标题“推荐歌单”。
- 近期热播：标题含“近期云村热播”“近期热播”，或 `HOMEPAGE_BLOCK_STYLE_RCMD`（与 MeloX 的映射一致）。
- 分地区热门：标题含“最近的热门歌曲”“分地区热门”；同响应中多个地区模块合并去重。
- 标题优先读取模块 `uiElement.subTitle.title`，其次 `mainTitle.title`，最后首个 creative 的主标题；识别时忽略空白。
- 接受歌单资源类型 `list`、`playlist`，歌曲类型 `song`。支持数值与字符串资源 ID；忽略无效资源、广告、视频、播客与缺少完整歌曲对象的资源。缺少可用内容时使用对应兜底。
- `resourceExtInfo.songData` / `song` 解码为现有 `Track`，保留专辑、歌手、时长及权限元数据。
- 歌单使用现有 `CoverCardBody`，卡片尺寸计算、圆角、间距、标题与副标题布局与“新碟上架”一致；支持详情导航与播放。歌单与新碟均通过 `HomeCoverShelf` 展示为上下两排，整组横向滚动，行高随卡片文字自适应。
- 歌曲使用现有 `MusicTrackPanel`，每列三行、横向滚动，复用播放及歌曲菜单。
- 不增加地区切换或设置项。分地区兜底并行请求，交错展示四个地区，避免首屏被单个地区占满。部分地区不可用时仍展示其余地区。

## 二级页面

从“根据你喜爱的歌曲推荐”开始，所有后续板块标题均提供小箭头入口。

- 喜爱歌曲推荐、根据某首歌推荐：进入当前推荐快照的完整歌曲列表。
- 推荐歌单、近期热播、分地区热门：进入各自的二级页面，按内容类型展示完整歌曲列表或歌单网格。
- 首页预览最多展示 18 张歌单卡片或 36 首歌曲；二级页面展示全部已加载内容，支持刷新、错误重试、空状态及登录提示。
- 排行榜、新碟、推荐歌手沿用已有二级页面。
- 返回首页保留原推荐快照，避免仅因导航重新抽取内容。

## 刷新与隔离

模型在 App 生命周期内复用，成功结果缓存 15 分钟，手动刷新绕过缓存。各板块独立兜底，刷新失败保留该板块上次内容并提供重试。账号变更清空旧内容；取消及被新请求替代的响应不提交。

## 参考

- [MeloX Home API](https://github.com/youshen2/MeloX/blob/main/MeloX/Core/Networking/NeteaseAPI%2BHome.swift)
- [MeloX 首页模块映射](https://github.com/youshen2/MeloX/blob/main/MeloX/Features/Home/HomeRecommendationFeed.swift)
- [MeloX 首页兜底策略](https://github.com/youshen2/MeloX/blob/main/MeloX/Features/Home/HomeRecommendationFallbackLoader.swift)
- [MeloX 资源结构](https://github.com/youshen2/MeloX/blob/main/MeloX/Core/Models/Home/HomePageResourceModels.swift)

Coda 独立实现数据解析、缓存和渲染，接口及模块契约参考上述公开源码；未引入 MeloX 的页面或卡片实现。
