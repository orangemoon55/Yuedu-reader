# 增强过渡（AutoMix 人声分离）归档

状态：**已下线，不参与构建，不随应用发布。** 归档于 2026-11-13。

## 下线原因

“增强过渡”用人声分离模型把歌曲拆成人声和伴奏，再在过渡中分别处理。上线前问题较多：拼接处对齐、GPU 耗电与内存占用、几百 MB 的模型下载、预渲染需要的提前量等都还不稳定，因此先整体下线，保留代码以便日后重新评估。

## 归档内容

目录结构与原仓库路径一一对应，恢复时按原路径移回即可。

| 归档路径 | 原用途 |
| --- | --- |
| `Sources/StemKit/` | MLX/Metal 上的 Mel-Band RoFormer 与 BS-RoFormer 分离器，以及权重加载和 STFT |
| `Sources/MacOS/StemSetup.swift` | 启动时把分离器以闭包形式注入 CodaCore |
| `Sources/Coda/Core/Player/Audition/StemSeparation.swift` | 分离器注册表（`StemSeparation`）和分离结果的磁盘缓存（`VocalStemCache`） |
| `Sources/Coda/Core/Stems/StemModelDownloader.swift` | 模型下载、SHA-256 校验和安装 |
| `Sources/Coda/Features/Pages/StemModelsSettingsSection.swift` | 设置页里的模型下载行 |
| `Tests/StemKitTests/` | StemKit 单元测试 |
| `Tests/CodaCoreTests/StemModelDownloaderTests.swift`、`StemCacheTests.swift` | 下载器、缓存及日志接线测试（后者从 `BedSplitTests` / `StemTechniqueTests` 中拆出） |
| `Scripts/` | MLX metallib 获取、四轨模型获取与转换、模型发布脚本 |
| `ThirdPartyNotices/Mel-RoFormer-MLX-Swift.md` | 分离模型代码的第三方说明 |

## 仍留在主代码中的部分

CodaCore 中的 stem 技巧契约保留未动，没有分离器时它们不起作用：`StemTechnique`、`StemEnvelope`、`StemTechniqueLayer`、`VocalExchange`、`TransitionSegmentRenderer`，以及 `TransitionPlanner` 的 `stems` 参数。这些代码同时服务于乐谱（score）和片段预渲染路径。

现在 `PlayerService` 始终向规划器传入 `StemAvailability.none`，所有转场都走整体混音路径；需要分离的乐谱（`bedIntro`）不会预渲染，改由实时混音完成。

## 同时移除的接线

- `Package.swift`：`StemKit` product、target、test target，以及 `mlx-swift` 依赖。
- `Scripts/build-app.sh` 与 CI/发布工作流：`mlx.metallib` 的获取、打包和签名。
- 设置：AutoMix 区块中的“增强过渡”开关和模型下载行，以及 `SettingsManager.automixStemsEnabled`。
- 存储空间页保留“人声分离模型”这一项，方便已经下载过模型的用户删除 `Application Support/<bundle id>/Models/`。

## 恢复步骤（概要）

1. 把本目录下的文件按原路径移回。
2. 在 `Package.swift` 中恢复 `mlx-swift`（固定为 `exact: "0.30.6"`，原因见 `Scripts/fetch-mlx-metallib.sh`）、`StemKit` target 和 `StemKitTests`，并让 `CodaLauncher` 依赖 `StemKit`。
3. 恢复 `Sources/MacOS/main.swift` 中的 `StemSetup.install()` 和下载完成回调。
4. 恢复 `SettingsManager.automixStemsEnabled`、设置页开关，以及 `PlayerService` 中的 `stemSeparationAllowed` 和预渲染时对分离器的分发。
5. 恢复 `build-app.sh` 的 metallib 打包和工作流中的 `FETCH_MLX_METALLIB=1` 及签名步骤。
6. 恢复相关本地化文案和 `ThirdPartyNotices/README.md` 条目。

可以用 git 历史作为参照：

```sh
git log --follow -- Archive/StemSeparation/Sources/StemKit
```
