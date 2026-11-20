#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

RUN_ID="${1:-44697347060}"
ADB_TARGET="${2:-192.168.1.154:41717}"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out/apk_${RUN_ID}"

mkdir -p "$OUT_DIR"
cd "$PROJ_DIR"

while true; do
  META="$(gh run view "$RUN_ID" --json status,conclusion,headSha,url 2>/dev/null || echo '{}')"
  ST="$(printf '%s' "$META" | jq -r '.status // "unknown"')"
  CN="$(printf '%s' "$META" | jq -r '.conclusion // ""')"
  SH="$(printf '%s' "$META" | jq -r '.headSha // ""')"
  UR="$(printf '%s' "$META" | jq -r '.url // ""')"
  printf '[%s] RUN=%s SHA=%s STATUS=%s CONCLUSION=%s\n' "$(date '+%H:%M:%S')" "$RUN_ID" "${SH:0:7}" "$ST" "$CN"
  if [ "$ST" = "completed" ]; then
    echo "RUN_URL=$UR"
    break
  fi
  sleep 7
done

if [ "$CN" != "success" ]; then
  echo "BUILD_FAILED RUN_ID=$RUN_ID CONCLUSION=$CN"
  gh run view "$RUN_ID" --log-failed 2>/dev/null | grep -E "(^|\s)e:\s+file://|Could not find |FAILURE:|BUILD FAILED|Execution failed" | head -n 50 || true
  exit 1
fi

gh run download "$RUN_ID" -D "$OUT_DIR" 2>/dev/null || true
APK_FILE="$(find "$OUT_DIR" "$PROJ_DIR" -maxdepth 4 -name "*.apk" 2>/dev/null | head -n 1 || true)"
[ -n "$APK_FILE" ] && [ -f "$APK_FILE" ] || { echo "ERR_APK_NOT_FOUND RUN_ID=$RUN_ID" >&2; exit 1; }
echo "APK_FILE=$APK_FILE"

adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
ACTIVE_DEV="$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | grep -F "$ADB_TARGET" || true)"
if [ -z "$ACTIVE_DEV" ]; then
  ACTIVE_DEV="$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -n 1 || true)"
fi
adb devices -l

[ -n "$ACTIVE_DEV" ] || { echo "ERR_NO_ACTIVE_ADB_DEVICE target=$ADB_TARGET" >&2; exit 1; }
echo "INSTALLING_ON=$ACTIVE_DEV"
adb -s "$ACTIVE_DEV" install -r "$APK_FILE"
adb -s "$ACTIVE_DEV" shell pm list packages | grep -iE "aiweb|tomaszewski" || true
echo "BUILD_AND_INSTALL_100_OK RUN_ID=$RUN_ID DEVICE=$ACTIVE_DEV"
