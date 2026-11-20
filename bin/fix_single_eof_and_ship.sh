#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_TARGET="${1:-192.168.1.154:41717}"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

mkdir -p "$OUT_DIR"
cd "$PROJ_DIR"

echo "=== 1. NAPRAWA KOŃCOWEJ KLAMRY W MAINACTIVITY.KT ==="
[ -f "$MAIN_KT" ] || { echo "ERR_MISSING_MAIN_KT=$MAIN_KT" >&2; exit 1; }

python3 - "$MAIN_KT" << 'PY'
import sys
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8").replace("\r\n", "\n").splitlines()

# Wyrównaj wcięcie 'fun loadTargetUrl(url: String) {' do 4 spacji
lines = [
    "    fun loadTargetUrl(url: String) {" if ln.strip() == "fun loadTargetUrl(url: String) {" else ln
    for ln in lines
]

# Jeśli na samym końcu pliku są co najmniej dwie linie zawierające wyłącznie '}', usuń ostatnią
while lines and lines[-1].strip() == "":
    lines.pop()
if len(lines) >= 2 and lines[-1].strip() == "}" and lines[-2].strip() == "}":
    lines.pop()

fixed = "\n".join(lines).rstrip() + "\n"
p.write_text(fixed, encoding="utf-8")
out_lines = fixed.splitlines()
print(f"MAIN_KT_EOF_CLEAN lines={len(out_lines)} last_line={out_lines[-1]!r}")
for i in range(max(0, len(out_lines) - 18), len(out_lines)):
    print(f"{i+1}: {out_lines[i]}")
PY

echo "=== 2. COMMIT I PUSH NA MAIN ==="
git add -A
if ! git diff --cached --quiet; then
  git commit -m "fix(aiweb): remove extra trailing closing brace in MainActivity.kt"
fi
git push origin main
TARGET_SHA="$(git rev-parse HEAD)"
echo "TARGET_SHA=$TARGET_SHA"

echo "=== 3. URUCHOMIENIE I OCZEKIWANIE NA BUILD-APK.YML ==="
gh workflow run "build-apk.yml" --ref main >/dev/null 2>&1 || true
sleep 4

RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId,headSha \
  --jq --arg sha "$TARGET_SHA" '[.[] | select(.headSha == $sha)][0].databaseId // empty' 2>/dev/null || true)"
if [ -z "${RUN_ID:-}" ]; then
  RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi
echo "WATCHING_RUN_ID=$RUN_ID"

while true; do
  META="$(gh run view "$RUN_ID" --json status,conclusion,headSha,url 2>/dev/null || echo '{}')"
  ST="$(printf '%s' "$META" | jq -r '.status // "unknown"')"
  CN="$(printf '%s' "$META" | jq -r '.conclusion // ""')"
  SH="$(printf '%s' "$META" | jq -r '.headSha // ""')"
  UR="$(printf '%s' "$META" | jq -r '.url // ""')"
  printf '[%s] RUN=%s SHA=%s STATUS=%s CONCLUSION=%s\n' "$(date '+%H:%M:%S')" "$RUN_ID" "${SH:0:7}" "$ST" "$CN"
  if [ "$ST" = "completed" ]; then
    echo "RUN_URL=$UR"
    break
  fi
  sleep 8
done

if [ "$CN" != "success" ]; then
  echo "BUILD_FAILED RUN_ID=$RUN_ID CONCLUSION=$CN"
  gh run view "$RUN_ID" --log-failed 2>/dev/null | grep -E "(^|\s)e:\s+file://|Could not find |FAILURE:|BUILD FAILED|Execution failed" | head -n 50 || true
  exit 1
fi

echo "=== 4. POBRANIE I INSTALACJA APK NA $ADB_TARGET ==="
APK_DIR="$OUT_DIR/apk_${RUN_ID}"
mkdir -p "$APK_DIR"
gh run download "$RUN_ID" -D "$APK_DIR" 2>/dev/null || true
APK_PATH="$(find "$APK_DIR" "$PROJ_DIR" -maxdepth 4 -name "*.apk" 2>/dev/null | head -n 1 || true)"
[ -n "$APK_PATH" ] && [ -f "$APK_PATH" ] || { echo "ERR_APK_NOT_FOUND RUN_ID=$RUN_ID" >&2; exit 1; }

echo "APK_PATH=$APK_PATH"
adb disconnect "$ADB_TARGET" >/dev/null 2>&1 || true
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb devices -l
adb -s "$ADB_TARGET" install -r "$APK_PATH"
adb -s "$ADB_TARGET" shell pm list packages | grep -iE "aiweb|tomaszewski" || true
echo "PIPELINE_100_OK RUN_ID=$RUN_ID ADB=$ADB_TARGET"
