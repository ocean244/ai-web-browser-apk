#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PKG_NAME="pl.tomaszewski.aiweb"
ADB_TARGET="${1:-192.168.1.154:33131}"

adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb -s "$ADB_TARGET" wait-for-device

PKG_OK=0
for attempt in 1 2 3 4 5; do
  OUT="$(adb -s "$ADB_TARGET" shell "cmd package path $PKG_NAME" 2>&1 | tr -d '\r' || true)"
  if echo "$OUT" | grep -q "package:"; then
    echo "$OUT"
    PKG_OK=1
    break
  fi
  if echo "$OUT" | grep -q "Failed transaction"; then
    sleep 1
    continue
  fi
  break
done

if [ "$PKG_OK" -eq 0 ]; then
  DUMP_OUT="$(adb -s "$ADB_TARGET" shell "dumpsys package $PKG_NAME" 2>/dev/null | grep -E "Package \[$PKG_NAME\]|versionCode=|codePath=" | head -n 5 | tr -d '\r' || true)"
  if [ -n "$DUMP_OUT" ]; then
    echo "$DUMP_OUT"
    PKG_OK=1
  fi
fi

PID_NOW="$(adb -s "$ADB_TARGET" shell "pidof $PKG_NAME" 2>/dev/null | tr -d '\r' || true)"
echo "RUNTIME_PID=${PID_NOW:-brak}"

if [ "$PKG_OK" -eq 0 ] && [ -z "$PID_NOW" ]; then
  echo "PAKIET_NIEZAINSTALOWANY_LUB_BRAK_UPRAWNIEN_PM"
  exit 1
fi
