#!/bin/sh
# Current reading/music and film-removal acceptance only; retired video suites are not replayed.
# Missing Xcode is an explicit failure, never a skipped pass.
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$root"
if ! command -v xcodebuild >/dev/null 2>&1; then
    echo 'BLOCKED: xcodebuild/iOS SDK unavailable; no Readcc native playback verdict.' >&2
    exit 69
fi
xcodebuild -resolvePackageDependencies -project Yuedu-Reader.xcodeproj -scheme Yuedu-Reader
exec bash scripts/xctest.sh -t 1200 -- \
    -only-testing:'yuedu appTests/AddedFilmRemovalTests' \
    -only-testing:'yuedu appTests/RemovedVideoUIBoundaryTests' \
    -only-testing:'yuedu appTests/MusicImportServiceTests' \
    -only-testing:'yuedu appTests/MusicPlayerPlaybackTests' \
    -only-testing:'yuedu appTests/MediaHubPresentationTests' \
    -only-testing:'yuedu appTests/MediaTabMenuTests' \
    -only-testing:'yuedu appTests/YingxiaMusicQueueTests' \
    -only-testing:'yuedu appTests/MusicJSSourceTests' \
    -only-testing:'yuedu appTests/MediaHubInteractionTests' \
    -only-testing:'yuedu appTests/SourceImportPlanTests' \
    "$@"
