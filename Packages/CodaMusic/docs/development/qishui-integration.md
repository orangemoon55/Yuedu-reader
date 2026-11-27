# 汽水音乐原生接入

## 歌单编辑与搜索联想（2026-11-10）

自建歌单可删除、改名、加歌和移歌，请求均走现有签名的 PC 写接口：`POST /luna/pc/me/playlist/delete`（`playlist_ids`）、`/update`（`playlist_id`、`name`）、`/media/append` 与 `/media/delete`（`playlist_id`、`media[{id, type: track}]`）。成功回包可能只有 `status_info` 而没有 `status_code`，按此判断成功。只对自己创建、非「我喜欢」、非电台/榜单的歌单开放。

搜索页的热搜词使用 `GET /luna/suggest-words/default`，输入联想使用 `GET /luna/pc/sug`（`sug_scene=main`，每次新的 `sug_search_id`）。两者回包形状随客户端版本变化，解析同时接受字符串和常见字段名。

协议参考 [libresoda playlist_edit.rs / search.rs](https://github.com/sodahub-org/libresoda/tree/HEAD/src/soda)。请求体与解析用单元测试覆盖；写操作未对用户账号实际执行，需真实账号验收。上游另有歌单排序、敏感词检查、删除最近播放、听歌时长（`music_wall`）、播放计数上报（`/luna/pc/action`）与下载，本轮未接入。

## 创建歌单（2026-11-08）

「我的歌单」使用签名的 `POST /luna/pc/me/playlist` 创建空歌单。服务端返回歌单 ID 后立即显示，待账号列表同步后按原始 ID 去重。请求格式和名称长度参考 [libresoda 创建接口](https://github.com/sodahub-org/libresoda/blob/0c6f4df10f214dee94eeea5b204804a3fe98e900/src/soda/playlist_edit.rs)。

## 最近播放（2026-11-07）

「最近播放」读取汽水账号的 `GET /luna/pc/me/recently-played-media`，沿用服务端顺序，以原始歌曲 ID 去重。登录后，播放器检测到至少 250 毫秒的实际播放进度时，通过同一路径的 `POST` 提交一次歌曲记录。请求直接发往汽水，成功应答后刷新历史缓存。该写入接口只用于最近播放。协议见 [libresoda 播放历史接口](https://github.com/sodahub-org/libresoda/blob/5edd2ff3b825f0a16b1e281204822ee06842df9c/src/soda/playback.rs)。

账号会话的只读检查验证了分页、歌曲数据和服务端播放时间。写入请求格式及业务错误处理用模拟响应检查，真实播放后的云端回读待验收。

## 歌曲红心与评论（2026-11-06）

歌曲红心使用签名的 `POST /luna/pc/me/collection/media` 和 `/delete`，沿用现有汽水签名服务。账号歌单中以 `type=1` 识别「我喜欢的音乐」，加载其中的歌曲以同步红心；收藏请求失败时恢复原状态。请求格式参考 [libresoda 收藏接口](https://github.com/sodahub-org/libresoda/blob/56577711af122a6cf452cd69963f86ea7eb49256/src/soda/collection.rs)。

评论改用 `GET /luna/pc/comments`，以数字 `group_type=0` 指定歌曲，最新排序使用 `sort_type=time`。匿名实测验证了热门、最新、翻页和空列表。收藏及取消收藏的签名请求和错误处理已用模拟响应验证，未对用户账号写入收藏。

## SodaM 协议更新（2026-11-06）

搜索改用 `GET /luna/search/track` 和 `GET /luna/search/playlist`，使用 Android 客户端参数和结果组返回的游标。歌词和播放先走 Web `GET /luna/pc/track_v2`，请求失败时回退到 SEO 接口。扫码继续使用已经验收的 WebKit Passport 会话。账号歌单支持按上游游标翻页。

当 Web 返回试听或音质较低，且已经登录时，客户端可以用 `POST /luna/pc/track_v2` 获取 App 播放流。签名器接收 URL、方法、原始 JSON、请求头及时间戳，返回逐请求的 `X-Helios` 和 `X-Medusa`。Coda 使用 SodaM 内置的默认 HTTP 签名服务，签名请求可能包含汽水登录 Cookie。

播放器按流返回的实际时长确认整曲，从 CDN 下载加密 MP4 后，以响应中的 `play_auth` 本地解密，再把文件交给现有播放器。受限曲目的试听片段仍会给出错误提示。协议版本和 Swift 移植的授权见 [第三方声明](../../ThirdPartyNotices/Qishui-API.md)。

## 首期接入记录

日期：2026-10-31。接入前完整审计见 [qishui-netease-api-comparison.md](../archive/qishui-netease-api-comparison.md)。开始前已将工作区完整保存为 Git 提交 `a3e1246`。

## 当前登录实现（后续签名修正）

最新修正与用户指定仓库的逐项对照见 [mineradio-qishui-login-comparison.md](../archive/mineradio-qishui-login-comparison.md)。在仅有 bdms 签名仍返回错误 7 后，本轮补齐了缺失的 msToken、account_sdk_source_info、设备身份持久化、2046 官方验证界面及同会话重发；43 项检查通过。2026-10-31 用户已在汽水音乐 App 确认登录；Mac 端观察到 scanned → confirmed 并收到会话，账号列表显示汽水会员及“登录状态：有效”，真实扫码登录和资料校验已验收。重启恢复、真实 2046 挑战仍未单独验收。

用户连续反馈扫码后的 1049 与访问频繁（7），此前直接 HTTP 请求的参数/等待修正仍不足以完成登录。现在 Passport 创建和轮询改为 `QishuiPassportSession`：每个二维码独立的非持久化 WebKit 会话，从官方 CDN 加载 `bdms.js 1.0.0.41`，由官方组件为同源 XHR 生成 `a_bogus`，并从同一浏览器 Cookie jar 收集包括 HttpOnly 在内的会话 Cookie。

- 不启动 Chrome、Node.js 或本地桥接服务器，不关闭 CORS、TLS 或其他浏览器保护；不复制第三方签名算法或伪造浏览器指纹。
- 请求限制为 `https://api.qishui.com/passport/web/`；组件未加载或请求未带组件生成的签名时停止，不回退无签名请求。
- 刷新/取消会废弃旧二维码、关闭该 WebKit 会话；拿到登录结果后仍先验证账号资料，再安全保存会话。二维码框和整个产品样式保持原样。
- 官方组件在每次登录时从官方 CDN 加载，加载失败会显示明确错误。后续已增加 2046 的官方验证组件承载窗口，用户完成后才重发；真实挑战仍需验收。

真实匿名验证已确认：官方 SDK 在系统 WebKit 初始化成功，创建和轮询均观测到 44 字符签名，服务端返回有效二维码及 waiting 状态。检查只记录签名长度，不输出签名、token、Cookie、SDK 状态或完整请求地址。这一轮只证明签名传输已接入；后续补齐上下文后的真实扫码登录结果见本节首段，会话重启恢复仍未单独验收。

本轮 QishuiMusicTests + AccountIsolationTests 共 25 项通过，含真实已签名取码/轮询、取消后废弃二维码、拒绝向其他域名发送 Passport 请求，以及关闭的安全会话不得继续请求。

下文保留之前各轮协议核对和错误处理记录；其中直接 HTTP 登录、未包含浏览器签名器的说明仅代表当轮历史状态。普通音乐数据接口仍使用原生 URLSession，不共享登录 WebKit 会话。

## 实现范围

采用 Swift URLSession 直连汽水上游，协议参考 qishui-api `e409c10fe7441a10d370da7da61d62bbc1e5126c`。无需在用户设备启动 Node.js 服务，也不向第三方中转用户 sessionid。

### 扫码网页 404 修正（2026-10-31）

用户反馈抖音扫码后网页 404，已实际确认 Passport 返回的旧二维码指向 `bff-pc.qishui.com/ucenter_web/app/sdk-next`，该页面当前 HTTP 404；创建二维码和未扫码轮询仍可正常返回，因此原先仅验证二维码图片和轮询不足以覆盖手机端链路。

改为从 `qrcode_index_url` 提取独立的扫码 token，构建官方 PC 扫码路由 `/light/invoke/scan_login`，使用原有 CoreImage 与二维码框渲染。提示更正为使用已登录的**汽水音乐 App**扫码。轮询继续使用原始 Passport token，二者不可混用。状态支持 confirmed/3/success，确认但尚未发会话 Cookie 时继续等待，不误报登录成功。

协议交叉参考：[扫码协议记录](https://github.com/zihe114514/qishui-reverse-report/blob/ef74501407ef91bad146f0398be16a80538e0f0d/docs/04-login.md)。只使用接口事实和自行编写的 Swift 实现；未移植其他客户端的浏览器签名或验证代码。普通浏览器访问新路由会进入官方扫码错误说明页，不能把 HTTP 200 当作手机 App 确认登录成功。此轮手机确认及二次验证尚待真实账号验收；后续扫码成功结果见本文首段，真实二次验证仍待验收。

本次 13 项汽水定向检查通过，新增扫码 token 与轮询 token 分离、URL 特殊字符保留、非官方域名拒绝，以及确认但未发会话时保持等待的检查。真实匿名检查已由“只取二维码图片”延伸为创建后实际调用轮询，确认新会话返回 waiting；没有替用户扫码或确认。

### 扫码后 1049 的轮询处理修正（2026-10-31）

用户随后反馈 Mac 弹窗显示 1049。原实现由通用响应校验直接抛错，轮询状态机没有机会保留已扫码状态，也丢弃了业务错误响应里可能更新的 Cookie。1049 单凭数字不能证明是临时状态或具体哪项客户端校验失败。

现将 Passport 的业务状态交给登录状态机处理：已观察到扫码时，1049 最多保留会话等待 3 次，每次冷却 5 秒；未扫码即拒绝、持续拒绝或其他业务错误明确停止，不靠循环隐藏失败。错误提示保留上游 description/status_msg，但隐藏 token、Cookie 和链接。限流 7 同样采用有上限的冷却。登录成功仍要求确认状态、有效会话与资料校验，不将 1049 当成功。

同轮补齐每次二维码流程独立且在创建/轮询中一致的设备/安装标识、Passport 公共参数、CSRF 请求头、trace 和表单 MD5 摘要，不再使用参考仓库的固定 iid。会话保存支持 sessionid_ss 以及必要的配套 Cookie，限定允许字段、存入钥匙串；校验、会员读取和后续请求延续同一组会话。

验证：QishuiMusicTests + AccountIsolationTests 共 23 项通过，包含临时 1049 后确认、持续 1049 的次数上限与敏感字段过滤、未扫码拒绝、限流冷却、Cookie 轮换、sessionid_ss + sid_guard 的资料校验，以及原生匿名取码/未扫码轮询。真实用户确认登录未完成验收；这些修正不是浏览器签名器或二次验证组件，不能据此宣称平台安全校验已通过。

状态处理交叉参考：[汽水插件 1049 记录](https://github.com/Px-asen/Twilight-Echo-plugins/blob/a66b84e8e8e16bc516cfef9cbcc8422b2320887d/plugins/qishui-provider/README.md)。使用协议事实和独立 Swift 实现，没有复制其 Electron 安全桥接代码。

- 设置的账号管理增加汽水音乐；复用 `PlatformLoginSheet / LoginQRCodeFrame`，提示用汽水音乐 App 扫码。二维码创建和轮询保留流程 Cookie；confirmed 必须带有效 sessionid 并通过资料校验才保存。支持在既有凭证导入区导入 sessionid 后校验账号。
- 账号保存、恢复、验证、移除和会员状态进入现有框架；凭证保存在钥匙串，网络使用独立临时会话。缺失会员字段保持未知，不套用网易云会员等级。
- 推荐歌单、歌单详情、账号歌单、歌曲和歌单搜索、歌词及只读评论转换成现有模型。歌曲和歌单保留字符串原始 ID；内部稳定负数 ID 与其他平台隔离。账号歌单统一显示“我的歌单”，不伪造创建者或收藏权限。
- 搜索的综合加载和分类选择按能力过滤；Feed/搜索的原始游标由数据层维护，不以去除视频后的歌曲数量推算下一页。歌单详情读取到真实结束，防重复页和循环游标。
- （首期状态，已过时）首期首页只提供推荐歌单，精选只提供全部/推荐歌单，并隐藏每日推荐、私人 FM、排行榜、歌手/专辑分类、收藏写入、云盘、下载和音质切换。之后已陆续接入排行榜、听歌场景、歌手/专辑、收藏写入、音质与歌单编辑；当前能力以 [music-platforms.md](../architecture/music-platforms.md) 为准。
- 沿用当前所有页面、卡片、歌曲列表、二维码框和唯一播放器；没有增加汽水主题或播放器界面模式。

## 首期播放边界（历史记录）

当前资源解析读取 H5 `track_player.video_model`，校验完整时长、可播放范围起点、资源到期和允许的 HTTPS 域名。只尝试完整、未加密资源；拒绝试听片段和带 spade 的加密资源，并显示具体错误。不读取脱敏的 `/media/player` 摘要来伪造播放成功；不在失败时自动使用其他平台音源。

本轮没有移植解密器、付费权限处理、App 播放上下文或 PC 签名生成器。未验证登录账号能取得完整资源，也未宣称完整播放已经通过真实账号验收。后续若上游只返回试听或加密资源，需要补充协议验证后继续实施。

## 验证记录

桌面 `swift test` 定向执行 QishuiMusicTests、MusicServiceCatalogTests、SearchRefreshTests、AccountIsolationTests，共 30 项通过（含 1 项显式开启的匿名真实服务读取）。覆盖扫码 Cookie、确认但无 session、业务拒绝、长 ID 持久化、歌单分页和去重、搜索原始游标、短歌词、会员未知态、试听/加密/不受信任资源拒绝、平台隔离及共享搜索/账号回归。

原生匿名真实读取结果：

| 能力 | 结果 |
| --- | --- |
| 推荐歌单 | 返回 5 个歌单 |
| 歌单 `7096700219496368135`，type=3 | 分页读到 22 首歌曲 |
| 歌词 | H5 返回 LRC |
| 登录二维码 | 返回 data:image 二维码；未替用户扫码或确认登录 |
| 曲目 `7079108541549643812` | 元数据全长 297240 ms；匿名音频约 30 秒，正确拒绝作为完整资源播放 |
| 匿名 PC 搜索 | 上游返回业务码 `1000004`；正确显示请求被拒绝，未伪装成空列表；登录后可用性未验证 |
| 账号资料、会员 | 真实扫码后已验证，Mac 账号列表显示有效及汽水会员 |
| 我的歌单、完整播放 | 请求层和模拟响应已覆盖，真实账号功能待验证 |
| 评论读取 | 已适配，尚未执行真实评论接口验收 |

部署按用户后续指示先限定为 Mac 开发版，保留开发版标识、证书签名和用户数据；未向 iPhone、iPad、模拟器部署，未启动真机自动化。

Mac 已执行 `bash Scripts/deploy-mac-dev.sh debug`，覆盖安装至 `/Applications/Coda Dev.app`。脚本确认安装副本标识为 `wow.caicai.coda.dev`，使用现有 Apple Development 证书签名，并对去除签名后的可执行文件与本次构建作一致性校验；安装后深度严格签名校验通过。应用未运行，未额外启动。

## 使用入口

Mac 设置 → 账号管理 → 登录汽水音乐账号，刷新二维码后使用已登录的汽水音乐 App 扫码。推荐歌单可匿名浏览；账号列表和权限以真实会话返回为准。未提供的编辑操作隐藏；搜索拒绝、试听和加密资源均保留明确错误。
