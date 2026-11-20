#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PKG_NAME="pl.tomaszewski.aiweb"
ADB_TARGET="${1:-192.168.1.154:33131}"

adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb -s "$ADB_TARGET" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1
sleep 1
adb -s "$ADB_TARGET" shell dumpsys activity activities | grep -E "mResumedActivity|topResumedActivity|$PKG_NAME" || true

APP_PID="$(adb -s "$ADB_TARGET" shell pidof "$PKG_NAME" 2>/dev/null | tr -d '\r' || true)"
echo "APP_PID=${APP_PID:-brak}"
if [ -n "$APP_PID" ]; then
  adb -s "$ADB_TARGET" logcat --pid="$APP_PID" -v time
else
  adb -s "$ADB_TARGET" logcat -v time | grep -E "$PKG_NAME|AndroidRuntime|WebView"
fi
