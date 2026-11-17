#!/usr/bin/env bash
# 仅在 GitHub Actions 的临时 macOS checkout 中运行。
set -Eeuo pipefail
umask 077
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
if [[ "${GITHUB_ACTIONS:-}" != true || "$(uname -s)" != Darwin ]]; then
  echo '错误：本脚本仅供 GitHub Actions macOS 临时 checkout 使用；本地仅执行 bash -n 语法检查。' >&2
  exit 1
fi
OUT="$ROOT/trollstore-output"
mkdir -p "$OUT"
# 不复用旧产物，任何一步失败均不保留 IPA。
rm -f "$OUT"/*.ipa "$OUT/build.log"
PRIVATE="$(mktemp -d "${RUNNER_TEMP:-/tmp}/qingyun.XXXXXX")"
export TROLLSTORE_PRIVATE_DIR="$PRIVATE"
exec 3>&1 4>&2
exec >"$PRIVATE/raw.log" 2>&1
finish() {
  status=$?
  trap - EXIT
  set +e
  python3 scripts/prepare_trollstore_test.py redact "$PRIVATE/raw.log" "$OUT/build.log"
  filtered=$?
  if [[ "$filtered" != 0 ]]; then
    printf '%s\n' '日志过滤失败，原始日志未上传。' >"$OUT/build.log"
    status=1
  fi
  if [[ "$status" != 0 ]]; then
    rm -f "$OUT"/*.ipa
    printf '%s\n' '构建失败，未交付 IPA；请查看以下过滤后的日志。' >&3
  else
    printf '%s\n' '真实编译与签名复核完成，IPA 已生成；尚未进行真机安装验证。' >&3
  fi
  cat "$OUT/build.log" >&3
  rm -f "$ROOT/GoogleService-Info.plist"
  rm -rf "$PRIVATE"
  exit "$status"
}
trap finish EXIT
printf '%s\n' '开始准备轻云出岫自用版身份、月夜苍岚图标及停用云服务的本地配置。' >&3
python3 scripts/prepare_trollstore_test.py prepare
# 防止 Xcode 子进程或 Build Settings 输出继承原始 secret。
unset GOOGLE_SERVICE_INFO_BASE64
export DEVELOPER_DIR="$(python3 scripts/prepare_trollstore_test.py select-xcode)"
xcodebuild -version
bash scripts/ensure_metal_toolchain.sh
printf '源码提交：%s\n' "$(git rev-parse HEAD)"
ARGS=(
  -project Yuedu-Reader.xcodeproj
  -scheme Yuedu-Reader
  -configuration Debug
  -destination 'generic/platform=iOS'
  -derivedDataPath "$PRIVATE/DerivedData"
  CODE_SIGNING_ALLOWED=NO
  CODE_SIGNING_REQUIRED=NO
  ONLY_ACTIVE_ARCH=NO
  ENABLE_DEBUG_DYLIB=NO
  # 保留 Debug 条件及 Crashlytics 的跳过逻辑，只优化机器码和调试信息。
  SWIFT_OPTIMIZATION_LEVEL=-Osize
  GCC_OPTIMIZATION_LEVEL=s
  DEAD_CODE_STRIPPING=YES
  MTL_ENABLE_DEBUG_INFO=NO
  SWIFT_REFLECTION_METADATA_LEVEL=all
  # 禁止 Xcode 提前 strip；独立打包阶段在签名前以 Darwin -S -x 去 debug/local，
  # 保留全部全局符号并逐项核验 Swift/ObjC/代码/导出信息。
  COPY_PHASE_STRIP=NO
  STRIP_INSTALLED_PRODUCT=NO
  STRIP_STYLE=debugging
  STRIP_SWIFT_SYMBOLS=NO
)
printf '%s\n' '正在解析依赖及读取构建设置；此步骤尚未完成编译。' >&3
xcodebuild "${ARGS[@]}" -showBuildSettings -json >"$PRIVATE/settings.json"
python3 scripts/prepare_trollstore_test.py locate "$PRIVATE/settings.json" "$PRIVATE/app-path.txt"
printf '%s\n' '正在进行完整 iOS 真机 Debug 配置编译（Swift -Osize / C -Os），编译错误将立即终止。' >&3
xcodebuild "${ARGS[@]}" build
printf '%s\n' '编译命令成功，开始复核 Mach-O、最低系统版本和嵌套签名。' >&3
python3 scripts/prepare_trollstore_test.py package "$PRIVATE/settings.json" "$PRIVATE/app-path.txt" "$OUT/Qingyun-1.0.1.ipa"
