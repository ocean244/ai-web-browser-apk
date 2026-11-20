#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_SLUG="ocean244/ai-web-browser-apk"
OUT_DIR="$HOME/ai-web-browser-apk/out"
mkdir -p "$OUT_DIR"

LATEST_RUN_ID="$(gh run list --repo "$REPO_SLUG" --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
if [ -n "$LATEST_RUN_ID" ]; then
  gh run watch "$LATEST_RUN_ID" --repo "$REPO_SLUG" || true
fi

rm -f "$OUT_DIR"/*.apk
gh release download --repo "$REPO_SLUG" --pattern "*.apk" --dir "$OUT_DIR"

APK_FILE="$(find "$OUT_DIR" -maxdepth 1 -name '*.apk' | head -n 1)"
if [ -z "$APK_FILE" ]; then
  echo "ERROR: Nie pobrano żadnego pliku .apk do $OUT_DIR" >&2
  exit 1
fi

ls -lh "$APK_FILE"

if command -v adb >/dev/null 2>&1 && adb get-state >/dev/null 2>&1; then
  adb install -r "$APK_FILE"
  echo "ZAINSTALOWANO PRZEZ ADB: $APK_FILE"
elif command -v termux-open >/dev/null 2>&1; then
  termux-open "$APK_FILE"
  echo "WYWOŁANO INSTALATOR ANDROID (termux-open): $APK_FILE"
else
  cp "$APK_FILE" /sdcard/Download/ 2>/dev/null || true
  echo "SKOPIOWANO DO /sdcard/Download/: $(basename "$APK_FILE")"
fi
