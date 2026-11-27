# 汽水音乐接入准备：接口、网易云差异与界面复用

整理日期：2026-10-31。本文保留接入前的源码审计与设计边界；后续首期原生实现及验证情况见 [qishui-integration.md](../development/qishui-integration.md)。

上游：[guowenye/qishui-api](https://github.com/guowenye/qishui-api)，固定审计提交 [`e409c10fe7441a10d370da7da61d62bbc1e5126c`](https://github.com/guowenye/qishui-api/tree/e409c10fe7441a10d370da7da61d62bbc1e5126c)。以路由模块、请求实现和归一化代码为准，README/OpenAPI 辅助对照。本次没有调用汽水业务服务、扫码或使用账号；下文“上游报告验证”不代表 Kumone 已实测可用。

## 1. 接入结论

沿用现有多平台架构和网易云页面：增加汽水数据适配、登录会话及能力判断，不新建汽水主题、卡片、详情页或播放器样式。播放器保持当前唯一界面，Mac、iPhone、iPad 仅响应式适配。

当前仓库提供 34 条能力路由，另有 `/`、`/health`、`/api/list` 三条服务入口。可优先联调推荐歌单、歌单详情、歌曲/歌单搜索、歌词、只读评论和账号歌单；是否启用由真实响应决定。

完整接入的首要待验证项是播放：`/media/player` 明确只给脱敏摘要；`/download/url` 或 `/audio/info` 能尝试从 H5 解析资源，但不能据此认定完整歌曲、会员音质、有效期刷新和播放引擎兼容已经解决。应先验证一个完整播放闭环，再开放平台入口。

汽水 Feed、电台、DailyMix 与网易云每日推荐/私人 FM 不完全等价。没有对应接口的喜欢写入、歌单编辑、收藏写入、云盘、历史、排行榜等功能，在汽水会话下隐藏或明确不支持，不借用网易云数据。

## 2. 与网易云的功能差异

本表的“缺失”仅指指定 qishui-api 提交未提供对应能力，不代表汽水官方产品没有该功能。网易云列以本项目实际接口为基准。

| 功能 | 网易云现有入口 | 汽水候选接口 | 差异与接入决定 |
| --- | --- | --- | --- |
| 登录 | `qrKey / qrCheck / loginCellphone` | `/auth/qrcode`、`/auth/qrcode/status` | 二维码文案要求已登录抖音 App 扫码；不沿用网易云状态码，不提供未经证实的短信登录 |
| 账号与会员 | `userAccount`、会员查询 | `/auth/me` | 返回 `profile.id/nickname/is_vip/vip_stage`；缺失字段不能认定非会员，不映射为网易云黑胶档位 |
| 推荐歌单 | `personalizedPlaylists / recommendResource` | `/recommend/playlist` | 从发现页混合块提取歌单；未证明个性化程度，使用“推荐歌单”文案 |
| 首页发现 | `homeDiscovery / homeTopSongs` | `/discover`、`/discover/mix` | 原始块需要映射；不原样复制汽水页面，不把任意 Feed 放入“热门榜” |
| 每日推荐 | `dailyRecommendSongs` | `/daily/mix` | 上游报告裸调通常 `ERR_REQUEST_FORBIDDEN`；属于持续推荐流，未证明按日固定列表，暂不开启 `dailySongs` |
| 私人 FM | `personalFM` | `/radio/list`、`/radio/tracks` | 主题电台不等价于个人 FM；后续可复用现有列表/漫游容器，但必须改为真实电台名称及语义 |
| 反馈 | `dislikeRecommendedSong / fmTrash` | 缺失 | 隐藏“不感兴趣”及对应远端反馈；下一首仅改变本地队列 |
| 雷达、地区歌曲、新碟、推荐歌手 | `radarPlaylists / homeTopSongs(areaID:) / newAlbums / topArtists` | 缺失等价接口 | 不显示对应模块；分享页附带歌曲不是完整榜单接口 |
| 排行榜 | `toplists / toplistPreviewTracks` | 缺失 | 不将电台、歌单或 `chart_tracks` 附带数据伪装为完整排行榜 |
| 歌单详情 | `playlistDetail` | `/playlist/detail` | `media_resources` 可能为混合媒体；保留歌单类型和游标，只转换实际歌曲 |
| 歌单推荐流 | 无完全等价入口 | `/playlist/feed/media`、`/playlist/related/media` | 不是歌单确定曲目清单；不可合并后声称歌单完整 |
| 曲目详情 | `songDetails(ids:)` | `/track/detail`、`/song/detail`、`/h5/seo/track` | PC/H5/分享页返回形状不同，缺少等价批量接口；详情元数据不等于可播放资源 |
| 歌曲搜索 | `search(type: .songs)` | `/search`、`/search/mixed` | PC 接口可能需要 Cookie 或签名；游标与搜索会话需要保留 |
| 歌单搜索 | `search(type: .playlists)` | `/search/playlist` | 专用接口失败时仅对 `UpstreamError` 回退混合搜索；业务拒绝不一定触发回退 |
| 综合搜索 | 现有各类型并发查询 | `/search/mixed` | 已归一化歌曲/歌单/视频；首期只显示歌曲、歌单，不新增视频页 |
| 歌手、专辑搜索与详情 | `search(.artists/.albums) / artist / album / artistAlbums` | 缺失独立接口 | 曲目附带作者/专辑只能展示元信息，不承诺完整详情或完整唱片目录 |
| 搜索建议、热词 | `searchSuggest / searchDefaultKeyword` | 缺失 | 隐藏平台建议，不回退网易云热词 |
| 我的歌单 | `userPlaylists` | `/me/playlists` | 只有读取；归一化字段不能直接证明创建者、收藏来源和可编辑权限 |
| 收藏/喜欢读取 | `likedTrackIDs / likedSongsPlaylist / likedAlbums / likedArtists` | `/me/collection/mixed` | 混合歌曲/歌单/视频，未证明等价完整“我喜欢”；先使用“收藏”语义，不能凭歌单名称识别喜欢列表 |
| 喜欢与收藏写入 | `likeTrack / subscribePlaylist / subscribeAlbum / subscribeArtist` | 缺失 | 隐藏写操作；不得本地改图标后宣称远端成功 |
| 歌单创建、删除、曲目编辑 | `createPlaylist / deletePlaylist / playlistTracks` | 缺失 | 不显示这些操作 |
| 播放 | `songURL / preferredSongURL` | `/media/player` 摘要；H5 `/audio/info /download/url` | 尚待完整播放验证；签名过期、试播、加密、鉴权、刷新均需单独处理 |
| 音质选择 | `songAudioQualities` | 缺失等价档位接口 | 首期不开放音质档位；编码/码率不能凭请求名称或会员状态推断 |
| 歌词 | `lyric` | `/lyric` | H5 可能只给 LRC，分享页可能给逐字时间；翻译、罗马音和完整逐字歌词无保证 |
| 评论读取 | `songComments` | `/comment` | 源码存在但 README 功能表遗漏；需转换 ID、时间、作者、排序及分页 |
| 评论操作 | `likeSongComment / sendSongComment / deleteSongComment` | 缺失 | 评论仅展示，隐藏点赞、回复、发布和删除 |
| 下载 | `songDownloadResource` | `/download/url /download/file /audio/decrypt` | 服务端工具接口，不等于现有离线契约；须先验证完整资源、可用授权、校验和文件格式 |
| 云盘 | `cloudSongs / cloudUpload / cloudDelete` | 缺失 | 隐藏云盘入口 |
| 云端历史、听歌排行、播放上报 | `recentSongs / playRecords / PlaybackHistoryReporter` | 缺失 | 不发送网易云上报；现有本地记录如保留，应标清本地来源并隔离账号 |
| 网易云账号同步 | `SyncService` | 缺失等价接口 | 不将汽水账号写入网易云专属同步路径；通用偏好同步与平台账号同步分开 |

## 3. 完整路由清单

方法缩写：G = GET，P = POST。下表状态均来自上游源码/说明，未做当前网络和用户账号的实时验证。能力清单里的 `auth=false` 不是匿名调用成功的保证。

### 3.1 登录与账号（5 条）

| 路由 | 方法 | 请求核心字段 | 返回与约束 |
| --- | --- | --- | --- |
| `/auth/qrcode` | G | 无必填 | `token / qrcode / qrcode_index_url / expire_time / copywriting / scan_app`；展示 `qrcode`，不要把二维码索引链接误当图片 |
| `/auth/qrcode/status` | P | `token` | `status / error_code / auth.sessionid`；同一扫码流程须命中保有临时 Cookie 的服务实例 |
| `/auth/me` | P | Cookie 或 JSON `sessionid`；可选 `aid` | `profile / upstream`；以真实平台用户 ID 建立本地账号 |
| `/me/playlists` | P | Cookie 或 JSON `sessionid`；`aid / iid / version_code` 可覆盖 | `playlists / total_num / upstream`；源码未透传 `cursor/count` |
| `/me/collection/mixed` | P | Cookie 或 JSON `sessionid`；可选 `aid` | `mixed_collections / total_num / upstream`；源码未透传 `cursor/count` |

以上四个 P 接口均为 bodyOnly：存在任何 URL query 即拒绝。账号接口的 Cookie 可放请求头，敏感参数不能放 query。`/video/detail` 和下载/解密的 P 接口同样按模块限制处理。

### 3.2 发现、推荐、电台与 Feed（13 条）

| 路由 | 方法 | 请求核心字段 | 返回与约束 |
| --- | --- | --- | --- |
| `/discover` | G/P | `first_request / ab_param` | 原始发现页块；上游报告已返回块；布尔值建议通过 JSON 真布尔传入 |
| `/discover/mix` | G/P | `block_type / sub_channel_id / cursor / count / session_id / feed_discover_extra / ab_param` | 原始混合块；分页游标与会话配套保存 |
| `/recommend/playlist` | G/P | 同混合流，`count` 默认 10 | `playlists / has_more / next_cursor / session_id / upstream` |
| `/playlist/detail` | G/P | `playlist_id`（或 `id/url`）、`playlist_type / cursor / count` | `playlist / media_resources / next_cursor / session_id / raw`；count 未走统一页大小上限 |
| `/playlist/feed/media` | G/P | `playlist_id / playlist_type / count / cursor / feed_session_id / server_session_id / played_media / feed_extra` | `items / has_more / feed_session_id / server_session_id / upstream`；下一游标未单独归一化；能力清单标需登录/App 上下文 |
| `/playlist/related/media` | G/P | `playlist_id / playlist_type / req_count或count / first_req_time / played_media / feed_extra / limited_free_scene / selected_boost` | 原始业务体；上游提示通常需登录，不能视为歌单内曲目 |
| `/radio/list` | G/P | 实际复用发现页参数 | `radios / upstream`；从发现页电台块提取 |
| `/radio/tracks` | G/P | `radio_id`（或 `id`）、`count / cursor` | `items / has_more / upstream`；未在顶层输出下一游标，不等价个人 FM |
| `/feed/mode` | G/P | 实现发空对象 | 原始模式数据；不据此新增播放器界面模式 |
| `/feed/mode/guidance` | G/P | 实现发空对象 | 原始引导数据；不新增独立引导样式 |
| `/daily/mix` | G/P | POST JSON 整体作为上游 payload | `supported_without_app_context / upstream`；只有 `status_code == 1000006` 判为 false，true 不保证业务成功 |
| `/feed/listen/video` | G/P | `count / cursor / played_media / feed_extra` | `items / has_more / upstream`；混合媒体，首期不开视频功能 |
| `/share/resolve` | G/P | 明确的 `track_id / playlist_id / video_id` 或 `url/id` | `input / ids / resource_types / primary_type`；本地解析，不会主动展开短链；裸数字可判 ambiguous |

### 3.3 搜索、详情、歌词与评论（8 条）

| 路由 | 方法 | 请求核心字段 | 返回与约束 |
| --- | --- | --- | --- |
| `/search` | G/P | `keywords`（兼容 `keyword/q`）、`cursor/offset / search_id / from_search_id / search_method / search_scene` | PC 原始业务体；设备字段可覆盖；可能依赖 Cookie/签名 |
| `/search/playlist` | G/P | 同搜索 | `playlists / source_strategy / upstream`；count 虽出现在 OpenAPI，PC 请求构造未使用 |
| `/search/mixed` | G/P | 同搜索 | `tracks / playlists / videos / mixed / source_strategy / upstream`；count 未透传，分页信息在原始业务体中 |
| `/track/detail` | G/P | `track_id`（或 `id/url`）、`media_type / queue_type` | PC 原始业务体；需自行解析业务失败 |
| `/video/detail` | P | `video_id`（或 `id/url`）、Cookie 或 `sessionid`、`type / scene_name / queue_type / aid` | `video / upstream`；bodyOnly，首期不接视频页 |
| `/song/detail` | G/P | `track_id/id/url` | 能提取 track ID 时走 H5 SEO，否则抓取允许域名分享页；两条分支字段不一致 |
| `/h5/seo/track` | G/P | `track_id`（或 `id/url`）、`device_platform` | H5 原始业务体，默认 web；不代表正式 App 资源权限 |
| `/lyric` | G/P | 同歌曲详情 | `lrc / lines`，H5 分支还带 raw；逐字结构见后文 |

另有评论路由 1 条：`/comment`（G/P），传 `group_id`（兼容 `track_id/id`）、`cursor`、`count`（默认 20）、`group_type`（默认 track）、`image_strategy`、`sort_type`（默认 hot，兼容 sortType）。返回 `comments / total / cursor / has_more / upstream`。归一化字段为 `id / group_id / user_id / user_name / user_avatar / content / like_count / reply_count / timestamp / is_liked`，不提供写操作。排序 `latest` 的真实效果仍需联调。

### 3.4 播放、音频与服务能力（7 条）

| 路由 | 方法 | 请求核心字段 | 返回与约束 |
| --- | --- | --- | --- |
| `/media/player` | G/P | GET 的 `media_id/track_id` 或 POST body 的明确 `media_id`；`media_type / queue_type / enable_refresh_api / enable_dash / scene_name / limited_free_param` | `player_infos` 的到期时间和存在性摘要；`url_player_info / video_model / play_auth / spade_a` 等脱敏；POST 不自动把 track_id 转成 media_id |
| `/audio/info` | G/P | 同歌曲详情，可选 `include_raw` | `track_id / name / artists / album / audio_url / has_audio_url / spade_a / has_spade_a / play_auth`；是否有完整资源未知 |
| `/download/url` | G/P | 曲目 ID/分享链接；可选 `sessionid` | 基于 audioInfo，要求解析出音频 URL 并通过域名校验；可以返回鉴权 URL，须区别于摘要接口 |
| `/download/file` | P | `audio_url/download_url/url` 或曲目/分享链接、`max_bytes` | `url / filename / content_type / size / audio_base64`；不是流式音频响应，下载资源时不转发入站 Cookie |
| `/decrypt/spade` | P | `spade_a` 或 `hex_key` | `hex_key / key_byte_length / decrypted_from_spade_a`；工具能力不表示资源授权或播放可用 |
| `/audio/decrypt` | P | `spade_a/hex_key` 加 `audio_base64/file_base64/audio_url` 等；可选 `return_base64 / max_bytes` | 本地 AES-CTR 等格式处理，输出文件/编码/大小/base64；服务可关闭；不直接形成 Kumone 离线资源契约 |
| `/api/capabilities` | G | 无 | 34 条静态能力声明，包含 methods/auth/app_context/raw；不是按账号实时探测结果 |

以上共 5 + 13 + 8 + 1 + 7 = 34 条。`/health` 只检查服务自身，不验证汽水上游；`/api/list` 列出模块；`/` 给出名称/版本/路由。这三条不纳入音乐功能能力。

## 4. 数据与协议差异

### 4.1 响应和业务失败

汽水服务正常封装为 `{code: 0, message, data, trace_id}`，网易云现有入口常按 `code: 200` 解析。不能直接复用网易云 Decoder 的成功判断。

`requestJson` 主要校验 HTTP 是否成功，没有统一校验汽水业务 `status_code`、登录错误或空结果。外层 code=0、HTTP 200 仍可能包裹 `ERR_REQUEST_FORBIDDEN`。适配器需要依接口检查 `data`、`data.upstream` 或原始业务体，区分需要登录、上下文不足、空列表、权限不足、超时和资源不可用，不把业务失败变成“暂无歌曲”。

默认 App 域名 `https://beta-luna.douyin.com`，PC 域名 `https://api.qishui.com`，分享域名 `https://music.douyin.com`。PC `X-Helios / X-Medusa` 仅从环境配置读取，源码没有自动生成签名；不能把“可配置签名”认定为“签名问题已解决”。默认设备标识运行时随机，账号及设备上下文稳定性需验证。

### 4.2 ID、权限和元数据

- 平台原始 track/playlist/artist/album/comment/user/vid ID 全程使用字符串。长数字 ID 不通过 JavaScript Number，也不使用内部负数键请求汽水。
- 延用 `PlatformMusicAPI.identifier(provider:kind:value:)` 生成内部稳定负数 ID；保留原始 ID 及 `playlist_type / media_type / vid`，不套用网易云 `mvID / fee / privilege` 语义。
- 现有 `BeansSong / BeansPlaylist` 不能直接承载全部汽水数据；优先增加可持久化的汽水引用或平台 DTO，不把 track_id 填进 QQ MID、酷狗 hash，也不要为歌单强制丢弃原始字符串 ID。
- 归一化歌单有 `id/title/type/description/cover_url/count_tracks`，没有可靠统一的 owned/subscribed 字段。未知曲目数不是 0；读取收藏不能证明编辑权限。
- 搜索/歌单歌曲 `duration` 直接使用上游 `duration ?? duration_ms`，分享页分支也没有统一单位；H5 formatH5SeoTrack 甚至不输出 duration/cover。需用实测样本和音频时长校准来源单位，不能凭字段名一律乘或除 1000。
- 曲目归一化封面在 album.cover_url；分享页可能有顶层 cover_url；H5 详情字段更少。合并元数据时保留已知封面/时长，缺失值不覆盖有效缓存。
- 会员 `Boolean(info.is_vip)` 会把缺失值当 false，字符串 `"0"` 当 true。后续应依据原始字段类型、业务成功状态和已验证的 vip_stage 含义解析；未知仍为未知，播放权限最终以资源结果为准。

### 4.3 分页和流

网易云共享入口偏向 offset/limit，汽水同时有整数搜索 cursor、字符串 Feed cursor、`next_cursor`、`session_id`、`feed_session_id`、`server_session_id`、`search_id`。不要通过 `offset += tracks.count` 代替原始游标，也不要用筛掉视频后的数量推断结束。

建议在数据层按“平台 + 账号 + 查询/歌单/电台 + 排序”保存分页状态；账号切换或查询变化即作废。返回已加载条目时按原始资源 ID 去重；重复页且游标不前进时结束并提示，不无限加载。

目前 `/radio/tracks`、`/playlist/feed/media`、`/feed/listen/video`、搜索的部分分页字段仅保留在 upstream；需确认真实字段后补归一化。账号列表没有真正分页透传；无法据 `total_num` 认定已经加载完整。

### 4.4 歌词和评论

分享页歌词可能有 `lines[{text,start_ms,end_ms,words[]}]`，词项也用毫秒；H5 通常只有 LRC，lines 为空。先接现有 LRC 路径；实测逐字字段后再转为现有逐字模型，不将句级时间伪造为逐字。

上游 `isMetadataLine` 会过滤所有 2–4 个汉字的纯中文行，可能误删正常短歌词。验收须包含短句；应优先保留原始歌词或修正过滤，再交给现有歌词渲染。原始分享数据不宜整包持久化，可能带资源凭据。

评论 ID/用户 ID 为字符串，要映射到当前 Int 模型并保存原始引用。`SongComment.time` 以毫秒解读，汽水 `timestamp` 未归一化单位，须实测转换。共享评论页热门读取 `hotComments`，最新读取 `comments`，适配器需按排序正确填充，不能只塞 comments 导致热门空白。作者缺失文案使用通用或汽水用户，避免默认成“网易云用户”。

## 5. 界面复用清单

| 页面/区域 | 复用现有实现 | 仅需的数据和能力适配 |
| --- | --- | --- |
| 账号管理 | `MusicAccountsSection / MusicAccountManager / AccountStore` | 增加平台及账号验证；sessionid 存钥匙串，不参与跨设备凭证同步 |
| 扫码弹层 | `PlatformLoginSheet / LoginQRCodeFrame` | 解码 qrcode 图片/data URI；展示抖音扫码文案；按新状态模型轮询和刷新 |
| 首页/精选 | `HomeView / ExploreView / HomeDiscoverySections / HomeCoverShelf` | 只装配真实支持的歌单和歌曲模块；不支持的栏目及分类隐藏 |
| 封面卡片 | `FeatureCard / CoverCardBody` 等现有组件 | 映射封面、标题、未知数量；保持当前 Theme token |
| 搜索 | `SearchView / SearchViewModel` | 首期综合、单曲、歌单；隐藏歌手/专辑分类，数据层按能力发请求 |
| 歌单详情 | `PlaylistDetailView / MeloXPlaylistDetailHero / MeloXPlaylistPrimaryActions` | 类型/ID/分页适配，只读权限；隐藏编辑、删除、收藏写入 |
| 歌曲列表 | `MusicTrackPanel / TrackList / TrackListScrollView` | 转 Track；隐藏缺失的喜欢/添加歌单/下载；歌曲元信息仍可展示 |
| 播放器、队列、歌词 | `NowPlayingView / PlayerBar / IOSPlaybackQueueView / AppleMusicLyricsColumn` | 资源解析、到期刷新、歌词模型适配；保留唯一播放器布局 |
| 评论栏 | `SongCommentsColumn` | 只读评论；统一空态、错误、分页，隐藏写操作 |
| 个人音乐库 | `IOSLibraryView / LibraryPages` 及现有歌单列表 | 先接账号歌单；收藏语义与完整性验证后再接；不显示不存在的云盘/排行 |

保持 `DesignSystem/Theme.swift` 与 [ui-layout-standard.md](../development/ui-layout-standard.md) 的间距、字体、卡片和空态规则。平台差异只涉及数据、文案、权限、可见入口和响应式布局，不建立 `QishuiHomeView`、`QishuiPlayerView` 或一套新视觉组件。

## 6. 现有代码需要改的具体位置（待实施）

1. `Core/Storage/MusicProvider.swift`、`Core/API/Beans/BeansModels.swift`：增加汽水枚举与持久化引用；审计未知来源回退网易云的逻辑，防止汽水对象误路由。
2. `Core/API/MusicServiceCatalog.swift`：增加汽水映射和限制说明；当前 supports 只看 endpoint 非空，应以“适配已经完成”为启用依据，不能填一条未验证路由就显示功能。
3. 新增数据层 `QishuiClient / QishuiAuth`（建议命名，尚未创建）：负责响应封装、业务错误、凭证、游标、DTO，不引入页面样式。
4. `Core/API/PlatformMusicAPI.swift`：现有多处 `provider == .qq ? QQ : Kugou` 及 if/else 需改为明确平台分派；只扩展枚举会把汽水请求发给酷狗。ID 注册同样需扩展，不使用默认酷狗句柄路径。
5. `Core/Storage/MusicAccountManager.swift`、`AccountStore.swift`、`MusicMembership.swift`：登录导入、保存、校验、恢复、移除、会员刷新均增加独立汽水分支。用户 ID 从 `/auth/me` 取，不把 sessionid 当用户 ID。
6. `Features/Pages/PlatformLoginSheet.swift`：当前非 QQ 默认酷狗。改为平台登录数据分派，保留弹层和二维码框；只有 confirmed 且有有效 session、随后资料校验成功才能保存账号。
7. `Features/Pages/SearchView.swift`：当前只按能力过滤歌单 tab；综合 tab 还会无条件并发歌曲/歌手/专辑/歌单。须同时处理分类可见性和综合加载能力，否则汽水缺失歌手/专辑会拖垮整页。分页放在数据层，不改视觉。
8. `Features/Pages/CollectionsView.swift`：当前缺少专辑收藏时默认展示歌手，汽水二者都未证实可用；避免展示错误空页，先按已验证集合语义提供现有列表入口。
9. `Core/API/NeteaseAPI.swift`、`SongCommentsAPI.swift`、首页数据和播放/下载/上报入口：复用当前入口时明确按汽水能力分派，禁止落回网易云资源或酷狗默认分支。
10. `Core/Player`、Storage 缓存和恢复路径：歌曲来源持久化；每次资源刷新检查请求 ticket，切换账号停止播放、清空队列并隔离旧请求。延用现有跨平台隔离机制，不共享临时音频 URL/密钥。

## 7. 服务部署与播放待办

qishui-api 是独立 Node.js 服务，不是可直接嵌入 Swift 的 SDK，也没有给出可长期依赖的公开服务地址。建议首期用受控服务做接口验证，客户端放在平台适配边界后；是否将部分请求迁为原生直连，待签名和上下文验证后决定。

- 服务 `0.0.0.0:3300` 仅为上游默认值。真机的 localhost 指向手机本身；联调需真机可达地址，正式连接应配置 HTTPS，不为此全局放宽客户端网络策略。
- 扫码临时 Cookie 在 QishuiClient 的内存 Map 中，服务重启或请求落到另一实例会丢失；验证前采用单实例或同一流程固定实例，并评估超时清理。
- HTTP 服务没有面向 Kumone 的调用方鉴权；CORS 不是鉴权。外部部署前需要接入认证、凭证日志脱敏及下载资源限制，不能直接裸露用户 session 和解密服务。
- `/media/player` 的原始播放字段即使 include_raw 也不可当作可用资源；不要为接入全局关闭脱敏。`/audio/info /download/url` 的音频字段则可能是真实凭据，须禁止日志/分析上报和普通元数据持久化。
- `/download/file` 返回 base64；默认文件上限 50 MiB，同时 POST JSON body 上限 1 MiB，base64 的额外体积和内存成本明显。其返回值不能直接塞入现有流式播放 URL；大文件优先受控 URL 或专门的资源传输方案。
- `QISHUI_ENABLE_DECRYPT` 可关闭解密；`QISHUI_DOWNLOAD_ALLOWED_HOSTS / QISHUI_DOWNLOAD_MAX_BYTES` 控制资源域名和大小。下载/解密只用于已获授权内容，能力开关不应绕过账号及资源权限。

完整播放验收需同时取得：真实有效资源、完整时长、支持的容器/编码、加密状态、授权边界、过期刷新方式和失败语义。未满足前 `playback / audioQualities / downloads` 不开放；不能将可解析一段试听资源报告为完整播放成功。

## 8. 分阶段实施与验收

| 阶段 | 工作 | 通过条件 |
| --- | --- | --- |
| P0 协议与播放验证 | 受控服务、业务错误、扫码、账号、资源样本 | 明确签名/App 上下文需求；用一个合法资源完成时长/格式/权限/过期刷新验证；记录实际响应而非仅 HTTP 200 |
| P1 数据与只读浏览 | 平台身份、DTO、账号隔离、推荐歌单、歌单、搜索、歌词、评论 | 长 ID 不丢失；分页去重；不混平台；混合视频正确过滤；仍使用现有样式 |
| P2 账号音乐库 | 我的歌单、收藏读取、会员未知态 | 明确 owned/subscribed、喜欢语义、列表完整性与失效会话；缺失写入入口均隐藏 |
| P3 推荐流与离线 | 电台/DailyMix、播放刷新、下载 | 逐项验证后才开放，不以推荐流替代固定歌单；离线资源满足现有校验和恢复契约 |

后续可用本地响应样本验证外层成功内层失败、confirmed 无 session、缺失会员字段、字符串长 ID、毫秒/秒、重复游标、切换账号迟到响应、短歌词及脱敏摘要。共享界面检查应涵盖首页缺模块、综合搜索缺类型、无详情跳转和只读操作隐藏。

本次只整理文档，不改客户端代码、不运行真机自动化或扫码、不构建和覆盖安装。后续影响客户端的实现完成后，再按 AGENTS.md 分别完成 Mac、已连接真机及已启动模拟器部署，真机和模拟器安装后不启动应用。

## 9. 审计来源

- [README](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/README.md)：上游报告的验证状态、登录说明和限制。
- [capabilities.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/capabilities.js)、[module](https://github.com/guowenye/qishui-api/tree/e409c10fe7441a10d370da7da61d62bbc1e5126c/module)、[server.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/server.js)：路由方法、bodyOnly、响应封装和服务入口。
- [qishuiClient.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/qishuiClient.js)、[http.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/http.js)：实际上游请求、分页字段、扫码 Cookie 和播放边界。
- [normalizers.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/normalizers.js)、[routerData.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/routerData.js)、[lyrics.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/lyrics.js)：统一模型、分享页与短歌词过滤。
- [redaction.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/redaction.js)、[config.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/src/config.js)：敏感字段和配置边界。
- [OpenAPI](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/openapi.json)、[smoke.test.js](https://github.com/guowenye/qishui-api/blob/e409c10fe7441a10d370da7da61d62bbc1e5126c/test/smoke.test.js)：接口声明与模拟响应测试；不是本次实测记录。
- 本地参照：[music-api-mapping.md](../architecture/music-api-mapping.md)、[music-platforms.md](../architecture/music-platforms.md)、`MusicServiceCatalog.swift`、`PlatformMusicAPI.swift`、`MusicProvider.swift`、`MusicAccountManager.swift`、`Track.swift`、`SongComment.swift`、`PlatformLoginSheet.swift`、`SearchView.swift`。
