# Mineradio 汽水登录实现对照

核对日期：2026-10-31。来源：[XxHuberrr/Mineradio-paused](https://github.com/XxHuberrr/Mineradio-paused)，提交 `d43de565acabfdc1a9c9820a27e81a98ccbebcef`。

## 核心结论

它实现的是完整的浏览器会话流程，不是给 HTTP 请求加一个签名字段。Kumone 前一轮虽然接入 bdms 并产生 44 字符 `a_bogus`，但实际检查发现 `msToken` 长度仍为 0、浏览器信息字段缺失；这两个检查没有纳入此前成功条件，因此“取码和未扫码轮询通过”不能证明手机确认后的认证能够成功。

本次补齐会话上下文、设备身份持久化和二次验证分支。仍保留 Swift/WebKit 和现有界面，不移植 Mineradio 的播放器、主题、Electron 或本地服务器。

## 登录流程对照

| 环节 | Mineradio 源码行为 | Kumone 对应修正 |
| --- | --- | --- |
| 设备身份 | `ensureIdentity` 持久化 deviceId、installId、verifyPortraitId | 同样持久化这三个非账号设备标识，取码和轮询使用同一组值 |
| 安全会话 | Electron 独立 partition，隐藏 BrowserWindow 加载种子页和安全页 | 每次登录使用独立的非持久化 WebKit；刷新/取消后旧上下文失效 |
| msToken | 先读 xmsty/xmst，不合要求时生成 88 字节安全随机种子，编码为 118 字符加 ==；SDK 加载前写入两个存储键 | 在 SDK 前初始化同格式种子，整条流程使用同一个值；校验最终签名 URL 中的值与上下文一致 |
| 浏览器信息 | 从 navigator、存储、WebGL、性能等生成 browserInfo；JSON UTF-8 字节 XOR 5 后转 hex，放入 account_sdk_source_info | 实际采集 WebKit 能力，按协议编码并加入请求；PC 协议的逻辑宿主字段与参考实现对齐 |
| SDK 初始化 | sdk-glue 调用 bdms.init，等待官方 bdms 就绪 | 直接加载同版本官方 bdms，等待 init；不把 sdk-glue 的监控字段当成登录凭据 |
| 请求一致性 | 相同设备身份、msToken、浏览器信息、Cookie；Passport trace 和 POST MD5 摘要 | 保留对应上下文和必要请求头，不退回无签名请求 |
| 成功前检查 | 要求 a_bogus 长度 44，并要求签名 URL 的 msToken 等于当前会话 token | 额外要求 msToken 长度 120、浏览器信息非空及 token 一致，不只检查签名长度 |
| 二维码 | 从 qrcode_index_url 提取扫码 token，生成 light/invoke/scan_login PC 地址 | 保留此路由；扫码 token 和轮询 token 分开使用 |
| 2046 | 合并业务决策，必要时 pack_verify_ways_data，展示官方 ucWebSecondVerify；完成后携带 biz_params + isResend=true 再轮询 | 复用同一个 WebKit 展示官方验证组件；用户自行完成；取消不重发，完成才重发，保护原 token 和设备字段 |
| 会话收集 | 从整个 Electron Cookie jar 收集 qishui.com Cookie，合并 session_cookie | 同一 WebKit Cookie jar 收集包括 HttpOnly 在内的会话；通过资料校验后存钥匙串 |
| 旧请求隔离 | qrGeneration 防止旧码、旧账号 Cookie 确认新码；新码未确认时不能复用旧 Cookie 宣称成功 | 增加同等代际检查，验证、重发、资料回读后均检查当前二维码仍有效 |

## 二次验证与样式

只增加承载官方验证组件的原生窗口，标题、间距和取消按钮复用现有 Theme。验证内容由官方组件显示，没有新增汽水播放器、卡片或主题。验证码、滑块或其他安全步骤由用户完成，代理不代为操作。

参考实现使用 React/ReactDOM 17.0.2 和 ucWebSecondVerify。Kumone 按需加载相同 React 版本，使用固定版本 URL 和 SRI；验证脚本地址限制为官方域名，浏览器 CORS/TLS 保持开启。参考仓库的 `webSecurity: false` 和 CORS 修改没有照搬。

## 验证与边界

- QishuiMusicTests、AccountIsolationTests、SearchRefreshTests、MusicServiceCatalogTests 共 43 项通过。
- 原生真实取码与未扫码轮询确认：签名 44 字符、msToken 120 字符、浏览器信息存在、msToken 与会话一致，服务端返回有效二维码和 waiting。
- 模拟响应覆盖 2046 普通/verify_center 分支、原 token 保护、同 Cookie 会话重发、取消验证、旧码迟到响应、临时/持续 1049、限流和敏感字段过滤。
- 2026-10-31 用户使用汽水音乐 App 扫码并确认后，诊断状态依次为 new → scanned → confirmed，确认响应包含会话；Mac 账号列表显示汽水账号、汽水会员及“登录状态：有效”。真实扫码、手机确认和资料校验已验收。
- 官方验证组件的 JavaScript 通过语法检查；本次没有触发真实 2046 挑战，重启后的账号恢复也尚未单独验收。
- 参考仓库自己的 `qishui-passport-live-smoke.js` 也只验证创建和首次未扫码轮询；它不能充当“今天所有账号都能成功登录”的证据。
- Electron/Chromium 与原生 WebKit 的浏览器环境仍有差异。本次补齐的是明确缺失的协议上下文及分支，不宣称已证明错误 7 的唯一根因。

本地诊断仅记录阶段、允许列表内的状态、业务码、签名/token 长度及字段存在性；不保存 token、Cookie 值、签名、完整 URL、账号身份或浏览器信息原文。诊断文件位于应用支持目录的 `Diagnostics/qishui-login.json`。

## 源码证据

- [qishui-auth-v6.js](https://github.com/XxHuberrr/Mineradio-paused/blob/d43de565acabfdc1a9c9820a27e81a98ccbebcef/qishui-auth-v6.js)：种子初始化、commonParams、签名与 token 一致性、2046、Cookie 收集。
- [security_host.html](https://github.com/XxHuberrr/Mineradio-paused/blob/d43de565acabfdc1a9c9820a27e81a98ccbebcef/qishui-auth-v6/security_host.html)：浏览器信息编码、官方验证组件参数及回调。
- [qishui-qr-login.js](https://github.com/XxHuberrr/Mineradio-paused/blob/d43de565acabfdc1a9c9820a27e81a98ccbebcef/qishui-qr-login.js)：代际和确认状态隔离。
- [qishui-passport-qr-login.test.js](https://github.com/XxHuberrr/Mineradio-paused/blob/d43de565acabfdc1a9c9820a27e81a98ccbebcef/tests/qishui-passport-qr-login.test.js)、[live smoke](https://github.com/XxHuberrr/Mineradio-paused/blob/d43de565acabfdc1a9c9820a27e81a98ccbebcef/tests/qishui-passport-live-smoke.js)：参考仓库实际测试范围。

参考仓库为 GPL-3.0。这里记录协议与流程事实，使用独立 Swift/WebKit 实现，没有复制其 Electron 文件、签名器、sdk-glue、打包 SDK 或视觉资产。
