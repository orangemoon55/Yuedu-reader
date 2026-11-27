# 网易云桌面首页模块

核对日期：2026-10-23。

来源：网易云官方 Mac 客户端 3.1.8.3330 的公开前端资源 `hybrid/app.chunk.f23ceff.js`、`hybrid/30.chunk.f23ceff.js`，并使用当前登录账号核对接口响应。官方安装包入口：https://music.163.com/api/osx/download/latest 。未执行下载的客户端。

## 雷达数据契约

Kumone 请求 `POST https://music.163.com/weapi/pc/customize/block/page`，使用现有 weapi 加密、当前账号 Cookie，载荷为 `{"newStyle":true}`。该接口的内部 API 路径是 `/api/pc/customize/block/page`。

只读取 `data.blocks` 中 `code == CUSTOMIZE_PLAYLIST_MGC` 的模块；同一响应里的 `CUSTOMIZE_PLAYLIST_OFFICIAL` 是其他模块，不混入雷达。所有有效歌单按照模块的 `creatives` 顺序展示，从 `resources[].resourceId` 取得歌单 ID，不设置固定成员、数量上限或名称白名单。

模块的 `uiElement.mainTitle.title` 提供当前推荐文案。根据用户要求，雷达卡片使用歌单第一首歌的专辑封面，左上角不叠加雷达图标。歌单详情以 `n=1` 获取首曲，优先按 `trackIds[0]` 定位；若响应缺少首曲对象或封面，则通过歌曲详情补齐。只有首曲封面不可用时才回退到歌单或模块封面。歌单详情也补齐卡片的简短歌单名称，不改变来源成员、顺序或推荐文案；详情失败仍保留对应卡片。

成功更新替换整组快照，包括删除、新增和排序变化；明确返回空列表会清空卡片。接口错误、缺少目标模块、目标模块缺少 creatives 时保留上次快照。沿用首页可见时五分钟刷新、跨天失效及下拉强制刷新。

其他首页数据在 App 启动首次打开首页时加载，手动刷新会同时更新推荐歌曲、榜单、新碟、每日推荐封面和雷达模块。首页与歌曲推荐模型在 App 生命周期内复用，切换侧栏后返回首页不会重新抽取推荐；账号切换会加载当前账号的推荐。

## 客户端代码中的首页模块标识

| 标识 | 用途 |
| --- | --- |
| `PC_HOMEPAGE_DAILY_MIX` | 每日推荐及混合推荐入口 |
| `HOMEPAGE_BLOCK_PLAYLIST_RCMD` | 推荐歌单 |
| `PC_HOMEPAGE_BANNER_BLOCK` | 首页横幅 |
| `PC_HOMEPAGE_TOPLIST` | 排行榜 |
| `HOMEPAGE_BLOCK_ALL_LISTEN` | 大家都在听 |
| `PC_HOMEPAGE_RECENT_LISTEN_BLOCK` | 最近常听 |
| `HOMEPAGE_BLOCK_RED_SIMILAR_SONG` | 红心歌曲与相似推荐 |
| `CUSTOMIZE_PLAYLIST_MGC` | 雷达歌单 |
| `HOMPAGE_BLOCK_VIP_RCMD` | VIP 歌曲推荐，HOMPAGE 是原始标识的拼写 |
| `HOMEPAGE_BLOCK_STYLE_RCMD` | 曲风推荐 |
| `HOMEPAGE_MUSIC_PODCAST_RCMD_BLOCK` | 每日音乐播客 |
| `PC_HOME_PAGE_PERSONAL_RCMD_VOICE` | 个性化播客 |
| `PC_HOMEPAGE_VOICEBOOK_RCMD` | 有声书推荐 |
| `CUSTOMIZE_PLAYLIST_OFFICIAL` | 专属场景歌单，同 customize 接口中的其他模块 |

模块是否出现在某次首页响应由服务端决定，不保证所有账号、版本和请求都返回全部模块。

客户端另使用 `/api/pc/page/rcmd/resource/show` 聚合首页，`pageCode` 为 `PC_RECOMMEND_HOME`；模块刷新接口为 `/api/pc/page/rcmd/block/resource/refresh`，支持 `blockCode` 与 `blockRequestParam`。上述是本次发现的接口，不表示 Kumone 已接入所有模块。
