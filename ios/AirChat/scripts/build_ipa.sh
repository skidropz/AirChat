#!/usr/bin/env bash
#
# Builds an unsigned AirChat.ipa for iOS. The result is meant to be signed with a free
# Apple ID via Sideloadly / AltStore / SideStore (or installed with TrollStore on old iOS).
#
#   ./ios/AirChat/scripts/build_ipa.sh    # → ios/AirChat/build/AirChat-unsigned.ipa
#
set -euo pipefail

cd "$(dirname "$0")/.."   # → ios/AirChat

CONFIGURATION="${CONFIGURATION:-Release}"
SCHEME="AirChat"
DERIVED="build/DerivedData"
OUTPUT_DIR="build"
IPA_NAME="AirChat-unsigned.ipa"

mkdir -p "$OUTPUT_DIR"

xcodebuild \
  -project AirChat.xcodeproj \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -sdk iphoneos \
  -derivedDataPath "$DERIVED" \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" \
  build

APP="$DERIVED/Build/Products/$CONFIGURATION-iphoneos/$SCHEME.app"

if [ ! -d "$APP" ]; then
  echo "error: $APP not found after build" >&2
  exit 1
fi

rm -rf "$OUTPUT_DIR/Payload"
mkdir -p "$OUTPUT_DIR/Payload"
cp -R "$APP" "$OUTPUT_DIR/Payload/"
(
  cd "$OUTPUT_DIR"
  rm -f "$IPA_NAME"
  zip -qry "$IPA_NAME" Payload
  rm -rf Payload
)

echo "Built $OUTPUT_DIR/$IPA_NAME"
