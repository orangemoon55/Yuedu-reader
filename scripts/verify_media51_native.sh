#!/bin/sh
# Native acceptance only. Missing Xcode is an explicit failure, never a skipped pass.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$root"
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo 'BLOCKED: xcodebuild/iOS SDK unavailable; no Readcc native playback verdict.' >&2
    exit 69
fi
xcodebuild -resolvePackageDependencies -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader
exec bash scripts/xctest.sh -t 1200 -- \
    -only-testing:'yuedu appTests/NativeKSVideoKernelTests' \
    -only-testing:'yuedu appTests/CatVodPlaybackFlowTests' \
    -only-testing:'yuedu appTests/SourceImportPlanTests' \
    "$@"
