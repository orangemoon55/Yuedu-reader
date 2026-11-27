# 酷狗云端历史、排行、只读云盘与下载

本轮按云端历史 → 云端排行 → 只读云盘 → 下载资源接入。沿用现有最近播放、账号页听歌排行、音乐云盘、已下载和下载任务界面，没有新增页面或播放器模式。本地统计和本地历史不在本轮范围。

## 真实播放上报

酷狗播放现在通过 `KugouPlaybackReporter` 接入 Mac/iOS 两套引擎。确认引擎实际推进后，按会话提交一次历史增量和 CSCC 开始事件；切歌、自然结束或正常退出时提交结束事件及实际播放毫秒数。暂停后继续、拖动进度和切换音质不会重复增加同一会话的历史次数。

时长通过引擎位置与单调时钟共同校验，排除暂停、缓冲及拖动进度跳变；即使标记自然结束也不把整首歌曲时长替换为实际收听时间。未真正发声推进的加载过程不产生上报。当前仅上报有有效曲库 `mixsongid` 的酷狗歌曲，不把私有云盘文件号当作曲库 ID。

`ProviderSong.kugouMixSongID` 专用于账号历史、统计及 CSCC 上报，独立于播放资源句柄 `kugouAlbumAudioId`。搜索结果可能同时提供不同的 `AlbumAudioID` 与 `MixSongID`；补全播放元数据、合并封面以及保存/恢复曲目后均保留这一区别。没有已知 `mixsongid` 的旧曲目不会拿资源 ID 代报。回归检查覆盖两种 ID 不相同的真实返回形状，保证上报仍使用 `MixSongID`。

- 历史写入：`POST gateway.kugou.com/playhistory/v1/upload_songs`，`plat=3`，携带真实开始时间、`mxid` 与一次 `pc=1` 增量。
- 正式播放事件：官方 CSCC `d.kugou.com/v3/qrydid` → `/v2/gen` → `/v2/post`；RSA 建立会话，AES-256-CBC 与两层 zlib 封装事件，按会话缓存握手。
- 上报保持事件顺序并绑定开始时的账号和设备；账号切换后丢弃旧队列，凭证不会换成新账号。iOS 使用有限后台任务；Mac 正常退出最多等候 3 秒。强制终止与无网络时不保证送达。
- 历史、开始事件和结束事件各自最多尝试一次；超时可能已经被服务端记账，因此不会自动重传，也不会靠重复上报催促排行更新。
- HTTP/业务应答仅表示请求被接受。后续最多约 4 分钟只读核对历史时间戳与排行次数增量，分别记录确认状态；未确认的数据不会在本地伪装成云端更新。

2026-10-30 已定位并修复本机 CSCC 断连：Clash 实际连接日志为 `d.kugou.com:80 match RuleSet(Ad) using 广告拦截[REJECT]`。广告规则先于通用国内直连规则匹配；即使诊断时连接官方公网 IP，流量仍经过 TUN，因此此前的公网 IP 断连不能排除分流拦截。已在本机全局覆盖配置最前加入仅针对 `d.kugou.com` 的 `DIRECT` 例外，并为该域名增加真实地址及国内 DNS 例外，保留其他广告规则和原配置备份。重新载入后核实运行中的第一条规则为该直连例外，原先失败的 `/v3/qrydid` 随即返回 HTTP 200、`status=1`、`error_code=0` 和有效设备 ID。客户端没有加入硬编码 IP 或修改用户网络配置的逻辑。

随后在 Mac 通过同一 Swift 上报实现进行真实静音解码/播放，实测有效收听 65,037 毫秒。CSCC 开始、结束事件与历史写入均获成功应答，历史服务端时间戳回读确认；结束后约 52 秒的回读窗口内，云端排行仍未出现次数增量。传输修复已经确认，排行入账仍须独立确认，不能将成功应答视为次数增加。

追加自然结束检查：由 `AVAudioPlayerDelegate.audioPlayerDidFinishPlaying` 确认成功结束，而不是仅以进度达到曲目时长判定结束；本次真实推进 202,076 毫秒，`completed=true`，开始、历史、结束均应答成功，历史回读确认。结束后约四分钟的只读核对结果仍为 `initialCount=2`、`finalCount=2`，故在线检查明确因 `rankingConfirmed=false` 失败。尚不能确认 CSCC 事件已被听歌排行收录，也没有证据把未入账直接归因为服务端延迟。未通过历史累计次数重算替代官方排行，未重复补报已发出的事件。

此前直接打开 `/Applications/Coda Dev.app` 验证播放、暂停、继续、切歌及正常退出时发现的资源 ID / 上报 ID 混用，已通过专用 `kugouMixSongID` 修正；历史写入应答后约 4 秒确认了服务端新时间戳。127 项本地协议、生命周期、ID 分离、历史/排行/云盘及下载回归检查通过；本地检查不替代在线入账验证。

## 接口与语义

| 能力 | 酷狗实际请求 | 展示与限制 |
| --- | --- | --- |
| 最近播放 | `POST gateway.kugou.com/playhistory/v1/get_songs` | 读取 `songs[].info`、`ot`，使用 `bp` 游标续页；去重、按服务端时间排序，最多取 500 首；服务端不足 500 首则显示实际记录 |
| 听歌排行 | `POST listenservice.kugou.com/v2/get_list` | `list_type=0` 最近一周，`1` 全部时间；使用 `listen_count`；服务端当前最多返回 120 首，不代表完整累计播放总次数 |
| 只读云盘 | `POST mcloudservice.kugou.com/v1/get_list` | 分页读取歌曲、`used_size`、`max_size`；AES-CBC 请求/响应与 RSA 凭证信封；兼容空云盘的 `list: ""` |
| 云盘删除 | `POST mcloudservice.kugou.com/v1/del_files` | 与列表相同的 AES/RSA 封装，`uid` 以字符串放入信封；只删除当前账号的 `kv_id` |
| 云盘上传 | `GET gateway/bsstrackercdngz/v1/upload/auth` → `POST bssulbig.kugou.com/v2/multipart/initiate/music` → `{external_host}/v3/multipart/upload`（1MB 分片）→ `/v3/multipart/complete` → `POST mcloudservice/v1/add_files` | 初始化无 `upload_id` 时为秒传；上传前经 gateway（`x-router: kmr.service.kugou.com`）按 MD5 匹配曲库，未命中时用文件标签；无歌手标签时以原文件名命名 |
| 云盘播放 | `GET gateway.kugou.com/bsstrackercdngz/v2/query_musicclound_url` | 使用云盘原始文件名，分别保留 `audio_id` 和 `album_audio_id`；拒绝使用其他账号的云盘引用 |
| 曲库下载 | `GET gateway.kugou.com/v5/url`，`x-router: trackercdn.kugou.com` | 复用完整播放地址；仅接受返回格式、实际音质、时长、文件大小、MD5 均可校验的完整文件；拒绝试听和缺少校验元数据的资源 |

全部请求直达酷狗，不把保存的登录凭证发送给 KA Music 的公共服务。保持现有概念版 token 的客户端签名身份；播放资源解析沿用现有概念版/标准版兼容策略。服务端权限拒绝或下架资源保留失败状态，不伪装为下载成功。

## 页面与账号边界

- `RecentsView` 展示远端历史，`AccountDetailsView` 沿用最近一周/全部时间选择器与播放次数行。
- `playRanking` 与 `profileStatistics` 分开，酷狗不展示网易云等级、累计听歌首数或未经确认的听歌时长。
- `CloudView` 的上传按钮、删除菜单与上传提示由独立 `cloudChanges` 能力控制；酷狗与网易云开放，QQ 不开放（无公开协议）。
- 云盘曲目保留账号、文件标识、原始文件名及两种音频 ID；其稳定 ID 与普通酷狗曲库歌曲分开，随曲目持久化恢复。
- 云盘资源不提供下载入口或多档音质入口；其地址是否始终返回完整原始文件尚未验证。
- 曲库下载复用现有 `DownloadManager`、后台传输、续传、空间预留、MD5/时长验证和账号隔离。离线库允许酷狗稳定负数 ID，来源仍须匹配。
- 切换账号后使用现有请求代际和资源绑定丢弃旧结果，不把酷狗请求回退到网易云。

## 验证

新增请求夹具与离线存储检查覆盖游标重复、歌曲去重、秒/毫秒时间戳、排行周期和远端次数、云盘容量与音频 ID、云盘所有者、跨来源 ID、持久化恢复、试听拒绝、完整下载描述及离线账号隔离。

只读网络集成检查可在 Mac 上显式运行：

```sh
CODA_KUGOU_LIBRARY_LIVE_AUDIT=1 swift test --filter KugouLibraryLiveTests
```

该检查通过系统钥匙串读取当前酷狗账号，只查询历史/排行/云盘，并下载一个临时音频文件验证；不启动客户端播放、不写平台数据，也不运行 iPhone/iPad 自动化。不会输出 token、账号 ID 或签名 URL。

真实播放写入检查与上述只读检查分开：

```sh
CODA_KUGOU_REPORT_LIVE_AUDIT=1 swift test --filter KugouPlaybackReportLiveTests
```

该检查会在 Mac 静音播放 65 秒真实音频，并提交一次历史及开始/结束事件，核对服务端回读；它会改变该账号的真实播放记录。若 CSCC 不可达或回读仍未确认，检查保留失败，不用“本地测试通过”替代线上成功。

需要核对自然结束时，可额外指定 `CODA_KUGOU_REPORT_FULL_TRACK=1`。该模式真实播放完整音频，保留引擎实测进度，不用总时长补造收听时间；结束后最多约四分钟只读核对历史和排行，并输出上报应答、前后次数与实际毫秒数。未见增量仍判为未通过，不重传事件。

当前账号云盘为空，已验证空云盘和容量读取；非空歌曲列表、播放地址参数与所有者检查由夹具覆盖，非空真实云盘播放仍需实际歌曲验证。

## 协议参考

- [KA Music](https://github.com/1970905901/kgka_Music_hl)：客户端功能与接口语义对照。
- [KuGouMusicApi user_history](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_history.js)、[user_listen](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_listen.js)。
- [user_cloud](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_cloud.js)、[user_cloud_url](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_cloud_url.js)、[song_url](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/song_url.js)、[crypto](https://github.com/MakcRe/KuGouMusicApi/blob/main/util/crypto.js)。
- [playhistory_upload](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/playhistory_upload.js)、[user_listen_report](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_listen_report.js)：历史与正式播放事件协议；二者的应答及服务端入账分别验证。

- [user_cloud_upload](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_cloud_upload.js)、[user_cloud_del](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_cloud_del.js)、[user_cloud_match](https://github.com/MakcRe/KuGouMusicApi/blob/main/module/user_cloud_match.js)：云盘上传、删除与曲库匹配。

仅使用端点、字段和协议参数作为参考，未捆绑 JavaScript 运行时或上游源文件。

## 云盘上传/删除实测

2026-11-10 用无标签的 24MB FLAC 实测：上传后出现在云盘列表，云盘播放地址返回完整原文件（24,341,111 字节，解码 235 秒，与本地一致），删除后列表回读确认移除；再次上传同一文件走秒传。该文件不在曲库中，匹配返回空结果。酷狗服务端按“歌手 - 歌名”解析无标签文件名，文件名顺序相反时歌手显示会不准确。

写入检查会改动账号云盘，需显式运行（优先读取开发版登录）：

```sh
CODA_KUGOU_CLOUD_LIVE_AUDIT=1 CODA_KUGOU_CLOUD_FILE=/path/to/song.flac swift test --filter KugouCloudChangesLiveTests
```

若文件已在云盘中，检查拒绝运行，避免删除原有副本。
