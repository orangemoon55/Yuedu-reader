# Coda 迁移验证与部署记录

日期：2026-11-05（America/Los_Angeles）。

## 原工程与来源

- 对原工程 633 个有效文件逐一进行 SHA-256 比对，无变更；未删除原目录，未修改原工程远程地址。
- 保留 Git 历史及未提交代码，新工程工作分支为 codex/coda-migration。未推送、创建线上仓库或发布。
- 迁移时 vendored AudioStreaming 源文件逐字节保持不变。

## 构建与身份

- Swift Package 构建通过；Xcode 能识别 CodaIOS 工程、工作区、Scheme 和本地功能包。
- iOS Debug 真机构建通过，使用本地配置的 Developer Team；构建产物标识 wow.caicai.coda.dev，显示名称 Coda Dev。
- Release 构建设置核对：正式标识 wow.caicai.coda，显示名称 Coda；未将本机团队写入项目默认配置。
- Mac Metal 资源已按原脚本获取并通过固定 SHA-256 校验。应用包包含图标、隐私清单和许可说明。
- Mac 安装包未配置 SUFeedURL、SUPublicEDKey，SUEnableAutomaticChecks 为 false；未使用原作者的更新密钥或更新渠道。

## 实际安装

| 平台 | 结果 |
|---|---|
| Mac | 已安装 /Applications/Coda Dev.app，固定 Apple Development 签名、开发标识及去签名后的可执行文件哈希验证通过；首次安装未启动 |
| iPhone | devicectl 安装成功，已从设备元数据核对 wow.caicai.coda.dev、Coda Dev、版本 0.1.0 / build 1；未启动 |
| iPad | pymobiledevice3 显式选择 Network 安装成功，已通过同一无线会话核对安装版本 build 1；未启动，无 USB 回退 |
| iOS 模拟器 | 检查时无已启动设备，按约定跳过构建和安装 |

iOS 描述文件包含上述两台设备，签名有效期至 2026-11-12（以描述文件为准）。未启动真机自动化 Runner、Accessibility Inspector 或辅助功能检查；无线安装服务会话已按上下文管理器关闭。

## 测试

- 迁移定向测试：39 项、5 个 Suite 全部通过。
- 产品隔离专项：5 项全部通过，覆盖开发/正式命名空间、登录导出跨产品拒绝、未发布仓库提示、Coda 更新资产解析和网易云协议加密固定结果。
- 其余主机测试：排除 PlaybackEngineSmoke 后，1273 项、146 个 Suite 全部通过（57.604 秒）。
- 旧下载能力、行高及不持久化凭据的断言与当前源码不符；仅更新断言，仍严格检查不写入凭据文件，没有改变产品功能。
- 扩展实时音频测试：resumeIsContinuousAndThePlayheadTracksTheOutput 存在两项连续性断言失败；后续 outgoingDeckStaysSilentAfterTransition 长时间未推进，已停止本次全量测试进程并清理其音频临时文件。该组不算通过，未在重命名任务中修改播放算法。
- 音频诊断和构建、安装日志保存在未跟踪的 dist/validation 中；迁移辅助脚本已清理，未遗留本次启动的测试进程。
