#!/usr/bin/env bash
# 打一个可以上传到 TestFlight 的包。
#   ios/scripts/archive.sh            # 归档 + 导出 ipa 到 build/
#   ios/scripts/archive.sh --upload   # 顺便上传到 App Store Connect（需要 API 密钥，见下）
#
# 上传需要 App Store Connect API 密钥（一次性准备）：
#   1. App Store Connect ▸ 用户与访问 ▸ 集成 ▸ App Store Connect API，新建密钥，下载 AuthKey_XXXX.p8
#   2. 放到 ~/.appstoreconnect/private_keys/
#   3. export ASC_KEY_ID=XXXX ASC_ISSUER_ID=xxxxxxxx-xxxx-...
set -euo pipefail
cd "$(dirname "$0")/.."

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
BUILD_DIR="$PWD/build"
ARCHIVE="$BUILD_DIR/YzVibe.xcarchive"

command -v xcodegen >/dev/null || { echo "需要 xcodegen：brew install xcodegen"; exit 1; }
xcodegen generate

rm -rf "$ARCHIVE"
xcodebuild archive \
  -project YzVibe.xcodeproj -scheme YzVibe -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$ARCHIVE" \
  -allowProvisioningUpdates

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>export</string>
  <key>teamID</key><string>TRVTR5HQP8</string>
  <key>uploadSymbols</key><true/>
  <key>signingStyle</key><string>automatic</string>
</dict></plist>
PLIST

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
  -exportPath "$BUILD_DIR" -allowProvisioningUpdates

echo "已导出：$BUILD_DIR/YzVibe.ipa"

if [[ "${1:-}" == "--upload" ]]; then
  : "${ASC_KEY_ID:?需要 export ASC_KEY_ID=...}"
  : "${ASC_ISSUER_ID:?需要 export ASC_ISSUER_ID=...}"
  xcrun altool --upload-app -f "$BUILD_DIR/YzVibe.ipa" -t ios \
    --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
  echo "已上传，去 App Store Connect ▸ TestFlight 里等处理完成。"
fi
