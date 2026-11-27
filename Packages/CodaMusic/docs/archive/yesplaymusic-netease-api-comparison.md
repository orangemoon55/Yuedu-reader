# YesPlayMusic 与 Kumone 网易云接口对照文档

核对日期：2026-10-27。本文用于理解两端现有接口、移植功能及排查兼容性，不是网易云官方开放 API 文档。

运行反馈补充：用户确认 Kumone/MeloX 播放不新增网易云历史，官方播放新增记录可被两端读取。本文所述 clientlog 上报只代表源码实现，不能作为实际入账成功的证明。见 [历史上报定位记录](netease-playback-history-diagnosis.md)。

后续修复补充（2026-10-28）：Kumone 已实现原生 NCBL `_plv/_pld`、Zstandard 日志体、文件回执校验及远端历史确认；模拟器真实播放已验证最近播放新增、累计听歌数增加。下文保留修复前的比较基线；周/累计排行次数的本次短时复查仍未变化，详见[实测记录](netease-playback-history-diagnosis.md)。

## 1. 版本、范围与结论

| 对象 | 本文依据 |
| --- | --- |
| YesPlayMusic | `qier222/YesPlayMusic` 的 `master`，提交 `5d5fa23b7429c82a9932bbc2c9f6036403c5757b`，版本 `0.4.11` |
| YesPlayMusic 中间层 | `package.json` 声明 `@neteaseapireborn/api ^4.29.7`，`yarn.lock` 锁定 `4.29.7`；同时检查该版本 npm 发布包源码 |
| Kumone | 本仓库提交 `1933f40d684b7da3dbc007d0746049c92032d457` 对应工作区，核对开始时无本地修改 |
| 分析范围 | 网易云请求传输、登录、曲库、播放、歌词、推荐、搜索、云盘、MV、评论与听歌记录；第三方音源仅说明边界 |
| 验证方式 | 静态核对调用端、路由注册、锁定依赖的模块及模型；没有使用用户账号发起线上请求，也没有验证服务端当前可用性 |

**主要区别是接入层和具体请求契约，而不是两套完全不同的网易云服务。**

- YesPlayMusic 的 Vue 前端调用 Node HTTP 中间层，由中间层完成网易云路径映射、加密、Cookie 和响应转换；Electron 内置此服务，Web 版使用部署者配置的服务。
- Kumone 在 Swift 中直接访问网易云，自己实现 weapi/eapi、Cookie 持久化及类型解码，不依赖该 Node 服务完成主要网易云业务。
- 共享业务的大多数内部 `/api/...` 路径一致，但扫码 `type`、账号路径、播放音质参数、歌词版本、部分加密方式和上报时机存在明确差异。
- YesPlayMusic 有 MV、云盘上传、云盘内嵌歌词等前端封装；Kumone 有独立下载、最近播放、雷达、推荐负反馈、搜索建议及评论接口。
- 两端都有第三方音源回退，不能把此能力误写为 YesPlayMusic 独有；两端当前的听歌上报也都使用 `clientlog` eapi。

以下清单覆盖 YesPlayMusic `src/api/` 中除 `lastfm.js` 外的 **57 个导出函数**。这是“前端封装清单”，不代表每个函数都有正在使用的 UI 入口。Electron 的 `src/ncmModDef.js` 注册了 **124 条路由**，注册数量不等于产品功能数量。

## 2. 读表约定

表中的“Y”指 YesPlayMusic，“K”指 Kumone。

| 记号 | 含义 |
| --- | --- |
| `W /xxx` | 内部路径 `/api/xxx`，实际 `POST https://music.163.com/weapi/xxx` |
| `E /xxx` | 内部路径 `/api/xxx`，实际 `POST https://interface.music.163.com/eapi/xxx` |
| `CL /feedback/weblog` | `POST https://clientlog.music.163.com/eapi/feedback/weblog`，签名路径 `/api/feedback/weblog` |
| `GET /xxx`、`POST /xxx` | Y 前端向中间层发出的请求，不是直接向网易云发出的 HTTP 方法 |
| “无对应封装” | 本次检查的 K `NeteaseAPI` 与扩展中没有对应方法，不推断线上服务不支持 |

Y 协议列按锁定发布包默认配置推导：`APP_CONF.encrypt=true`，模块未指定协议时默认 **eapi**；`createOption(query, 'weapi')` 等可指定默认值，显式 `query.crypto` 又可覆盖它。Web 部署的 API 版本和配置可由部署者替换，因此此列不保证适用于任意公共实例。

ID 在 K 中通常为 `Int`；Y 查询参数经 HTTP 传输后通常是字符串。数组参数要区分逗号字符串、真实数组和 JSON 编码字符串；三者不能直接互换。下表标注的返回字段为业务关注部分，未列出字段不表示服务端不返回。

## 3. 请求传输与鉴权

### 3.1 调用链

```text
YesPlayMusic Web
  Vue → axios → VUE_APP_NETEASE_API_URL → Node API → 网易云

YesPlayMusic Electron（示例配置）
  Vue → 本地页面服务 127.0.0.1:27232 的 /api 代理
      → Node API 127.0.0.1:10754 → 网易云
  开发环境也可直接请求 127.0.0.1:10754

Kumone
  页面 / Store / Player → NeteaseAPI → NeteaseClient → 网易云
```

Y 地址由 `VUE_APP_NETEASE_API_URL`、`VUE_APP_ELECTRON_API_URL`、`VUE_APP_ELECTRON_API_URL_DEV` 决定。示例值分别是 `/api`、`/api`、`http://127.0.0.1:10754`。`/api` 是代理前缀；例如 `/api/song/url` 在中间层匹配的是 `/song/url`，不是网易云内部 `/api/song/url`。

| 项目 | Y | K |
| --- | --- | --- |
| HTTP 客户端 | 前端 axios；Node 侧另发请求 | `URLSession` |
| 普通请求超时 | 前端 15 秒；云盘上传 200 秒；自定义上报 10 秒 | 普通 15 秒；歌词单次请求 20 秒 |
| 参数载体 | 多数请求使用 axios `params`，包括多数 POST；上传额外使用 multipart body | 加密前构造 JSON，最终 POST 表单 |
| Cookie | `withCredentials=true`；Cookie 与 `localStorage cookie-*`；部分跨域 Web 请求显式传 `cookie=MUSIC_U=...;` | 自管 Cookie 字典，关闭系统 Cookie 自动接收，读取 `Set-Cookie`，写入应用支持目录 `cookies.json` |
| 匿名身份 | 发布包在无 `MUSIC_U` 时可补 `MUSIC_A`，并生成客户端标记 | 当前传输层没有同样的匿名 token 初始化流程 |
| 客户端标识 | 发布包按 Cookie/os 配置生成设备头，默认 pc 配置；eapi 默认使用 iPhone UA | 普通请求使用桌面浏览器 UA，默认 Cookie `os=pc; appver=3.1.17`；歌词和上报有独立请求配置 |
| IP 参数 | Web 非登录请求默认传 `realIP`；环境变量或设置可覆盖 | 当前 `NeteaseClient` 无同类 `realIP` 参数注入 |
| 应用内代理参数 | 可传 `proxy`，由 Node 侧配置代理 | 当前主要网易云传输层无同类业务参数 |
| 缓存 | 发布包服务端有 2 分钟 HTTP 200 响应缓存；前端多个接口加 `timestamp`；歌曲/歌词/专辑还用 IndexedDB | 由原生曲库快照、歌词缓存、音频缓存及下载存储管理；没有该 Node HTTP 缓存层 |
| 账号切换中的在途响应 | 检查到的请求层没有 K 同类的账号代次过滤 | `authEpoch` 与会话绑定校验旧响应，避免旧账号回包污染新会话 |

Y 的 `realIP` 会成为中间层发向网易云的 `X-Real-IP`/`X-Forwarded-For`。这只是请求头配置，不能据此保证地域限制可绕过。

### 3.2 加密契约

K 的 `NeteaseCrypto` 实现：

- **weapi**：JSON → 两次 AES-128-CBC → 表单 `params` 与 `encSecKey`。K 使用固定第二层密钥和预先计算的 RSA 密文；Y 发布包的 weapi 为每次请求生成第二层密钥并进行 RSA 加密。
- **eapi**：使用内部 `/api/...` 路径与 JSON 计算 MD5 摘要，再 AES-128-ECB，发送十六进制 `params`。两者此协议的核心算法一致。
- K 的普通 eapi 会把客户端 `header` 放进加密 JSON；歌词与听歌上报额外设置 `e_r=false`。Y 发布包也支持加密响应配置，默认关闭；K 当前按明文 JSON 响应处理。
- K 的 weapi 在载荷中放 `csrf_token`，存在值时也追加到 URL；eapi 的鉴权还包含加密 `header` 中的 `MUSIC_U`/`__csrf`。

所有后续 payload 示例都表示**加密前**的数据，不能把示例 JSON 原样 POST 到 `/weapi` 或 `/eapi`。

### 3.3 错误处理

| 情况 | Y | K |
| --- | --- | --- |
| HTTP 失败 | axios 错误拦截器处理；当前错误回调末尾没有统一 `Promise.reject`，部分错误可能向调用者表现为 `undefined` | 非 2xx 抛 `NeteaseAPIError.http(status)` |
| 业务 `code=301` | 在错误拦截器中匹配 `code=301` 且 `msg=需要登录` 时登出并跳转；HTTP 200 内的 301 不经过该错误分支 | 经 `decoded` 解码时抛 `needLogin`，不要求特定文案 |
| 其他非 200 业务码 | 成功拦截器直接返回 JSON，由业务调用处处理；中间层也会转换部分状态码 | 经 `decoded` 时抛 `business(code,message)`，接受 `message` 或 `msg` |
| 二维码 800–803 | 正常状态数据 | `qrCheck` 特意绕过通用业务码检查，直接解码 |
| 字段不兼容 | 各调用处处理 | 类型解码失败包装为 `decoding`；部分模型容忍字段缺省或类型差异 |
| 听歌上报失败 | Electron 自定义模块返回 HTTP 200，body `code=500`，避免直接透传 301 触发退出 | Reporter 捕获并记录错误，播放继续 |

K 并非所有方法都走通用 `decoded`：`qrCheck`、`refreshLogin`、`playlistTracks` 有专门逻辑。不能把上述规则无条件套用到每个方法。

## 4. YesPlayMusic 57 个前端封装逐项对照

### 4.1 登录与会话（7 个）

源码：Y `src/api/auth.js`；K `NeteaseAPI.swift` 的 Auth 部分。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数与关注返回 | K 对应及区别 |
| --- | --- | --- | --- |
| `loginWithPhone` / `POST /login/cellphone` | `E /w/login/cellphone` | `phone,countrycode=86,password/md5_password`；模块也接受 `captcha`；返回 `code,profile,cookie` 等 | `loginCellphone(phone:captcha:countryCode:)` → `W /w/login/cellphone`；当前 UI 使用短信验证码，额外传 `secureCaptcha=""` |
| `loginWithEmail` / `POST /login` | `E /w/login` | `email,password/md5_password`；返回账号及 Cookie | 无邮箱密码登录封装 |
| `loginQrCodeKey` / `GET /login/qr/key` | `E /login/qrcode/unikey`，`type=3` | 前端附 `timestamp`；读取 `data.unikey` | `qrKey()` → `W /login/qrcode/unikey`，`type=1`；直接读取顶层 `unikey` |
| `loginQrCodeCreate` / `GET /login/qr/create` | 中间层本地生成，无网易云请求 | `key,qrimg?`；返回 `data.qrurl, data.qrimg` | `qrLoginURL(unikey:)` 本地拼 URL；二维码在原生端绘制，无此 HTTP 路由 |
| `loginQrCodeCheck` / `GET /login/qr/check` | `E /login/qrcode/client/login`，`type=3` | `key,timestamp`；返回状态及成功时 `cookie` | `qrCheck(unikey:)` → `W /login/qrcode/client/login`，`type=1`；从 `Set-Cookie` 接收登录态 |
| `refreshCookie` / `POST /login/refresh` | `E /login/token/refresh` | 无业务参数；模块成功时附 `cookie` | `refreshLogin()` → `W /login/token/refresh`；函数本身吞掉错误；账户层每日最多尝试一次 |
| `logout` / `POST /logout` | `E /logout` | 当前 Cookie | `logout(detachedCookies:using:)` → `W /logout`；使用隔离客户端，禁止接收退出响应 Cookie |

Y 的 `loginAccount.vue` 实际包含手机/邮箱密码及扫码登录，密码在前端先 MD5，再传 `md5_password`。它实际扫码界面自己使用二维码库绘制，不能因为存在 `loginQrCodeCreate` 就断言页面一定调用该 HTTP 接口。

Y 还有 `loginUsername.vue`，通过 `search(type=1002)` 查用户，设为只读的 username 登录状态；它不等于获得 `MUSIC_U`。K 当前登录界面没有同类只读用户模式。

### 4.2 用户、收藏与云盘（13 个）

源码：Y `src/api/user.js`；K 的 User library 部分。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数 / 关注字段 | K 对应及区别 |
| --- | --- | --- | --- |
| `userDetail` / `GET /user/detail` | `W /v1/user/detail/{uid}` | `uid`；`level,listenSongs,profile` | `userDetail(uid:)` 同路径/协议；K 只声明所需统计字段 |
| `userAccount` / `GET /user/account` | `W /nuser/account/get` | 无业务参数；账号/`profile` | `userAccount(using:)` → **`W /w/nuser/account/get`**；路径多一层 `/w` |
| `userPlaylist` / `GET /user/playlist` | `W /user/playlist` | `uid,limit=30,offset=0,includeVideo=true`；`playlist,more` | `userPlaylists` 默认 `limit=2000`；只返回歌单数组，丢弃分页标记 |
| `userPlayHistory` / `GET /user/record` | `W /v1/play/record` | `uid,type=0`；`weekData/allData` | `playRecords(uid:week:)`；`week=true` 转 `type=1`；这是听歌排行，不是按时间排列的最近播放 |
| `userLikedSongsIDs` / `GET /likelist` | `E /song/like/get` | `uid,timestamp`；`ids` | `likedTrackIDs(uid:)` → `W /song/like/get`，返回 `[Int]` |
| `dailySignin` / `POST /daily_signin` | `E /point/dailyTask` | `type=0`；积分/业务码 | 无对应封装；Y 导出函数不等于仍执行每日自动签到 |
| `likedAlbums` / `GET /album/sublist` | `W /album/sublist` | Y 前端只转发 `limit` 和时间戳；模块默认 `limit=25,offset=0`；`data,count,hasMore` | `likedAlbums(limit:offset:)` 默认 `500,0`；返回数组 |
| `likedArtists` / `GET /artist/sublist` | `W /artist/sublist` | 与上一项类似，前端没有转发 `offset` | `likedArtists(limit:offset:)` 默认 `500,0`；返回数组 |
| `likedMVs` / `GET /mv/sublist` | `W /cloudvideo/allvideo/sublist` | 前端传 `limit`；模块支持 `offset`；收藏视频数据 | 无对应 MV 收藏列表封装 |
| `uploadSong` / `POST /cloud` | 多步骤云盘上传 | multipart 文件字段 **`songFile`**，附 `timestamp`；前端超时 200 秒 | 无云盘上传封装；本地下载功能与此相反，不能混为一谈 |
| `cloudDisk` / `GET /user/cloud` | `W /v1/cloud/get` | `limit=30,offset=0` 为模块默认；`data,hasMore,size,maxSize` | `cloudSongs(limit:offset:)` 默认 `1000,0`；保留容量与分页字段 |
| `cloudDiskTrackDetail` / `GET /user/cloud/detail` | `W /v1/cloud/get/byids` | `id` 逗号串 → `songIds` 数组 | 无单独云盘详情封装；当前读取云盘列表中的 `simpleSong` |
| `cloudDiskTrackDelete` / `GET /user/cloud/del` | `W /cloud/del` | 前端 `id`；发布包构造 `songIds:[query.id]` | `cloudDelete(id:)` 传 **JSON 字符串** `songIds="[id]"`；两侧数组类型不同 |

云盘上传内部依次涉及 `/api/cloud/upload/check`、`/api/nos/token/alloc`、必要时上传文件、`/api/upload/cloud/info/v2`、`/api/cloud/pub/v2`。`POST /cloud` 是完整编排入口，不是一个可直接照搬到 K 的单一网易云路径。

### 4.3 歌曲、歌词与上报（7 个）

源码：Y `src/api/track.js`、`src/utils/Player.js`、`src/electron/scrobble.js`。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数 / 关注字段 | K 对应及区别 |
| --- | --- | --- | --- |
| `getMP3` / `GET /song/url` | `E /song/enhance/player/url` | `id` 逗号串，`br`；返回 `data[]`；模块按输入 ID 顺序排序 | `songURL(ids:level:)` → **`E /song/enhance/player/url/v1`**；传 `ids` JSON 字符串、`level,encodeType`；没有同样的返回重排序 |
| `getTrackDetail` / `GET /song/detail` | `W /v3/song/detail` | `ids` 逗号串 → `c` JSON 字符串；`songs,privileges` | `songDetails(ids:)` 同路径；输入 `[Int]`；空数组直接返回空；K 曲库按 500 首分批补齐 |
| `getLyric` / `GET /lyric` | `E /song/lyric` | `id,tv=-1,lv=-1,rv=-1,kv=-1,_nmclfl=1` | `lyric(id:)` 先 **`E /song/lyric/v1`**，异常后回退 `/song/lyric`；使用专用 iOS 歌词请求配置 |
| `getCloudLyric` / `GET /api` | 显式 `E /cloud/lyric/get` | 通用入口传 `uri=/api/cloud/lyric/get,data={songId,userId,lv:"-1",kv:"-1"},crypto=eapi` | 无独立的云盘内嵌歌词封装 |
| `topSong` / `GET /top/song` | `W /v1/discovery/new/songs` | `type` → `areaId`，`total=true`；`data` | 无同接口封装；`personalizedNewSongs()` 是 `/personalized/newsong`，推荐语义及响应结构不同 |
| `likeATrack` / `GET /like` | `W /radio/like` | `id→trackId,like,alg=itembased,time=3` | `likeTrack(id:like:)` 同业务；`alg,trackId,time` 放入 URL 查询，payload 另含 `trackId,like` |
| `scrobble` / `GET /scrobble` | Electron 自定义 **CL**；外置 Web API 取决于部署 | `id,sourceid,time`，单位秒；自定义模块返回 `code,data,details` | `scrobbleStart` + `scrobbleFinish` 都走 **CL**；分开发送；详见第 5.4 节 |

Y `getMP3` 默认从设置取得 `musicQuality`，缺省 `320000`；值为 `flac` 时改传 `350000`。源码“高码率优先 Hi-Res”的注释不能视为当前服务器承诺，实际 `/song/url` 模块仍发送旧版 `br` 契约。

### 4.4 歌单与每日推荐（13 个）

源码：Y `src/api/playlist.js`；K Playlists 部分。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数 / 关注字段 | K 对应及区别 |
| --- | --- | --- | --- |
| `recommendPlaylist` / `GET /personalized` | `W /personalized/playlist` | `limit=30,total=true,n=1000`；`result` | `personalizedPlaylists(limit:)` 同契约，返回数组 |
| `dailyRecommendPlaylist` / `GET /recommend/resource` | `W /v1/discovery/recommend/resource` | 前端把传入值放在嵌套 `params`，模块实际不读取这些业务参数；`recommend` | `recommendResource()` 无参数，返回数组 |
| `getPlaylistDetail` / `GET /playlist/detail` | `E /v6/playlist/detail` | `id,n=100000,s=8`；`playlist,privileges`；`noCache` 仅控制加时间戳 | `playlistDetail(id:)` → **W**，同主体载荷；还有榜单十首预览和 `n=1` 简略请求 |
| `highQualityPlaylist` / `GET /top/playlist/highquality` | `W /playlist/highquality/list` | `cat=全部,limit=50,before→lasttime,total=true`；`playlists,lasttime,more` | `highQualityPlaylists(category:limit:before:)` 同业务；注意 Y 注释写 20，发布包实际缺省为 50 |
| `topPlaylist` / `GET /top/playlist` | `W /playlist/list` | `cat=全部,order=hot,limit=50,offset=0,total=true`；`playlists,total,more` | `topPlaylists(category:order:limit:offset:)` 同业务，K 分类参数需显式传入 |
| `playlistCatlist` / `GET /playlist/catlist` | `E /playlist/catalogue` | 无业务参数；分类数据 | 无远端歌单分类列表封装 |
| `toplists` / `GET /toplist` | `E /toplist` | `list` | `toplists()` 同协议/路径，返回榜单数组 |
| `subscribePlaylist` / `POST /playlist/subscribe` | `E /playlist/subscribe` 或 `/playlist/unsubscribe` | `id,t=1/2`；模块强制启用请求头 `X-antiCheatToken`，特定参数类型下还放载荷 `checkToken` | `subscribePlaylist(id:subscribe:)` → **W**，只传 `id`；无上述 token 注入 |
| `deletePlaylist` / `POST /playlist/delete` | `W /playlist/remove` | `id` → `ids="[id]"` | `deletePlaylist(id:)` 同主体载荷；K 单 ID 方法 |
| `createPlaylist` / `POST /playlist/create` | `W /playlist/create` | `name,privacy=0/10,type=NORMAL`；模块也可接受其他类型 | `createPlaylist(name:isPrivate:)` 固定 `type=NORMAL`；返回可选 `id` |
| `addOrRemoveTrackFromPlaylist` / `POST /playlist/tracks` | `E /playlist/manipulate/tracks` | `op=add/del,pid,tracks` 逗号串 → `trackIds` JSON 字符串，`imme="true"` | `playlistTracks(op:playlistID:trackIDs:)` → **W**；对 add/512 做双份 ID 重试，见第 7 节 |
| `dailyRecommendTracks` / `GET /recommend/songs` | `W /v3/discovery/recommend/songs` | 无主体参数；`data.dailySongs, data.privileges` | `dailyRecommendSongs(afresh:)` 可额外传 `afresh=true`；容忍 `data=null` 返回空数组 |
| `intelligencePlaylist` / `GET /playmode/intelligence/list` | `E /playmode/intelligence/list` | `id→songId,pid→playlistId,sid→startMusicId`，`type=fromPlayOne,count=1` | `intelligenceList(songID:playlistID:)` → **W**；`startMusicId` 固定为种子歌曲；提取 `data[].songInfo` |

`playlist.tracks` 不应被当作完整成员列表：Y 注释和 K 实现都以 `trackIds` 补齐详情。K 的 `PlaylistContent` 还检查成员数量、防止不完整回包截掉已有尾部，并按原 ID 顺序组合数据。`n=100000` 不是服务端一定返回完整 tracks 的保证。

### 4.5 专辑（4 个）

源码：Y `src/api/album.js`。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数 / 关注字段 | K 对应及区别 |
| --- | --- | --- | --- |
| `getAlbum` / `GET /album` | `W /v1/album/{id}` | `id`；`album,songs` | `album(id:)` 同路径/协议 |
| `newAlbums` / `GET /album/new` | `W /album/new` | `area=ALL,limit=30,offset=0,total=true`；`albums` | `newAlbums(area:limit:offset:)` 同主体契约 |
| `albumDynamicDetail` / `GET /album/detail/dynamic` | **W** `/album/detail/dynamic` | `id,timestamp`；收藏/评论/分享等动态数据 | `albumDynamic(id:)` → **E** 同路径；K 只解码 `isSub,subCount` |
| `likeAAlbum` / `POST /album/sub` | `W /album/sub` 或 `/album/unsub` | `id,t=1/其他` | `subscribeAlbum(id:subscribe:)` 用 Bool 选择路径 |

### 4.6 歌手（6 个）

源码：Y `src/api/artist.js`。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数 / 关注字段 | K 对应及区别 |
| --- | --- | --- | --- |
| `getArtist` / `GET /artists` | `W /v1/artist/{id}` | `id`；`artist,hotSongs` | `artist(id:)` 同路径；Y 未账号登录时还请求歌曲详情补热门歌曲 |
| `getArtistAlbum` / `GET /artist/album` | `W /artist/albums/{id}` | 模块默认 `limit=30,offset=0,total=true`；`hotAlbums,more` | `artistAlbums(id:limit:offset:)` 默认 `limit=100`；Y 注释称 50，与模块实际缺省不同 |
| `toplistOfArtists` / `GET /toplist/artist` | `W /toplist/artist` | `type=1`；发布包固定 `limit=100,offset=0`；`list.artists` | `topArtists(limit:)` 固定 `type=1`，limit 可传；Y 可选择地区 type |
| `artistMv` / `GET /artist/mv` | `W /artist/mvs` | `id→artistId,limit,offset,total=true` | 无对应封装 |
| `followAArtist` / `POST /artist/sub` | `W /artist/sub` 或 `/artist/unsub` | `id,t` → `artistId,artistIds="[id]"` | `subscribeArtist(id:subscribe:)` 同字段，显式使用字符串；要求登录及正 ID |
| `similarArtists` / `POST /simi/artist` | `W /discovery/simiArtist` | `id→artistid`；`artists` | `similarArtists(id:)` 同业务，返回数组 |

### 4.7 MV（4 个）

源码：Y `src/api/mv.js`。K 虽在 `Track` 模型里保留 `mvID`，本次没有找到对应 MV API 封装；有 MV ID 不等于已接入 MV 播放。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数 / 关注字段 | K 对应 |
| --- | --- | --- | --- |
| `mvDetail` / `GET /mv/detail` | `W /v1/mv/detail` | `mvid→id`；`data` 元数据、清晰度等 | 无对应封装 |
| `mvUrl` / `GET /mv/url` | `W /song/enhance/play/mv/url` | `id,r=1080`；`data.url` | 无对应封装 |
| `simiMv` / `GET /simi/mv` | `W /discovery/simiMV` | `mvid`；`mvs` 等相似视频数据 | 无对应封装 |
| `likeAMV` / `POST /mv/sub` | `W /mv/sub` 或 `/mv/unsub` | `mvid→mvId,mvIds`，`t=1/其他` | 无对应封装 |

### 4.8 搜索与私人 FM（3 个）

源码：Y `src/api/others.js`。

| Y 函数 / 中间层方法 | Y 内部请求 | 参数 / 关注字段 | K 对应及区别 |
| --- | --- | --- | --- |
| `search` / `GET /search` | **E `/search/get`**；type=2000 分支另走语音搜索 | `keywords→s,type=1,limit=30,offset=0`；`result` | `search(_:type:limit:offset:)` → **E `/cloudsearch/pc`**，额外 `total=true`；不能认为搜索数据结构完全一致 |
| `personalFM` / `GET /personal_fm` | `W /v1/radio/get` | 前端时间戳；`data[]` | `personalFM()` 同业务，缺省空数组 |
| `fmTrash` / `POST /fm_trash` | `W /radio/trash/add` | `id→songId,alg=RT,time=25` | `fmTrash(id:)` 将 alg/songId/time 放在 URL 查询，body 传 songId |

K `SearchType` 仅声明单曲 `1`、专辑 `10`、歌手 `100`、歌单 `1000`。Y 搜索参数可传用户 `1002`、MV `1004` 等；其用户搜索登录及 MV 搜索页面确有调用。模块接受的类型范围不等于每一种都有独立 UI。

## 5. 核心调用契约与示例

### 5.1 扫码与短信登录

K 扫码流程：

```text
qrKey() → 顶层 unikey
  → 本地生成 https://music.163.com/login?codekey=<unikey>
  → qrCheck(unikey:) 循环
  → 803 + Set-Cookie → AccountStore.bootstrap() 获取 profile/曲库
```

| code | 含义 |
| --- | --- |
| 800 | 二维码已过期 |
| 801 | 等待扫码 |
| 802 | 已扫码，等待确认 |
| 803 | 授权成功，仍应确认收到有效账号 Cookie 并能获取账号资料 |

Y `/login/qr/key` 返回 `{"code":200,"data":{"code":200,"unikey":"..."}}` 这一类封装；K `qrKey()` 解码顶层 `unikey`。Y 扫码 key 与 check 都使用 `type=3`，K 两者都使用 `type=1`。移植时要把类型、响应层级及 Cookie 接收方式一起核对，不能只替换路径。

K 短信发送接口为 `W /sms/captcha/sent`，加密前载荷：

```json
{"ctcode":"86","cellphone":"<手机号>","secrete":"music_middleuser_pclogin"}
```

随后 `W /w/login/cellphone`：

```json
{"type":"1","https":"true","phone":"<手机号>","countrycode":"86","captcha":"<验证码>","remember":"true","secureCaptcha":""}
```

这两步均由 `NeteaseClient` 补充 CSRF/Cookie。Y 本地服务注册了 `/captcha/sent`，但其 57 个前端封装中没有发短信函数；“后端有路由”和“登录 UI 已使用”需要区分。

### 5.2 播放 URL、音质与试听

Y 的旧 URL 契约可表示为：

```text
GET <Y_API_BASE>/song/url?id=123,456&br=320000
  → E /song/enhance/player/url
  → { ids: "[\"123\",\"456\"]", br: 320000 }
```

K `songURL(ids:[123,456],level:"lossless")`：

```json
{"ids":"[123,456]","level":"lossless","encodeType":"flac"}
```

实际发送到 `E /song/enhance/player/url/v1`；`level=sky` 时另加 `immerseType="c51"`。

| K level | 显示含义 | 歌曲详情中用于判断是否有源的字段 |
| --- | --- | --- |
| `standard` | 标准 | `l` |
| `higher` | 较高 | `m` |
| `exhigh` | 极高 | `h` |
| `lossless` | 无损 | `sq` |
| `hires` | Hi-Res | `hr` |
| `jyeffect` | 高清臻音 | `je` |
| `sky` | 沉浸环绕声 | `sk` |
| `jymaster` | 超清母带 | `jm` |

`songAudioQualities(id:)` 从歌曲详情中检查各档是否有非零 `br` 或 `size`。这说明歌曲存在该档资源，不等于账号具备播放权。

`preferredSongURL` 的最高音质策略会从可用档位高到低尝试，并比较**实际返回**的 `level` 与试听标记；固定档位策略在非标准档失败或无 URL 时再试标准档。实际播放层还有下载、缓存及第三方音源处理，因此不能把这个辅助函数的次序当作完整播放器行为。

关键返回字段（两端播放信息存在交集，以下为 K 消费字段）：

| 字段 | 解释 / K 用法 |
| --- | --- |
| `data[]` | 播放接口的逐首结果；用 `id` 关联，批量结果不要假设顺序 |
| `id,url` | 歌曲 ID、可能为 null 的媒体地址 |
| `code` | 单条资源业务码，与响应顶层 code 分开 |
| `level,type,br` | 实际档位、实际编码与码率；请求 `flac` 不保证返回无损 |
| `freeTrialInfo` | 非 null 表示试听；`start/end` 描述试听范围 |
| `time` | 音频时长，K 按毫秒换算 |
| `size,md5` | 文件大小与内容摘要，下载校验使用 |
| `fee` | 付费类别；展示提示不能替代 URL 服务端权限判断 |

Y 账号登录时拒绝 `freeTrialInfo !== null` 的播放地址；未账号登录时直接使用 `https://music.163.com/song/media/outer/url?id=<id>`。K 两个平台都通过 URL API 获取资源；iOS 在第三方回退失败但仍有试听 URL 时可播放并提示试听。K 的独立下载明确拒绝试听。不能据此宣称 K 播放端完全禁止试听，或把 Y 未登录外链策略直接套到 K。

### 5.3 歌词

K 首选 `E /song/lyric/v1`：

```json
{"id":123,"cp":false,"tv":0,"lv":0,"rv":0,"kv":0,"yv":0,"ytv":0,"yrv":0}
```

发生非取消异常后回退 `E /song/lyric`：

```json
{"id":123,"tv":-1,"lv":-1,"rv":-1,"kv":-1,"_nmclfl":1}
```

**回退触发点是请求或解码异常，不是“缺少 yrc 字段”。** 请求成功却没有逐字歌词时，当前函数不会因此自动请求旧接口。

| 返回字段 | K 关注内容 |
| --- | --- |
| `lrc.lyric` | 逐行原文 |
| `tlyric.lyric` | 逐行翻译 |
| `romalrc.lyric` | 逐行罗马音 |
| `yrc.lyric` | 逐字时间数据 |
| `ytlrc.lyric, yromalrc.lyric` | 配套翻译、罗马音 |
| `lyricUser,transUser` | 贡献者 |
| `nolyric,uncollected` | 纯音乐/未收集状态标记，具体展示交给歌词处理层 |

歌词请求独立使用 iOS 客户端 `header`、移动 UA 和 `e_r=false`，与 K 普通 eapi 的桌面标识不同。Y 当前 `getLyric` 只调用旧 `/song/lyric`，没有相同的 v1 优先链路。

此外 K `AlternativeLyricsAPI` 可并行从网易云、QQ、酷狗、LRCLIB 取候选并匹配；这是 K 的歌词选择层能力，不是 `/song/lyric/v1` 自身返回了其他平台歌词。

### 5.4 听歌上报与最近播放

两端当前 Electron/K 原生实现均向以下位置上报：

```text
POST https://clientlog.music.163.com/eapi/feedback/weblog
eapi 签名路径：/api/feedback/weblog
加密前主体：{ logs: "<JSON 数组字符串>", header: {...}, e_r: false }
```

`startplay` 的日志内容示意：

```json
[{"action":"startplay","json":{"id":"123","type":"song","mainsite":"1","mainsiteWeb":"1","content":"id=456"}}]
```

`play` 内容额外带 `sourceId,time,download=0,end=playend,wifi=0,source=list`。`time` 为秒，`content` 的来源 ID 与 `sourceId` 应保持一致。

| 行为 | Y Electron | K |
| --- | --- | --- |
| 调用入口 | 前端 `scrobble({id,sourceid,time})` | `PlaybackHistoryReporter.start` / `finish` |
| 发送时机 | 切歌或播完时，一次 `/scrobble` 在模块中依次补发 startplay 和 play；小于 1 秒跳过并做单次去重 | 开始与结束分别入队，串行保持事件顺序；完成时用总时长，否则限制在有效播放时长范围 |
| 账号绑定 | 自定义模块读取请求 Cookie | 会话保存账号指纹；账号变化后不继续提交该会话 |
| 无登录 | 模块返回 `code=200,data=skipped` | start 不创建已登录上报会话；传输层也检查登录绑定 |
| 客户端信息 | 自定义 macOS `osx` 配置，版本 `3.1.10.5100`，桌面浏览器 UA | 独立 `osx` 上报配置，默认版本 `3.1.17.204416`，iPhone UA；部分字段可沿用 Cookie |
| 成功后刷新 | 该模块不提供 K 同类 Store 失效通知 | 立即标记播放数据变化，并在后续延迟再次失效以等待统计传播 |

Y 的自定义实现仅通过 Electron 的模块定义替换 `/scrobble`。Web 页面调用同一路由时，实际行为取决于外置 API；不能默认也具备此覆盖。

K 读取记录区分两个接口：`playRecords(uid:week:)` 是累计/周排行；`recentSongs(limit:)` 是 `/play-record/song/list` 的按播放时间排列记录。它们不能互相替代。静态源码只能确认上报协议和时序，不能据此保证网易云此刻一定计入统计。

### 5.5 下载与缓存

K 的 `songDownloadURL(id:level:)` 使用 **`E /song/enhance/download/url/v1`**：

```json
{"id":123,"level":"lossless","immerseType":"c51"}
```

与播放接口 `data[]` 不同，此方法解码单个 `data` 对象。`songDownloadResource` 还要求 ID 一致、资源 `code=200`、无试听、存在 MD5/档位/支持的编码及有效 HTTP(S) URL，并核对已知时长；生成带账号范围的离线资源标识。

Y Electron 注册的 `/song/download/url` 映射到旧版 `E /song/enhance/download/url`，参数是 `id,br`；在 57 个前端封装中没有对应下载函数。Y `Player` 的自动缓存保存的是已选播放音源，可能包括第三方音源。这与 K 通过专门下载权限接口生成离线资源的契约不同。

## 6. Kumone 额外接口清单

这些方法没有在上述 Y 57 个前端封装中找到直接对应。即使某中间层有通用 `/api` 入口，也不等于该功能已经由 Y 页面接入。

| K 方法 | 真实请求 | 关键载荷 / 结果 |
| --- | --- | --- |
| `sendSMSCode` | `W /sms/captcha/sent` | `ctcode,cellphone,secrete`；详见 5.1 |
| `recentSongs(limit=100)` | `W /play-record/song/list` | `limit`；取 `data.list`，按 `playedAt` 降序 |
| `radarPlaylists` | `W /pc/customize/block/page` | `newStyle=true`；读取 `data.blocks` 中 `CUSTOMIZE_PLAYLIST_MGC`，保留资源成员/顺序并补卡片详情 |
| `playlistBrief` | `W /v6/playlist/detail` | `id,n=1,s=0`；雷达补名及首曲封面 |
| `toplistPreviewTracks` | `W /v6/playlist/detail` | `id,n=10,s=0`；按 `trackIds` 关联，缺曲再调用 `songDetails`；读取排名/增长字段 |
| `dislikeRecommendedSong` | `W /v2/discovery/recommend/dislike` | `resId,resType=4,sceneType=1`；校验替换歌曲 `data` |
| `songAudioQualities` | `W /v3/song/detail` | `c` JSON 字符串；读取 l/m/h/sq/hr/je/sk/jm |
| `songDownloadURL` / `songDownloadResource` | `E /song/enhance/download/url/v1` | 下载资格、实际音质及文件校验；详见 5.5 |
| `similarSongs(id:limit=30)` | `W /v1/discovery/simiSong` | `songid,limit,offset=0`；`songs` |
| `searchSuggest` | `W /search/suggest/web` | `s`；`result` 中歌曲/歌手/专辑/歌单 |
| `searchDefaultKeyword` | `E /search/defaultkeyword/get` | 无业务参数；只返回 `data.showKeyword`，模型虽声明 `realkeyword` 但此方法未返回它 |
| `personalizedNewSongs(limit=10)` | `W /personalized/newsong` | `type=recommend,limit,areaId=0`；从 `result[].song` 提取歌曲 |
| `songComments`，热门 | `W /v1/resource/hotcomments/R_SO_4_{id}` | `rid=id,offset=0,limit=20,beforeTime=0`；取 `hotComments` |
| `songComments`，最新 | `W /v1/resource/comments/R_SO_4_{id}` | 同类分页参数；取 `comments` |
| `likeSongComment` | `W /v1/comment/like` 或 `/unlike` | `threadId=R_SO_4_{trackID},commentId`；需要登录 |
| `sendSongComment`，发布 | `E /resource/comments/add` | `threadId,content`；去首尾空白且不允许空内容；需要登录 |
| `sendSongComment`，回复 | `E /resource/comments/reply` | 同上并增加 `commentId`；需要登录 |
| `deleteSongComment` | `E /resource/comments/delete` | `threadId,commentId`；需要登录 |

评论页响应模型为 `comments,hotComments,total,more,hasMore`；时间 `time` 在模型里按毫秒转换。最新与热门分页是两条资源路径，应使用对应集合及服务端分页标记。

雷达模块更完整的现有约定见 [网易云桌面首页模块](netease-desktop-home-modules.md)。

## 7. 已发现的兼容性差异与排查建议

以下是源码差异及其可能影响，**不是线上故障结论**。需要复现时应按同一账号、同一资源、同一时间和同一客户端标识进行受控比较。

| 优先检查点 | 已确认的差异 | 排查时应记录 |
| --- | --- | --- |
| 扫码登录 | Y type=3/eapi/嵌套响应；K type=1/weapi/顶层响应 | key/check 的 type 是否成对、状态码、是否收到 MUSIC_U、账号资料是否可读 |
| 登录后的账号读取 | Y `/nuser/account/get`；K `/w/nuser/account/get` | 实际请求路径与 profile；不能只依据接口简称认定完全相同 |
| 收藏歌单 | Y eapi + antiCheatToken；K weapi + id | 协议、token 有无、业务码；源码差异本身不足以证明 K 会失败 |
| 播放音质 | Y 旧 br；K v1 level | 返回 level/type/br/freeTrialInfo；不要把请求档位直接写成实际播放档位 |
| 搜索 | Y `/search/get`；K `/cloudsearch/pc` | type、result 层级、privilege 所在位置、分页计数 |
| 专辑动态 | Y weapi；K eapi | isSub/subCount、业务码，避免误判为只差前端字段名 |
| 歌单增删曲 | Y eapi；K weapi；均有 512 双份 ID 兼容逻辑 | 首次与重试响应；K 当前重试后未再做 `decoded` 业务码校验，有误报成功的可能 |
| 歌单增删曲返回层级 | Y 发布包首次成功分支把 request 的整个结果展开进 body | 可能出现 `body.code` 而非预期顶层 code；前端不能只按理想响应推断 |
| 歌词回退 | K 仅异常触发旧接口回退 | 缺 yrc、无歌词、纯音乐与请求失败分别记录 |
| 试听 | Y 丢弃登录态试听；K iOS 可提示并播放；K 下载拒绝 | freeTrialInfo 与当前音源来源，不要混用试听/下载资格 |
| 云盘删除 | Y 真数组 `[id]`；K JSON 字符串 `"[id]"` | 加密前字段的实际类型、业务码；不能只比较解码后的字符外观 |
| 收藏分页 | Y likedAlbums/likedArtists 注释有 offset，但包装函数未转发；K 有 offset 参数但返回数组 | 调用层是否继续分页；大 limit 不保证已经取尽全部内容 |
| 客户端身份 | Y 默认 eapi 有 MUSIC_A/设备标记；K 普通请求配置不同 | 匿名与登录分别复现；domain、UA、os、appver、协议一并比对 |
| 上报统计 | 两端都有 clientlog，但 Y 结束时补两事件，K 开始/结束分开发 | 不只看 code=200，还要区分最近播放、周排行与统计传播延迟 |
| UI 可播放性 | Y VIP 判断只认账号 `vipType===11`；K 代码使用 `vipType>0`，且优先取 privilege.fee | 此为列表展示判定差异，最终以 URL/试听返回为准 |

Y `getTrackDetail/getLyric/getAlbum` 都先调用一次 `fetchLatest()`，缓存未命中时又可调用第二次；因此偶发重复请求可由封装逻辑造成。缓存响应也可能早于后台更新，不应直接拿首次显示数据与 K 网络结果比较。

建议延续 K 原生传输层，按实际需求补齐缺失业务契约；若只是为了增加 MV 或云盘上传，并没有必要先把现有全部网易云请求改为 Node 中转。此建议来自当前架构与接口覆盖情况，不代表中间层在所有场景都不适合。

## 8. 第三方音源边界

| 项目 | Y | K |
| --- | --- | --- |
| 回退实现 | Electron IPC 调用 `@unblockneteasemusic/rust-napi`，源列表、匹配策略与第三方 Cookie 可配置；Web 不走该原生链路 | Swift `UnblockService`，当前顺序为启用的网易云镜像，再酷狗、酷我 |
| 网易云失败触发 | 缓存 → 网易云 → 原生第三方回退；登录态无 URL/试听会返回空源 | 网易云没有 URL或仅试听时可尝试启用的第三方来源；完整顺序还受下载、缓存及平台策略影响 |
| 网易云镜像的含义 | 无对应固定专用入口 | 当前代码实际请求 `music-api.gdstudio.xyz/api.php`，传 `types=url,source=netease,id,br=320`；这是外部服务，不是网易云官方 URL 接口 |
| 数据归属 | 第三方返回 URL 仍是第三方契约 | 有独立 source 标识与匹配/缓存处理，不能当作网易云官方实际音质返回 |

不要将两端第三方取到的可播放 URL 用作“网易云同一账号官方接口允许下载”的证据。

## 9. 源码与可追溯依据

### 9.1 YesPlayMusic 固定版本源码

- [提交与版本基线](https://github.com/qier222/YesPlayMusic/commit/5d5fa23b7429c82a9932bbc2c9f6036403c5757b)
- [依赖声明](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/package.json) 与 [锁定版本](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/yarn.lock)
- [请求层](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/utils/request.js)、[鉴权存储](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/utils/auth.js)、[播放与回退](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/utils/Player.js)
- [Auth](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/auth.js)、[User](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/user.js)、[Track](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/track.js)、[Playlist](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/playlist.js)
- [Album](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/album.js)、[Artist](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/artist.js)、[MV](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/mv.js)、[Search/FM](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/api/others.js)
- [本地服务](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/electron/services.js)、[路由注册](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/ncmModDef.js)、[Electron 上报覆盖](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/electron/scrobble.js)
- [账号登录页面](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/views/loginAccount.vue)、[只读用户搜索页面](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/views/loginUsername.vue)、[可播放性判定](https://github.com/qier222/YesPlayMusic/blob/5d5fa23b7429c82a9932bbc2c9f6036403c5757b/src/utils/common.js)

### 9.2 锁定的 Node API 发布包

[4.29.7 发布元数据](https://registry.npmjs.org/@neteaseapireborn/api/4.29.7) 与 [4.29.7 发布源码包](https://registry.npmjs.org/@neteaseapireborn/api/-/api-4.29.7.tgz)。本次下载源码只用于阅读，没有安装或运行该包。

- 与 Y `yarn.lock` 对应的 SHA-1：`14fd91504150564ffe7ebe9253b1e3eeb9d041d4`，下载后已比对。
- 传输规则来源：`util/option.js`、`util/request.js`、`util/config.json`、`util/crypto.js`、`server.js`。
- 表格内部路径及参数来源：相应 `module/<路由名下划线形式>.js`，例如 `song_url.js`、`login_qr_key.js`、`playlist_subscribe.js`、`album_detail_dynamic.js`。
- npm [包页面](https://www.npmjs.com/package/%40neteaseapireborn/api?activeTab=versions) 当前提示旧包名已弃用、迁移到 `@neteasecloudmusicapienhanced/api`。本文没有用替代包的新源码推断锁定 `4.29.7` 的行为；未来更新依赖时应重新核对。

### 9.3 Kumone 对应源码

- [接口方法](../../Sources/Coda/Core/API/NeteaseAPI.swift)、[HTTP 与 Cookie](../../Sources/Coda/Core/API/NeteaseClient.swift)、[加密](../../Sources/Coda/Core/API/NeteaseCrypto.swift)
- [评论接口](../../Sources/Coda/Core/API/SongCommentsAPI.swift)、[评论模型](../../Sources/Coda/Core/Models/SongComment.swift)、[歌曲与权限](../../Sources/Coda/Core/Models/Track.swift)、[URL / 歌词 / 云盘模型](../../Sources/Coda/Core/Models/Models.swift)
- [账号存储](../../Sources/Coda/Core/Storage/AccountStore.swift)、[登录页面](../../Sources/Coda/Features/Pages/LoginSheet.swift)、[歌单补齐](../../Sources/Coda/Core/Storage/PlaylistContent.swift)
- [macOS 播放链路](../../Sources/Coda/Core/Player/PlayerService.swift)、[iOS 播放链路](../../Sources/Coda/Core/Player/PlayerServiceIOS.swift)、[上报时序](../../Sources/Coda/Core/Player/PlaybackHistoryReporter.swift)、[音质枚举](../../Sources/Coda/Core/Storage/SettingsManager.swift)
- [下载管理](../../Sources/Coda/Core/Storage/DownloadManager.swift)、[第三方音源](../../Sources/Coda/Core/Player/UnblockService.swift)、[歌词候选选择](../../Sources/Coda/Core/API/AlternativeLyricsAPI.swift)

本文只新增文档，未改变接口实现、默认签名或 UI，也未触发设备构建、安装、启动或自动化测试。
