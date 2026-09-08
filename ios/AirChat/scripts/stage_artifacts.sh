#!/usr/bin/env bash
#
# stage_artifacts.sh — puts the installable artifacts into the iOS app bundle so an
# iPhone host can hand them out over its own hotspot, exactly like the Android app
# streams its .apk from /download-app.
#
# What ends up in AirChat/WebApp/share/ (served by GET /download-app/<file>):
#   AirChat.apk                <- your release build, for Android friends
#   AirChat-unsigned.ipa       <- the CI artifact, for iPhone friends to self-sign
#   INSTALL.txt                <- the same guide the /install.html page shows
#
# Nothing is committed to git (see .gitignore) — the share folder is populated right
# before a build, and an iOS build without it is still a fully working chat host.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO="$(cd "$ROOT/../.." && pwd)"
DEST="$ROOT/AirChat/WebApp/share"
mkdir -p "$DEST"

# --- Android APK (optional) --------------------------------------------------
APK=""
for candidate in \
  "$REPO/app/build/outputs/apk/release/app-release.apk" \
  "$REPO/app/build/outputs/apk/debug/app-debug.apk" \
  "${AIRCHAT_APK:-}"
do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then APK="$candidate"; break; fi
done

if [ -n "$APK" ]; then
  cp "$APK" "$DEST/AirChat.apk"
  echo "staged $(basename "$APK") -> share/AirChat.apk ($(du -h "$DEST/AirChat.apk" | cut -f1))"
else
  echo "no Android APK found (build one with ./gradlew assembleRelease, or set AIRCHAT_APK=/path/app.apk)"
fi

# --- Unsigned iOS IPA (optional) ---------------------------------------------
for candidate in \
  "${AIRCHAT_IPA:-}" \
  "$ROOT/build/AirChat-unsigned.ipa" \
  "./AirChat-unsigned.ipa"
do
  if [ -n "$candidate" ] && [ -f "$candidate" ]; then
    cp "$candidate" "$DEST/AirChat-unsigned.ipa"
    echo "staged $candidate -> share/AirChat-unsigned.ipa"
    break
  fi
done

# --- Guide text served as a plain file too -----------------------------------
cat > "$DEST/INSTALL.txt" <<'TXT'
AirChat for iOS — install without a paid Apple developer account
=================================================================

Why not the App Store? AirChat self-hosts a server and keeps itself alive in the
background with a silent audio session; that combination does not survive App Store
review, so it is distributed directly. Why not TestFlight? TestFlight uploads require
the $99/yr Apple Developer Program. Both of the following need no paid account.

A) Sideloadly (Windows or macOS) — easiest
   1. Install Sideloadly.
   2. Drag AirChat-unsigned.ipa onto it.
   3. Enter your (free) Apple ID when asked; it signs the app with a personal
      certificate and installs over USB.
   4. On the iPhone: Settings > General > VPN & Device Management > tap your Apple ID
      > Trust. Re-run step 3 every 7 days (free certs expire).

B) SideStore (self-refreshing, no computer after setup) or AltStore
   1. Install AltServer (or SideStore's companion) on a computer once.
   2. Install SideStore/AltStore on the phone with your free Apple ID.
   3. Add this phone's own /download-app URL as a source, or drop the .ipa in
      ~/Library/AltStore/Apps on the Mac to publish it.
   4. AltStore/SideStore re-sign every ~24h while on the same network, so the 7-day
      clock never runs out. Limits of a free Apple ID: 3 sideloaded apps, 10 new app
      IDs per week, no push notifications (AirChat needs none).

C) You have Xcode and the device at hand (no account at all)
   1. Open ios/AirChat/AirChat.xcodeproj.
   2. Signing & Capabilities: Team = "No Account"/your personal team, change the
      bundle id if it collides.
   3. Select the iPhone, then Run. First launch needs the device trusted + the app
      trusted (steps as in A.4).

If someone in your group does have a paid developer account, `scripts/build_ipa.sh
--archive` produces an archive you can drop into App Store Connect → TestFlight, and
the internal testers never need a computer.
TXT

echo "share folder: $DEST"
ls -la "$DEST"
