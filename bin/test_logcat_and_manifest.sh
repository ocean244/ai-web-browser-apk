#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

STATE_FILE="$HOME/.adb_aiweb_target"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out"
MANIFEST_XML="$PROJ_DIR/app/src/main/AndroidManifest.xml"
PKG="pl.tomaszewski.aiweb"
TEST_URL="${2:-https://example.com}"

mkdir -p "$OUT_DIR/backups"
cd "$PROJ_DIR"

if [ -f "$STATE_FILE" ]; then
  # Wczytaj ADB_TARGET jeśli nie podano jawnie w $1
  SAVED_TARGET="$(awk -F= '$1=="ADB_TARGET" {print $2}' "$STATE_FILE" | tr -d '\r' || true)"
else
  SAVED_TARGET=""
fi

ADB_TARGET="${1:-${SAVED_TARGET:-192.168.1.154:36529}}"
cat << STATE_EOF > "$STATE_FILE"
ADB_TARGET=$ADB_TARGET
LAST_TEST_URL=$TEST_URL
UPDATED_AT=$(date '+%Y-%m-%dT%H:%M:%S')
STATE_EOF

echo "=== 1. POŁĄCZENIE ADB ($ADB_TARGET) ==="
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb devices -l
ACTIVE_DEV="$(adb devices | awk -v t="$ADB_TARGET" 'NR>1 && $1==t && $2=="device" {print $1}' | head -n 1 || true)"
if [ -z "$ACTIVE_DEV" ]; then
  ACTIVE_DEV="$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -n 1 || true)"
fi
[ -n "$ACTIVE_DEV" ] || { echo "ERR_NO_ADB_DEVICE target=$ADB_TARGET" >&2; exit 1; }
echo "ACTIVE_DEVICE=$ACTIVE_DEV"

echo "=== 2. TEST URL I FUNKCJI W $PKG ($TEST_URL) ==="
adb -s "$ACTIVE_DEV" logcat -c >/dev/null 2>&1 || true
adb -s "$ACTIVE_DEV" shell am start -a android.intent.action.VIEW -d "$TEST_URL" "$PKG" >/dev/null 2>&1 || \
  adb -s "$ACTIVE_DEV" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 3

PID="$(adb -s "$ACTIVE_DEV" shell pidof "$PKG" 2>/dev/null | tr -d '\r\n ' || true)"
echo "APP_PID=${PID:-not_running}"
adb -s "$ACTIVE_DEV" shell dumpsys activity activities | grep -E "ResumedActivity|TopResumedActivity|$PKG" | head -n 10 || true

RAW_LOG="$OUT_DIR/logcat_${PKG}_$(date '+%Y%m%d_%H%M%S').txt"
adb -s "$ACTIVE_DEV" logcat -d -v time > "$RAW_LOG" 2>/dev/null || true

echo "=== 3. OCZYSZCZONY LOGCAT DLA $PKG I RUNTIME ==="
python3 - "$RAW_LOG" "$PKG" "$PID" << 'PY'
import re
import sys
from pathlib import Path

raw_bytes = Path(sys.argv[1]).read_bytes()
# Usuń bajty binarne / kontrolne poza TAB i LF
clean_text = re.sub(rb"[^\x09\x0a\x20-\x7e\xc0-\xff]", b" ", raw_bytes).decode("utf-8", errors="replace")
lines = clean_text.splitlines()

pkg = sys.argv[2]
pid = sys.argv[3]
keywords = ("aiweb", "tomaszewski", "webview", "chromium", "androidruntime", "activitymanager", "loadtargeturl")
if pid:
    keywords = keywords + (pid,)

matched = [ln for ln in lines if any(k in ln.lower() for k in keywords)]
print(f"TOTAL_LOG_LINES={len(lines)} MATCHED_LINES={len(matched)}")
for ln in matched[-60:]:
    print(ln)
PY

echo "=== 4. BEZPIECZNA ROZBUDOWA ANDROIDMANIFEST.XML ==="
if [ -f "$MANIFEST_XML" ]; then
  BACKUP_XML="$OUT_DIR/backups/AndroidManifest_$(date '+%Y%m%d_%H%M%S').xml"
  cp "$MANIFEST_XML" "$BACKUP_XML"
  echo "MANIFEST_BACKUP=$BACKUP_XML"
  python3 - "$MANIFEST_XML" << 'PY'
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

path = Path(sys.argv[1])
ANDROID_NS = "http://schemas.android.com/apk/res/android"
ET.register_namespace("android", ANDROID_NS)

tree = ET.parse(path)
root = tree.getroot()
app = root.find("application")
if app is not None:
    def set_android_attr(elem, name, val):
        key = f"{{{ANDROID_NS}}}{name}"
        if key not in elem.attrib:
            elem.set(key, val)

    set_android_attr(app, "usesCleartextTraffic", "true")
    set_android_attr(app, "hardwareAccelerated", "true")
    set_android_attr(app, "supportsRtl", "true")

tree.write(path, encoding="utf-8", xml_declaration=True)
print(f"MANIFEST_UPDATED={path}")
PY
else
  echo "INFO_NO_LOCAL_MANIFEST_AT=$MANIFEST_XML"
fi
