#!/bin/bash
# Read the literal shared settings without evaluating configuration as shell code.
CODA_IDENTITY_CONFIG="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/Config/AppIdentity.xcconfig"
coda_setting() {
  awk -v key="$1" '$1 == key && $2 == "=" { sub(/^[^=]*=[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$CODA_IDENTITY_CONFIG"
}
APP_NAME="$(coda_setting CODA_APP_NAME)"
BUNDLE_ID="$(coda_setting CODA_BUNDLE_IDENTIFIER)"
DEV_BUNDLE_ID="$BUNDLE_ID.dev"
REPO="$(coda_setting CODA_REPOSITORY)"
DEVELOPER_NAME="$(coda_setting CODA_DEVELOPER_NAME)"
