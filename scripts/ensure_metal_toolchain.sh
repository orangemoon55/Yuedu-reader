#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$(uname -s)" == Darwin ]] || { echo 'Metal预检必须在macOS执行。' >&2; exit 1; }
CHECK_DIR="$(mktemp -d "${RUNNER_TEMP:-/tmp}/qingyun-metal.XXXXXX")"
trap 'rm -rf "$CHECK_DIR"' EXIT
# xcrun may find only a shim even when the downloadable component is absent.
# Compile a real kernel for both targets instead of checking path existence.
printf '%s\n' '#include <metal_stdlib>' 'using namespace metal;' 'kernel void qingyun_probe(device float *p [[buffer(0)]], uint i [[thread_position_in_grid]]) { p[i] = 0; }' > "$CHECK_DIR/probe.metal"
probe() {
  xcrun --sdk iphoneos metal -c -target air64-apple-ios17.0 "$CHECK_DIR/probe.metal" -o "$CHECK_DIR/device.air" &&
  xcrun --sdk iphonesimulator metal -c -target air64-apple-ios17.0-simulator "$CHECK_DIR/probe.metal" -o "$CHECK_DIR/simulator.air"
}
if ! probe > "$CHECK_DIR/probe.log" 2>&1; then
  cat "$CHECK_DIR/probe.log"
  echo '当前Xcode的Metal组件不可用，安装官方Metal Toolchain。'
  xcodebuild -downloadComponent MetalToolchain
  probe
fi
echo 'Metal真机与模拟器实际编译预检通过。'
