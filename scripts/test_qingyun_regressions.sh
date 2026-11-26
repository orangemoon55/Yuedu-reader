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
  if [[ -n "${MANGA_FIXTURE_PID:-}" ]]; then kill "$MANGA_FIXTURE_PID" 2>/dev/null || true; fi
  if [[ -f "$PRIVATE/manga-fixture.log" ]]; then
    cat "$PRIVATE/manga-fixture.log" >> "$PRIVATE/test.log"
  fi
  python3 scripts/prepare_trollstore_test.py redact "$PRIVATE/test.log" trollstore-output/regressions.log || true
  for suite in ipad phone; do
    if [[ -f "$PRIVATE/$suite-test.log" ]]; then
      python3 scripts/prepare_trollstore_test.py redact "$PRIVATE/$suite-test.log" \
        "trollstore-output/media51-$suite-test.log" || true
    fi
  done
  if [[ -f "$PRIVATE/media51-exit-status.txt" ]]; then
    cp "$PRIVATE/media51-exit-status.txt" trollstore-output/media51-exit-status.txt
  fi
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
if [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == media51 ]]; then
  # Run the wide-toolbar/sidebar suite on iPad; the separate crash pass below uses iPhone.
  DEST="$(bash scripts/sim.sh dest iPad)"
else
  DEST="$(bash scripts/sim.sh dest)"
fi
if [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == media51 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/NativeKSVideoKernelTests'
    -only-testing:'yuedu appTests/CatVodPlaybackFlowTests'
    -only-testing:'yuedu appTests/MusicImportServiceTests'
    -only-testing:'yuedu appTests/MusicPlayerPlaybackTests'
    -only-testing:'yuedu appTests/YingxiaMusicLyricsTests'
    -only-testing:'yuedu appTests/MusicOnlineLyricsTests'
    -only-testing:'yuedu appTests/MusicPlatformCatalogTests'
    -only-testing:'yuedu appTests/MusicSevenPlatformCatalogTests'
    -only-testing:'yuedu appTests/MediaHubVideoLayoutTests'
    -only-testing:'yuedu appTests/MusicPlaybackCapsuleTests'
    -only-testing:'yuedu appTests/YingxiaMusicQueueTests'
    -only-testing:'yuedu appTests/MusicJSSourceTests'
    -only-testing:'yuedu appTests/MusicCatalogTests'
    -only-testing:'yuedu appTests/ModuleMediaImportTests'
    -only-testing:'yuedu appTests/CatVodHTTPPlaybackTests'
    -only-testing:'yuedu appTests/MediaHubInteractionTests'
    -only-testing:'yuedu appTests/SourceImportPlanTests'
    -only-testing:'yuedu appTests/MediaTabMenuTests'
    -only-testing:'yuedu appTests/MediaHubPresentationTests'
    -only-testing:'yuedu appTests/MediaPreferencesTests'
    -only-testing:'yuedu appTests/RootTabCustomizationTests'
    -only-testing:'yuedu appTests/ReadccBackdropBlurTests'
    -only-testing:'yuedu appTests/VideoTransportTests'
    -only-testing:'yuedu appTests/CatVodContentTests'
    -only-testing:'yuedu appTests/MovieRatingTests'
    -only-testing:'yuedu appTests/TMDBClientTests'
    -only-testing:'yuedu appTests/CatVodHomeFlowTests'
    -only-testing:'yuedu appUITests/MediaTabToolbarUITests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == catvod-home ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/CatVodContentTests'
    -only-testing:'yuedu appTests/CatVodHomeFlowTests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc35 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/SourcePickerManagementTests'
    -only-testing:'yuedu appTests/SourcePickerLayoutTests'
    -only-testing:'yuedu appTests/IOS17SearchResultTableTests'
    -only-testing:'yuedu appTests/SearchResultsBottomInsetTests'
    -only-testing:'yuedu appTests/FloatingRootTabBarTests'
    -only-testing:'yuedu appTests/ReadccLegacyGlassTests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc33 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/VideoSeekTests'
    -only-testing:'yuedu appTests/VideoTransportTests'
    -only-testing:'yuedu appTests/VideoTimelineBarTests'
    -only-testing:'yuedu appTests/VideoHeroActionLayoutTests'
    -only-testing:'yuedu appTests/ReaderCompactTailTests'
    -only-testing:'yuedu appTests/ReaderTextAlignmentTests'
    -only-testing:'yuedu appTests/PlainTextParagraphFormattingTests'
    -only-testing:'yuedu appTests/BottomJustifyPaginationTests'
    -only-testing:'yuedu appTests/MangaCanvasLayoutTests'
    -only-testing:'yuedu appTests/FixedPageToolbarOfflineTests'
    -only-testing:'yuedu appTests/FixedPagePositionSaveTests'
    -only-testing:'yuedu appTests/DownloadLiveActivityPublicationTests'
    -only-testing:'yuedu appTests/DownloadLiveActivityStateTests'
    -only-testing:'yuedu appTests/DiscoveryScrollStabilityTests'
    -only-testing:'yuedu appTests/FixedPagePDFCropTests'
    -only-testing:'yuedu appTests/FixedPageZoomableScrollViewTests'
    -only-testing:'yuedu appTests/SourcePickerManagementTests'
    -only-testing:'yuedu appTests/SourcePickerLayoutTests'
    -only-testing:'yuedu appTests/DiscoverySourcePinsTests'
    -only-testing:'yuedu appTests/SourceDiscoverySelectionTests'
    -only-testing:'yuedu appTests/ReaderTOCEdgeNavigationTests'
    -only-testing:'yuedu appTests/ReadccGlassDesignTests'
    -only-testing:'yuedu appTests/ReadccLegacyGlassTests'
    -only-testing:'yuedu appTests/FloatingRootTabBarTests'
    -only-testing:'yuedu appTests/RootTabCustomizationTests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc32 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/ReaderTextAlignmentTests'
    -only-testing:'yuedu appTests/PlainTextParagraphFormattingTests'
    -only-testing:'yuedu appTests/ReaderRenderSettingsSnapshotTests'
    -only-testing:'yuedu appTests/ReaderRenderRefreshTests'
    -only-testing:'yuedu appTests/ReadingSettingsScopeTests'
    -only-testing:'yuedu appTests/BottomJustifyPaginationTests'
    -only-testing:'yuedu appTests/BrowserLayoutJustificationTests'
    -only-testing:'yuedu appTests/BrowserBottomJustifyEngineTests'
    -only-testing:'yuedu appTests/ReadccGlassDesignTests'
    -only-testing:'yuedu appUITests/ReaderSettingsEntryUITests/testParagraphAlignmentBelowBottomAndPersists'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc30 ]]; then
  python3 -u scripts/readcc_manga_offline_fixture.py > "$PRIVATE/manga-fixture.log" 2>&1 &
  MANGA_FIXTURE_PID=$!
  python3 - <<'PY'
import time, urllib.request
for attempt in range(40):
    try:
        with urllib.request.urlopen('http://localhost:18779/health', timeout=1) as r:
            assert r.status == 200
        break
    except Exception:
        time.sleep(0.1)
else:
    raise SystemExit('Synthetic manga loopback fixture did not start')
PY
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/FixedPagePositionSaveTests'
    -only-testing:'yuedu appTests/FixedPageNextChapterPrefetchTests'
    -only-testing:'yuedu appTests/FixedPageWebtoonAutoScrollTests'
    -only-testing:'yuedu appTests/FixedPageToolbarOfflineTests'
    -only-testing:'yuedu appTests/OfflineChapterStoreTests'
    -only-testing:'yuedu appTests/OfflineDownloadManagerTests'
    -only-testing:'yuedu appTests/OfflineDownloadTaskTests'
    -only-testing:'yuedu appTests/ReaderTOCEdgeNavigationTests'
    -only-testing:'yuedu appTests/ReaderTOCEdgeRenderingTests'
    -only-testing:'yuedu appTests/SourceToastLifecycleTests'
    -only-testing:'yuedu appTests/SourceMenuJSFailureRecoveryTests'
    -only-testing:'yuedu appTests/DiscoveryScrollStabilityTests'
    -only-testing:'yuedu appUITests/MangaOfflineCacheUITests/testCacheButtonOpensSelectionAndDownloadsSyntheticPages'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testCompactHeaderKeepsEqualReferenceButtonsAndSeparateFilterRow'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testSearchSourceHonorsSavedListLayout'
    -only-testing:'yuedu appTests/VideoHeroActionLayoutTests'
    -only-testing:'yuedu appTests/ReadccGlassDesignTests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc29 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/AndroidBitmapStripRuleTests'
    -only-testing:'yuedu appTests/FixedPageImageDecodeTests'
    -only-testing:'yuedu appTests/ImageDecodeResultStreamTests'
    -only-testing:'yuedu appTests/LegadoRuntimeContractTests'
    -only-testing:'yuedu appTests/LegadoJavaIOInteropTests'
    -only-testing:'yuedu appTests/ReaderTOCEdgeNavigationTests'
    -only-testing:'yuedu appTests/ReaderTOCEdgeRenderingTests'
    -only-testing:'yuedu appTests/FixedPageChapterListItemTests'
    -only-testing:'yuedu appTests/BookSourceFileExportTests'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc28 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/DiscoveryCategoryTests'
    -only-testing:'yuedu appTests/DiscoverySourceControlsTests'
    -only-testing:'yuedu appTests/DiscoveryScrollStabilityTests'
    -only-testing:'yuedu appTests/DiscoverySourcePinsTests'
    -only-testing:'yuedu appTests/LoginFormLayoutTests'
    -only-testing:'yuedu appTests/ReaderQuickPanelBackgroundTileTests'
    -only-testing:'yuedu appTests/FixedPageProcessorsTests'
    -only-testing:'yuedu appTests/FixedPageWebtoonLayoutTests'
    -only-testing:'yuedu appTests/FixedPagePositionSaveTests'
    -only-testing:'yuedu appTests/ChangeSourceTOCResolutionTests'
    -only-testing:'yuedu appTests/MangaContentPreservationTests'
    -only-testing:'yuedu appTests/SourceCallBackTests'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testUnlimitedCategoriesAndSettingsApply'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testSourcePickerPinAndReopen'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testTopFieldSubmitsCurrentSourceQueryWithoutSecondEntry'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testSearchFeedUsesCompactRankRows'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc25 || "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc26 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/DiscoveryScrollStabilityTests'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testSearchFeedUsesCompactRankRows'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testAggregateFiltersStayBelowCategoriesWithAndWithoutKeyboard'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testTopFieldSubmitsCurrentSourceQueryWithoutSecondEntry'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests/testSearchListDoesNotReturnToFirstBookAfterRepeatedUpwardScrolls'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc24 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/DiscoveryCategoryTests'
    -only-testing:'yuedu appTests/DiscoverySourceControlsTests'
    -only-testing:'yuedu appTests/DiscoveryScrollStabilityTests'
    -only-testing:'yuedu appTests/ReaderHotCommentPageLimitTests'
    -only-testing:'yuedu appTests/ReaderCommentRefreshTests'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests'
    -only-testing:'yuedu appUITests/HomeEditorUITests/testFirstTemplateTapShowsNewSectionForm'
    -only-testing:'yuedu appUITests/HomeEditorUITests/testPickerKeepsTheNewSectionForm'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc22 || "${QINGYUN_REGRESSION_SCOPE:-all}" == readcc23 ]]; then
  TEST_SELECTION=(
    -only-testing:'yuedu appTests/OriginalGenreSourcesTests'
    -only-testing:'yuedu appTests/OriginalGenreRuntimeTests'
    -only-testing:'yuedu appTests/ReadccGlassDesignTests'
    -only-testing:'yuedu appTests/DiscoverySourceControlsTests'
    -only-testing:'yuedu appTests/DiscoveryScrollStabilityTests'
    -only-testing:'yuedu appTests/DiscoveryCategoryTests'
    -only-testing:'yuedu appTests/RootTabCustomizationTests'
    -only-testing:'yuedu appTests/FloatingRootTabBarTests'
    -only-testing:'yuedu appTests/ReaderHotCommentPageLimitTests'
    -only-testing:'yuedu appTests/ReaderCommentRefreshTests'
    -only-testing:'yuedu appUITests/DiscoveryFiveCategoryUITests'
    -only-testing:'yuedu appUITests/HomeEditorUITests/testFirstTemplateTapShowsNewSectionForm'
    -only-testing:'yuedu appUITests/HomeEditorUITests/testPickerKeepsTheNewSectionForm'
  )
elif [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == reader-comments ]]; then
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
    -only-testing:'yuedu appTests/SourcePickerManagementTests'
    -only-testing:'yuedu appTests/SourcePickerLayoutTests'
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
# Resolve into this job's exact DerivedData before correcting the known upstream plist.
xcodebuild -resolvePackageDependencies -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader \
  -derivedDataPath "$PRIVATE/Tests" >> "$PRIVATE/test.log" 2>&1
python3 scripts/normalize_ksplayer_frameworks.py "$PRIVATE/Tests/SourcePackages" >> "$PRIVATE/test.log" 2>&1
if [[ "${QINGYUN_REGRESSION_SCOPE:-all}" == media51 ]]; then
  # Run both device-class suites even if the iPad suite fails. Preserve independent logs
  # and statuses; the aggregate status below still fails if either test command fails.
  set +e
  xcodebuild test -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader \
    -configuration Debug -destination "$DEST" -derivedDataPath "$PRIVATE/Tests" \
    -resultBundlePath "$PRIVATE/result.xcresult" -parallel-testing-enabled NO \
    -collect-test-diagnostics never -testLanguage zh-Hans -testRegion CN CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    "${TEST_SELECTION[@]}" > "$PRIVATE/ipad-test.log" 2>&1
  IPAD_STATUS=$?
  set -e
  printf '===== iPad media51 suite (exit %s) =====\n' "$IPAD_STATUS" >> "$PRIVATE/test.log"
  cat "$PRIVATE/ipad-test.log" >> "$PRIVATE/test.log"

  if PHONE_DEST="$(bash scripts/sim.sh dest iPhone)"; then
    set +e
    xcodebuild test -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader \
      -configuration Debug -destination "$PHONE_DEST" -derivedDataPath "$PRIVATE/Tests" \
      -resultBundlePath "$PRIVATE/phone-crash.xcresult" -parallel-testing-enabled NO \
      -collect-test-diagnostics never -testLanguage zh-Hans -testRegion CN \
      CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
      -only-testing:'yuedu appUITests/MediaMenuCrashUITests' > "$PRIVATE/phone-test.log" 2>&1
    PHONE_STATUS=$?
    set -e
  else
    PHONE_STATUS=$?
    printf 'iPhone simulator destination lookup failed (exit %s); phone suite was not launchable.\n' \
      "$PHONE_STATUS" > "$PRIVATE/phone-test.log"
  fi
  printf '===== iPhone MediaMenuCrashUITests (exit %s) =====\n' "$PHONE_STATUS" >> "$PRIVATE/test.log"
  cat "$PRIVATE/phone-test.log" >> "$PRIVATE/test.log"
  printf 'MEDIA51_IPAD_EXIT_STATUS=%s\nMEDIA51_IPHONE_EXIT_STATUS=%s\n' \
    "$IPAD_STATUS" "$PHONE_STATUS" > "$PRIVATE/media51-exit-status.txt"
  cat "$PRIVATE/media51-exit-status.txt" >> "$PRIVATE/test.log"
  if [[ "$IPAD_STATUS" -ne 0 || "$PHONE_STATUS" -ne 0 ]]; then
    echo 'media51 suites failed; both suite statuses and logs were retained.' >&2
    exit 1
  fi
  python3 - "$PRIVATE/ipad-test.log" "$PRIVATE/phone-test.log" <<'PY'
from pathlib import Path
import sys
for path in sys.argv[1:]:
    text = Path(path).read_text(errors='replace')
    if '** TEST SUCCEEDED **' not in text:
        raise SystemExit(f'missing successful test marker in {Path(path).name}')
    print(Path(path).name + ': ** TEST SUCCEEDED **')
PY
else
  xcodebuild test -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader \
    -configuration Debug -destination "$DEST" -derivedDataPath "$PRIVATE/Tests" \
    -resultBundlePath "$PRIVATE/result.xcresult" -parallel-testing-enabled NO \
    -collect-test-diagnostics never -testLanguage zh-Hans -testRegion CN CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    "${TEST_SELECTION[@]}" >> "$PRIVATE/test.log" 2>&1
fi
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
