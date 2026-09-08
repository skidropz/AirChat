#!/usr/bin/env bash
#
# sync_web_assets.sh — keeps ios/AirChat/AirChat/WebApp in step with the Android
# app's assets/, which is the single source of truth for the chat UI (index.html,
# app.js, style.css, manifest.json, sw.js, airchat-bridge.js).
#
# The Xcode target runs this as its first build phase, so the iOS app can never drift
# away from the Android one. The files are also committed, which means:
#   * the repo stays clonable + buildable without running anything first,
#   * `git diff` shows cross-platform changes to the shared UI,
#   * a conflict in app.js is resolved once, for both platforms.
#
# Anything under WebApp/share/ is left alone (that is where stage_artifacts.sh puts
# the APK / unsigned IPA the host phones serve to their friends).
set -euo pipefail

SRCROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SRCROOT_DIR/../.." && pwd)"
ASSETS="$REPO_ROOT/app/src/main/assets"
DEST="$SRCROOT_DIR/AirChat/WebApp"

if [ ! -d "$ASSETS" ]; then
  echo "sync_web_assets: $ASSETS not found — keeping the committed copy." >&2
  exit 0
fi

FILES=(index.html app.js style.css manifest.json sw.js airchat-bridge.js install.html)

mkdir -p "$DEST"
changed=0
for f in "${FILES[@]}"; do
  if [ -f "$ASSETS/$f" ]; then
    if [ ! -f "$DEST/$f" ] || ! cmp -s "$ASSETS/$f" "$DEST/$f"; then
      cp "$ASSETS/$f" "$DEST/$f"
      echo "sync_web_assets: updated $f"
      changed=1
    fi
  fi
done

# Files that only exist on one platform must not be copied blindly.
for stale in "$DEST"/*.png "$DEST"/airchat.p12; do
  [ -e "$stale" ] && rm -f "$stale"
done

[ "$changed" = "0" ] && echo "sync_web_assets: WebApp already in sync."
exit 0
