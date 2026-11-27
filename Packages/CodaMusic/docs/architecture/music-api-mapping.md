# 音乐接口与界面能力对应关系

[返回平台总览](music-platforms.md)

更新：2026-11-10。本文由 `Sources/Coda/Core/API/MusicServiceCatalog.swift` 的能力契约生成，并在 Mac 版 Coda Dev 中逐平台核对过首页、精选、搜索标签、侧栏与云盘页（见 [music-platforms.md](music-platforms.md#mac-实测记录)）。界面用 `MusicProvider.supports(_:)` 决定功能是否出现；网络入口沿用 `NeteaseAPI` 名称兼容旧调用，内部按当前平台路由到 `PlatformMusicAPI`（QQ / 酷狗）或 `QishuiMusicAPI`（汽水）。未接入的功能不得退回其他平台，也不得伪装成等价接口。

汽水的接口审计见 [qishui-netease-api-comparison.md](../archive/qishui-netease-api-comparison.md)，各轮接入与验证见 [qishui-integration.md](../development/qishui-integration.md)；酷狗云端能力见 [kugou-cloud-library.md](../development/kugou-cloud-library.md)。

## 共用界面

四个平台共用 `HomeView`、`ExploreView`、`SearchView`、`IOSLibraryView`、`AccountDetailsView` 和现有歌单、专辑、歌手详情页，继续使用 `FeatureCard`、`HomeToplistPreview`、`HomeCoverShelf`、`CoverCardBody`、`ProfileDetailPage`、`MeloXPlaylistDetailHero`、`MeloXPlaylistPrimaryActions`、`MusicTrackPanel`；登录二维码共用 `LoginQRCodeFrame`。没有平台独立的页面样式，仅切换数据与可见功能。

首页板块由 `MusicProvider.homeDiscoverySlots` 决定：网易云为推荐歌单、热门、地区热歌；QQ 为推荐歌单、热门、新歌、电台；酷狗为推荐歌单、热门、为你推荐、新歌、冷门佳作；汽水为听歌场景（电台）加排行榜。QQ 的“推荐歌曲”来自榜单混排，“推荐歌单”来自官网热门歌单，酷狗的“每日推荐”为榜单/个性化混合，均不标为用户口味推荐。没有对应数据的模块不显示。

## 功能映射

下表每格是该平台的适配入口，「—」表示契约中未接入（界面不显示，直接调用会抛出 `MusicProviderError.unsupported`）。接入数量：网易云 51 / QQ 37 / 酷狗 39 / 汽水 31（共 51 项能力）。

| 功能 | 网易云 | QQ 音乐 | 酷狗 | 汽水 | 语义边界 |
| --- | --- | --- | --- | --- | --- |
| **登录与账号** | | | | | |
| `login` 扫码登录 | `qrKey / qrCheck / loginCellphone` | `QQMusicAuth.fetchQRCode / poll → QQConnectLogin.LoginServer.QQLogin` | `qrKey / pollQR` | `passport/web/get_qrcode / check_qrconnect` |  |
| `profile` 账号资料 | `userAccount` | `QQMusicAuth session profile` | `KugouMusicAuth session profile` | `luna/pc/me` |  |
| `accountSync` 跨设备账号同步 | `SyncService` | — | — | — |  |
| **搜索** | | | | | |
| `searchSongs` 搜索单曲 | `search(type: .songs)` | `searchSongs` | `searchSongs` | `luna/search/track` |  |
| `searchArtists` 搜索歌手 | `search(type: .artists)` | `searchArtists` | `searchArtists` | `luna/search/artist` |  |
| `searchAlbums` 搜索专辑 | `search(type: .albums)` | `searchAlbums` | `searchAlbums` | `luna/search/album` |  |
| `searchPlaylists` 搜索歌单 | `search(type: .playlists)` | `DoSearchForQQMusicLite` | `searchPlaylists / v1/search/special` | `luna/search/playlist` |  |
| `searchSuggestions` 热搜 / 联想 | `searchSuggest / searchDefaultKeyword` | `GetSmartBoxResult / GetHotkeyForQQMusicMobile` | `hotWords / v2/getSearchTip` | `luna/suggest-words / luna/pc/sug` |  |
| **榜单与目录** | | | | | |
| `toplists` 排行榜 | `toplists` | `topLists` | `topLists` | `luna/pc/discover` |  |
| `toplistSongs` 榜单歌曲 | `toplistPreviewTracks / playlistDetail` | `topListSongs` | `rankSongs` | `luna/pc/charts/{id}` |  |
| `playlistDetail` 歌单详情 | `playlistDetail` | `playlistSongs` | `playlistSongs` | `luna/playlist/detail` |  |
| `songDetails` 歌曲详情 | `songDetails` | `catalog / embedded platformSong` | `catalog / embedded platformSong` | `embedded qishui track` | QQ：从已返回的歌曲元数据恢复；酷狗：从已返回的歌曲元数据恢复 |
| `albumDetail` 专辑详情 | `album` | `albumSongs / GetAlbumSongList` | `albumSongs / v1/album_audio/lite` | `luna/pc/albums/{id}` | 酷狗：缺少 album_id 时才按名称匹配唯一专辑 |
| `artistDetail` 歌手详情 | `artist` | `artistHotSongs / GetSingerSongList` | `artistSongs` | `luna/pc/artists/{id}` |  |
| `artistAlbums` 歌手专辑 | `artistAlbums` | `artistAlbums / GetAlbumList` | `searchAlbums → artist-name match` | `luna/pc/artists/{id}/albums` | 酷狗：搜索匹配，非完整唱片目录 |
| `similarArtists` 相似歌手 | `similarArtists` | `GetSimilarSingerList` | — | — |  |
| `topArtists` 热门歌手 | `topArtists` | `SingerList.GetSingerListIndex` | `hotSingers / ocean/v6/singer/list` | — |  |
| **推荐与发现** | | | | | |
| `recommendedPlaylists` 推荐歌单 | `personalizedPlaylists / recommendResource` | `PlaylistSquare.GetRecommendFeed` | `recommendPlaylists` | `luna/discover/mix` |  |
| `recommendedSongs` 推荐歌曲 | `homeDiscovery / homeTopSongs` | `GetRadarSong / get_radio_track` | `everydayRecommend` | — |  |
| `dailySongs` 每日推荐 | `dailyRecommendSongs` | `uniform_get_Dissinfo (202)` | `everydayRecommend` | — |  |
| `personalFM` 私人 FM / 漫游 | `personalFM` | `GetRadarSong` | `personalFM` | — |  |
| `personalizedSuggestions` 相似歌曲推荐 | `similarSongs` | `GetSimilarSongs` | — | — |  |
| `newAlbums` 新碟上架 | `newAlbums` | `get_new_album_info` | `newAlbums / mobile_newalbum_sp` | — | 酷狗：每个地区仅返回少量新碟，不支持翻页 |
| `regionalSongs` 地区热歌 | `homeTopSongs(areaID:)` | — | — | — |  |
| `radarPlaylists` 雷达歌单 | `radarPlaylists` | — | — | — |  |
| `intelligenceList` 心动模式 | `intelligenceList` | — | — | — |  |
| `highQualityPlaylists` 精品歌单 | `highQualityPlaylists` | — | — | — |  |
| `recommendationFeedback` 推荐反馈 | `dislikeRecommendedSong` | — | — | — |  |
| `fmFeedback` FM 反馈 | `fmTrash` | — | — | — |  |
| **播放内容** | | | | | |
| `playback` 整曲播放 | `songURL / preferredSongURL` | `songURLResult (songmid / media_mid)` | `songURL (hash / album_audio_id)` | `luna/pc/track_v2 / luna/h5/seo_track` |  |
| `audioQualities` 音质切换 | `songAudioQualities` | — | `songAudioQualities / songURL(quality:)` | `luna/pc/track_v2 full streams` | 酷狗：提供标准、极高、无损与 Hi-Res 请求，实际可用音质由歌曲及账号决定 |
| `lyrics` 歌词 | `lyric` | `lyric(songmid:)` | `lyric(hash:duration:)` | `luna/h5/seo_track` |  |
| `comments` 评论读取 | `songComments` | `comments(songID:)` | `comments(mixSongID:hash:)` | `luna/pc/comments` |  |
| `commentChanges` 评论写入 | `likeSongComment / sendSongComment / deleteSongComment` | — | — | — |  |
| `playbackReporting` 播放上报 | `PlaybackHistoryReporter / NCBL` | — | `KugouPlaybackReporter / CSCC / upload_songs` | `POST luna/pc/me/recently-played-media` | 酷狗：按真实引擎进度上报；历史回读与排行入账分别确认 |
| **个人音乐库** | | | | | |
| `userPlaylists` 账号歌单 | `userPlaylists` | `userPlaylists` | `userPlaylists` | `luna/pc/me/playlist` | QQ：按来源区分创建与收藏；酷狗：区分创建与收藏的账号歌单 |
| `likedSongs` 喜欢的歌曲 | `likedTrackIDs / likedSongsPlaylist` | `favoriteSongs / qqLikedPlaylistID` | `userPlaylists → playlistSongs` | `luna/pc/me/playlist (type 1) → playlist/detail` |  |
| `recentPlays` 最近播放 | `recentSongs / playRecords` | — | `recentSongPlays / playhistory/v1/get_songs` | `GET luna/pc/me/recently-played-media` |  |
| `collectionAlbums` 收藏专辑 | `likedAlbums / subscribeAlbum` | `favoriteAlbums / AlbumFavWrite` | — | `luna/me/collection/mixed / luna/pc/me/collection/album` |  |
| `collectionArtists` 关注歌手 | `likedArtists / subscribeArtist` | `followedArtists / followArtist` | `v4/follow_list / followservice/v3/(un)follow_singer` | `luna/me/collection/artist / luna/pc/me/collection/artist` |  |
| `playRanking` 个人听歌排行 | `playRecords` | `ListenReportSvr.GetRank` | `listeningRanking / v2/get_list` | — |  |
| `profileStatistics` 听歌统计 | `userDetail / playRecords` | — | — | — |  |
| **写入能力** | | | | | |
| `favoriteChanges` 喜欢 / 取消喜欢 | `likeTrack` | `PlaylistDetailWrite / SongFavRead` | `我喜欢 list: v6/add_song / v4/delete_songs` | `luna/pc/me/collection/media[/delete]` |  |
| `playlistCreation` 创建歌单 | `createPlaylist` | `AddPlaylist / GetPlaylistByUin` | `createPlaylist / v5/add_list` | `POST luna/pc/me/playlist` |  |
| `playlistDeletion` 删除歌单 | `deletePlaylist` | `DelPlaylist` | `deleteKugouPlaylist / v2/delete_list` | `POST luna/pc/me/playlist/delete` |  |
| `playlistTrackAddition` 向自建歌单加歌 | `playlistTracks(add)` | `AddSonglist` | `addSongs / v6/add_song` | `POST luna/pc/me/playlist/media/append` |  |
| `playlistChanges` 移歌（QQ / 酷狗 / 汽水另含改名） | `createPlaylist / deletePlaylist / playlistTracks` | `AddPlaylist / EditPlaylist / DelPlaylist / PlaylistDetailWrite` | `v4/delete_songs / v1/modify_list` | `luna/pc/me/playlist/media/delete / playlist/update` |  |
| `playlistSubscriptions` 收藏歌单 | `subscribePlaylist` | `PlaylistFavWrite` | `createPlaylist(type: 1) / unsubscribePlaylist` | `luna/me/collection/mixed / luna/pc/me/collection/playlist` |  |
| **云盘与下载** | | | | | |
| `cloud` 音乐云盘 | `cloudSongs` | `WeiyunMusicRead.GetMatchAudio` | `cloudLibrary / userCloudURL` | — | 酷狗：列表、容量与播放 |
| `cloudChanges` 云盘上传 / 删除 | `cloudUpload / cloudDelete` | — | `uploadCloudFile / deleteCloudSongs (add_files / del_files)` | — |  |
| `downloads` 离线下载 | `songDownloadResource` | — | `downloadResource / v5/url` | — | 酷狗：仅完整且可校验的曲库音频；不提供云盘下载 |

## 实际 HTTP / musicu 入口

QQ 的 musicu 请求统一访问 `https://u.y.qq.com/cgi-bin/musicu.fcg`，按 module/method 分派；其余入口位于 `https://c.y.qq.com`。

| 功能 | QQ 网络入口 | 酷狗网络入口 / x-router |
| --- | --- | --- |
| 扫码登录 | `ssl.ptlogin2.qq.com/ptqrshow`、`ptqrlogin` → `check_sig` → `graph.qq.com/oauth2.0/authorize` → `QQConnectLogin.LoginServer.QQLogin` | `login-user.kugou.com/v2/qrcode`、`/v2/get_userinfo_qrcode` |
| 单曲搜索 | `/soso/fcgi-bin/search_for_qq_cp` | gateway `/v3/search/song`；`complexsearch.kugou.com` |
| 歌手搜索 | `music.search.SearchCgiService.DoSearchForQQMusicDesktop`，旧接口备用 | gateway `/v1/search/author`；`complexsearch.kugou.com` |
| 专辑搜索 | musicu 搜索 / 旧搜索 t=8 | 当前参考实现从歌曲搜索结果去重提取专辑，不声称独立专辑搜索接口 |
| 账号歌单 | `music.musichallSong.PlayListDataServer.GetUserPlaylist`；创建、收藏旧接口备用 | gateway `/v7/get_all_list`；`cloudlist.service.kugou.com` |
| 喜欢歌曲 | `fcg_musiclist_getmyfav.fcg` / `music.srfDissInfo.DissInfo.CgiGetDiss` | 从账号喜欢歌单读取 |
| 歌单内容 | `/qzone/fcgi-bin/fcg_ucc_getcdinfo_byids_cp.fcg` / `music.playlist.PlayListDataServer.GetPlaylistDetail` | `/v4/get_list_all_file`；`cloudlist.service.kugou.com`，公开歌单有官网备用通道 |
| 榜单列表 | `/v8/fcg-bin/fcg_myqq_toplist.fcg` | gateway `/ocean/v6/rank/list` |
| 榜单歌曲 | `/v8/fcg-bin/fcg_v8_toplist_cp.fcg` | `/openapi/kmr/v2/rank/audio`，官网与旧移动接口补全 |
| 推荐歌单 | `y.qq.com` 首页 / `music.srfDissInfo.RecommendPlaylist.GetRecommendPlaylist` | gateway `/v2/special_recommend`；`specialrec.service.kugou.com` |
| 每日歌曲 / FM | QQ 为按日榜单混排；没有接入私人 FM | `/everyday_song_recommend` / `/v2/personal_recommend` |
| 播放地址 | `vkey.GetVkeyServer.CgiGetVkey`，使用 songmid、media_mid | gateway `/v5/url` 等通道；`trackercdn.kugou.com`，使用 hash、album_audio_id |
| 歌词 | `/lyric/fcgi-bin/fcg_query_lyric_new.fcg` | 参考客户端的歌词搜索与下载通道 |
| 评论读取 | `/base/fcgi-bin/fcg_global_comment_h5.fcg` | `/mcomment/v1/cmtlist`；`mcomment.service.kugou.com` |
| 歌手热门歌曲 / 专辑 | `musichall.song_list_server.GetSingerSongList` / `music.musichallAlbum.AlbumListServer.GetAlbumList` | 作者歌曲接口；专辑按歌手名搜索匹配 |
| 输入联想 | `music.smartboxCgi.SmartBoxCgi.GetSmartBoxResult` | gateway `/v2/getSearchTip`；`searchtip.kugou.com` |
| 歌单搜索 | `DoSearchForQQMusicLite` | gateway `/v1/search/special`；`complexsearch.kugou.com` |
| 歌单移歌 / 改名 | `PlaylistDetailWrite` / `EditPlaylist` | `/v4/delete_songs`（歌单内 `fileid`）；`/v1/modify_list`（AES/RSA 加密云歌单请求，回传原简介 / 标签 / 排序） |
| 关注歌手 | `fcg_order_singer_add / del / getlist` | `/v4/follow_list`（`relationuser.kugou.com`）；`/followservice/v3/follow_singer`、`unfollow_singer`（3116 身份） |
| 喜欢 / 取消喜欢 | `PlaylistDetailWrite / SongFavRead` | 「我喜欢」歌单 `/v6/add_song`、`/v4/delete_songs` |

酷狗 gateway 请求统一为 `https://gateway.kugou.com`，按接口携带 x-router 和签名。上述列出主通道，适配器保留参考仓库的备用通道；不要把备用通道、搜索匹配和原生完整数据当成同一种能力。

### 汽水（Luna）

汽水请求直连 `QishuiMusicAPI`（URLSession），无需本机 Node 服务；登录走 `QishuiPassportSession` 的独立 WebKit 会话，普通数据接口不共享该会话。

| 功能 | 入口 |
| --- | --- |
| 扫码登录 / 资料 | `passport/web/get_qrcode`、`check_qrconnect`（官方 PC 扫码路由 `/light/invoke/scan_login`）；`luna/pc/me` |
| 搜索 | `GET luna/search/track`、`/artist`、`/album`、`/playlist`（Android 客户端参数，结果组游标分页） |
| 推荐 / 榜单 | `luna/discover/mix`（推荐歌单与听歌场景）、`luna/pc/discover`、`luna/pc/charts/{id}` |
| 歌单 / 专辑 / 歌手 | `luna/playlist/detail`、`luna/pc/albums/{id}`、`luna/pc/artists/{id}[/albums]` |
| 账号歌单 / 喜欢 | `luna/pc/me/playlist`（`type=1` 为我喜欢的音乐；`POST` 创建）、`luna/pc/me/collection/media[/delete]` |
| 收藏专辑 / 歌单 / 关注歌手 | `luna/me/collection/mixed`、`luna/pc/me/collection/{album,playlist,artist}` |
| 播放 / 歌词 | `GET luna/pc/track_v2`（Web）→ 失败回退 `luna/h5/seo_track`；登录后可 `POST luna/pc/track_v2` 取 App 流，本地用 `play_auth` 解密，仅接受完整未加密资源 |
| 评论读取 | `GET luna/pc/comments`（`group_type=0`，`sort_type=time` 为最新） |
| 最近播放 | `GET` / `POST luna/pc/me/recently-played-media`（播放进度 ≥ 250 毫秒时上报一次） |

| 歌单删除 / 改名 | `POST /luna/pc/me/playlist/delete`（`playlist_ids`）、`/update`（`playlist_id`、`name`） |
| 加歌 / 移歌 | `POST /luna/pc/me/playlist/media/append`、`/media/delete`（`playlist_id`、`media[{id, type: track}]`） |
| 热搜 / 联想 | `GET /luna/suggest-words/default`（`suggest_words[].keyword`）、`GET /luna/pc/sug`（`sugs[].suggestion`） |

汽水未接入：每日推荐、私人 FM、热门歌手、云盘、下载、评论写入；这些在界面中不出现。

## 模型和隔离

- 对界面统一输出 `Track`、`PlaylistSummary`、`ToplistItem`、`AlbumSummary`、`ArtistSummary` 等原有模型。
- QQ 保留 songmid / media_mid，酷狗保留 hash / album_audio_id / album_id，汽水保留原始 track / playlist ID。元数据不足时明确失败，不拿外部平台 ID 请求网易云。
- 外部对象 ID 按平台、对象类型和原始句柄生成稳定负数；网易云正数 ID 保持原样。
- 账号切换停止当前播放、重置队列和导航。模型请求与缓存按音乐会话隔离，迟到响应不能覆盖新账号的数据。
- `authenticatedAccountID` 仍用于网易云专属同步和权限；通用页面使用统一登录状态。显示用户 ID 时使用平台原始 ID，不显示内部负数键。

接口来源：Beans-Music `f9881318caf774129205c3160510ef0dfa318adc`；具体适配源码及 MIT 声明见 `ThirdPartyNotices/Beans-Music.md`。


## QQ 写操作与歌手页修复

- 创建走 `music.musicasset.PlaylistBaseWrite.AddPlaylist`，使用真实 TID 而不是目录 dirId，保留名称和隐私设置，业务拒绝及无回执时不报告成功。
- 收藏/取消收藏歌单走 `fcg_qm_order_diss.fcg`（optype 1/2）。关注/取消关注歌手走 `fcg_order_singer_add.fcg` / `fcg_order_singer_del.fcg`，关注列表走 `fcg_order_singer_getlist.fcg`。
- 统一层将内部负数 ID 还原为歌单 TID 或歌手 MID，再提交操作；不把内部 ID 发给 QQ。
- 歌手单曲、专辑与专辑内容改为 musicu RPC，保留原始 MID、分页并检查业务响应。专辑优先按 albumType 分类；未知数量不再被当作单曲，平台明确为 EP 时不受歌曲数影响。
- 写操作通过本地模拟服务覆盖成功、拒绝、账号隔离和请求参数；未使用用户账号创建测试歌单。匿名真实服务读取已验证歌手单曲、专辑及专辑内容。

酷狗云歌单写入使用与扫码登录一致的 `3116 / 11440` 客户端身份及签名，并在缺失 dfid 时注册持久设备。创建结果支持 `data.info.listid` 和 `data.info[].listid`，不将账号 userid 当作歌单编号。

酷狗本轮云端历史、排行、只读云盘与下载的详细边界见 [kugou-cloud-library.md](../development/kugou-cloud-library.md)。
