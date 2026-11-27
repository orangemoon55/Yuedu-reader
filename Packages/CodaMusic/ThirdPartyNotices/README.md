# 开源仓库与第三方参考索引

本目录汇总 Coda 使用或参考的全部开源仓库。各条目的详细修改说明、参考版本与许可证全文见对应的说明文件。新增引用时，请同步更新本索引和对应说明。

## 1. 派生来源

| 仓库 | 许可证 | 说明 |
| --- | --- | --- |
| [missuo/kumone](https://github.com/missuo/kumone) | LGPL-3.0（[Kumone-LGPL-3.0.txt](Kumone-LGPL-3.0.txt)） | Coda 的上游项目。保留原作者版权；派生前的版本历史见[上游变更记录](https://github.com/missuo/kumone/blob/main/CHANGELOG.md)。 |

## 2. 集成或改编的代码与资源

这些仓库的代码、算法或素材已进入本仓库，分发时需遵守其许可证。

| 仓库 | 版本 | 许可证 | 在 Coda 中的位置 | 说明文件 |
| --- | --- | --- | --- | --- |
| [dimitris-c/AudioStreaming](https://github.com/dimitris-c/AudioStreaming) | 1.2.8 `4d9bb98` | MIT | `Sources/Coda/Core/Player/Streaming`（iOS 播放） | [AudioStreaming.md](AudioStreaming.md) |
| [youshen2/MeloX](https://github.com/youshen2/MeloX) | `a41ea0e`、`09713ed` | GPL-3.0-only | `Core/Player/Lyrics`、`LyricsCursor`、`DesktopLyricScrollTransition`、歌词排版与网易云歌词请求 | [MeloX.md](MeloX.md) |
| [XIaodou0416/Beans-Music](https://github.com/XIaodou0416/Beans-Music) | `f988131` | MIT | QQ 音乐 / 酷狗 API 与登录（`Core/API/Providers`） | [Beans-Music.md](Beans-Music.md) |
| [WXRIW/Lyricify-Lyrics-Helper](https://github.com/WXRIW/Lyricify-Lyrics-Helper) | `77e7acb` | Apache-2.0 | `AlternativeLyricsAPI.swift`（QQ / 酷狗 / LRCLIB 歌词、KRC 解码） | [Lyricify-Lyrics-Helper.md](Lyricify-Lyrics-Helper.md) |
| [guowenye/qishui-api](https://github.com/guowenye/qishui-api) | `e409c10` | MIT | `QishuiMusicAPI.swift` | [Qishui-API.md](Qishui-API.md) |
| [sodahub-org/libresoda](https://github.com/sodahub-org/libresoda) | `5edd2ff` | AGPL-3.0-or-later | `QishuiPlayback.swift`、`QishuiAudio.swift` | [Qishui-API.md](Qishui-API.md)、[许可证全文](libresoda-AGPL-3.0.txt) |
| [sodahub-org/sodam](https://github.com/sodahub-org/sodam) | `f43a22b`、`a378433` | 见上游 NOTICE | 汽水播放协议；`Features/Home/QishuiModeIcons` 图标 | [Qishui-API.md](Qishui-API.md) |
| [guohuiyuan/music-lib](https://github.com/guohuiyuan/music-lib) | — | 见 libresoda NOTICE | libresoda 的原始 Rust 实现 | [Qishui-API.md](Qishui-API.md) |
| [yakult-green-tea/qq-music-api](https://github.com/yakult-green-tea/qq-music-api) | `d27a9b5` | MIT | QQ 音乐登录态收藏传输与歌曲 / 专辑 / 歌单操作 | [QQMusicProtocolReferences.md](QQMusicProtocolReferences.md) |
| [jixunmoe/qmweb-sign](https://github.com/jixunmoe/qmweb-sign) | `15305a3` | MIT | QQ 音乐网页请求签名与加密 | [QQMusicProtocolReferences.md](QQMusicProtocolReferences.md) |
| [NeteaseCloudMusicApiEnhanced/api-enhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced) | `984cc02` | MIT | `NeteasePlaybackLog.swift`（NCBL 听歌记录上报） | [NeteasePlaybackLog.md](NeteasePlaybackLog.md) |
| [lucide-icons/lucide](https://github.com/lucide-icons/lucide) | — | ISC | 播放器、歌词、收藏等按钮图标 | [Lucide.md](Lucide.md) |

## 3. 依赖包与运行时下载资源

| 仓库 | 版本 | 许可证 | 用途 |
| --- | --- | --- | --- |
| [sparkle-project/Sparkle](https://github.com/sparkle-project/Sparkle) | 2.9.x | MIT 类（见上游 LICENSE） | macOS 自动更新（Swift Package 依赖） |
| 字节跳动浏览器安全 SDK（`bdms.js`） | — | 各自条款 | 汽水音乐登录页运行时加载，未复制进仓库 |
| [facebook/react](https://github.com/facebook/react) React / ReactDOM | 17.0.2 UMD 生产版 | MIT（[React-LICENSE](React-LICENSE)） | 原样内置于 `Core/API/QishuiVerificationAssets`，供汽水二次验证组件使用 |

## 4. 仅参考接口协议（未复制源码）

以下仓库仅用于核对接口名、请求字段与返回结构，Swift 实现为独立编写。

| 仓库 | 许可证 | 参考内容 | 记录位置 |
| --- | --- | --- | --- |
| [MakcRe/KuGouMusicApi](https://github.com/MakcRe/KuGouMusicApi) | — | 酷狗歌单、云盘、听歌历史、会员接口与加密参数 | [KugouPlaylistProtocolReferences.md](KugouPlaylistProtocolReferences.md)、`docs/development/kugou-cloud-library.md` |
| [moli-lihuashi/Mineradio-Vision](https://github.com/moli-lihuashi/Mineradio-Vision) | — | 酷狗云盘客户端身份与设备注册 | [KugouPlaylistProtocolReferences.md](KugouPlaylistProtocolReferences.md) |
| [1970905901/kgka_Music_hl](https://github.com/1970905901/kgka_Music_hl) | — | 酷狗客户端功能与接口语义 | `docs/development/kugou-cloud-library.md` |
| [jsososo/QQMusicApi](https://github.com/jsososo/QQMusicApi) | GPL-3.0 | QQ 音乐歌单、歌手关注、专辑接口 | [QQMusicProtocolReferences.md](QQMusicProtocolReferences.md) |
| [Yyyangshenghao/simple-music](https://github.com/Yyyangshenghao/simple-music) | GPL-3.0 | 同上 | [QQMusicProtocolReferences.md](QQMusicProtocolReferences.md) |
| [GitHub-ZC/wp_MusicApi](https://github.com/GitHub-ZC/wp_MusicApi) | — | QQ 音乐搜索、播放地址与歌词请求 | [QQMusicProtocolReferences.md](QQMusicProtocolReferences.md) |
| [MeoProject/lx-music-api-server](https://github.com/MeoProject/lx-music-api-server) | — | QQ 音乐会员身份字段 | `docs/architecture/music-platforms.md` |
| [chongya369/qqmusic-api-py](https://github.com/chongya369/qqmusic-api-py) | — | QQ 音乐 identity 返回结构 | `docs/architecture/music-platforms.md` |
| [XxHuberrr/Mineradio-paused](https://github.com/XxHuberrr/Mineradio-paused) | GPL-3.0 | 汽水 Passport 会话与二次验证流程 | [Qishui-API.md](Qishui-API.md) |
| [zihe114514/qishui-reverse-report](https://github.com/zihe114514/qishui-reverse-report) | — | 汽水扫码登录协议 | `docs/development/qishui-integration.md` |
| [Px-asen/Twilight-Echo-plugins](https://github.com/Px-asen/Twilight-Echo-plugins) | — | 汽水登录 1049 状态处理 | `docs/development/qishui-integration.md` |
| [jayfunc/BetterLyrics](https://github.com/jayfunc/BetterLyrics) | — | 流光背景与歌词高亮的视觉参考 | [BetterLyrics.md](BetterLyrics.md) |
| [FFmpeg/FFmpeg](https://github.com/FFmpeg/FFmpeg) | LGPL-2.1+ | `qt-faststart.c` 的 MP4 重排思路（AudioStreaming 上游注释） | `Streaming/.../Mp4Restructure.swift` |

## 5. 历史调研资料

`docs/archive` 中的调研文档还提到以下仓库，仅用于方案对比，未进入代码：

- 网易云接口对照：[qier222/YesPlayMusic](https://github.com/qier222/YesPlayMusic)、[Lincb522/NeteaseCloudMusicAPI-Swift](https://github.com/Lincb522/NeteaseCloudMusicAPI-Swift)
- AutoMix 混音：[walkywalker/automix](https://github.com/walkywalker/automix)、[sony/fxnorm-automix](https://github.com/sony/fxnorm-automix)、[c4dm/qm-dsp](https://github.com/c4dm/qm-dsp)、[libsndfile/libsamplerate](https://github.com/libsndfile/libsamplerate)
- 音源分离：[facebookresearch/demucs](https://github.com/facebookresearch/demucs)、[adefossez/demucs](https://github.com/adefossez/demucs)、[lucidrains/BS-RoFormer](https://github.com/lucidrains/BS-RoFormer)、[deezer/spleeter](https://github.com/deezer/spleeter)、[sigsep/open-unmix-pytorch](https://github.com/sigsep/open-unmix-pytorch)、[Anjok07/ultimatevocalremovergui](https://github.com/Anjok07/ultimatevocalremovergui)、[CarlGao4/Demucs-Gui](https://github.com/CarlGao4/Demucs-Gui)、[dexxdean/htdemucs-coreml](https://github.com/dexxdean/htdemucs-coreml)、[StemSplit/demucs-onnx](https://github.com/StemSplit/demucs-onnx)、[sevagh/demucs.cpp](https://github.com/sevagh/demucs.cpp)、[sevagh/demucs.onnx](https://github.com/sevagh/demucs.onnx)、[ssmall256/demucs-mlx](https://github.com/ssmall256/demucs-mlx)、[ssmall256/mlx-audio-separator](https://github.com/ssmall256/mlx-audio-separator)
- 其他模型与工具：[apple/coremltools](https://github.com/apple/coremltools)、[ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)、[snakers4/silero-vad](https://github.com/snakers4/silero-vad)、[CPJKU/madmom_models](https://github.com/CPJKU/madmom_models)、[f0k/ismir2015](https://github.com/f0k/ismir2015)、[tensorflow/models](https://github.com/tensorflow/models)

## 许可证说明

Coda 整体以 AGPL-3.0-or-later 发布（[LICENSE](../LICENSE)）。各来源的许可关系：

- Kumone（LGPL-3.0）：LGPL-3.0 允许改按 GPL / AGPL 分发，原文保留在 [Kumone-LGPL-3.0.txt](Kumone-LGPL-3.0.txt)。
- MeloX（GPL-3.0-only）：改编文件保持 GPL-3.0-only 并带 SPDX 文件头，全文见 [COPYING](../COPYING)；GPL-3.0 第 13 条允许与 AGPL-3.0 代码组合。
- libresoda（AGPL-3.0-or-later）：与项目许可一致，原文另见 [libresoda-AGPL-3.0.txt](libresoda-AGPL-3.0.txt)。
- MIT、ISC、Apache-2.0 代码均可并入 AGPL-3.0 项目，保留各自的版权与许可声明。

GPL / AGPL 应用无法上架 App Store；如需上架，须先移除 MeloX 与 libresoda 的改编代码。汽水听歌模式图标来自 SodaM，其声明仅称“受各自许可和来源条款约束”，再分发授权尚未确认。
