# Coda 迁移说明

原 Kumone 工程目录保持不变，新工程即本仓库。迁移保留 Git 历史、当前未提交改动与有效新增文件，排除构建缓存、安装包及个人 IDE 状态。

| 原名称 | 新名称 |
|---|---|
| Kumone / Kumone Dev | Coda / Coda Dev |
| KumoneCore / KumoneLauncher / KumoneObjC | CodaCore / CodaLauncher / CodaObjC |
| KumoneIOS | CodaIOS |
| KumoneIOSFeature | 并入 CodaCore |
| Sources/Kumone、Tests/KumoneCoreTests | Sources/Coda、Tests/CodaCoreTests |
| 原正式版标识 | wow.caicai.coda |
| sb.moe.kumone.dev | wow.caicai.coda.dev |

源码 API 中的产品前缀同步改名，不保留旧模块别名；音乐服务协议字段、第三方模块与算法名称保持原义。历史变更、上游版权、第三方说明和模型资源地址仍可能出现 Kumone，这是来源信息。

资料和缓存以实际安装标识划分目录，例如 `~/Library/Application Support/wow.caicai.coda.dev`；模型位于其 Models 子目录。钥匙串服务和后台下载会话也采用该命名空间。开发版与正式版本地资料互不覆盖，不读取或迁移 Kumone 旧资料。需要重新登录及按需下载模型。

同步默认使用 Coda / Coda Dev 文件夹，拒绝其他产品的仓库清单。登录导出格式使用 coda-login，不接受 kumone-login。未实现自动账号或旧加密同步数据迁移。

Mac 使用 `bash Scripts/deploy-mac-dev.sh debug`，指定证书可设置 `CODA_DEV_SIGN_IDENTITY`。安装副本使用固定 Apple Development 证书，保留已有 Coda Dev 数据；首次不启动，原先正在运行的 Coda Dev 正常退出后替换并重开。原 Kumone 安装不受影响。

[验证与部署记录](validation.md) 记录本次实际结果。

网易云 weapi 的固定加密参数与预计算 RSA 密文配套，其中仍含旧名称的协议常量必须保留；已用独立 AES 固定结果增加回归验证。
