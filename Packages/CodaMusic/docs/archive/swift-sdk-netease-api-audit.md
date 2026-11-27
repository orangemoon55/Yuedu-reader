# Kumone 与 NeteaseCloudMusicAPI-Swift 接口核查

核查日期：2026-10-29（Asia/Shanghai）。本次是源码、请求契约与离线验证，不是生产账号的全接口在线验收。

## 结论

**不建议整体替换目前的网易云接口层。大部分核心路径已有对应；该 SDK 不能直接解决累计听歌数问题。**

- SDK 的 `scrobble` 仍是 WEAPI `/api/feedback/weblog` 的 `play` 事件，没有 NCBL、`_plv/_pld`、文件回执匹配或远端时间确认。Kumone 当前已经有这些保障，不能退回旧实现。
- 最近播放、周/累计排行、累计听歌数是不同读取契约。SDK 使用的核心读取路径与我们对应，并没有一个“调用后保证累计数增加”的新接口。
- 我们发现 1 处明确的业务结果漏校验（P1-01），另有平台身份、查询参数位置、分页等需要独立验证的差异。没有把每个默认值差异都认定为故障。
- SDK 可用于补充接口目录和跨语言对照；其“路径覆盖 100%”报告不等于参数、账号状态和当前服务端行为均正确。

## 核查基线与范围

- 参考仓库：https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift
- 固定提交：`8626b8fe628144e051dd9e07180850d253c808f2`，本次开始时 HEAD；后续仓库更新不自动改变本报告结论。
- Kumone 基线：`76e0498ce23038429d180a61725bf6e7f3a18756` 加核查时工作区。工作区另有进行中的布局修改，本次未改动这些代码。
- 核查 `NeteaseAPI.swift`、`NeteaseHomeDiscovery.swift`、`SongCommentsAPI.swift` 的业务方法，以及 `NeteaseClient`、`NeteaseCrypto`、`NeteasePlaybackLog` 和播放器上报调度。`PlaylistCoverSource` 两次直连复用已列出的歌单/歌曲详情路径。
- 参考 SDK 的 `API/*.swift` 实数为 **373 个 public func 声明**；其中 **361 个方法含远端路径字面量**。这不是 373 个独立远端端点，也不是线上可用率。
- Kumone 上述三个 API facade 共 **67 个 static func 声明**，其中 **61 个含路径字面量的方法**列于附表；其余包含组合策略、转换或辅助函数。独立的 NCBL 上传另列，不与业务方法重复计数。
- 路径比对去掉 SDK 输入的 `/api` 前缀，再检查实际 WEAPI/EAPI 重写、参数及业务含义。Node 包装路由（如 `/song/url/v1`）不能直接当成网易云原始路径。

## 1. 传输、加密和会话

| 项目 | Kumone 当前实现 | SDK 当前实现 | 判断 |
|---|---|---|---|
| 请求拓扑 | 原生直连网易云；NCBL 独立通道 | 可原生直连，也可设置 serverUrl 走 Node 代理 | 参考时必须注明采用哪一种模式 |
| WEAPI | music.163.com/weapi + 双层 AES-CBC；固定密钥及配对 RSA 密文 | 同协议，每次生成随机 16 字符密钥并做 RSA | 离线计算验证固定 encSecKey 正确，不是本次计数问题的已知原因 |
| EAPI | interface.music.163.com/eapi；签名用 /api 原始路径 | 同样改写并以原始 uri 签名 | AES/MD5/帧结构对照通过 |
| CSRF | WEAPI body 注入 csrf_token，并按现有实现加入 query | EAPI header 有 __csrf；WEAPI 通用构造函数未自动注入 csrf_token | 不应整体替换我们的鉴权构造 |
| 响应校验 | typed decoded() 检查 JSON code，301 转 needLogin | 直连 processResponse 主要依赖 HTTP status，特定 body code 归一化为 200 | SDK 的不抛错不能证明业务成功 |
| 账号隔离 | auth epoch + login binding；拒绝旧会话回复；登出独立 client | Cookie 字典有 NSLock；未见等价的登录世代回复拦截 | 不能将 SDK 误写为“完全没有锁”，也不能认为字典锁等价账号隔离 |
| 配置身份 | 通用 EAPI 固定 PC header；Cookie 保留导入字段；歌词/NCBL 独立配置 | 平台映射 + 可继承 Cookie 字段，默认 iPhone | K 存在通用 header/Cookie 不一致风险，需 P2-01 验证 |
| 调试日志 | 现有上报只记录事件、歌曲、秒数和回执 | 直连响应预览；代理模式还打印参数、Cookie 前缀和含 token 的 URL | 不要直接照搬 SDK 调试输出 |

SDK 直连的具体缺口：HTTP 200、body.code=301 时，`normalizeStatusCode` 返回 HTTP 200；`processResponse` 不再按该业务 code 抛错。HTTP 200、body.code=500 等也可能被当作正常响应对象返回。这是静态控制流结论，不是在用户账号上制造过期会话验证。代理模式有独立的响应处理，不能把此结论不加区分地推广到代理模式。

## 2. 历史、排行和累计统计（重点）

| 功能 | Kumone | SDK | 结论 |
|---|---|---|---|
| 最近播放读取 | WEAPI /play-record/song/list，读取歌曲与 playTime | recordRecentSong → 同路径，另有 offset 参数 | 读取路径基本一致 |
| 听歌周榜/累计榜 | WEAPI /v1/play/record，uid + type=1/0 | userRecord → 同路径与枚举语义 | 这是榜单，不是完整的历史清单 |
| 累计听歌数/等级 | WEAPI /v1/user/detail/{uid} 的 listenSongs/level | userDetail → 同路径 | SDK 没有新增计数机制 |
| 等级进度 | 当前常规页面未封装 /user/level | userLevel → WEAPI /api/user/level | 可作为额外读取，不等于 listenSongs，也不保证满级仍返回有效进度计数 |
| 当前播放上报 | HTTPS NCBL v3 + Zstd + _plv/_pld；第一方备用路由 | scrobble → WEAPI /api/feedback/weblog，仅 play，time 默认 0 | SDK 版本不能作为修复方案回退 |
| 接收与入账确认 | code + successfiles 文件名校验；有限远端历史确认 | 普通 APIResponse；没有历史/统计变化确认 | 两边的 200 都不能代替统计最终变化 |
| 更新时机 | 当前结束上报有 iOS 后台执行保障；统计缓存 60 秒，有限延迟刷新至 180 秒 | SDK 无应用页面缓存/播放器生命周期策略 | 应用层问题不能靠替换接口名字解决 |

SDK 另有 `listenDataRealtimeReport`、`listenDataReport`、`listenDataTodaySong`、`listenDataTotal`、`listenDataYearReport`，对应 `/content/activity/listen/data/...`。源码注释及方法参数表明这些用于读取听歌足迹/时长/报告；**不能因路径叫 report 就理解为补报播放器事件**。可选增加一个独立统计页，但不能将收听时长伪装成累计歌曲数。

此前 2026-10-28 的单账号实测记录见 [播放与统计诊断](netease-playback-history-diagnosis.md)。它只证明当时最近播放恢复、累计数延迟变化；不证明 2026-10-29 每一首 iPhone 完整播放均计入。本次没有再次发起播放，也没有用探针伪造历史。

## 3. 发现与处理优先级

### P1-01：我们歌单曲目操作的重试响应漏校验（明确代码问题）

位置：`NeteaseAPI.playlistTracks`。首次返回非 200 时会检查；当 `code=512` 且 `op=add`，将 trackIds 加倍后重试，第二次只 `await client.weapi`，未 decoded/检查 JSON code 就刷新资料并 return。

具体后果：第二次 HTTP 200 但业务返回 301/512/500 时，可能在 UI 被当作加歌成功。SDK 也不能作为正确性裁判，因为其直连通用业务码检查存在上述缺口。

建议：第二次回应必须解析业务 code；只在明确成功或产品认可的“已存在”结果下刷新。加入“首次 512 → 重试 301/500 不得成功”的离线回归用例。当前只审计记录，未修改运行代码。

### P2-01：通用 EAPI 平台身份可能与 Cookie 不一致（风险，未证明为现有故障根因）

K 的加密 header 固定 os=pc、appver=3.1.17、deviceId=kumone，而 HTTP Cookie 仅补齐缺省平台字段，已导入的 os/appver 会保留。SDK 提供平台映射可借鉴；但不应强行让所有端点共用一种身份，歌词、歌手订阅和 NCBL 已有各自兼容要求。

建议：建立显式 endpoint profile；通用 EAPI 的 metadata/HTTP Cookie/UA 在同一请求中一致。用 URLProtocol 解密请求验证，不先在账号上批量切换 UA 或设备字段。不要覆盖歌手订阅当前 os=web 特例。

### P2-02：参数位置与客户端约定需要验证（差异，非已证实故障）

- 红心 `likeTrack`：K 将 alg/time（以及重复的 trackId）放 URL query，SDK 放加密 body。SDK 的存在不能证明服务端忽略 query；若统一，应先以录制请求和真实红心读回做单点验收。
- FM 丢弃：K 使用 query 的 alg/songId/time，SDK 放 body。两者有相同原始端点。
- 二维码轮询：K WEAPI/type=1；SDK EAPI/type=3。不要只改 type 或只改 crypto；须成套验证 key、轮询状态及 Cookie 落盘。K 目前 800–803 独立解码有意保留状态码，不能走普通业务失败分支。
- 评论列表：K rid 为数字歌曲 ID，SDK 热评 rid 为完整 threadId；路径已包含资源类型。需要按具体端点验证，不能将两个字段的类型差异直接定为我们的错误。

### P2-03：列表上限与分页（产品限制，不等于接口损坏）

K 收藏专辑/歌手默认 limit=500，用户歌单 limit=2000，云盘 limit=1000；有 offset 参数，但上层是否循环分页需要另行处理。SDK 默认通常只有 25/30 条，不能替换后把首页数量变少误称修复。SDK 最近播放的 offset 参数也不证明服务端可以越过其真实历史窗口。

## 4. 参考 SDK 的局限，避免反向引入问题

1. **旧上报契约**：没有 NCBL；保留当前已实现的日志格式和服务端读回验证。
2. **直连业务码**：HTTP 与业务 code 未完整区分，见第 1 节。
3. **评论操作两种模式混合的疑点**：`comment()` 对原始 `/api/resource/comments/{action}` 发送 t/type/id，却不构造 threadId，和 K 当前原始端点 payload 不同。它同时支持 Node 代理；直连与代理都需各自验证，不能直接移植该方法。这里只判定契约差异，未实测断言所有评论必失败。
4. **调试数据泄露风险**：不要把原始 Cookie 前缀、登录参数、响应预览及 URL token 直接打入我们的日志。
5. **代理 5xx 重试**：全局对 5xx 自动重试一次，涵盖写操作；若服务端先完成操作再返回错误，可能重复提交。K 不应全局照搬，须按幂等性决定。
6. **覆盖率口径**：其 `docs/AUDIT_Node_vs_Swift.md` 是 2026-02-09 的路径匹配审计，不是本次真实 API 成功率，也不覆盖我们现在额外的 PC 雷达/NCBL 契约。

## 5. 离线验证结果及边界

- 45 项测试、6 个 suite 通过：`NeteaseLyricsAPITests`、`NeteaseDownloadTests`、`ArtistSubscriptionTests`、`SongCommentsTests`、`AccountIsolationTests`、`PlaybackHistoryReportingTests`。
- 使用参考 SDK 固定提交的 `CryptoEngine` 独立计算：K 的 WEAPI 双层 AES 输出匹配；固定 encSecKey 与 SDK RSA 运算匹配；三条 EAPI 路径的原始路径、JSON、MD5 及 AES-ECB 帧结构解密验证通过。离线合成输入包含中文与 `+ & =`，不含用户凭据。
- 没有改业务代码、运行 SDK 示例、读取真实账号 Cookie、发送验证码/评论/红心、创建歌单或生成新播放记录。没有真机/模拟器安装、Mac 应用替换或自动化 Runner；本次只新增文档和核查清单。
- 测试通过不覆盖 P1-01 的缺失场景，因此没有写成“45 项通过，所以没有问题”。

## 6. 当前方法逐项映射

下表按方法声明计数，不按独立 URL 计数。同一个详情端点被多个组合方法复用是正常现象。路径匹配只证明存在对应实现，参数、响应结构与当前线上有效性仍以正文为准。`WEAPI/EAPI` 是本地实际选择，SDK 未显式指定时其 request 默认 EAPI。

| Kumone 方法 | 原始路径（省略 /api 前缀） | K 模式 | SDK 对应方法 | 核查备注 |
|---|---|---|---|---|
| `qrKey` | `/login/qrcode/unikey` | WEAPI | [loginQrKey](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Auth.swift#L121) | 路径对应；默认值或响应封装可有不同。 |
| `qrCheck` | `/login/qrcode/client/login` | WEAPI | [loginQrCheck](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Auth.swift#L154) | K: WEAPI/type=1；SDK: 默认 EAPI/type=3；同一路径不是同一配置。 |
| `sendSMSCode` | `/sms/captcha/sent` | WEAPI | [captchaSent](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Auth.swift#L80) | 路径对应；默认值或响应封装可有不同。 |
| `loginCellphone` | `/w/login/cellphone` | WEAPI | [loginCellphone](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Auth.swift#L18) | 路径对应；默认值或响应封装可有不同。 |
| `logout` | `/logout` | WEAPI | [logout](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Auth.swift#L68) | 路径对应；默认值或响应封装可有不同。 |
| `refreshLogin` | `/login/token/refresh` | WEAPI | [loginRefresh](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Auth.swift#L177) | 路径对应；默认值或响应封装可有不同。 |
| `userAccount` | `/w/nuser/account/get` | WEAPI | [loginStatus](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Auth.swift#L167) | SDK 的 loginStatus 同路径；userAccount 方法另用 /nuser/account/get。 |
| `userDetail` | `/v1/user/detail/\(uid)` | WEAPI | [userDetail](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+User.swift#L14) | 路径对应；默认值或响应封装可有不同。 |
| `userPlaylists` | `/user/playlist` | WEAPI | [userPlaylist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+User.swift#L28) | 路径对应；默认值或响应封装可有不同。 |
| `likedTrackIDs` | `/song/like/get` | WEAPI | [likelist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L165) | 路径对应；默认值或响应封装可有不同。 |
| `likeTrack` | `/radio/like?alg=itembased&trackId=\(id)&time=3` | WEAPI | [like](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L148) | K 的 alg/time 位于 query；SDK 放在加密 body；先保留现有行为。 |
| `likedAlbums` | `/album/sublist` | WEAPI | [albumSublist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Album.swift#L61) | K 默认 limit=500；SDK=25。 |
| `likedArtists` | `/artist/sublist` | WEAPI | [artistSublist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Artist.swift#L193) | K 默认 limit=500；SDK=25。 |
| `playRecords` | `/v1/play/record` | WEAPI | [userRecord](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+User.swift#L51) | K week=true→type=1，false→0；与 SDK 枚举一致。 |
| `recentSongs` | `/play-record/song/list` | WEAPI | [recordRecentSong](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Misc.swift#L656) | SDK 额外暴露 offset；未证明服务端支持无限分页。 |
| `cloudSongs` | `/v1/cloud/get` | WEAPI | [userCloud](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Cloud.swift#L16) | 路径对应；默认值或响应封装可有不同。 |
| `cloudDelete` | `/cloud/del` | WEAPI | [userCloudDel](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Cloud.swift#L51) | 路径对应；默认值或响应封装可有不同。 |
| `personalizedPlaylists` | `/personalized/playlist` | WEAPI | [personalized](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Recommend.swift#L14) | 路径对应；默认值或响应封装可有不同。 |
| `recommendResource` | `/v1/discovery/recommend/resource` | WEAPI | [recommendResource](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Recommend.swift#L98) | 路径对应；默认值或响应封装可有不同。 |
| `dailyRecommendSongs` | `/v3/discovery/recommend/songs` | WEAPI | [recommendSongs](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Recommend.swift#L88) | 路径对应；默认值或响应封装可有不同。 |
| `dislikeRecommendedSong` | `/v2/discovery/recommend/dislike` | WEAPI | [recommendSongsDislike](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Recommend.swift#L142) | 路径对应；默认值或响应封装可有不同。 |
| `playlistDetail` | `/v6/playlist/detail` | WEAPI | [playlistDetail](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L77) | 路径对应；默认值或响应封装可有不同。 |
| `toplistPreviewTracks` | `/v6/playlist/detail` | WEAPI | [playlistDetail](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L77) | 路径对应；默认值或响应封装可有不同。 |
| `radarPlaylists` | `/pc/customize/block/page` | WEAPI | 未找到公开对应方法 | 本地 PC 雷达接口；SDK 没有公开对应方法。 |
| `radarFirstSongCover` | `/v3/song/detail` | WEAPI | [songDetail](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L14) | 路径对应；默认值或响应封装可有不同。 |
| `playlistBrief` | `/v6/playlist/detail` | WEAPI | [playlistDetail](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L77) | 路径对应；默认值或响应封装可有不同。 |
| `songDetails` | `/v3/song/detail` | WEAPI | [songDetail](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L14) | 路径对应；默认值或响应封装可有不同。 |
| `topPlaylists` | `/playlist/list` | WEAPI | [topPlaylist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L244) | 路径对应；默认值或响应封装可有不同。 |
| `highQualityPlaylists` | `/playlist/highquality/list` | WEAPI | [topPlaylistHighquality](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L270) | 路径对应；默认值或响应封装可有不同。 |
| `toplists` | `/toplist` | EAPI | [toplist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Ranking.swift#L13) | K EAPI；SDK WEAPI；不能仅凭模式不同判错。 |
| `createPlaylist` | `/playlist/create` | WEAPI | [playlistCreate](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L17) | 路径对应；默认值或响应封装可有不同。 |
| `deletePlaylist` | `/playlist/remove` | WEAPI | [playlistDelete](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L37) | 路径对应；默认值或响应封装可有不同。 |
| `subscribePlaylist` | `/playlist/\(subscribe ? "subscribe" : "unsubscribe")` | WEAPI | [playlistSubscribe](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L176) | 路径对应；默认值或响应封装可有不同。 |
| `playlistTracks` | `/playlist/manipulate/tracks` | WEAPI | [playlistTracks](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Playlist.swift#L110) | K 512/add 重试分支漏校验第二次业务结果，见 P1-01。 |
| `intelligenceList` | `/playmode/intelligence/list` | WEAPI | [playmodeIntelligenceList](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Misc.swift#L622) | 路径对应；默认值或响应封装可有不同。 |
| `songAudioQualities` | `/v3/song/detail` | WEAPI | [songDetail](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L14) | 路径对应；默认值或响应封装可有不同。 |
| `songURL` | `/song/enhance/player/url/v1` | EAPI | [songUrlV1](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L56) | ids JSON 字符串、level、encodeType=flac、仅 sky 加 immerseType=c51 一致。 |
| `songDownloadURL` | `/song/enhance/download/url/v1` | EAPI | [songDownloadUrlV1](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L257) | 两边均始终传 immerseType=c51；都需单独验证下载权限。 |
| `lyric` | `/song/lyric/v1`<br>`/song/lyric` | EAPI | [lyric](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L107)、[lyricNew](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L125) | K 新版失败回退旧版，保留取消；SDK 两个独立方法。 |
| `personalFM` | `/v1/radio/get` | WEAPI | [personalFm](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Recommend.swift#L108) | 路径对应；默认值或响应封装可有不同。 |
| `fmTrash` | `/radio/trash/add?alg=RT&songId=\(id)&time=25` | WEAPI | [fmTrash](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Misc.swift#L96) | K alg/songId/time 在 query；SDK 放 body。 |
| `similarSongs` | `/v1/discovery/simiSong` | WEAPI | [simiSong](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Misc.swift#L70) | 路径对应；默认值或响应封装可有不同。 |
| `album` | `/v1/album/\(id)` | WEAPI | [album](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Album.swift#L14) | 路径对应；默认值或响应封装可有不同。 |
| `newAlbums` | `/album/new` | WEAPI | [albumNew](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Album.swift#L83) | 路径对应；默认值或响应封装可有不同。 |
| `albumDynamic` | `/album/detail/dynamic` | EAPI | [albumDetailDynamic](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Album.swift#L25) | 路径对应；默认值或响应封装可有不同。 |
| `subscribeAlbum` | `/album/\(subscribe ? "sub" : "unsub")` | WEAPI | [albumSub](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Album.swift#L41) | 路径对应；默认值或响应封装可有不同。 |
| `artist` | `/v1/artist/\(id)` | WEAPI | [artists](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Artist.swift#L27) | 路径对应；默认值或响应封装可有不同。 |
| `artistAlbums` | `/artist/albums/\(id)` | WEAPI | [artistAlbum](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Artist.swift#L68) | 路径对应；默认值或响应封装可有不同。 |
| `subscribeArtist` | `/artist/\(subscribe ? "sub" : "unsub")` | WEAPI | [artistSub](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Artist.swift#L172) | K 对此接口覆盖 os=web；不可按 SDK 默认身份回退。 |
| `topArtists` | `/toplist/artist` | WEAPI | [toplistArtist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Ranking.swift#L73) | 路径对应；默认值或响应封装可有不同。 |
| `similarArtists` | `/discovery/simiArtist` | WEAPI | [simiArtist](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Artist.swift#L126) | 路径对应；默认值或响应封装可有不同。 |
| `search` | `/cloudsearch/pc` | EAPI | [cloudsearch](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Search.swift#L57) | 路径对应；默认值或响应封装可有不同。 |
| `searchSuggest` | `/search/suggest/web` | WEAPI | [searchSuggest](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Search.swift#L91) | K 固定 web；SDK 默认 mobile，可选 web；响应结构有差异。 |
| `searchDefaultKeyword` | `/search/defaultkeyword/get` | EAPI | [searchDefault](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Search.swift#L107) | 路径对应；默认值或响应封装可有不同。 |
| `personalizedNewSongs` | `/personalized/newsong` | WEAPI | [personalizedNewsong](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Recommend.swift#L31) | 路径对应；默认值或响应封装可有不同。 |
| `homeDiscovery` | `/homepage/block/page` | EAPI | [homepageBlockPage](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Misc.swift#L541) | 路径对应；默认值或响应封装可有不同。 |
| `homeTopSongs` | `/v1/discovery/new/songs` | WEAPI | [topSong](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Ranking.swift#L33) | 路径对应；默认值或响应封装可有不同。 |
| `songComments` | `/v1/resource/hotcomments/\(resource)`<br>`/v1/resource/comments/\(resource)` | WEAPI | [commentHot](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Comment.swift#L104)、[commentMusic](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Comment.swift#L190) | K rid=数字 id；SDK 热评 rid=完整 threadId；先验证服务端实际约束。 |
| `likeSongComment` | `/v1/comment/\(like ? "like" : "unlike")` | WEAPI | [commentLike](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Comment.swift#L165) | 路径对应；默认值或响应封装可有不同。 |
| `sendSongComment` | `/resource/comments/\(commentID == nil ? "add" : "reply")` | EAPI | [comment](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Comment.swift#L30) | K: EAPI + threadId；SDK: WEAPI + t/type/id，直连契约需验证。 |
| `deleteSongComment` | `/resource/comments/delete` | EAPI | [comment](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Comment.swift#L30) | 同上，SDK 动态 action 路径展开后对应。 |

## 7. 主要源码依据（固定提交）

- [请求默认模式、直连/代理分流](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/NCMClient.swift#L140)
- [直连响应处理、路径改写与请求构造](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/Network/RequestClient.swift#L140)
- [平台身份和 Cookie](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/Session/SessionManager.swift#L143)
- [加密协议](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/Crypto/CryptoEngine.swift#L59)
- [歌曲音源、歌词、旧版上报](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Song.swift#L181)
- [账户详情、排行、等级](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+User.swift#L14)
- [听歌足迹读取](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Misc.swift#L183)
- [评论参数](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/Sources/NeteaseCloudMusicAPI/API/NCMClient+Comment.swift#L30)
- [SDK 路径覆盖报告](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift/blob/8626b8fe628144e051dd9e07180850d253c808f2/docs/AUDIT_Node_vs_Swift.md#L1)
