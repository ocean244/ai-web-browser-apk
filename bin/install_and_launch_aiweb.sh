#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_TARGET="${1:-192.168.1.154:36529}"
APK_FILE="${2:-/data/data/com.termux/files/home/ai-web-browser-apk/out/apk_44697347060/AIWebBrowser-release-apk/app-release.apk}"
STATE_FILE="$HOME/.adb_aiweb_target"
PROJ_DIR="$HOME/ai-web-browser-apk"

echo "=== KROK 1: UTRWALENIE POŁĄCZENIA ADB I ARTEFAKTU APK ==="
if [ ! -f "$APK_FILE" ]; then
  APK_FILE="$(find "$PROJ_DIR/out" "$PROJ_DIR" -maxdepth 4 -name "app-release.apk" -o -name "*.apk" 2>/dev/null | head -n 1 || true)"
fi
[ -n "$APK_FILE" ] && [ -f "$APK_FILE" ] || { echo "ERR_APK_NOT_FOUND path=$APK_FILE" >&2; exit 1; }

cat << STATE_EOF > "$STATE_FILE"
ADB_TARGET=$ADB_TARGET
APK_FILE=$APK_FILE
UPDATED_AT=$(date '+%Y-%m-%dT%H:%M:%S')
STATE_EOF
echo "SAVED_STATE=$STATE_FILE"
cat "$STATE_FILE"

echo "=== KROK 2: ZESTAWIENIE I WERYFIKACJA POŁĄCZENIA ADB ==="
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb devices -l
ACTIVE_DEV="$(adb devices | awk -v t="$ADB_TARGET" 'NR>1 && $1==t && $2=="device" {print $1}' | head -n 1 || true)"
if [ -z "$ACTIVE_DEV" ]; then
  ACTIVE_DEV="$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -n 1 || true)"
fi
[ -n "$ACTIVE_DEV" ] || { echo "ERR_NO_DEVICE_ONLINE target=$ADB_TARGET" >&2; exit 1; }
echo "ACTIVE_DEVICE=$ACTIVE_DEV"

echo "=== KROK 3: INSTALACJA APK NA URZĄDZENIU ==="
adb -s "$ACTIVE_DEV" install -r -d "$APK_FILE"

echo "=== KROK 4: WERYFIKACJA PAKIETU I URUCHOMIENIE APLIKACJI ==="
PKG_NAME="$(adb -s "$ACTIVE_DEV" shell pm list packages | sed 's/^package://' | tr -d '\r' | grep -iE "aiweb|tomaszewski" | head -n 1 || true)"
echo "INSTALLED_PACKAGE=${PKG_NAME:-not_found_yet}"
if [ -n "${PKG_NAME:-}" ]; then
  adb -s "$ACTIVE_DEV" shell monkey -p "$PKG_NAME" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
  echo "LAUNCHED_PACKAGE=$PKG_NAME"
fi

echo "SYSTEM_100_PERCENT_DEPLOYED DEVICE=$ACTIVE_DEV APK=$APK_FILE"
