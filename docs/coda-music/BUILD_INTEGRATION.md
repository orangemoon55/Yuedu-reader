# CodaCore 工程接入结果

- 基于已删除新增影视的 Readcc 2b55f7f 独立副本；整个官方 Coda v0.1.2 的802受控文件路径保留，未引入独立 Coda @main；上游源码和旧IPA不变。
- `Packages/CodaMusic` 本地 SwiftPM 库导出 `CodaCore`，生产目录仍为 `Sources/Coda`，329个原核心Swift实现全部保留并加1个宿主bridge。Swift5语言模式与Readcc Swift6隔离，避免Song/HomeView/PlayerService等重名。原Package.swift保存在Package.upstream.swift.txt；mac launcher/ObjC/Sparkle等原文件仍在，但不加入iOS依赖图，也不再为iOS引入Sparkle网络依赖。
- `Yuedu-Reader.xcodeproj/project.pbxproj` 中主app和yuedu appTests都实际注册CodaCore package product及frameworks链接。Ruby xcodeproj原生项目解析器成功。没有修改app bundle id/签名team/根阅读结构，也没有加入未经授权的CarPlay entitlement。
- Coda原localization、privacy、React汽水验证资源、模式资源、完整法律文档在SPM module bundle；主app同步官方iOS imagesets（不覆盖Readcc app icon/accent）。法律页明确解析Bundle.module/CodaLegal，不能误读Readcc MPL根LICENSE。
- 48个模式图标使用原创SVG→PNG替代，保留原resource key/布局/颜色模板方式；未确认版权的上游SodaM图不作为本候选实际模式图资源发布。生成器依赖源码包内输入，不依赖设备绝对源码路径。
- 原120 CodaCore测试源保留；iOS testTarget明确排除2个未guard AppKit的测试文件，其余macOS-only guard仍原样保留。新增宿主9项XCTest在Readcc test target。保留测试不等于全部iOS执行通过。
- LICENSING.md明确Coda AGPL/GPL及组合发行对应源码、修改和构建资料义务，不以MPL或通知替代。没有宣称App Store许可/再分发合规性已由法律确认。

## 真实执行

`python3 candidate/scripts/verify_coda_integration.py`：exit0，Ruby xcodeproj解析/主app+test实际链接/模块全部资源/48原创PNG+SVG/iOS imageset逐字节等闭包断言通过。详细literal stdout/stderr/exit保存在VERIFY_COMMANDS.json。

`python3 audit/test_host_storage_fix.py`：26项离线检查通过（策略模型和临时文件实测，非Swift运行）。

`sh candidate/scripts/verify_media51_native.sh -only-testing:yuedu appTests/CodaMusicHostIntegrationTests`：真实exit69、stdout为空、stderr为`BLOCKED: xcodebuild/iOS SDK unavailable; no Readcc native playback verdict.`。没有Swift编译、XCTest/UI成功、实机安装、远端登录/音频播放或本候选新IPA。

## 仍需原生验收

完整Coda模块首次加入Readcc后，必须在受授权Xcode环境进行类型检查和device build，再做原生音频所有权/菜单切换/UI验证。CarPlay仅保留代码，无Readcc授权/scene激活。同步采用原版用户文件夹，不冒充Readcc CloudKit或自动iCloud容器；宏观音乐能力以audit/REVIEW.md四平台51能力矩阵为准，macOS AutoMix/桌面歌词等代码保留不等于iOS激活。
