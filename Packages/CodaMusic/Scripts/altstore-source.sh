#!/usr/bin/env bash
# Generates the AltStore / SideStore source JSON for a release.
#
#   BUILD_NUMBER=<CFBundleVersion> \
#     Scripts/altstore-source.sh <version> <ipa-path> <notes.md> > dist/altstore.json
#
# The JSON is published as a release asset, so the URL users add to AltStore —
# .../releases/latest/download/altstore.json — is a permalink that always
# resolves to the newest release, the same trick Scripts/build-app.sh uses for
# the Sparkle feed. So users add the source once and AltStore picks up every
# later release on its own, which is why this file lists only the version being
# published.
#
# <ipa-path> must be the packaged IPA: the file's exact byte size goes into the
# source as the version's `size`, and AltStore holds the download to it. Both
# <version> and BUILD_NUMBER have to match the IPA's CFBundleShortVersionString
# and CFBundleVersion, so publishers pass the same values the build was made
# with (a mismatch makes AltStore offer an update the user already has).
#
# Field reference: https://faq.altstore.io/developers/make-a-source
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-}"
IPA="${2:-}"
NOTES="${3:-}"
if [ -z "$VERSION" ] || [ -z "$IPA" ] || [ -z "$NOTES" ]; then
  echo "usage: BUILD_NUMBER=<n> $(basename "$0") <version> <ipa-path> <notes.md>" >&2
  exit 1
fi
if [ -z "${BUILD_NUMBER:-}" ]; then
  echo "ERROR: set BUILD_NUMBER to the CFBundleVersion of the IPA" >&2
  echo "       (CI does this with git rev-list --count HEAD)" >&2
  exit 1
fi

[ -f "$IPA" ] || { echo "ERROR: no IPA at $IPA" >&2; exit 1; }
[ -s "$NOTES" ] || { echo "ERROR: release notes at $NOTES are missing or empty" >&2; exit 1; }

# The catalogue entry has to match the built app — AltStore checks the bundle
# identifier and hides versions the device cannot run — so read both from the
# file that defines them for the build rather than from a copy that can drift.
XCCONFIG="$ROOT/Sources/iOS&iPadOS/Config/Shared.xcconfig"
setting() { awk -F'[[:space:]=]+' -v key="$1" '$1 == key { print $2; exit }' "$XCCONFIG"; }
source "$ROOT/Scripts/app-identity.sh"
MIN_OS="$(setting IPHONEOS_DEPLOYMENT_TARGET)"
[ -n "$BUNDLE_ID" ] || { echo "ERROR: no PRODUCT_BUNDLE_IDENTIFIER in $XCCONFIG" >&2; exit 1; }
[ -n "$MIN_OS" ] || { echo "ERROR: no IPHONEOS_DEPLOYMENT_TARGET in $XCCONFIG" >&2; exit 1; }

REPO="${GITHUB_REPOSITORY:-$REPO}"
RELEASE_BASE="https://github.com/$REPO/releases/download/v$VERSION"
ICON_URL="https://raw.githubusercontent.com/$REPO/main/docs/assets/icon.png"
TINT="#EC4949" # Theme.accent — Sources/Coda/DesignSystem/Theme.swift
SIZE="$(wc -c < "$IPA" | tr -d '[:space:]')"
DATE="$(date -u +%Y-%m-%d)"

# Escape the release notes into a one-line JSON string. This walks the string
# instead of using gsub(): in a gsub() replacement a backslash is an escape in
# its own right, so the very character we are trying to emit needs a different
# number of source backslashes depending on the awk implementation.
NOTES_JSON="$(
  LC_ALL=C awk '
    function esc(s,   out, i, c) {
      out = ""
      for (i = 1; i <= length(s); i++) {
        c = substr(s, i, 1)
        if      (c == "\\") out = out "\\\\"
        else if (c == "\"") out = out "\\\""
        else if (c == "\t") out = out "\\t"
        else if (c == "\r") out = out "\\r"
        else                out = out c
      }
      return out
    }
    BEGIN { printf "\"" }
    { printf "%s%s", (NR > 1 ? "\\n" : ""), esc($0) }
    END { printf "\"" }
  ' "$NOTES"
)"

cat <<JSON
{
  "name": "Coda",
  "subtitle": "多平台原生音乐客户端 · Native music client",
  "description": "Coda 是独立维护的原生音乐客户端，支持网易云音乐、QQ 音乐、酷狗音乐与汽水音乐，各平台能力不同。iOS IPA 未签名，需通过适用的侧载签名工具安装。\n\nAn independently maintained native music client for NetEase Cloud Music, QQ Music, KuGou and Qishui. Service capabilities vary. The iOS IPA requires signing before installation.",
  "iconURL": "$ICON_URL",
  "website": "https://github.com/$REPO",
  "tintColor": "$TINT",
  "featuredApps": ["$BUNDLE_ID"],
  "apps": [
    {
      "name": "Coda",
      "bundleIdentifier": "$BUNDLE_ID",
      "developerName": "$DEVELOPER_NAME",
      "subtitle": "多平台原生音乐客户端 · Native music client",
      "localizedDescription": "原生播放、歌词、歌单与多平台账号管理，各音乐服务支持的功能不同。安装前需对 IPA 签名。\n\nNative playback, lyrics, playlists and multi-provider account management. Sign the IPA with an applicable sideloading tool before installation.",
      "iconURL": "$ICON_URL",
      "tintColor": "$TINT",
      "category": "entertainment",
      "versions": [
        {
          "version": "$VERSION",
          "buildVersion": "$BUILD_NUMBER",
          "marketingVersion": "$VERSION",
          "date": "$DATE",
          "localizedDescription": $NOTES_JSON,
          "downloadURL": "$RELEASE_BASE/$(basename "$IPA")",
          "size": $SIZE,
          "minOSVersion": "$MIN_OS"
        }
      ],
      "appPermissions": {
        "entitlements": [],
        "privacy": {}
      }
    }
  ]
}
JSON
