#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

APK_PATH="/data/data/com.termux/files/home/ai-web-browser-apk/out/app-release.apk"
PKG_NAME="pl.tomaszewski.aiweb"

if [ ! -f "$APK_PATH" ]; then
  echo "BRAK_APK=$APK_PATH" >&2
  exit 1
fi

ls -lh "$APK_PATH"
sha256sum "$APK_PATH"

if command -v apksigner >/dev/null 2>&1; then
  apksigner verify --verbose "$APK_PATH" || true
fi

if command -v pm >/dev/null 2>&1; then
  pm path "$PKG_NAME" || echo "PAKIET_NIEZAINSTALOWANY_LUB_BRAK_UPRAWNIEN_PM"
fi

termux-open "$APK_PATH"
echo "WYWOŁANO_PONOWNIE_INSTALATOR=$APK_PATH"
