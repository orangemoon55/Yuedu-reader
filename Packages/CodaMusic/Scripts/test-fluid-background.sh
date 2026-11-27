#!/bin/bash
# Host-only checks of production artwork shader, appearance and beat envelopes.
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HARNESS_ROOT="$(mktemp -d /tmp/coda-background-tests.XXXXXX)"
trap 'rm -rf "$HARNESS_ROOT"' EXIT
mkdir -p "$HARNESS_ROOT/Sources/CodaCore" "$HARNESS_ROOT/Tests/CodaCoreTests"
cat > "$HARNESS_ROOT/Package.swift" <<'PACKAGE'
// swift-tools-version: 6.1
import PackageDescription
let package = Package(name: "CodaBackgroundChecks", platforms: [.macOS(.v15)], targets: [
    .target(name: "CodaCore", swiftSettings: [.swiftLanguageMode(.v5)]),
    .testTarget(name: "CodaCoreTests", dependencies: ["CodaCore"], swiftSettings: [.swiftLanguageMode(.v5)])
])
PACKAGE
for source in \
    Sources/Coda/Core/PlatformCompatibility.swift \
    Sources/Coda/Core/MainWindowVisibility.swift \
    Sources/Coda/Core/Player/AudioSpectrum.swift \
    Sources/Coda/DesignSystem/ArtworkPalette.swift \
    Sources/Coda/Features/Player/NowPlayingFluidBackground.swift; do
    cp "$PROJECT_ROOT/$source" "$HARNESS_ROOT/Sources/CodaCore/"
done
cp "$PROJECT_ROOT/Tests/CodaCoreTests/FluidBackgroundTests.swift" "$HARNESS_ROOT/Tests/CodaCoreTests/"
swift test --package-path "$HARNESS_ROOT"
