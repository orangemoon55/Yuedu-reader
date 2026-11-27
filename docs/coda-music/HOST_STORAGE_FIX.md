# Readcc 嵌入 Coda：宿主存储保护适配

## 范围与状态

已按追加授权修改独立 candidate 的四个文件；上游 source 未改，未删任何官方文件/函数，未动 UI/Bridge/Player/Onboarding/Updater、Package/project/Info/许可资源、state、四角色；未 commit/publish。原802文件已保留，但不得再称“802文件仍逐字节无修改”，应称“完整原模块＋有记录的适配补丁”。

本轮完成 **P1-02 宿主范围清理保护**及 **P2-01 最小产品身份命名空间**。偏好 `.standard` 的独立 suite 迁移、凭据明文、其他 P1/P2 不在此授权范围内，不宣称全部账号隔离已完成。

## 1. 实际临时写入核查

仍然存在多种直接写宿主 tmp 的原版路径：

- `Sources/Coda/Core/API/QishuiAudio.swift:8`：固定 `tmp/Coda-Qishui-Audio/`，实际音乐解密缓存目录；保留音乐缓存统计和有时间保护的清理。
- `Sources/Coda/Core/API/QishuiPlayback.swift:642`：直接写 `tmp/<UUID>` 拼接文件，不可由目录/前缀统一确认归属。
- `Sources/Coda/Core/API/NeteaseCloudUpload.swift:142`：`tmp/coda-cloud-<UUID>/` 快照；没有本轮授权改此写入端。
- `Sources/Coda/Core/Player/PlayerService.swift:1653–1654`：macOS `coda-trial-<id>.part`，同样未改写入端。
- URLSession 自身还可能产生系统下载临时文件；不能仅凭“旧于10分钟”认定为音乐所有。

因此采取安全回退：**嵌入模式不扫描/删除宿主整个 tmp；原 `.temporary` 和 `.networkCache` 清理行均禁止删除，并明确显示受保护原因**。没有假装已经把以上所有 writer 改写到专用目录，也没有增加“删除成功”掩盖被保护请求。

## 2. 四文件精确变化

### `Sources/Coda/Core/CodaIdentity.swift`

- 保留官方独立产品 `wow.caicai.coda`、`wow.caicai.coda.dev` 的原 namespace、原 Coda/Coda Dev 同步目录。
- 所有其他非空 bundle 使用 `<hostBundle>.coda-music`，不再借用官方 release 身份；`nil`/空 bundle 使用 `local.coda-music` 且启用保护模式，不把测试进程视为官方产品。
- 导出 internal、Foundation-only、`nonisolated static var isEmbeddedHost: Bool`（当前第22行），供其他适配复用；保留 `isEmbedded` 别名和原接口。
- Keychain service、现有音乐目录、后台下载 session ID 会经原有 `CodaIdentity.namespace` 调用链自动采用宿主音乐域；同步目录也按宿主音乐 namespace 隔离。未添加共享 App Group/Keychain entitlement，未迁移读取旧官方 Coda 凭据。

### `Sources/Coda/Core/Storage/CodaPaths.swift`

- 增加预留专用 `tmp/<musicNamespace>/`，但明确原无前缀临时 writer 未全部迁入。
- 嵌入统计根严格为 `[applicationSupport, networkCache, temporaryDirectory]`，均是音乐域；不再把宿主 Library/Documents/tmp 全根纳入统计。
- `applicationBundleRoots` 在嵌入模式为空，不把整个 Readcc App 包计作音乐模块占用；独立 Coda 维持原行为。
- 增加专用 `embeddedResponseCache` 与 `responseCache` resolver；不会替换 `URLCache.shared`。官方独立 App resolver 仍返回原 `.shared`；嵌入模式只可能返回音乐专用 cache。
- **限制**：本轮未获授权修改所有 API 配置，既有 default URLSession 仍可能使用宿主 shared cache。它们被视为受保护的宿主数据，不计入音乐网络缓存清理；专用 responseCache 只是明确的可供后续 client 选择的对象，不能宣称所有请求已迁入。

### `Sources/Coda/Core/Storage/StorageUsage.swift`

- `AppDataKind.isDeletable` 对嵌入模式 `.temporary`、`.networkCache` 返回 false；原独立 Coda 的删除分类保留。
- 原 UI 已按 `item.isDeletable` 决定是否显示删除按钮，因此不需越权改 UI 源码即可移除这两类宿主清理入口。

### `Sources/Coda/Core/Storage/StorageSpaceModel.swift`

- 统计不再加入宿主 `Bundle.main.bundleURL`；temporary 分类在嵌入模式只指向专用预留目录。
- 删除了直接调用 `URLCache.shared.removeAllCachedResponses()` 的路径，改走 `CodaPaths.responseCache`；且嵌入 networkCache 请求先被 `isDeletable` 拦截，不会触碰宿主 shared cache。
- 程序化请求保护类型同样返回“受保护，未执行清理”，不是只隐藏按钮。
- 原 UI 的 `model.message` 在统计/清理后持续显示：**“受保护：宿主临时文件和共享网络缓存不纳入音乐统计或清理。”**
- 递归删除入口另加嵌入白名单：只允许音乐 storageRoots 或实际写入的 QishuiAudio 专用目录，拒绝其他根及根符号链接；不扩张到全宿主 tmp。
- 图像、音乐缓存、歌单/分析/诊断等原有自有目录功能保留；没有删除官方函数。

## 3. 离线实测与证据

`audit/test_host_storage_fix.py` 执行结果：**26/26 PASS**。检查包括：

1. 独立 release/dev 域保持原值、Readcc/其他测试 bundle 使用宿主独立音乐域、nil/空不复用官方 release。
2. 源码静态约束：Foundation-only nonisolated 标志、嵌入统计根白名单、排除主 bundle、无直接 shared URLCache purge、保护请求先返回、既有 UI 能显示保护说明并隐藏删除按钮。
3. 四文件中原有函数名均仍存在。
4. **实际创建并操作本地临时夹具**：旧宿主 EPUB、无关目录 sentinel、音乐歌单、指向无关目录的符号链接。策略模型拒绝宿主 tmp/旧导入文件/符号链接根，允许并实际删除音乐歌单夹具；宿主两个 sentinel 均保持内容不变。

必须准确区分：第4项是独立 Python 文件系统策略模型实测，**不是运行 Swift 实现**；静态断言把该策略绑定到已修改代码。环境无 swift/swiftc/xcrun，因此 **Swift/Xcode 编译和真机 UI/文件系统运行未验证**，需主 agent/build agent 在最终构建验收。原 `Tests/CodaCoreTests/CodaIdentityTests.swift:10–11` 对外部 bundle/nil 回退官方域的旧断言将不再成立，这是有意的安全语义变更；未越权修改原测试，请构建验收相应更新期望。

## 4. 可复现补丁与数据

- `audit/HOST_STORAGE_FIX.patch`：仅本轮授权四文件相对官方 source 的 unified diff。
- `audit/host_storage_fix_checks.json`：26项结果、四文件双方 SHA-256 和未编译声明。
- `audit/test_host_storage_fix.py`：无网络标准库检查与临时夹具测试。
- 原 `REVIEW.md` 为修复前独立审查快照；P1-02/P2-01 以本说明为最新状态，其他问题没有被本次修复自动消除。

主 agent 必须保留的边界说明：当前只是将音乐统计/清理限制为可确定归属的音乐文件，不是给 Swift Package 创建了独立 OS 沙箱；仍与 Readcc 同进程。没有对旧 host-global 临时文件做自动迁移/回收，也没有把全宿主网络缓存冒称音乐可清理数据。
