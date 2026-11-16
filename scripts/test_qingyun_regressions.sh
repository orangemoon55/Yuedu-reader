#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
[[ "${GITHUB_ACTIONS:-}" == true && "$(uname -s)" == Darwin ]] || { echo '此检查需要云端 macOS 与 iOS 模拟器。' >&2; exit 1; }
PRIVATE="$(mktemp -d "${RUNNER_TEMP:-/tmp}/qingyun-tests.XXXXXX")"
export TROLLSTORE_PRIVATE_DIR="$PRIVATE"
mkdir -p trollstore-output
finish() {
  local status=$?
  trap - EXIT
  python3 scripts/prepare_trollstore_test.py redact "$PRIVATE/test.log" trollstore-output/regressions.log || true
  if [[ -f "$PRIVATE/result.xcresult/Info.plist" ]]; then
    ditto -c -k --norsrc --keepParent "$PRIVATE/result.xcresult" trollstore-output/regressions.xcresult.zip || true
  fi
  if [[ -n "${DEST:-}" ]]; then
    local container_path
    container_path="$(xcrun simctl get_app_container "${DEST#id=}" com.local.qingyun data 2>/dev/null || true)"
    for preview_root in "$container_path/Documents/qingyun-layout-preview" "$container_path/tmp/qingyun-layout-preview"; do
      if [[ -d "$preview_root" ]]; then
        mkdir -p trollstore-output/layout-preview
        ditto "$preview_root" trollstore-output/layout-preview
      fi
    done
  fi
  rm -f GoogleService-Info.plist
  rm -rf "$PRIVATE"
  exit "$status"
}
trap finish EXIT
: > "$PRIVATE/test.log"
python3 scripts/prepare_trollstore_test.py prepare >> "$PRIVATE/test.log" 2>&1
export DEVELOPER_DIR="$(python3 scripts/prepare_trollstore_test.py select-xcode)"
bash scripts/ensure_metal_toolchain.sh >> "$PRIVATE/test.log" 2>&1
DEST="$(bash scripts/sim.sh dest)"
echo '正在模拟器检查圆盘分区、章节定位和退出过渡。'
xcodebuild test -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader \
  -configuration Debug -destination "$DEST" -derivedDataPath "$PRIVATE/Tests" \
  -resultBundlePath "$PRIVATE/result.xcresult" -parallel-testing-enabled NO \
  -collect-test-diagnostics never CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  -only-testing:'yuedu appTests/BookshelfRingTests' \
  -only-testing:'yuedu appTests/BookshelfRingPresentationTests' \
  -only-testing:'yuedu appTests/BookshelfRingLayoutTests' \
  -only-testing:'yuedu appTests/BookshelfTangMirrorTests' \
  -only-testing:'yuedu appTests/QingyunNightCopperThemeTests' \
  -only-testing:'yuedu appTests/BookshelfDrawRecommendationTests' \
  -only-testing:'yuedu appTests/BookshelfRingDrawStateTests' \
  -only-testing:'yuedu appTests/DiscoverySourcePinsTests' \
  -only-testing:'yuedu appTests/OnlineCoverSourceSearchTests' \
  -only-testing:'yuedu appTests/ChapterListOrderTests' \
  -only-testing:'yuedu appTests/ReaderCardTransitionMathTests' \
  -only-testing:'yuedu appTests/ReaderNavigationOpeningGateTests' \
  -only-testing:'yuedu appTests/ReaderCardCloseFallbackTests' \
  -only-testing:'yuedu appTests/ReaderNavigationCoordinatorTests' \
  -only-testing:'yuedu appTests/ReaderSwipeUpExitMotionTests' \
  -only-testing:'yuedu appTests/ReaderQuickPanelNavigationTests' \
  -only-testing:'yuedu appTests/ReaderQuickPanelPresentationTests' \
  -only-testing:'yuedu appTests/ReaderQuickThemePanelLayoutTests' \
  -only-testing:'yuedu appTests/ReaderSettingsPublicationTests' \
  -only-testing:'yuedu appTests/DismissalSequencedPresentationTests' \
  -only-testing:'yuedu appTests/ReaderBarEditorRenderingTests' \
  -only-testing:'yuedu appTests/FloatingRootTabBarTests' \
  -only-testing:'yuedu appUITests/ReaderSettingsEntryUITests' \
  >> "$PRIVATE/test.log" 2>&1
python3 - "$PRIVATE/test.log" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text(errors='replace')
if '** TEST SUCCEEDED **' not in text:
    raise SystemExit('未读到完整测试成功标记，停止。')
for line in text.splitlines():
    if 'Test run with' in line or ' TEST SUCCEEDED ' in line:
        print(line)
PY
