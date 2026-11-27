# Coda 发布准备

发布前在 [CHANGELOG.md](../../CHANGELOG.md) 写好对应版本的段落（`## <版本号> - <日期>`），否则发布流水线会在提取发行说明时停止。Mac 版本号在 `Scripts/build-app.sh` 中设置，打标签时以标签版本为准。

推送 `v*` 标签触发发布流水线。证书与密钥均为可选，按已配置的内容决定 Mac 版发布方式：

- **Developer ID 签名与公证**：同时配置 `MACOS_SIGN_IDENTITY`（Developer ID Application）、`MACOS_CERTIFICATE_P12`、`MACOS_CERTIFICATE_PASSWORD`、`APPLE_ID`、`APPLE_TEAM_ID`、`APPLE_APP_PASSWORD` 六个 Secrets。用户下载后可直接打开。
- **未公证（ad-hoc 签名）**：六项都不配置。应用照常发布，发行说明自动附上 [首次打开说明](unsigned-mac-install.md)，用户需在「隐私与安全性」中点「仍要打开」。只配置其中一部分会直接报错，避免意外降级。
- **应用内自动更新**：另行配置 `SPARKLE_PRIVATE_KEY` Secret 与 `CODA_SPARKLE_PUBLIC_ED_KEY` 仓库变量（用 Sparkle 的 `generate_keys` 免费生成，不需要 Apple 账号）。两者都不配置时不发布 appcast，应用内更新保持关闭。

私钥、证书及密码不能提交到源码。iOS 始终发布未签名 IPA，由用户通过 AltStore / SideStore 自签安装。

本地 Mac 打包不提供 `CODA_SPARKLE_PUBLIC_ED_KEY` 时不会生成 Sparkle 更新源或公钥配置，也不会启动更新器。提供自己的公钥后才可启用；自动检查仍由用户设置控制。iOS 更新检查和 AltStore 源使用 Coda 仓库，仓库或 Release 尚不存在时提示暂无已发布版本。Homebrew 发布已移除。

正式版标识是 `wow.caicai.coda`；开发标识为 `wow.caicai.coda.dev`。本机开发证书不能代替 Mac 公开分发的 Developer ID 签名与公证。iOS 流水线输出未签名 IPA，安装需适用的签名渠道；本次没有上架 App Store 或 TestFlight。

发布前核对实际功能、截图、隐私说明、音乐服务与内容授权，许可证说明见 [ThirdPartyNotices/README.md](../../ThirdPartyNotices/README.md)。保留上游版权及所有第三方许可。安装包位于 dist，不提交源码仓库。
