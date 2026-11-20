#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APK_PATH="/data/data/com.termux/files/home/ai-web-browser-apk/out/app-release.apk"
PKG_NAME="pl.tomaszewski.aiweb"

if ! command -v adb >/dev/null 2>&1; then
  pkg install -y android-tools
fi

adb start-server
adb devices
adb install -r "$APK_PATH"
adb shell pm path "$PKG_NAME"
