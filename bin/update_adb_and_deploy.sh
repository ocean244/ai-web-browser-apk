#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
NEW_TARGET="${1:-192.168.1.154:36375}"
PKG_NAME="pl.tomaszewski.aiweb"
APK_OUT="$PROJ_DIR/out/app-release.apk"

for script in \
  "$PROJ_DIR/bin/install_and_snap.sh" \
  "$PROJ_DIR/bin/build_deploy.sh" \
  "$PROJ_DIR/bin/clean_log.sh" \
  "$PROJ_DIR/bin/run_clean_snapshot.sh" \
  "$PROJ_DIR/bin/deploy_latest_run.sh"
do
  if [ -f "$script" ]; then
    sed -i -E "s|192\.168\.1\.154:[0-9]+|${NEW_TARGET}|g" "$script"
  fi
done

echo "UPDATED_ADB_TARGET=${NEW_TARGET}"
adb disconnect >/dev/null 2>&1 || true
adb connect "$NEW_TARGET"
adb -s "$NEW_TARGET" wait-for-device

if [ ! -f "$APK_OUT" ]; then
  echo "APK_NOT_FOUND=$APK_OUT"
  exit 1
fi

adb -s "$NEW_TARGET" install -r "$APK_OUT"
adb -s "$NEW_TARGET" shell am force-stop "$PKG_NAME"
adb -s "$NEW_TARGET" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null
sleep 1

NEW_PID="$(adb -s "$NEW_TARGET" shell pidof "$PKG_NAME" 2>/dev/null | tr -d '\r' || true)"
echo "DEPLOYED PKG=$PKG_NAME PID=${NEW_PID:-brak} TARGET=$NEW_TARGET"

if [ -x "$PROJ_DIR/bin/run_clean_snapshot.sh" ]; then
  "$PROJ_DIR/bin/run_clean_snapshot.sh" "$NEW_TARGET"
fi
