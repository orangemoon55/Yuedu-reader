# Coda 工程目录说明

本说明对应本仓库。原 Kumone 工程目录保留作迁移前备份。

## 整体结构

```text
Coda/
├── Sources/                 应用源码与内部模块
│   ├── Coda/                Mac 与 iOS 共用的主要功能
│   │   ├── CodaApp.swift    Mac 应用场景及生命周期
│   │   ├── Core/            音乐接口、播放、存储及同步
│   │   │   ├── Player/Streaming/  iOS 流媒体与播放接入
│   │   │   └── Player/Lyrics/     歌词解析、同步及高亮
│   │   ├── Features/        页面、播放器与导航界面
│   │   ├── DesignSystem/    颜色、字体、间距与通用组件
│   │   ├── Resources/       本地化文案及隐私清单
│   │   └── HotKey/          Mac 全局快捷键
│   ├── iOS&iPadOS/          iPhone 与 iPad 共用的应用入口
│   │   └── Config/          iOS 和 iPadOS 构建、权限及测试配置
│   ├── MacOS/               Mac 可执行程序入口
│   └── CodaObjC/            Objective-C 异常捕获辅助模块
├── ios/                     iPhone 与 iPad 工程
│   ├── CodaIOS/             iOS 图标和资源
│   ├── CodaIOSUITests/      iOS 界面自动化测试源码
│   ├── CodaIOS.xcworkspace/ Xcode 工作区，日常打开此入口
│   ├── CodaIOS.xcodeproj/   Xcode 工程
│   └── project.yml         XcodeGen 工程生成配置
├── Archive/                 已下线功能的归档代码，不参与构建
├── Config/                  跨平台产品身份配置
├── Scripts/                 构建、安装、资源获取和发布脚本
├── Tests/                   主机、iOS 单元及独立音频测试源码
│   ├── CodaCoreTests/       共享功能的主机测试
│   ├── CodaIOSCoreTests/    iOS CarPlay 单元测试，由 Xcode 工程运行
│   └── StreamingPlaybackTests/  iOS 流媒体、播放适配与缓存的主机测试
├── docs/                    项目文档
│   ├── architecture/       架构、接口与功能设计
│   ├── development/        开发规范、迁移说明与验证记录
│   ├── release/            签名、更新与发布准备
│   ├── archive/            历史调研和检查报告
│   └── assets/             文档图片及截图
├── ThirdPartyNotices/       第三方代码来源、版权及许可证
├── design/                  图标方案等设计源文件
├── AppIcon.icon/            Mac 图标源资源
├── .github/                 持续集成与发布流程
├── .build/                  自动生成的 Swift 编译缓存与 Mac 应用包
├── .swiftpm/                自动生成的 Swift Package 工作区状态
├── dist/                    生成产物与验证日志，不纳入源码版本管理
└── .git/                    Git 历史、分支及远程配置
```

`Sources/Coda` 在 Swift Package 中对应模块名 **CodaCore**。iOS 工程直接依赖这个模块，大部分功能开发在共享源码中进行。当前图标的 PNG 预览见 [docs/assets/icon.png](../assets/icon.png)。

## 日常修改去哪里

| 工作内容 | 主要位置 |
|---|---|
| 登录、音乐平台 API 与请求协议 | `Sources/Coda/Core/API` |
| 播放队列、音频引擎与歌词时序 | `Sources/Coda/Core/Player` |
| iOS 流媒体实现与回归测试 | `Sources/Coda/Core/Player/Streaming`、`Scripts/test-streaming-playback.sh` |
| 歌词解析、同步和逐字高亮 | `Sources/Coda/Core/Player/Lyrics` |
| 账号、下载、缓存及偏好存储 | `Sources/Coda/Core/Storage` |
| 设备间资料同步 | `Sources/Coda/Core/Sync` |
| 首页、歌单、搜索和设置等页面 | `Sources/Coda/Features` |
| 正在播放界面及控件 | `Sources/Coda/Features/Player` |
| 统一颜色、字体、间距和组件 | `Sources/Coda/DesignSystem` |
| 界面文案翻译 | `Sources/Coda/Resources` |
| iOS 和 iPadOS 启动入口 | `Sources/iOS&iPadOS/CodaIOSApp.swift` |
| Mac 启动入口 | `Sources/MacOS/main.swift` |
| iOS 和 iPadOS 构建及权限配置 | `Sources/iOS&iPadOS/Config` |
| iOS 和 iPadOS 图标资源 | `ios/CodaIOS/Assets.xcassets` |
| 产品名称、应用标识和仓库地址 | `Config/AppIdentity.xcconfig` |
| 新增或维护主机单元测试 | `Tests/CodaCoreTests` |
| 新增或维护 iOS 单元测试 | `Tests/CodaIOSCoreTests` |

跨平台共享源码会通过条件编译区分 Mac 与 iOS 行为；修改共享页面后应分别构建验证。

## 根目录关键文件

| 文件 | 用途 |
|---|---|
| `README.md` | 项目入口说明（中文） |
| `Package.swift` | Swift 模块、依赖和测试目标定义 |
| `Package.resolved` | 锁定外部 Swift 依赖版本，应保留 |
| `Makefile` | 常用构建和开发命令入口 |
| `AGENTS.md` | 播放器界面、测试限制和设备部署约定 |
| `LICENSE` | 项目许可证（AGPL-3.0-or-later） |
| `COPYING` | GPL-3.0 全文，MeloX 改编文件适用 |
| `CHANGELOG.md` | Coda 版本变更记录，发布流程从中提取发行说明 |
| `.gitignore` | 排除编译产物、个人状态及本地凭据 |

## 常用操作入口

在本仓库根目录下执行：

```sh
swift build
swift test
bash Scripts/deploy-mac-dev.sh debug
```

iOS 使用 Xcode 打开 `ios/CodaIOS.xcworkspace`，选择 `CodaIOS`。iPad 的明确无线安装入口是 `Scripts/deploy-ipad-network.py`；设备构建与安装参数见 [iOS 说明](../../ios/README.md)。

`Tests` 或 `ios/CodaIOSUITests` 目录存在并不代表应自动运行真机测试；执行前遵守 [AGENTS.md](../../AGENTS.md)。

## 源码目录与用户资料的区别

工程目录保存代码、配置和文档；实际登录资料、离线音乐与缓存位于系统应用资料目录或 iOS 沙盒中。

- 正式版应用标识为 `wow.caicai.coda`，开发版为 `wow.caicai.coda.dev`。
- Mac 开发版安装在 `/Applications/Coda Dev.app`，其应用资料位于 `~/Library/Application Support/wow.caicai.coda.dev`，缓存位于对应标识的缓存目录。
- 正式版、开发版及原 Kumone 的本地资料相互隔离；不应通过搬动源码目录来迁移账号或下载内容。
- `.build` 是可重新生成的构建缓存；`dist/validation` 保存本次验证证据，需要留存时先备份。二者都不作为源码提交。
- `ThirdPartyNotices`、许可证文件和 `Package.resolved` 保存工程依赖及来源记录。

更多信息见 [迁移说明](coda-migration.md)、[验证与安装记录](validation.md) 和 [发布准备](../release/README.md)。
