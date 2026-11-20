#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:33131}"
RUN_ID="${2:-44655894618}"
OUT_DIR="$PROJ_DIR/out"
CI_DIR="$OUT_DIR/ci_artifact"

rm -rf "$CI_DIR"
mkdir -p "$OUT_DIR" "$CI_DIR"

gh run watch "$RUN_ID" --exit-status
gh run download "$RUN_ID" -D "$CI_DIR"

NEW_APK="$(find "$CI_DIR" -name "*.apk" | head -n 1 || true)"

if [ -n "${NEW_APK:-}" ] && [ -f "$NEW_APK" ]; then
  rm -f "$OUT_DIR/app-release.apk"
  cp -f "$NEW_APK" "$OUT_DIR/app-release.apk"
  sha256sum "$OUT_DIR/app-release.apk"
  "$PROJ_DIR/bin/build_deploy.sh" "$ADB_TARGET"
else
  echo "CI_APK_NOT_FOUND w $CI_DIR"
  exit 1
fi
