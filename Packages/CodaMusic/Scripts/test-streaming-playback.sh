#!/bin/bash
# Exercise iOS streaming playback and caching on the Mac host with muted output.
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_HARNESS="$(mktemp -d /tmp/coda-audio-deck.XXXXXX)"
trap 'rm -rf "$TASK_HARNESS"' EXIT
export TASK_ROOT TASK_HARNESS
python3 - <<'PY'
import os, pathlib, shutil
root = pathlib.Path(os.environ['TASK_ROOT'])
harness = pathlib.Path(os.environ['TASK_HARNESS'])
player = root / 'Sources/Coda/Core/Player'
sources = harness / 'Sources/DeckHarness'
shutil.copytree(player / 'Streaming', sources / 'Streaming')
for name in ('StreamingAudioCacheFile.swift', 'ByteRangePlanner.swift', 'FLACSeekTable.swift'):
    shutil.copy2(player / name, sources / name)
shutil.copytree(root / 'Tests/StreamingPlaybackTests', harness / 'Tests/DeckTests')
(harness / 'Package.swift').write_text('''// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "DeckHarness", platforms: [.macOS(.v15)], targets: [
    .target(name: "DeckHarness", swiftSettings: [.swiftLanguageMode(.v5), .define("CODA_STREAMING_TESTS")]),
    .testTarget(name: "DeckTests", dependencies: ["DeckHarness"], resources: [.copy("Fixtures")], swiftSettings: [.swiftLanguageMode(.v5)])
])
''')
PY
swift test --package-path "$TASK_HARNESS" --scratch-path /tmp/coda-audio-deck-build
