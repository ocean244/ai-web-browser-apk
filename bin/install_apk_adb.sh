#!/usr/bin/env bash
set -euo pipefail

APK_FILE="${1:-}"
RAW_TARGET="${2:-192.168.1.154}"
PKG_NAME="pl.tomaszewski.aiweb"
MAIN_ACT="pl.tomaszewski.aiweb/.MainActivity"

if [ -z "$APK_FILE" ]; then
  APK_FILE="$(find "$HOME/ai-web-browser-apk" -maxdepth 6 -name "*.apk" -type f 2>/dev/null | head -n 1 || true)"
fi

if [ -z "$APK_FILE" ] || [ ! -f "$APK_FILE" ]; then
  echo "ERR: Nie znaleziono pliku APK (przekaż ścieżkę jako 1. argument: install_apk_adb.sh /sciezka/do/app.apk)" >&2
  exit 1
fi

TARGET="$("$HOME/ai-web-browser-apk/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"
adb -s "$TARGET" wait-for-device
adb -s "$TARGET" install -r -d "$APK_FILE"
adb -s "$TARGET" shell am force-stop "$PKG_NAME" >/dev/null 2>&1 || true
adb -s "$TARGET" shell am start -n "$MAIN_ACT" >/dev/null
sleep 1.2

PID_AI="$(adb -s "$TARGET" shell pidof "$PKG_NAME" | tr -d '\r' || true)"
echo "DEPLOY_APK=OK APK=$APK_FILE TARGET=$TARGET PID_AI=${PID_AI:-<none>}"
