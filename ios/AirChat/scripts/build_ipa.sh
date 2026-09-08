#!/usr/bin/env bash
#
# build_ipa.sh — two build modes, because there is no Apple account involved by default.
#
#   ./scripts/build_ipa.sh
#         Release build with signing DISABLED → build/AirChat-unsigned.ipa.
#         This is the artifact for Sideloadly / AltStore / SideStore: they re-sign it
#         with the *recipient's* free Apple ID. A .ipa nobody can install yet is
#         normal here — Apple forbids pre-signed distribution outside its store.
#
#   ./scripts/build_ipa.sh --team TEAMID1234 [--device "Mihai's iPhone"]
#         Free-provisioning / signed build. With a team id it also produces
#         build/AirChat.xcarchive, which is what you drag into Transporter for
#         TestFlight (paid Apple Developer account required for upload only).
#
#   ./scripts/build_ipa.sh --sync-share
#         Same as default, then stages the result into AirChat/WebApp/share/ so an
#         iPhone host can hand the .ipa to friends over its hotspot.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
BUILD="$ROOT/build"
TEAM=""
DEVICE=""
SYNC_SHARE=0
ARCHIVE=0

while [ $# -gt 0 ]; do
  case "$1" in
    --team) TEAM="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --sync-share) SYNC_SHARE=1; shift ;;
    --archive) ARCHIVE=1; shift ;;
    -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

mkdir -p "$BUILD"
COMMON=(-project AirChat.xcodeproj -scheme AirChat -configuration Release
        -allowProvisioningUpdates -derivedDataPath "$BUILD/DerivedData")

if [ -n "$TEAM" ]; then
  COMMON+=(-destination "generic/platform=iOS" DEVELOPMENT_TEAM="$TEAM" CODE_SIGN_STYLE=Automatic)
else
  # No team: build everything unsigned. Provisioning is skipped entirely, which is
  # precisely what makes this work without an Apple Developer account.
  COMMON+=(-destination "generic/platform=iOS"
            CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" EXPANDED_CODE_SIGN_IDENTITY="")
fi

if [ "$ARCHIVE" = "1" ] && [ -n "$TEAM" ]; then
  echo "▶ archiving"
  xcodebuild "${COMMON[@]}" archive -archivePath "$BUILD/AirChat.xcarchive" \
    ${DEVICE:+"-destination"} ${DEVICE:+"platform=iOS,name=$DEVICE"}
  xcodebuild -exportArchive -archivePath "$BUILD/AirChat.xcarchive" \
    -exportPath "$BUILD" -allowProvisioningUpdates \
    -exportOptionsPlist <(cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>teamID</key><string>$TEAM</string>
  <key>uploadBitcode</key><false/>
  <key>compileBitcode</key><false/>
  <key>manifest</key><dict/>
</dict>
</plist>
PLIST
)
  echo "✓ $BUILD/AirChat.ipa  (upload to TestFlight with Transporter)"
  exit 0
fi

echo "▶ building (unsigned=${TEAM:+no}$([ -n "$TEAM" ] || echo yes))"
xcodebuild "${COMMON[@]}" build

APP="$BUILD/DerivedData/Build/Products/Release-iphoneos/AirChat.app"
[ -d "$APP" ] || APP="$(find "$BUILD/DerivedData/Build/Products" -maxdepth 2 -name 'AirChat.app' | head -1)"
[ -d "$APP" ] || { echo "build products not found under $BUILD/DerivedData" >&2; exit 1; }

echo "▶ packaging ipa"
STAGE="$BUILD/ipa-payload"
rm -rf "$STAGE"; mkdir -p "$STAGE/Payload"
cp -R "$APP" "$STAGE/Payload/"
[ -f "$STAGE/Payload/AirChat.app/embedded.mobileprovision" ] || \
  echo "  (no embedded.mobileprovision — expected for the unsigned flow)"
( cd "$STAGE" && zip -qry "$BUILD/AirChat-unsigned.ipa" Payload )
echo "✓ $BUILD/AirChat-unsigned.ipa ($(du -h "$BUILD/AirChat-unsigned.ipa" | cut -f1))"
echo "  → give this file to Sideloadly/AltStore on the target's computer, or put it"
echo "    in the host phone's share folder so friends can download it from the hotspot."

if [ "$SYNC_SHARE" = "1" ]; then
  AIRCHAT_IPA="$BUILD/AirChat-unsigned.ipa" "$ROOT/scripts/stage_artifacts.sh"
fi
