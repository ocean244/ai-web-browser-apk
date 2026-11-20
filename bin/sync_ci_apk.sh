#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:33131}"
RUN_ID="${2:-44655328521}"
OUT_DIR="$PROJ_DIR/out"

mkdir -p "$OUT_DIR"
gh run watch "$RUN_ID" --exit-status
gh run download "$RUN_ID" -D "$OUT_DIR/ci_artifact"
NEW_APK="$(find "$OUT_DIR/ci_artifact" -name "*.apk" | head -n 1 || true)"

if [ -n "${NEW_APK:-}" ] && [ -f "$NEW_APK" ]; then
  cp -f "$NEW_APK" "$OUT_DIR/app-release.apk"
  sha256sum "$OUT_DIR/app-release.apk"
  "$PROJ_DIR/bin/build_deploy.sh" "$ADB_TARGET"
else
  echo "CI_APK_NOT_FOUND w $OUT_DIR/ci_artifact"
  exit 1
fi
