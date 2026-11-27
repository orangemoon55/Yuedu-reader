# Coda iOS / iPadOS

支持 iOS/iPadOS 16+；使用 Xcode 打开 `CodaIOS.xcworkspace`，选择 `CodaIOS` Scheme。

iPhone 和 iPad 共用 `Sources/iOS&iPadOS/CodaIOSApp.swift` 作为 App 入口，同目录的 `Config/` 存放两端的构建设置、权限和 `Info.plist`。应用直接依赖根 Swift 包提供的 `CodaCore`，主要功能位于 `Sources/Coda`，移动端资源位于 `ios/CodaIOS/Assets.xcassets`。跨平台产品身份由根目录的 `Config/AppIdentity.xcconfig` 定义。`project.yml` 定义 XcodeGen 工程，生成的工程也纳入版本管理。修改工程定义后运行 `make project`。

CarPlay 单元测试源码位于根目录的 `Tests/CodaIOSCoreTests`，使用 `CodaIOSCoreTests` Scheme。界面测试源码位于 `CodaIOSUITests`，使用 `CodaIOS` Scheme。两个模拟器测试入口分别是 `make ios-test` 和 `make ios-uitest`，可以通过 `IOS_DESTINATION` 指定目标。

正式版标识为 `wow.caicai.coda`。开发安装通过构建参数覆盖为 `wow.caicai.coda.dev`，显示 Coda Dev，不修改项目默认团队配置。

```sh
xcodebuild -workspace ios/CodaIOS.xcworkspace -scheme CodaIOS -configuration Debug \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/coda-device-build \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$CODA_DEVELOPMENT_TEAM" \
  PRODUCT_BUNDLE_IDENTIFIER=wow.caicai.coda.dev \
  INFOPLIST_KEY_CFBundleDisplayName='Coda Dev' build
```

命令在仓库根目录执行。签名团队需匹配有效证书和设备描述文件；安装说明与设备约定见 [AGENTS.md](../AGENTS.md)。iPad 必须显式选择 Network 连接，无线不可用时停止该设备部署并报告。安装后不启动 App、测试 Runner 或辅助功能检查；不卸载 Kumone。

CarPlay 默认关闭，仅拥有 Apple 授权后执行 `make configure-carplay`。不要为重命名开启新的权限。

仅在构建与签名验证成功后执行 iPad 无线安装：

```sh
python3 Scripts/deploy-ipad-network.py /tmp/coda-device-build/Build/Products/Debug-iphoneos/CodaIOS.app
```

该脚本依赖本机 pymobiledevice3，显式选择 Network，验证安装版本并关闭会话，不启用辅助功能检查。
