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
    mkdir -p trollstore-output/layout-preview
    xcrun xcresulttool export attachments --path "$PRIVATE/result.xcresult" --output-path trollstore-output/layout-preview >/dev/null 2>&1 || true
    ditto -c -k --norsrc --keepParent "$PRIVATE/result.xcresult" trollstore-output/regressions.xcresult.zip || true
  fi
  if [[ -n "${DEST:-}" ]]; then
    local container_path
    container_path="$(xcrun simctl get_app_container "${DEST#id=}" "${TEST_BUNDLE_ID:-com.local.readcc}" data 2>/dev/null || true)"
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
if [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == reader-comments ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/ReaderHotCommentPageLimitTests'
    -only-testing:'yuedu appTests/ReaderCommentRefreshTests'
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/decorator()'
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/splice()'
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/paging()'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == settings-ui ]]; then
  TEST_SELECTION=(-only-testing:'yuedu appUITests/ReaderSettingsEntryUITests')
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == chapter-title ]]; then
  TEST_SELECTION=(-only-testing:'yuedu appTests/ReaderChapterTitlePresentationTests')
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == toc-pins ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/ReaderTOCEdgeNavigationTests'
    -only-testing:'yuedu appTests/ReaderTOCEdgeRenderingTests'
    -only-testing:'yuedu appTests/ChapterListOrderTests'
    -only-testing:'yuedu appTests/DiscoverySourcePinsTests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == ui-polish ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/FloatingRootTabBarTests'
    -only-testing:'yuedu appTests/ReaderMenuAppearanceTests'
    -only-testing:'yuedu appTests/ReaderQuickPanelNavigationTests'
    -only-testing:'yuedu appTests/ReaderQuickPanelPresentationTests'
    -only-testing:'yuedu appTests/ReaderQuickThemePanelLayoutTests'
    -only-testing:'yuedu appTests/ReaderQuickPanelRedesignTests'
    -only-testing:'yuedu appTests/ReaderQuickPanelBackgroundTileTests'
    -only-testing:'yuedu appTests/AccessibilityStepperTests/quickPanelFontSize()'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == discovery-glass ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/DiscoveryCategoryTests'
    -only-testing:'yuedu appTests/RootTabCustomizationTests'
    -only-testing:'yuedu appTests/CustomItemOrderTests'
    -only-testing:'yuedu appTests/FloatingRootTabBarTests'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == module-compat ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/commentsValidated()'
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/notesValidated()'
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/notes()'
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/moyueNestedTTLsExpireIndependently()'
    -only-testing:'yuedu appTests/ModuleScriptAndCommentsTests/nestedCacheDurationSchemaPaths()'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == ranked-home ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/HomeRankBehaviorTests'
    -only-testing:'yuedu appTests/HomeRankRecommendationTests'
    -only-testing:'yuedu appTests/HomeRankLoadingTests'
    -only-testing:'yuedu appTests/HomeRankNativeTests'
    -only-testing:'yuedu appTests/FloatingRootTabBarTests'
    -only-testing:'yuedu appTests/HomeSourceBookTests'
    -only-testing:'yuedu appTests/HomeModelTests'
    -only-testing:'yuedu appTests/HomeSectionEditorTests'
    -only-testing:'yuedu appTests/LayoutPreviewTests'
  )
else
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/HomeSourceBookTests'
    -only-testing:'yuedu appTests/HomeSectionTests'
    -only-testing:'yuedu appTests/LayoutPreviewTests'
    -only-testing:'yuedu appTests/HomeModelTests'
    -only-testing:'yuedu appTests/FloatingRootTabBarTests'
    -only-testing:'yuedu appTests/ReaderMenuAppearanceTests'
    -only-testing:'yuedu appTests/ReaderNightCopperBackgroundTests'
    -only-testing:'yuedu appTests/ReaderQuickPanelNavigationTests'
    -only-testing:'yuedu appTests/ReaderQuickPanelPresentationTests'
    -only-testing:'yuedu appTests/ReaderQuickThemePanelLayoutTests'
    -only-testing:'yuedu appTests/QingyunNightCopperThemeTests'
  )
fi
echo "正在验证范围：${QINGYUN_REGRESSION_SCOPE:-all}"
xcodebuild test -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader \
  -configuration Debug -destination "$DEST" -derivedDataPath "$PRIVATE/Tests" \
  -resultBundlePath "$PRIVATE/result.xcresult" -parallel-testing-enabled NO \
  -collect-test-diagnostics never -testLanguage zh-Hans -testRegion CN CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  "${TEST_SELECTION[@]}" >> "$PRIVATE/test.log" 2>&1
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
