#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:33131}"
PKG_NAME="pl.tomaszewski.aiweb"
APK_OUT="$PROJ_DIR/out/app-release.apk"

if [ ! -f "$APK_OUT" ]; then
  APK_OUT="$(find "$PROJ_DIR/out" -maxdepth 3 -name "*.apk" | head -n 1 || true)"
fi

if [ -z "${APK_OUT:-}" ] || [ ! -f "$APK_OUT" ]; then
  echo "APK_NOT_FOUND w $PROJ_DIR/out"
  exit 1
fi

echo "APK_TARGET=$APK_OUT"
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb -s "$ADB_TARGET" wait-for-device
adb -s "$ADB_TARGET" install -r "$APK_OUT"
adb -s "$ADB_TARGET" shell am force-stop "$PKG_NAME"
adb -s "$ADB_TARGET" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 1

NEW_PID="$(adb -s "$ADB_TARGET" shell pidof "$PKG_NAME" 2>/dev/null | tr -d '\r' || true)"
echo "DEPLOY_OK=$PKG_NAME PID=${NEW_PID:-brak} TARGET=$ADB_TARGET"

if [ -x "$PROJ_DIR/bin/verify_apk.sh" ]; then
  "$PROJ_DIR/bin/verify_apk.sh" "$ADB_TARGET"
fi
