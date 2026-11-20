#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$HOME/ai-web-browser-apk}"
RAW_TARGET="${2:-192.168.1.154:33177}"
PKG_NAME="pl.tomaszewski.aiweb"
MAIN_ACT="pl.tomaszewski.aiweb/.MainActivity"

cd "$PROJECT_DIR"

if [ -x "./gradlew" ]; then
  chmod +x ./gradlew
  ./gradlew --no-daemon assembleDebug
else
  gradle --no-daemon assembleDebug
fi

APK_PATH="$(find "$PROJECT_DIR" -path "*/build/outputs/apk/debug/*.apk" -type f | head -n 1)"
if [ -z "$APK_PATH" ] || [ ! -f "$APK_PATH" ]; then
  echo "ERR: Nie znaleziono zbudowanego pliku APK" >&2
  exit 1
fi

TARGET="$("$PROJECT_DIR/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"
adb -s "$TARGET" wait-for-device
adb -s "$TARGET" install -r -d "$APK_PATH"
adb -s "$TARGET" shell am force-stop "$PKG_NAME" >/dev/null 2>&1 || true
adb -s "$TARGET" shell am start -n "$MAIN_ACT" >/dev/null
sleep 1.5

PID_AI="$(adb -s "$TARGET" shell pidof "$PKG_NAME" | tr -d '\r' || true)"
echo "BUILD_STATUS=OK APK=$APK_PATH TARGET=$TARGET PID_AI=${PID_AI:-<none>}"
[ -n "$PID_AI" ] && adb -s "$TARGET" shell logcat -d --pid="$PID_AI" | grep -E "AiWebMainActivity|AndroidNative|E/|F/" | tail -n 15 || true
