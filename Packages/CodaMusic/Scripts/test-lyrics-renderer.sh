#!/bin/bash
# Host-only tests of the actual typography/timing sources, independent of
# unrelated application test targets. Never invokes iOS automation.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS_ROOT="$(mktemp -d /tmp/coda-lyrics-tests.XXXXXX)"
trap 'rm -rf "$HARNESS_ROOT"' EXIT
mkdir -p "$HARNESS_ROOT/Sources/CodaCore" "$HARNESS_ROOT/Tests/CodaCoreTests"
cat > "$HARNESS_ROOT/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "CodaLyricsChecks", platforms: [.macOS(.v15)], targets: [
    .target(name: "CodaCore", swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "CodaCoreTests", dependencies: ["CodaCore"], swiftSettings: [.swiftLanguageMode(.v5)])
])
PACKAGE
for source in \
    Sources/Coda/Core/PlatformCompatibility.swift \
    Sources/Coda/DesignSystem/RubyText.swift \
    Sources/Coda/Features/Player/KaraokeGlyphRenderer.swift \
    Sources/Coda/Core/Player/Lyrics/LyricModels.swift \
    Sources/Coda/Core/Player/Lyrics/LyricTimingTextAttribute.swift \
    Sources/Coda/Core/Player/Lyrics/TimedLyricTextBuilder.swift \
    Sources/Coda/Core/Player/Lyrics/LyricWordSegmenter.swift \
    Sources/Coda/Core/Player/Lyrics/LyricLongToneEmphasis.swift \
    Sources/Coda/Core/Player/Lyrics/LyricHighlightRevealProgress.swift; do
    cp "$PROJECT_ROOT/$source" "$HARNESS_ROOT/Sources/CodaCore/"
done
# Use the production model declarations without the API/parser dependencies.
python3 - "$PROJECT_ROOT" "$HARNESS_ROOT" <<'PY'
import pathlib, sys
root, harness = map(pathlib.Path, sys.argv[1:])
models = (root / 'Sources/Coda/Core/Models/LyricsParser.swift').read_text().split('struct ParsedLyrics:')[0]
ruby = (root / 'Sources/Coda/Core/Models/Furigana/RubyAligner.swift').read_text().split('/// Splits a word')[0]
(harness / 'Sources/CodaCore/Models.swift').write_text(models + '\n' + ruby)
PY
cp "$PROJECT_ROOT/Tests/CodaCoreTests/KaraokeGlyphVisualStateTests.swift" "$HARNESS_ROOT/Tests/CodaCoreTests/"
cp "$PROJECT_ROOT/Tests/CodaCoreTests/KaraokeGlyphRendererTests.swift" "$HARNESS_ROOT/Tests/CodaCoreTests/"
swift test --package-path "$HARNESS_ROOT"
