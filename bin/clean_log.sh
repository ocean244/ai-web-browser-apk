#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PKG_NAME="pl.tomaszewski.aiweb"
ADB_TARGET="${1:-192.168.1.154:33131}"

adb connect "$ADB_TARGET" >/dev/null 2>&1 || true

APP_PID="$(adb -s "$ADB_TARGET" shell pidof "$PKG_NAME" 2>/dev/null | tr -d '\r' || true)"
if [ -z "$APP_PID" ]; then
  adb -s "$ADB_TARGET" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null
  sleep 1
  APP_PID="$(adb -s "$ADB_TARGET" shell pidof "$PKG_NAME" 2>/dev/null | tr -d '\r' || true)"
fi

echo "STREAMING_PID=${APP_PID:-brak} TARGET=$ADB_TARGET"

NOISE_FILTER="setRequestedFrameRate|InsetsState:|onStateChanged: host=pl\.tomaszewski\.aiweb|BLASTBufferQueue_Java|handleResized|reportDrawFinished|mWNT:|RoundedCornerOffset|getInterlacedFlag|setFrameRateCategory|Shader compilation failed|Pipeline create failed|libpenguin\.so|Unsupported mediaType|Unsupported mime"

if [ -n "$APP_PID" ]; then
  adb -s "$ADB_TARGET" logcat --pid="$APP_PID" -v time | grep -v -E "$NOISE_FILTER"
else
  adb -s "$ADB_TARGET" logcat -v time | grep -E "$PKG_NAME|AndroidRuntime|WebView" | grep -v -E "$NOISE_FILTER"
fi
