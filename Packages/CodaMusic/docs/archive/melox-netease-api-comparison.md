# MeloX 与 Kumone 网易云接口对照文档

核对日期：2026-10-27。用途：比较当前源码接口、识别已移植部分、评估后续接入与排查兼容性。

运行反馈补充：用户确认两端播放均不新增网易云历史，但官方播放新增记录可在两端读取。因此，下文“上报契约接近/已移植”仅指实现，不能作为入账有效性证明。见 [历史上报定位记录](netease-playback-history-diagnosis.md)。

后续修复补充（2026-10-28）：Kumone 已实现原生 NCBL `_plv/_pld`、Zstandard 日志体、文件回执校验及远端历史确认；模拟器真实播放已验证最近播放新增、累计听歌数增加。下文保留修复前的比较基线；周/累计排行次数的本次短时复查仍未变化，详见[实测记录](netease-playback-history-diagnosis.md)。

## 1. 基线与结论

| 对象 | 核对依据 |
| --- | --- |
| MeloX | `youshen2/MeloX`，`main` 提交 `9c2f87b57b54ddbab76a4a53736f4840719a0947`，提交日期 2026-10-24 UTC |
| Kumone | 提交 `1933f40d684b7da3dbc007d0746049c92032d457` 的当前代码；本次开始时仅有上次生成的 YesPlayMusic 对比文档未跟踪 |
| 已移植来源 | `ThirdPartyNotices/MeloX.md`：歌词与听歌上报参考 MeloX 的 `a41ea0e1e1fa69fb543d827b853fe3aff5420951`；另一些 UI 适配参考 `9c2f87b...` |
| 范围 | 主体 iOS 网络层、9 个接口扩展、社交/一起听扩展；另核对 macOS 与 Watch 差异，以及登录、音质、上报、歌词相关代码 |
| 验证方式 | 源码静态分析；本地已有参考文件先与固定提交的 Git blob SHA-1 核对，不一致的两个 iOS 网络文件重新从 GitHub 获取；没有使用用户账号调用线上接口 |

**MeloX 与 Kumone 都用 Swift 原生直连网易云，架构比 YesPlayMusic 更接近；但两者并非整套接口已经一致。**

- 已接近：网易云逐字歌词的 v1/旧版请求链路、`clientlog` 听歌上报、v1 的 `level` 播放与下载接口。
- 仍不同：MeloX 的 eapi 默认客户端配置、完整浏览器 Cookie 补齐、空响应重试/切换协议、账号兼容路径、搜索与搜索建议、歌单增删曲路径。
- MeloX 扩展更多：聚合首页、播客、云盘上传、歌曲百科、楼层回复、听歌识曲、私信/动态分享、一起听。
- Kumone 也有自己的扩展：桌面雷达模块、每日推荐负反馈、独立热门评论与评论写操作、第三方音源、下载资源校验；不能把 MeloX README 的功能数量当作接口覆盖的单向超集。

MeloX iOS 的这 12 个 API 源文件中，有 **77 个非 private 业务方法声明**，其中 `playbackSource` 有两个重载；另有 `validate` 校验方法。这个数字包含聚合、分页及转换方法，**不等于 77 条独立远端接口**。下文按方法归类，远端路径重复的地方明确标注。

与前一份文档联读：[YesPlayMusic 与 Kumone 对照](yesplaymusic-netease-api-comparison.md)。

## 2. 路径、协议与参数约定

| 记号 | 实际请求 |
| --- | --- |
| `W /xxx` | 内部 URI `/api/xxx` → `POST https://music.163.com/weapi/xxx` |
| `E /xxx` | 内部 URI `/api/xxx` → `POST https://interface.music.163.com/eapi/xxx` |
| `CL /feedback/weblog` | `POST https://clientlog.music.163.com/eapi/feedback/weblog`；签名 URI `/api/feedback/weblog` |
| `W → E` | 先 weapi；仅捕获 `APIError.emptyResponse` 后切 eapi，不是任意业务错误都切换 |
| “M” / “K” | 分别指 MeloX / Kumone |

M 方法传入完整 `/api/...` URI，K `NeteaseClient` 通常接受去掉 `/api` 的后缀。两边都把 JSON 加密后作为 `application/x-www-form-urlencoded` 表单发送，表格及示例均是**加密前**的业务载荷。

M `authenticated:true` 是**选择鉴权客户端配置**，不等于函数本身验证登录，更不表示 `false` 时不发送 `MUSIC_U`：默认配置也会从 Cookie 字符串读取并加入已有的 `MUSIC_U`。

## 3. 传输层与登录差异

### 3.1 请求配置

| 项目 | M | K |
| --- | --- | --- |
| 入口 | `@MainActor NeteaseAPI` + `NeteaseDirectClient`，注入设置和 URLSession | `NeteaseAPI` 静态方法 + 共享或隔离的 `NeteaseClient` |
| weapi 加密 | 每次随机 16 字符密钥，AES-CBC 两轮，Security 框架做原始 RSA 加密 | AES-CBC 两轮，固定第二层密钥及预计算 RSA 密文 |
| eapi 加密 | 内部 URI + JSON + MD5 摘要，AES-ECB；所有 eapi 显式 `e_r=false` | 同核心算法；普通 eapi 未显式设置 `e_r`，歌词/上报设置 false |
| 默认 eapi 身份 | `os=ios,appver=9.0.90,osver=18.0,channel=distribution`，移动浏览器 UA | 普通 eapi 是 pc 配置、桌面浏览器 UA；歌词使用与 M 接近的独立移动配置 |
| authenticated eapi | Cookie/os 决定设备配置，生成 deviceId/requestId；加密 header 同时作为编码后的 HTTP Cookie；使用 iPhone 客户端 UA | 普通 eapi 没有该统一开关；听歌上报另有匹配的专门实现 |
| weapi Cookie | 补 `__remember_me,ntes_kaola_ad,_ntes_nuid,_ntes_nnid,WNMCID,WEVNSM,NMTID` 及设备/os/appver/channel 等 | 主要使用持久化 Cookie，加默认 `os=pc,appver=3.1.17` |
| Cookie 保存 | `AppSettings.cookie` 字符串，持久化到 UserDefaults；允许只填 MUSIC_U token 或完整 Cookie | 自管字典，持久化到应用支持目录 `cookies.json`；持续接收 `Set-Cookie` |
| API 返回 Cookie | 主体 DirectClient `send/decode` 未将响应 Cookie 合并回设置；Watch 客户端另有响应 Cookie 提取 | `perform` 解析并吸收响应 Cookie，带 authEpoch 检查 |
| 会话切换保护 | Reporter 比较 Cookie 字符串；普通传输层未见 K 同类会话代次校验 | 请求前后检查会话绑定与 authEpoch；导入与退出可用隔离客户端 |
| 超时 | 普通 POST 15 秒；通用 GET 20 秒；NOS 上传 200 秒 | 普通 15 秒；歌词单次 20 秒 |

M 的浏览器 Cookie 补齐是其请求配置的一部分。源码注释把它与 CFNetwork 的空响应问题关联，但本次没有做受控线上复现，不能断言补齐某个 Cookie 就能解决 K 的所有空包问题。

### 3.2 空响应、重试和业务码

| 情况 | M | K |
| --- | --- | --- |
| HTTP 非 2xx | 抛 `APIError.server` | 抛 `NeteaseAPIError.http` |
| HTTP 2xx 但 body 为空 | 单独抛 `emptyResponse(statusCode:)` | 未单独建模，通常在后续解码时失败 |
| weapi 空 body | iOS 默认最多 3 次总尝试，间隔 180/360ms；可 `retryEmptyResponse=false` 禁用 | 没有同类通用重试循环 |
| W/E 协议回退 | 在指定业务方法里显式实现，多数只捕获 emptyResponse | 普通曲库请求没有统一协议回退；歌词有 v1 → 旧版回退 |
| 可解码的非成功业务码 | 传输层只解码；调用 `validate` 的方法才检查 2xx 业务码；部分读取方法未统一检查 | 大多数方法通过 `decoded`，要求业务 `code=200`，301 映射 `needLogin` |
| 取消 | 多数回退处显式重新抛出 CancellationError | 歌词/音质等保留取消，其他请求沿 async 传播 |
| 写操作重试 | iOS 收藏歌单明确关闭空响应重试；歌单增删曲有 512 特殊兼容 | 无空包通用重试；增删曲 add/512 特殊重试 |

M 的 `validate` 接受 `[200,300)` 范围的业务 code，K 通用 `decoded` 只接受 200。M `decode` 中“成功解码”为真也不代表业务成功，因此不能仅比较传输层是否抛错。

自动重试会影响写操作语义。空响应不证明服务端未执行；M 的 iOS 收藏歌单已经为此关闭重试，后续若借鉴读取端回退，应保留这种按业务区分的处理。

### 3.3 登录方式：主体 WebView，Watch 扫码

| 平台 / 项目 | 登录流程 |
| --- | --- |
| M iOS | 加载网易云网页 `https://music.163.com/#`，使用 WebKit 数据存储，每 500ms 检查有效 `.163.com` Cookie；发现非空 MUSIC_U 后写入设置并刷新资料 |
| M macOS | WKWebView 加载 `https://music.163.com/#/login`，同样从 WebKit 提取 Cookie |
| M Watch | 独立 `E /login/qrcode/unikey` 和 `E /login/qrcode/client/login`，两者 `type=3`；检查响应 Cookie 字段或 Set-Cookie |
| K iOS/macOS | 自己实现二维码 key/check 与短信验证码登录；二维码 `W`、`type=1`；API 响应 Set-Cookie 入库 |

M iOS/macOS 的 `NeteaseAPI` 没有 K 同样的短信发送、手机验证码登录、二维码轮询、token 刷新与远端 logout 封装。其 WebKit Cookie 清理和 `settings.cookie=""` 是本地登录状态操作，不应误写成调用 `/logout`。

## 4. 共用业务逐项对照

### 4.1 用户、收藏与云盘列表

| M 方法 | M 请求与主要参数 | 返回 / K 对应与区别 |
| --- | --- | --- |
| `accountProfile` | `E /w/nuser/account/get`，authenticated；非取消失败再 `E /nuser/account/get` | 必须 code=200 且有 profile；K `userAccount` 只请求 `W /w/nuser/account/get` |
| `userDetail` | `W /v1/user/detail/{id}`；空包后 `E /w/v1/user/detail/{id}`，`all="true",userId`，authenticated | M 汇总 profile/level/listenSongs/createDays；K 同初始 W 路径，无该后备路径 |
| `userPlaylists` | `E /user/playlist`，`uid,limit=2000,offset=0,includeVideo=true`，authenticated | 返回 playlist；K `userPlaylists` 用 W，且方法可传 offset |
| `likedSongIDs` | 优先 `playlist(id:likedPlaylistID,trackLimit:0)` 取有序 trackIDs；失败再 `E /song/like/get`，`uid` | K `likedTrackIDs` 直接 W 请求 ID 列表；不采用此优先读取喜欢歌单的策略 |
| `subscribedAlbums` | `W → E /album/sublist`，`limit=2000,offset=0,total=true`；E authenticated | 从 `data` 提取数组；K `likedAlbums` 用 W，默认 limit=500，可传 offset |
| `subscribedArtists` | `W → E /artist/sublist`，`limit=2000,offset=0,total=true`；E authenticated | 从 data 提取数组；K `likedArtists` 同初始 W，默认 500，可传 offset |
| `setArtistFollowed` | `W → E /artist/sub` 或 `/unsub`；`artistId:id,artistIds:"[id]"` | K `subscribeArtist` 用 W；两个字段都显式为字符串，并先要求登录和正 ID |
| `userPlayRecords` | `W → E /v1/play/record`；`uid,type=周/累计枚举`；E authenticated | 返回对应记录并过滤无效歌 ID；K `playRecords` 用 W，week Bool 转 1/0 |
| `recentSongs` | `W → E /play-record/song/list`；`limit=100`；E authenticated | M 只提取 `data.list[].data` 的歌曲；K 返回带 playedAt 的记录并排序 |
| `cloudSongs` | `W → E /v1/cloud/get`；`limit=200,offset=0`；E authenticated | M 返回 CloudMusicPage；K 默认 limit=1000，用 W；两边都有云盘列表分页参数 |
| `deleteCloudSong` | `W → E /cloud/del`；`songIds:[id]` **真实数组**；E authenticated | K `cloudDelete` 使用 W，songIds 是 JSON 编码字符串 `"[id]"` |

M 账户资料的备选路径与空包兼容读取是两个不同机制：前者会捕获一般非取消错误并尝试旧账号路径，后者大多只因 emptyResponse 触发。

### 4.2 推荐、歌单与曲库详情

| M 方法 | M 请求与参数 | 返回 / K 对应与区别 |
| --- | --- | --- |
| `recommendedPlaylists` | `E /personalized/playlist`；`limit=10,total=true,n=1000` | result；K `personalizedPlaylists` 用 W，默认 30 |
| `newAlbums` | `E /album/new`；`limit=10,offset=0,total=true,area=参数或设置` | albums；K W，默认 30/ALL，可传 offset |
| `toplists` | `E /toplist` | list；K 同协议/路径，但使用独立 ToplistItem 模型 |
| `topArtists` | `E /toplist/artist`；无显式业务参数 | list.artists；K W，显式 type=1,limit=100,offset=0,total=true |
| `playlists` | 推荐/榜单分类委托已有方法；精品用 `E /playlist/highquality/list`，cat=全部,lasttime=0；其他用 `E /playlist/list`，cat,order=hot,offset,limit=50 | 返回数组；K 分为 topPlaylists/highQualityPlaylists；精品 K 可传 before，M 此方法固定 lasttime=0 |
| `playlist` | `E /v6/playlist/detail`；`id,n=0…100,s=8`，trackLimit 默认 100 | 按 trackIDs 再补歌曲；trackLimit=nil 表示取全部 ID；K playlistDetail 用 W、n=100000，后续交由 PlaylistContent 补齐 |
| `songDetails` | `W → E /v3/song/detail`；`c` 为 `[{id:...}]` 的 JSON 字符串 | 返回 songs；K 用 W，返回 songs 与 privileges |
| `songDetailsCollection` | 聚合方法，按缺失 ID **100 首**调用 songDetails，使用 prefetched、按输入顺序返回 | 不产生新路径；K 曲库补齐按 500 首分批，并保留权限/账号快照 |
| `songDetailsPage` | 本地 offset/limit 切 ID，limit 限制到 1…100，再调用 songDetails | 返回 songs,nextOffset,totalCount；不是服务端歌曲详情的 offset 分页 |
| `album` | `E /v1/album/{id}` | 返回 `(Album,[Song])`；K W，返回 AlbumDetailResponse |
| `albumSubscriptionStatus` | `W /album/detail/dynamic`；id | 返回 isSub，缺省 false；K albumDynamic 用 E，还读取 subCount |
| `setAlbumSubscribed` | `W /album/sub` 或 `/unsub`；id | K subscribeAlbum 同业务/协议 |
| `artist` | `E /v1/artist/{id}` + `E /artist/albums/{id}`，limit=100,offset=0,total=true | 一次方法返回歌手/热门歌/专辑；K artist 与 artistAlbums 分成两个 W 方法 |
| `dailySongs` | 首选 **E** `/v3/discovery/recommend/songs`，afresh=true 可选；仅 E 空包后切 W | K dailyRecommendSongs 首选 W；data=null 时 K 返回空，M 模型要求非空 data |
| `similarSongs` | iOS `W /v1/discovery/simiSong`；songid,limit=50,offset=0 | K 同 W，默认 30；M macOS 另有 W 空包 → authenticated E 回退 |
| `setSongLiked` | `E /radio/like`；alg=itembased,trackId,like,time="3"，authenticated | K likeTrack 用 W，把 alg/trackId/time 放查询串，载荷含 trackId/like |
| `setPlaylistSubscribed` | iOS `W /playlist/subscribe` 或 `/unsubscribe`，id；**retryEmptyResponse=false** | K 同 W 与主体载荷；M macOS 改用 authenticated E + token，详见第 8 节 |
| `createPlaylist` | `W /playlist/create`；name,privacy="10"/"0",type=NORMAL | M 要求响应 playlist 非空且 ID>0；K 返回顶层可选 id，两边关注的响应形状不同 |
| `deletePlaylist` | `W /playlist/remove`；ids JSON 字符串 | K 相同主体契约 |
| `addSong` / `removeSong` | 委托 manipulatePlaylistTrack，op=add/del | 只是单曲增删包装方法 |
| `manipulatePlaylistTrack` | **E `/v1/playlist/manipulate/tracks`**；op,pid,trackIds 为字符串 ID 数组的 JSON 字符串，imme="true"；authenticated | K 用 **W `/playlist/manipulate/tracks`**，没有 `/v1`，支持多首；M 对 512 的双份 ID 重试后还校验业务码 |
| `intelligenceModeSongs` | `E /playmode/intelligence/list`；songId,type=fromPlayOne,playlistId,startMusicId,count=1，authenticated | M 提取返回 ID 后再查详情，并按原 ID 排序；K 用 W，直接提取 `data[].songInfo` |

M 的精品列表虽然接受 `offset` 参数，但精品分支不传它，也固定 `lasttime=0`；不能把这个方法当作完整精品歌单翻页实现。M 歌单和 K 歌单都需要处理 trackIDs 与嵌入 tracks 不完整的情况。

### 4.3 播放、下载、搜索、歌词和评论

| M 方法 | M 请求与参数 | 返回 / K 对应与区别 |
| --- | --- | --- |
| `playbackSource(id:)` | 根据网络/设置选音质，委托内部解析；无法解析且 Cookie 字符串为空时可退官方外链 | K 统一走原生解析与下载/缓存/第三方回退，不采用同样的匿名官方外链策略 |
| `playbackSource(for:)` | 同上，额外用 Song.audioAvailability 过滤候选档位 | 两个重载属于同一远端播放契约 |
| `songURL` | 仅返回 playbackSource(id:).url | 包装方法，不是另一条远端 URL 接口 |
| `downloadSource` | `E /song/enhance/download/url/v1`，id,level，sky 时 immerseType=c51；失败可回 playbackSource | K songDownloadResource 独立校验下载资格、文件类型/摘要/时长，不以播放 URL 作为此方法的权限回退 |
| `search` | `E /search/get`；s,type,limit=30,offset=0 | K search 用 **E /cloudsearch/pc**，有分页 offset 与数量字段；M 额外声明播客 type=1009 |
| `searchSuggestions` | `W /search/suggest/keyword`；s | M 从 result.allMatch[].keyword 去重、最多 8 个字符串；K searchSuggest 用 **W /search/suggest/web**，返回歌曲/歌手/专辑/歌单对象 |
| `neteaseLyrics` | `E /song/lyric/v1`，异常后 `E /song/lyric` | 与 K lyric 的路径、主要版本参数和移动请求配置已接近；见第 5 节 |
| `lyrics` | 调用 neteaseLyrics 后交给 LyricParser 转行 | 本地解析包装，不新增远端路径 |
| `songComments` | `W → E /v1/resource/comments/R_SO_4_{id}`；rid,offset=0,limit=20,beforeTime=0 | 返回评论响应；K 最新评论同路径 W，热门另有专用 hotcomments 路径 |
| `songCommentReplies` | `W → E /resource/comment/floor/get`；parentCommentId,threadId,time=-1,limit=20 | M 楼层回复列表；K 尚无此独立读取接口，已有评论对象中的 beReplied 不是完整回复分页 |
| `recordRecentPlayback` | CL，action=startplay，字符串歌曲 ID/source content | K scrobbleStart 对应契约，已参考 M 移植 |
| `recordPlaybackDuration` | CL，action=play，字符串 id/sourceId/time，time≥0 | K scrobbleFinish 对应契约，已参考 M 移植 |

M 远端播放解析内部使用 `E /song/enhance/player/url/v1`，载荷 `ids:"[id]",level,encodeType:"flac"`，sky 增加 immerseType=c51；这点与 K 相同。返回实际 quality/format 仍由服务器决定。

## 5. 播放、下载与歌词的关键区别

### 5.1 音质不是只比较枚举名字

| API level | M MusicQuality / 保存值 | K AudioQuality |
| --- | --- | --- |
| standard | standard / `128000` | standard |
| higher | 未独立声明 | higher |
| exhigh | high / `320000` | exhigh |
| lossless | lossless / `flac` | lossless |
| hires | hiResolution / `hires` | hires |
| jyeffect | highDefinitionSurround / `jyeffect` | jyeffect |
| sky | immersiveSurround / `sky` | sky |
| jymaster | ultraClearMaster / `jymaster` | jymaster |

M 设置保存的 `flac`、`320000` 不是直接发送给新版 URL 接口的 level；调用时会转换为 lossless/exhigh。M iOS 还有蜂窝网络独立音质，macOS 使用普通 quality 设置。

M 每档有明确的降级序列，例如 hires → lossless → exhigh → standard，sky → jyeffect → lossless → exhigh → standard，并过滤歌曲详情已知不支持的档位。其循环仅在 noPlayableSource 时继续下档；其他错误可能直接跳到外层失败/匿名外链处理。

K `preferredSongURL` 有固定档位到 standard 或“始终最高”的候选选择，还比较实际返回 level 与 freeTrialInfo。播放器整体另有下载、缓存、第三方音源逻辑，不能将两个 API 辅助方法当作完整播放器等价实现。

### 5.2 下载与试听：M 的兼容回退更宽，K 的下载校验更严格

M `requestDownloadSource` 首次下载解析会检查歌曲 ID、非空 URL、`freeTrialInfo==nil`；但 `downloadSource` 捕获失败后会回到播放解析。其 `requestPlaybackSource` **没有排除 freeTrialInfo**，输出 `PlaybackSource` 也不携带试听标记。

因此，在 API 层不能把 M downloadSource 的所有返回结果都当作“下载权限已通过且是完整音频”。本次没有据此判断其最终下载管理层是否还会作其他限制。

K `songDownloadResource` 除拒绝试听外，还要求单条 code=200、MD5、实际 quality、可用格式、URL 和有效时长；已知歌曲时长与响应时长差异过大时拒绝。此差异是离线资源契约，不应为追求“接口一致”直接删除。

| 字段 | M SongURL / PlaybackSource | K SongURLData / 离线资源 |
| --- | --- | --- |
| id/url | 解码、查 ID、HTTPS 升级 | 解码，下载额外校验 ID/URL |
| br/type/level | 转 bitrate/format/quality | 保留，缺少 level 时可按实际编码/码率判断显示档位 |
| freeTrialInfo | SongURL 解码；下载初次解析检查；PlaybackSource 不保留 | 保留，参与播放与下载判断 |
| code/md5/size/time | 此 SongURL 模型未声明 | 离线资源身份、完整性与时长核对所需字段 |

### 5.3 歌词已移植，但“请求相近”不代表选择结果相同

两边首选 `/song/lyric/v1` 的加密前主体：

```json
{"id":123,"cp":false,"tv":0,"lv":0,"rv":0,"kv":0,"yv":0,"ytv":0,"yrv":0}
```

非取消异常后请求 `/song/lyric`：

```json
{"id":123,"tv":-1,"lv":-1,"rv":-1,"kv":-1,"_nmclfl":1}
```

两边都是异常触发回退；“请求成功但缺 yrc”不单独触发此回退。

| 内容 | M | K |
| --- | --- | --- |
| 移动 eapi 配置 | 普通默认 eapi 配置 | 专门 lyricsEAPI 配置，已参考 M 适配 |
| v1 字段 | lrc/yrc/tlyric/ytlrc/romalrc/yromalrc/pureMusic | 同类字段，并保留贡献者、nolyric/uncollected 等 |
| 旧接口回退输出 | 显式把 yrc/translatedYRC/romanizedYRC 置 nil | 解码并返回旧响应模型；并未同样显式清除这些字段 |
| 多来源 | M 有 AMLL TTML、网易云、QQ；自动策略优先 AMLL，再按逐字/翻译等条件选择 | K AlternativeLyricsAPI 在网易云、QQ、酷狗、LRCLIB 间匹配候选；当前没有同样的 AMLL 优先契约 |
| 上游解析算法 | MeloX 原实现 | K 保留多个 MeloX 前缀解析/时序模块，有 iOS 16 渲染适配 |

K 已移植范围见 [MeloX 来源说明](../../ThirdPartyNotices/MeloX.md)。纯音乐字段、移动请求配置及取消处理已被参考；不能把整个 M 网络层或歌词来源选择策略都视为已移植。

### 5.4 听歌上报已接近，账号绑定与刷新仍有区别

两边都将日志数组编码成 `logs` 字符串，发送到 CL，使用 eapi、`e_r=false`、osx 客户端配置：

```json
{"logs":"[{\"action\":\"startplay\",\"json\":{\"id\":\"123\",\"type\":\"song\",\"mainsite\":\"1\",\"mainsiteWeb\":\"1\",\"content\":\"id=456\"}}]"}
```

结束事件 play 增加 `download=0,end=playend,sourceId,time,type=song,wifi=0,source=list` 等；id/sourceId/time 使用字符串，time 单位秒。

- M PlaybackHistoryRecorder 将开始/结束提交串行化；以去首尾空白后的 Cookie 字符串识别账号是否变化；来源可回退到专辑 ID。
- K PlaybackHistoryReporter 使用会话指纹绑定开始时的账号和来源，适配 token 刷新及账号切换；成功后标记历史数据失效，并在后续延迟再次失效等待统计传播。
- K 普通传输层也有会话代次校验，避免旧响应覆盖新凭据；M 此 Reporter 的字符串检查不等于 K 整体的账号隔离实现。

本次只能确认源码协议与时序相近，没有用用户账号验证网易云当前是否实际计入最近播放和听歌排行。

## 6. MeloX 额外业务接口

### 6.1 首页、FM、百科与识曲

| M 方法 | 请求及加密前参数 | 返回 / K 差异 |
| --- | --- | --- |
| `homePage` | E /homepage/block/page，refresh=false,cursor?，authenticated | data 聚合首页；K 雷达使用另一条 PC 模块请求，不是同一契约 |
| `topSongs` | W → E /v1/discovery/new/songs，areaId=地区,total=true；E authenticated | data 歌曲，过滤 ID 后按 limit=12 截取；K 没有同路径方法 |
| `personalizedNewSongs` | W → E /personalized/newsong，type=recommend,limit=1…100,areaId；E authenticated | result[].song；K 同业务 W，默认 limit=10 且固定 areaId=0 |
| `recommendedPodcastPrograms` | W → E /program/recommend/v1，limit=1…50,offset=0；E authenticated | programs；K 无对应播客方法 |
| `personalFM` | E /v1/radio/get，mode=EXPLORE/FAMILIAR,limit=1…50 | data；K personalFM 用 W、不传模式和 limit；K 另有 fmTrash |
| `songWiki` | E /song/play/about/block/page，songId，authenticated | 解析 data 为 SongWiki；K 无百科聚合接口 |
| `audioMatches` | **GET** https://interface.music.163.com/api/music/audio/match | 指纹识曲，详见下方；K 无该网络方法 |

识曲参数：`sessionId=0123456789abcdef,algorithmCode=shazam_v2,duration=1…15,rawdata=<URL编码指纹>,times=1,decrypt=1`。它是原始 GET 路径，不经过 weapi/eapi；rawdata 来自本地音频指纹生成，不能替换成歌曲标题。

### 6.2 云盘上传：多步骤编排

`uploadCloudSong(fileAt:)` 没有 K 对应方法。它使用准备好的文件 MD5/大小/元数据，而不是只向某一个接口传文件 URL。

| 步骤 | 请求 | 核心参数 / 依赖 |
| --- | --- | --- |
| 1 | E /cloud/upload/check，authenticated | bitrate="999000",ext="",length,md5,songId="0",version=1；获得 songID/needUpload |
| 2 | E /nos/token/alloc，authenticated | bucket="",ext,filename,local=false,nos_product=3,type=audio,md5；保存 metadata resourceId |
| 3，必要时 | W → E /nos/token/alloc | 固定音频 bucket，申请独立上传 token；E authenticated |
| 4，必要时 | GET https://wanproxy.127.net/lbs | version=1.0,bucketname；获取 NOS upload host |
| 5，必要时 | POST <uploadHost>/<bucket>/<编码objectKey> | offset=0,complete=true,version=1.0；原文件 body；x-nos-token、Content-MD5、Content-Length；超时 200 秒 |
| 6 | E /upload/cloud/info/v2，authenticated | md5,songid,filename,song,album,artist,bitrate,resourceId；使用步骤 2 的资源 ID |
| 7 | E /cloud/pub/v2，authenticated | songid 使用步骤 6 的返回 ID |

“云盘上传”和“下载到本地”是相反的数据方向。步骤 2 的 metadata resourceId 与步骤 3 的传输 token/objectKey 不是同一用途，不能混用。

### 6.3 播客（8 个方法）

均由 `podcastRequest` 首选 W；仅空包后同路径切 E。标记 authenticated 的项目在 E 回退时使用对应配置；初始 W 一律使用已有 Cookie。

| M 方法 | 内部路径 | 关键参数 / 关注返回 |
| --- | --- | --- |
| `podcastCategories` | /djradio/category/get | categories，过滤无效 ID |
| `featuredPodcasts` | /djradio/recommend/v1 | 播客集合 |
| `personalizedPodcasts` | /djradio/personalize/rcmd | limit≥1，默认 12；个性化播客 |
| `podcasts` | /djradio/hot | cateId,limit=1…50,offset≥0；返回列表/hasMore/totalCount |
| `podcast` | /djradio/v2/get | id；要求播客对象非空 |
| `podcastPrograms` | /dj/program/byradio | radioId,limit=1…50,offset≥0,asc=false；节目页 |
| `subscribedPodcasts` | /djradio/get/subed | limit=1…100,offset≥0,total=true；E authenticated |
| `setPodcastSubscribed` | /djradio/sub 或 /unsub | id；E authenticated，校验业务码 |

K 当前没有这组播客网络封装。接入时还需要播客/节目模型及队列语义，不能仅把节目 ID 当作普通歌曲 ID。

### 6.4 私信、联系人与动态分享（6 个方法）

下列动作只作源码记录，本次没有读取用户私信或发送任何消息。

| M 方法 | 请求 | 参数 / 返回 |
| --- | --- | --- |
| `privateMessageConversations` | W → E /msg/private/users；E authenticated | offset=0,limit=50,total="true"；会话 messages |
| `privateMessageHistory` | W → E /msg/private/history；E authenticated | userId,limit=100,time=before或-1,total="true"；消息按时间升序返回 |
| `sendPrivateText` | E /msg/private/send，authenticated | type=text,msg,userIds 为去重排序 ID 数组的 JSON 字符串 |
| `messageContacts` | 聚合 W → E /user/getfollows/{id}；E authenticated | offset,limit,order=true；按 more 分页，去重，默认 pageSize=100/最多1000 |
| `sendPrivateMessage` | E /msg/private/send，authenticated | id=资源ID,msg,type=资源类型,userIds JSON 字符串 |
| `shareToTimeline` | E /share/friends/resource，authenticated | type,msg,id；先检查资源支持动态分享 |

M 源码指出私信历史初次 `time=-1` 同时承担已读上报，`time=0` 不等价。即使名为读取历史，也可能改变未读状态；这不是普通无副作用的曲库读取。

K 没有上述网易云社交封装；系统分享链接不等于已经接入 `/msg/private/send` 或 `/share/friends/resource`。

### 6.5 一起听（9 个方法）

除状态读取首选 W 外，其余均是 authenticated E。房间 ID 与 inviterId 使用字符串；进度单位为**毫秒**，与听歌上报的秒不同。

| M 方法 | 内部路径 | 载荷 / 返回 |
| --- | --- | --- |
| `createListenTogetherRoom` | /listen/together/room/create | refer=songplay_more；校验 data.roomInfo.id |
| `listenTogetherRoomStatus` | W → E /listen/together/status/get | 无业务参数；data 状态 |
| `checkListenTogetherRoom` | /listen/together/room/check | roomId；data 房间检查结果 |
| `acceptListenTogetherInvitation` | /listen/together/play/invitation/accept | refer=inbox_invite,roomId,inviterId |
| `listenTogetherPlayback` | /listen/together/sync/playlist/get | roomId；播放/队列状态 |
| `reportListenTogetherPlaylist` | /listen/together/sync/list/command/report | roomId,playlistParam 为 JSON 字符串；带 commandType、version[]、displayList/randomList 等 |
| `reportListenTogetherCommand` | /listen/together/play/command/report | roomId,commandInfo 为 JSON 字符串；commandType,progress,playStatus,formerSongId,targetSongId,clientSeq |
| `sendListenTogetherHeartbeat` | /listen/together/heartbeat | roomId,songId,playStatus,progress；可返回 data.timeSpan |
| `endListenTogetherRoom` | /listen/together/end/v2 | roomId；同时检查业务码与 data.success/result |

commandType 枚举为 PLAY/PAUSE/NEXT/PREV/GOTO/PROGRESS。队列同步另有命令字符串，默认 REPLACE，不要与播放命令枚举混用。

队列请求的加密前示意：

```json
{
  "roomId":"<房间ID>",
  "playlistParam":"{\"commandType\":\"REPLACE\",\"version\":[{\"userId\":123,\"version\":1}],\"anchorSongId\":\"\",\"anchorPosition\":-1,\"randomList\":[\"456\"],\"displayList\":[\"456\"]}"
}
```

Action 类型响应除了 code 校验，还检查 data.result/success 是否显式 false。一起听不是“拿到房间 ID 就开始普通播放”，还依赖版本号、命令序号、心跳与播放器同步 Store。K 当前没有同类接口与房间状态模型。

## 7. Kumone 已有、M 主体网络层未见直接对应的契约

这里比较的是已检查的 iOS/macOS 网络封装，不据此否认 M 聚合首页可能显示类似内容。

| K 方法 / 契约 | K 请求 | 区别 |
| --- | --- | --- |
| `recommendResource` | W /v1/discovery/recommend/resource | 独立每日推荐歌单；M 可能从首页聚合数据取得相似内容，但无同名独立方法 |
| `radarPlaylists` | W /pc/customize/block/page，newStyle=true | K 读取 PC 雷达 `CUSTOMIZE_PLAYLIST_MGC`，并补首曲封面；M homePage 用 /homepage/block/page，成员/文案/结构不等价 |
| `dislikeRecommendedSong` | W /v2/discovery/recommend/dislike | resId,resType=4,sceneType=1；M 无此直接负反馈封装 |
| `similarArtists` | W /discovery/simiArtist | M artist 方法不等于相似歌手接口 |
| `fmTrash` | W /radio/trash/add | K 已有 FM 丢弃；M personalFM 当前仅模式取歌接口 |
| `searchDefaultKeyword` | E /search/defaultkeyword/get | M searchSuggestions 是建议词，不是默认搜索词接口 |
| 热门评论 | W /v1/resource/hotcomments/R_SO_4_{id} | M songComments 响应可含热门评论，但没有同样的独立热门分页方法 |
| `likeSongComment` | W /v1/comment/like 或 /unlike | M 当前所查 API 文件无评论点赞方法 |
| `sendSongComment` | E /resource/comments/add 或 /reply | M 楼层回复读取不等于发送回复 |
| `deleteSongComment` | E /resource/comments/delete | K 已有写接口 |
| 独立下载资源契约 | E /song/enhance/download/url/v1 + 本地严格验证 | 路径两边都有；K 额外要求文件摘要、时长等信息 |
| 第三方音源回退 | 网易云镜像、酷狗、酷我等外部服务 | M 所查 playbackSource 无同样的灰歌第三方音频解析链；QQ 歌词来源不等于 QQ 音源 |

## 8. macOS 与 Watch 不能直接套用 iOS 结论

### 8.1 MeloX macOS 已确认差异

| 项目 | iOS | macOS |
| --- | --- | --- |
| 收藏歌单 | W，id，禁用空响应重试 | authenticated E，requiresCheckToken=true；收藏时载荷另加 checkToken |
| 相似歌曲 | W，同一路径，无 API 级 E 回退 | W 空包后切 authenticated E |
| 音质选择 | 蜂窝网络与其他网络可使用不同设置 | 使用 settings.quality |
| 表单编码 | 专用 formEncodedData，把 Base64 中的 `+` 做百分号编码 | 当前 send 使用 URLComponents.percentEncodedQuery；其语义不等于专用表单编码，应检查 `+` 是否按表单要求转义 |
| 空包重试控制 | weapi 提供 retryEmptyResponse 参数 | weapi 固定最多 3 次空包尝试，无该参数 |

因此，不能笼统建议 K 收藏歌单“按 MeloX 改成 eapi”：M 自己两个平台也不同。本次只识别差异，不以静态代码宣布某一种方式线上一定更稳定。

K 当前 encodeForm 的允许字符不含 `+`，会转义 Base64 的加号；借鉴 M 传输层时不应把 macOS 的 URL 查询编码方式直接替换过来。

### 8.2 Watch 网络层摘要

Watch 使用独立 `WatchNeteaseClient`，不是把主体 NeteaseAPI 原样编译到手表。其主要 API 包括搜索、每日推荐、账号、用户歌单、歌单/歌曲详情、v1 播放 URL、歌词及二维码登录；网易云调用使用 eapi。

| Watch 项目 | 契约 |
| --- | --- |
| 扫码 key/check | /login/qrcode/unikey 与 /login/qrcode/client/login，type=3；key 兼容顶层或 data.unikey |
| Cookie | QR 结果优先使用 body.cookie，否则从响应 Set-Cookie 组装；与主体 DirectClient 不同 |
| 歌单补齐 | n=100，请求缺失详情时每批 100 首，按 trackIDs 排序 |
| 歌词 | 并行准备网易云 v1 与 AMLL；有可用 TTML 时优先采用，失败再使用网易云解析 |
| 对 K 的意义 | 不能用 Watch type=3 推断 M iOS 的登录页面也直接轮询该接口；K 当前没有这套独立 Watch 网络客户端 |

## 9. 对当前 Kumone 的实际建议

| 顺序 | 可以借鉴的内容 | 接入边界 |
| --- | --- | --- |
| 1 | 对明确出现 HTTP 200 空 body 的读取接口单独建模，增加有限重试和同路径协议回退 | 先定位发生空包的真实请求；取消不重试；不要给所有写接口统一加重试 |
| 2 | accountProfile 的备选路径、歌单增删曲的 /v1 EAPI 与重试后业务码校验 | 作为兼容候选验证，保留现有账号绑定与错误语义 |
| 3 | 云盘上传的完整 NOS 编排 | 同时接入文件准备、token、资源发布与失败恢复；不能只增加一个路径常量 |
| 4 | 楼层回复、歌曲百科、移动建议词 | API 相对独立；搜索建议词字符串与现有实体建议属于不同交互 |
| 5 | 播客、识曲、一起听 | 涉及新的模型和播放器状态；按业务模块接入，不混进现有普通曲库模型 |

歌词与听歌上报优先维护现有已移植部分的一致性；下载保留 K 的完整资源校验。M 的 UI 参考与 API 迁移是不同工作，本次没有修改播放器界面或增加界面模式。

## 10. 源码依据

以下 M 链接全部固定到本次提交，避免 main 后续变化影响结论。

- [版本基线](https://github.com/youshen2/MeloX/commit/9c2f87b57b54ddbab76a4a53736f4840719a0947)
- [主体接口](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI.swift)、[主体传输层](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseDirectClient.swift)
- [专辑收藏](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BAlbumSubscriptions.swift)、[歌手收藏](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BArtistSubscriptions.swift)、[歌单管理](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BPlaylistManagement.swift)
- [首页与 FM](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BHome.swift)、[心动队列](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BIntelligenceMode.swift)、[听歌排行](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BUserPlayRecords.swift)
- [播客](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BPodcasts.swift)、[搜索建议](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BSearchSuggestions.swift)、[歌曲百科](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseAPI%2BSongWiki.swift)
- [私信与分享](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseSocialAPI.swift)、[一起听 API](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Networking/NeteaseListenTogetherAPI.swift)
- [iOS 网页登录与 Cookie 提取](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Features/Settings/Account/NeteaseLoginView.swift)、[macOS 登录](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloXDesktop/Features/Account/DesktopLoginView.swift)、[设置持久化](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Settings/Application/AppSettings.swift)
- [音质与降级策略](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Settings/Playback/MusicQuality.swift)、[URL/歌词响应模型](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Models/Networking/APIResponses.swift)、[多来源歌词选择](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Lyrics/LyricSourceMerger.swift)
- [上报队列](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Playback/Session/PlaybackHistoryRecorder.swift)、[一起听状态与同步](https://github.com/youshen2/MeloX/tree/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloX/Core/Playback/Session)
- [macOS 接口](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloXDesktop/Core/Networking/NeteaseAPI.swift)、[macOS 传输层](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloXDesktop/Core/Networking/NeteaseDirectClient.swift)
- [Watch 接口](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloXWatch/Networking/WatchNeteaseAPI.swift)、[Watch 传输层](https://github.com/youshen2/MeloX/blob/9c2f87b57b54ddbab76a4a53736f4840719a0947/MeloXWatch/Networking/WatchNeteaseClient.swift)

K 对应实现：[NeteaseAPI](../../Sources/Coda/Core/API/NeteaseAPI.swift)、[NeteaseClient](../../Sources/Coda/Core/API/NeteaseClient.swift)、[NeteaseCrypto](../../Sources/Coda/Core/API/NeteaseCrypto.swift)、[评论接口](../../Sources/Coda/Core/API/SongCommentsAPI.swift)、[URL/歌词模型](../../Sources/Coda/Core/Models/Models.swift)、[音质设置](../../Sources/Coda/Core/Storage/SettingsManager.swift)、[账号存储](../../Sources/Coda/Core/Storage/AccountStore.swift)、[歌单补齐](../../Sources/Coda/Core/Storage/PlaylistContent.swift)、[上报 Reporter](../../Sources/Coda/Core/Player/PlaybackHistoryReporter.swift)、[多来源歌词](../../Sources/Coda/Core/API/AlternativeLyricsAPI.swift)、[第三方音源](../../Sources/Coda/Core/Player/UnblockService.swift)。

本次只新增接口文档；没有更改 App 代码，也没有执行真机/模拟器构建、安装、启动或自动化测试。
