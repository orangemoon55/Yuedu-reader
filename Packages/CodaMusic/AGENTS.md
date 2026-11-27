# 项目工作约定

## 真机自动化检查与测试

- 默认不要唤起 iPhone / iPad 上显示“Automation Running”的自动化测试，包括 XCUITest、测试 Runner 和通过 `xcodebuild test` / `test-without-building` 启动的真机测试。
- 只有用户明确要求自行检查、测试或运行自动化时，才启动上述真机自动化；普通修复请求不视为自动化测试授权。
- 构建、打包和覆盖安装仍按下方真机部署约定执行；安装后不启动应用，不启动自动化测试 Runner。
- 每次真机检查或测试结束后，必须清理本次创建的检查会话、测试 Runner、本机辅助脚本和设备端检查高亮；成功、失败、超时、中断或用户要求停止时都必须执行，优先用 `finally` 保证清理。
- 使用 Accessibility Inspector / `pymobiledevice3` 辅助功能检查后，不能仅隐藏绿色框或关闭本机连接。设备支持时，应关闭应用监听与事件监听，执行 `deviceInspectorShowVisuals: false`、`deviceEnableHighlight: false`、`deviceInspectorEnable: false` 和 `devicePerformFinalCleanup`；等待设备响应确认后再断开连接，避免旋转屏幕后绿色框重新出现。
- 清理时只恢复本次检查产生的状态，不使用重置全部辅助功能设置代替会话清理，不更改用户原有辅助功能偏好。检查清理结果，明确说明已完成的清理及未验证项；未经旋转验证，不声称已确认旋转后不会复现。
- 用户说“测试交给我”时，立即停止自动化测试及其准备工作，清理已建立的检查会话；后续仅按授权构建、覆盖安装，不再启动应用、测试 Runner 或辅助功能检查。

## 修改后的 Mac 部署

- 本机开发部署使用 `bash Scripts/deploy-mac-dev.sh debug`；使用固定的 Apple Development 证书签名，不得对安装副本使用 ad-hoc（`codesign --sign -`）签名，以免每次构建改变钥匙串授权身份。多证书时通过 `CODA_DEV_SIGN_IDENTITY` 指定；证书不可用时保留原安装并报告，不降级为临时签名。
- 每次完成影响 Mac 客户端的代码修改后，默认构建、打包并覆盖替换 `/Applications/Coda Dev.app`，无需再次询问；不得仅交付构建目录中的应用。用户当次另有要求时，以用户要求为准。
- 保留开发版应用标识 `wow.caicai.coda.dev`、应用名称 `Coda Dev` 及现有用户数据，不卸载应用、不清除偏好或资料目录，不覆盖正式版。
- 必须在构建成功后执行替换。打包产物若使用正式版标识，应仅在部署副本中改为开发版标识与名称，重新签名并验证，不为本机部署修改项目默认配置。
- 替换前检查开发版是否正在运行；若正在运行，先正常退出，替换成功后重新打开开发版，使本次修改生效；若原本未运行则不自动启动。
- 检查安装后的应用标识、签名及可执行文件是否与本次构建一致，明确报告替换结果；构建或替换失败时保留已有应用并说明原因。

## 修改后的真机部署

- 完成影响 iOS 界面的代码修改后，默认构建并覆盖安装到用户已连接的实际 iPhone 和 iPad，不启动应用，无需再次询问是否安装。用户当次另有要求时，以用户要求为准。
- 优先更新设备上已有的开发版 `wow.caicai.coda.dev`，保留应用数据，不卸载应用。
- iPad（`$CODA_IPAD_UDID`）后续开发版更新使用 Wi-Fi 无线部署；USB 用于首次配对或连接排查。安装时显式选择 Network 连接，并确认无线安装结果，不把插线时的 USB 安装成功当作 Wi-Fi 验证。无线不可用时先排查并报告，不静默改用 USB。
- 设备 UDID 与开发签名团队保存在本地未提交的 `.env.local`（格式见 `.env.example`）：iPad 为 `CODA_IPAD_UDID`，iPhone 为 `CODA_IPHONE_UDID`，团队为 `CODA_DEVELOPMENT_TEAM`。执行前读取该文件，并检查设备连接及签名是否仍有效；不得把这些值写回已提交的文件。
- iPhone（`$CODA_IPHONE_UDID`）使用同一开发签名团队。执行前重新确认设备连接、解锁及签名状态；可用 `xcrun devicectl` 安装。
- 使用构建参数覆盖本机签名与应用标识，不为部署修改项目默认签名配置。
- iPad 运行 iPadOS 16.6，可使用 `ios-deploy` 安装；不要仅依赖 `devicectl` 判断 iPad 是否连接。
- 若设备未连接、未解锁或签名不可用，明确说明阻塞原因；不得将模拟器构建成功表述为真机安装成功。
- 分别检查并报告 iPhone 与 iPad 的安装结果；某台设备不可用时，继续向其余可用设备部署。

参考命令（在项目根目录执行，先 `set -a; source .env.local; set +a`）：

```sh
xcodebuild -project ios/CodaIOS.xcodeproj -scheme CodaIOS -configuration Debug -destination "id=$CODA_IPAD_UDID" -derivedDataPath /tmp/coda-device-build -allowProvisioningUpdates DEVELOPMENT_TEAM=$CODA_DEVELOPMENT_TEAM PRODUCT_BUNDLE_IDENTIFIER=wow.caicai.coda.dev 'INFOPLIST_KEY_CFBundleDisplayName=Coda Dev' build
python3 Scripts/deploy-ipad-network.py /tmp/coda-device-build/Build/Products/Debug-iphoneos/CodaIOS.app
```

同一真机构建产物可覆盖安装到 iPhone；确认构建成功和设备可用后执行：

```sh
xcrun devicectl device install app --device "$CODA_IPHONE_UDID" /tmp/coda-device-build/Build/Products/Debug-iphoneos/CodaIOS.app
```

必须在构建成功后才执行安装，并检查安装结果。

## 修改后的模拟器部署

- 完成影响 iOS 界面的代码修改后，除上述真机部署外，也默认构建并覆盖安装到当前已启动的 iOS 模拟器，无需再次询问。用户当次另有要求时，以用户要求为准。
- 执行前通过 `xcrun simctl list devices booted` 检查当前已启动的模拟器，仅向这些设备安装；不得为部署自动启动其他模拟器，也不要求凑齐 iPhone 和 iPad。没有已启动的模拟器时，跳过模拟器构建与安装并说明，继续执行真机部署。
- 单独构建适用于 iOS Simulator 的产物，不使用真机构建产物安装模拟器。使用构建参数指定 `PRODUCT_BUNDLE_IDENTIFIER=wow.caicai.coda.dev`，不为部署修改项目默认配置。
- 仅在模拟器构建成功后，通过 `xcrun simctl install <设备 UDID> <模拟器 app 路径>` 覆盖安装，保留应用数据，不卸载应用；安装后不启动应用或自动化测试 Runner。
- 分别检查并报告模拟器的安装结果，与 iPhone、iPad 真机安装结果分开说明；模拟器不可用不影响继续向可用真机部署。
