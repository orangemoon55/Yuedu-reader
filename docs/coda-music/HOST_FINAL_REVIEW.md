# Coda 音乐接入 Readcc：宿主最终补充

## 已实际落盘

主音乐路径为 `MediaHubRootView.body → CodaMusicDestination → CodaCore.IOSMainWindow`。首页、搜索、音乐库、播放器、逐字歌词、队列、设置使用完整上游真实界面和自有导航/主题，不将接口套入旧 Readcc JS 音乐布局。首页和书架音乐库分别选择上游 home/library，iPhone 与两种 iPad root 的初始落点都有接线。原阅读 root 保持挂载；仅音乐覆盖层移除多余外层 NavigationStack。

宿主仅增加“返回阅读”和旧 JS 音乐源 sheet 两个薄入口。返回只关闭界面，不在 onAppear/onDisappear 清空 Coda 播放队列，不修改书架资料。真正播放 TTS/听书/旧 JS 或 Coda 时才转移音频所有权。Coda 让出时废弃 resolver generation、取消解析和离线扫描、移除自有远控 token；保留 Coda 队列/歌词/账号域/恢复位置。听书等原引擎仍按既有机制保存进度。

主线程补齐：AudioOwnership 明确 @MainActor；Coda 远控回调主执行器守卫并拒绝 detached 迟到事件；命令数组显式 MPRemoteCommand；旧听书 ±15s 目标在 handoff 清理；Coda next/FM next/FM trash/立即插队/汽水续页恢复均在用户播放意图前声明所有权。

后台下载通过现有 RSSAppNotificationDelegate 转发；未知 identifier 不初始化音乐下载管理器，由既有 delegate 完成一次。未新增 @main 或第二 UIApplicationDelegateAdaptor。

## 宿主副作用与隐私适配

- 嵌入模式拒绝免责声明仅返回阅读，不预置同意，不退出宿主。
- Coda 独立更新器的自动/手动检查及安装、下载、release/share入口均有嵌入禁用守卫。
- 原版 iPad 私有 AirPlay presenter 在宿主走公开 AVRoutePickerView；原按钮及路由保留。
- 音乐缓存清理不触碰阅读 tmp 或共享 URLCache；身份使用 `<ReadccBundle>.coda-music`。详见 audit/HOST_STORAGE_FIX.md。
- 音乐账号敏感导出增加确认，iOS仅本机剪贴板并两分钟过期。没有读取任何实际账户秘密。
- 原网易活动会话仍按上游文件格式持久化；同步默认关闭，原登录同步仍可能在用户指定目录写入可登录凭据，未声称端到端加密或全部凭据仅存Keychain。应仅选择私有目录。第三方备用音源仍遵循上游设置；不是只向四平台官方服务联网的声明。

## 测试和边界

新增 CodaMusicHostIntegrationTests 9项原生测试：真实四平台集合、安装hooks不抢音频、同owner幂等、反复交接、重入拒绝、更换hook不暂停、外部后台identifier拒绝及completion归属、嵌入更新禁用。已落盘但没有原生执行成功记录。

冻结校验实际通过：工程PBX解析/真实product+framework链接、资源闭包、所有802个上游路径保留、所有适配在ADAPTATIONS.json登记、无新tree-sitter语法错误。14个原封不动上游文件有parser局限错误，逐文件原字节/原parser结果一致，未以它们伪造Swift编译通过。

本机原生尝试真实 exit69：`BLOCKED: xcodebuild/iOS SDK unavailable; no Readcc native playback verdict.` 不将9项测试源码、Python策略夹具或语法树当成Swift/XCTest/UI/实播结论。未登录、安装、远端播放、发布commit、dispatch或产生新IPA。所有云端与设备行为待独立验收。
