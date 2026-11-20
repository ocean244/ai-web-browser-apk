#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APK_PATH="/data/data/com.termux/files/home/ai-web-browser-apk/out/app-release.apk"
PKG_NAME="pl.tomaszewski.aiweb"
DEBUG_PORT="${1:-}"
PAIR_ADDR="${2:-}"
PAIR_CODE="${3:-}"

if [ ! -f "$APK_PATH" ]; then
  echo "BRAK_APK=$APK_PATH" >&2
  exit 1
fi

if ! command -v adb >/dev/null 2>&1; then
  pkg install -y android-tools
fi

adb start-server

if [ -n "$PAIR_ADDR" ] && [ -n "$PAIR_CODE" ]; then
  adb pair "$PAIR_ADDR" "$PAIR_CODE"
fi

if [ -z "$DEBUG_PORT" ]; then
  DEBUG_PORT="$(ss -tulpn 2>/dev/null | awk '/adbd/ {print $5}' | sed 's/.*://' | head -n 1 || true)"
fi

if [ -n "$DEBUG_PORT" ]; then
  adb connect "127.0.0.1:${DEBUG_PORT}"
fi

adb devices
adb install -r "$APK_PATH"
adb shell pm path "$PKG_NAME"
