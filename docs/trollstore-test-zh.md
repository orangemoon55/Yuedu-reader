# 书架试用版：Fork 后通过 GitHub Actions 构建

本流程为 Yuedu Reader 3.0.1（基线提交 `cc566a8433a64ffdd8fe1c50ea7e3d10f885968d`）生成独立身份的 iOS 测试包。当前只完成脚本语法和静态检查；本地 Alpine/iSH 没有 Xcode，尚未进行云端编译、IPA 安装或真机运行验证。

## 运行前准备

1. Fork 仓库，确认默认分支包含 `.github/workflows/trollstore-test.yml` 及两个脚本。自用版不接入账号登录、Firestore、Crashlytics 和账号云同步，不需要 Firebase 账号或 Secret。在自己的 Fork 的 Actions 页面启用工作流。工作流只接受手动运行，不会发布 Release、提交或推送。
2. 准备新的主应用 Bundle ID，例如默认 `com.local.readerpreview`。桌面名称默认“书架试用版”；可在手动运行表单修改。不要使用原应用的 Bundle ID。
3. 在自己的 Fork 中进入 Actions，运行“书架试用版 · TrollStore 云端构建”。选择主分支，填写 Bundle ID 和显示名称，然后等待构建完成。

脚本会在云端临时目录生成关闭账号服务的本地配置，只为让 Firebase SDK 资源阶段完成；不会连接官方 Firebase 项目，也不会读取或上传官方 IPA 内的配置。

## 手动构建与下载

进入 Fork 的 **Actions → 书架试用版 · TrollStore 云端构建 → Run workflow**，选择含有测试界面代码的分支，填写 Bundle ID 和显示名称后运行。

流程使用普通 GitHub 托管 `xcode-27` arm64 runner，不指定付费大 runner；实际使用额度和是否收费受仓库可见性、GitHub 套餐与账户配额约束。该标签是会更新的镜像，脚本会检查 `/Applications` 中的 Xcode 并选择满足 **Xcode ≥ 27.1** 的版本；只有 27.0 时明确失败，不会降低要求。可在 GitHub 官方 [runner-images](https://github.com/actions/runner-images) 核对标签及软件清单。镜像排队或不可用需在 GitHub 平台侧解决。

实际编译命令使用 `xcodebuild`、`Yuedu-Reader` scheme、`Debug`、`generic/platform=iOS`，并传入：

```text
CODE_SIGNING_ALLOWED=NO
CODE_SIGNING_REQUIRED=NO
ONLY_ACTIVE_ARCH=NO
ENABLE_DEBUG_DYLIB=NO
```

Debug 避开现有 Release 专用 Crashlytics 符号上传。脚本先用 `-showBuildSettings -json` 读取 `BUILT_PRODUCTS_DIR`、`WRAPPER_NAME`，此步骤可能解析或下载 Swift Package；随后独立执行完整 `build`。任何命令失败都会停止，不跳过编译错误、不生成空包。首次解析依赖可能较久。

编译结束后会检查主应用、分享扩展、Widget 的 Bundle ID 和 `MinimumOSVersion`，检查嵌套 Mach-O 的真机 arm64 架构、iOS 平台和最低系统版本。接着用 macOS `codesign` 由内到外 ad-hoc 签名 framework/dylib、扩展、主应用，保留源 entitlements 的必要项并同步新 App Group / iCloud 容器；签名校验成功后才生成 `Payload/*.app` 结构的 IPA，并检查 ZIP 完整性。不会伪造 Apple Team ID。

运行成功时下载“书架试用版-IPA-…” artifact，解压后取得 `ReaderPreview.ipa`；IPA artifact 默认保存 3 天。无论成功或失败，尽可能保存“书架试用版-日志-…” artifact（7 天）。详细 Xcode 输出会先写入 runner 私有临时文件，收尾过滤配置值后才显示或上传，因此构建期间页面可能只有阶段提示。取消任务、超时或 runner 中断时，可能来不及生成过滤日志。

## 独立安装与兼容性

脚本只在云端临时 checkout 中更改目标 Bundle ID、App Group 字符串、iCloud 容器字符串、显示名称、Google 回调和图标选择；不会提交这些修改。分享扩展和 Widget 分别使用新 ID 的 `.shareextension`、`.widget` 后缀，共享组统一为 `group.<新 Bundle ID>`。原应用与试用版使用独立数据容器，不自动迁移原版书架。

脚本不改 StoreKit 授权、订阅判断或付费逻辑，也不改 iOS 部署目标。新 Bundle ID 不会自动继承原版购买或订阅权益；界面中仍可能出现需要独立服务配置或合法授权才能使用的功能。

试用版不注册原有 `yuedu`、`legado` URL scheme，避免抢占原版导入链接；这些外部深链接及仍使用旧 scheme 的 Widget 跳转在试用版中不会自动可用。可使用系统分享、文件导入或应用内已有入口。Google 登录仅注册自己的回调。脚本用 Python 标准库生成原创几何书籍桌面图标；应用内部的品牌插图、文字与关于页面不在此脚本替换范围，界面代码仍需单独处理。

本工程最低系统版本为 **iOS/iPadOS 17.0**。结合 TrollStore 的系统支持范围，面向 17 系统的用户需要**确切为 17.0 的受支持真机**，且已经具备可用的 TrollStore 安装条件；17.0.1、17.1 及更高版本不能因“17+”误判为支持。16.x 虽可能支持 TrollStore，却不满足本工程的 17.0 最低要求。本流程不提供 TrollStore 安装漏洞或设备支持保证。

通过 TrollStore 导入 IPA 后仍需真机测试启动、书架、文件导入、分享扩展、Widget 和数据持久化。ad-hoc 签名及静态校验不保证系统允许所有扩展或共享容器行为。测试前备份重要数据；相同测试 Bundle ID 的后续安装会更新已有试用版。

## Firebase、Apple 服务与配置可见性

自建 Firebase 配置只切换客户端连接目标。官方项目中的用户、Firestore/Storage 数据、数据库规则、Cloud Functions、Remote Config、App Check 配置以及账户网关不会自动复制。仓库中的官方网关、外部服务域名或调用约定可能仍需自行审查和部署；此脚本没有自动替换所有后端地址，不应假设登录后官方云功能可复用。

ad-hoc 签名不能授予 Apple 云服务资格。虽然保留了原 entitlements 中推送、Apple 登录、CloudKit、共享组等声明，并将 iCloud 容器改为独立名称，但 APNs、Sign in with Apple、iCloud/CloudKit 仍需要有效的 Apple 开发者配置、服务端设置和受支持的签名。新容器字符串不等于 Apple 已创建容器。StoreKit 也不会因 TrollStore 安装获得购买授权。

工作流仅上传 IPA 和过滤后的纯文本日志，不上传 Secret 原文、独立 plist、原始日志、DerivedData、源码归档或 xcresult。原始配置和临时构建文件在正常收尾时清理。**可运行 IPA 本身必须内置自己的 Firebase 客户端 GoogleService-Info.plist；下载者能够解包读取其客户端配置。** “Secret 不上传”指不单独上传 Secret 原文或把配置泄露到日志，不代表 IPA 能隐藏 Firebase 客户端 API Key。不要把服务账号私钥放进客户端；通过 Firebase Security Rules、App Check 和 API 限制保护资源，并控制 Fork、Actions 和 artifact 的访问权限。

## 本地可运行的检查与边界

在没有 Xcode 的环境，只运行以下检查，它们不修改 Swift 或项目文件：

```sh
bash -n scripts/build_trollstore_test.sh
python3 -c 'import ast; from pathlib import Path; ast.parse(Path("scripts/prepare_trollstore_test.py").read_text()); print("Python 语法检查通过")'
git diff --check
```

不要在工作中的本地源码直接执行准备脚本。脚本对 `prepare` / `package` 设置了 GitHub Actions macOS 环境检查；它们应在可丢弃的 runner checkout 中运行。`showBuildSettings`、依赖解析、完整 Xcode 编译、codesign、实际 IPA 产出和真机验证必须等待云端运行。工程目标数量或配置结构变化时脚本会主动失败，需复核更新，不会静默继续打包。
