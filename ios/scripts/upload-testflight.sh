#!/usr/bin/env bash
# Upload an existing archive using a shared App Store Connect team API key.
# ASC_KEY_ID=... ASC_ISSUER_ID=... bash ios/scripts/upload-testflight.sh path/to/App.xcarchive
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${ASC_KEY_ID:?Set ASC_KEY_ID to your App Store Connect API key ID}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID to your App Store Connect issuer ID}"
ARCHIVE="${1:?Pass an existing .xcarchive path; this script does not rebuild}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${ASC_KEY_ID}.p8}"
[[ -f "$ARCHIVE/Info.plist" ]] || { echo "Archive not found: $ARCHIVE" >&2; exit 1; }
[[ -f "$KEY_PATH" ]] || { echo "API key not found: $KEY_PATH" >&2; exit 1; }
openssl pkey -in "$KEY_PATH" -check -noout >/dev/null
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
EXPORT_PATH="${ASC_EXPORT_PATH:-${ARCHIVE%.xcarchive}-upload}"

echo "Uploading existing archive: $ARCHIVE"
xcodebuild -exportArchive \
  -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$SCRIPT_DIR/ExportOptions-TestFlight.plist" \
  -exportPath "$EXPORT_PATH" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$KEY_PATH" \
  -authenticationKeyID "$ASC_KEY_ID" \
  -authenticationKeyIssuerID "$ASC_ISSUER_ID"
echo "Upload completed. Check Apple processing and internal testing availability in App Store Connect."
