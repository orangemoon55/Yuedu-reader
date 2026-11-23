#!/usr/bin/env bash
# Fetches the open-source nodejs-mobile iOS framework the MD5 (CatVod) runner needs. It is not
# vendored into the repository (54 MB per slice): CI downloads it once per run and the packaging
# step embeds it into the app's Frameworks folder. The app re-signs it with the rest of the
# bundle; the Swift side loads it with dlopen, so a build without it still launches.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="$ROOT/Vendor/NodeMobile.xcframework"
URL="https://github.com/nodejs-mobile/nodejs-mobile/releases/download/v18.20.4/nodejs-mobile-v18.20.4-ios.zip"
SHA="8c5ca3a0d1e38de7f182a5642593e82593b820efd375a14b3ecafc4bcfee620e"

if [[ -d "$DEST/ios-arm64/NodeMobile.framework" ]]; then
  echo "NodeMobile framework already present."
  exit 0
fi

mkdir -p "$ROOT/Vendor"
ZIP="$ROOT/Vendor/nodejs-mobile-ios.zip"
echo "Downloading NodeMobile v18.20.4 for iOS…"
curl -fsSL --retry 3 --retry-delay 2 -o "$ZIP.download" "$URL"
ACTUAL="$(shasum -a 256 "$ZIP.download" | awk '{print $1}')"
if [[ "$ACTUAL" != "$SHA" ]]; then
  echo "NodeMobile zip checksum mismatch: $ACTUAL" >&2
  rm -f "$ZIP.download"
  exit 1
fi
mv "$ZIP.download" "$ZIP"
rm -rf "$ROOT/Vendor/nodejs-mobile-unpack"
unzip -q -o "$ZIP" -d "$ROOT/Vendor/nodejs-mobile-unpack"
mv "$ROOT/Vendor/nodejs-mobile-unpack/NodeMobile.xcframework" "$DEST"
rm -rf "$ROOT/Vendor/nodejs-mobile-unpack"
echo "NodeMobile framework ready at $DEST"
