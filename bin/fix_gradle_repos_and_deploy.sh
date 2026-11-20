#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

STATE_FILE="$HOME/.adb_aiweb_target"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out"
PKG="pl.tomaszewski.aiweb"
TEST_URL="${2:-https://example.com}"

mkdir -p "$OUT_DIR/backups"
cd "$PROJ_DIR"

SAVED_TARGET=""
if [ -f "$STATE_FILE" ]; then
  SAVED_TARGET="$(awk -F= '$1=="ADB_TARGET" {print $2}' "$STATE_FILE" | tr -d '\r' || true)"
fi
ADB_TARGET="${1:-${SAVED_TARGET:-192.168.1.154:36529}}"

echo "=== 1. DIAGNOSTYKA I NAPRAWA GRADLE / WORKFLOW REPOZYTORIÓW ==="
python3 - "$PROJ_DIR" << 'PY'
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])

# 1. Naprawa gradle.properties (wyłączenie offline)
gp = root / "gradle.properties"
if gp.exists():
    txt = gp.read_text(encoding="utf-8", errors="replace")
    new_lines = []
    changed = False
    for ln in txt.splitlines():
        if re.match(r"^\s*org\.gradle\.offline\s*=\s*true\s*$", ln):
            new_lines.append("org.gradle.offline=false")
            changed = True
        else:
            new_lines.append(ln)
    if changed:
        gp.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
        print("FIXED_GRADLE_PROPERTIES_OFFLINE=true")

# 2. Sprawdzenie i uzupełnienie google() oraz mavenCentral() w settings.gradle* i build.gradle*
for pattern in ("settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts"):
    f = root / pattern
    if f.exists():
        txt = f.read_text(encoding="utf-8", errors="replace")
        orig = txt
        txt = re.sub(r"--offline\b", "", txt)
        if "repositories" in txt:
            if "google()" not in txt:
                txt = re.sub(r"(repositories\s*\{)", r"\1\n        google()", txt, count=1)
            if "mavenCentral()" not in txt:
                txt = re.sub(r"(repositories\s*\{)", r"\1\n        mavenCentral()", txt, count=1)
        if txt != orig:
            f.write_text(txt, encoding="utf-8")
            print(f"UPDATED_GRADLE_FILE={f}")

# 3. Sprawdzenie workflow w .github/workflows/*.yml pod kątem --offline
wf_dir = root / ".github" / "workflows"
if wf_dir.is_dir():
    for yml in wf_dir.glob("*.yml"):
        txt = yml.read_text(encoding="utf-8", errors="replace")
        if "--offline" in txt:
            yml.write_text(txt.replace(" --offline", "").replace("--offline", ""), encoding="utf-8")
            print(f"REMOVED_OFFLINE_FLAG_IN_WORKFLOW={yml}")
PY

echo "=== 2. AKTUALIZACJA .GITIGNORE DLA KATALOGU OUT/ ==="
GITIGNORE="$PROJ_DIR/.gitignore"
touch "$GITIGNORE"
grep -qxF "out/" "$GITIGNORE" || echo "out/" >> "$GITIGNORE"

echo "=== 3. COMMIT I PUSH POPRAWKI DO REPOZYTORIUM ==="
git status --short
if ! git diff --quiet || [ -n "$(git ls-files --others --exclude-standard)" ]; then
  git add -A
  git commit -m "fix: ensure online repositories and clean gradle resolution in CI"
  git push origin main
else
  echo "NO_NEW_CHANGES_PUSHING_HEAD"
  git push origin main || true
fi

HEAD_SHA="$(git rev-parse HEAD)"
echo "TARGET_HEAD_SHA=$HEAD_SHA"

echo "=== 4. OCZEKIWANIE NA BUDOWANIE APK W GITHUB ACTIONS ==="
RUN_ID=""
for _ in $(seq 1 20); do
  RUN_ID="$(gh run list --branch main --limit 5 --json databaseId,headSha,status,conclusion \
    | jq -r --arg sha "$HEAD_SHA" '.[] | select(.headSha == $sha) | .databaseId' | head -n 1 || true)"
  if [ -n "$RUN_ID" ]; then
    break
  fi
  sleep 4
done
if [ -z "$RUN_ID" ]; then
  RUN_ID="$(gh run list --branch main --limit 1 --json databaseId --jq '.[0].databaseId // empty')"
fi
[ -n "$RUN_ID" ] || { echo "ERR_NO_GH_RUN_FOUND" >&2; exit 1; }
echo "MONITORING_RUN_ID=$RUN_ID"

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
  sleep 7
done

if [ "$CN" != "success" ]; then
  echo "BUILD_FAILED RUN_ID=$RUN_ID CONCLUSION=$CN"
  gh run view "$RUN_ID" --log-failed 2>/dev/null | grep -E "(^|\s)e:\s+file://|Could not find |FAILURE:|BUILD FAILED|Execution failed" | head -n 50 || true
  exit 1
fi

echo "=== 5. POBRANIE APK, INSTALACJA NA $ADB_TARGET I TEST NA ŻYWO ==="
APK_OUT_DIR="$OUT_DIR/apk_${RUN_ID}"
mkdir -p "$APK_OUT_DIR"
gh run download "$RUN_ID" -D "$APK_OUT_DIR" >/dev/null 2>&1 || true
APK_FILE="$(find "$APK_OUT_DIR" "$PROJ_DIR" -maxdepth 4 -name "*.apk" 2>/dev/null | head -n 1 || true)"
[ -n "$APK_FILE" ] && [ -f "$APK_FILE" ] || { echo "ERR_APK_NOT_FOUND" >&2; exit 1; }
echo "APK_FILE=$APK_FILE"

cat << STATE_EOF > "$STATE_FILE"
ADB_TARGET=$ADB_TARGET
APK_FILE=$APK_FILE
LAST_TEST_URL=$TEST_URL
LAST_RUN_ID=$RUN_ID
UPDATED_AT=$(date '+%Y-%m-%dT%H:%M:%S')
STATE_EOF

adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
ACTIVE_DEV="$(adb devices | awk -v t="$ADB_TARGET" 'NR>1 && $1==t && $2=="device" {print $1}' | head -n 1 || true)"
if [ -z "$ACTIVE_DEV" ]; then
  ACTIVE_DEV="$(adb devices | awk 'NR>1 && $2=="device" {print $1}' | head -n 1 || true)"
fi
[ -n "$ACTIVE_DEV" ] || { echo "ERR_NO_ADB_DEVICE target=$ADB_TARGET" >&2; exit 1; }

adb -s "$ACTIVE_DEV" install -r -d "$APK_FILE"
adb -s "$ACTIVE_DEV" logcat -c >/dev/null 2>&1 || true
adb -s "$ACTIVE_DEV" shell am start -a android.intent.action.VIEW -d "$TEST_URL" "$PKG" >/dev/null 2>&1 || \
  adb -s "$ACTIVE_DEV" shell monkey -p "$PKG" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 || true
sleep 3

PID="$(adb -s "$ACTIVE_DEV" shell pidof "$PKG" 2>/dev/null | tr -d '\r\n ' || true)"
echo "APP_PID=${PID:-not_running}"
RAW_LOG="$OUT_DIR/logcat_${PKG}_${RUN_ID}_$(date '+%Y%m%d_%H%M%S').txt"
adb -s "$ACTIVE_DEV" logcat -d -v time > "$RAW_LOG" 2>/dev/null || true

python3 - "$RAW_LOG" "$PKG" "$PID" << 'PY'
import re
import sys
from pathlib import Path

raw_bytes = Path(sys.argv[1]).read_bytes()
clean_text = re.sub(rb"[^\x09\x0a\x20-\x7e\xc0-\xff]", b" ", raw_bytes).decode("utf-8", errors="replace")
lines = clean_text.splitlines()
pkg, pid = sys.argv[2], sys.argv[3]
kws = ("aiweb", "tomaszewski", "webview", "chromium", "androidruntime", "activitymanager")
if pid:
    kws = kws + (pid,)
matched = [ln for ln in lines if any(k in ln.lower() for k in kws)]
print(f"TOTAL_LOG_LINES={len(lines)} MATCHED_LINES={len(matched)}")
for ln in matched[-50:]:
    print(ln)
PY
echo "CYCLE_COMPLETE_100_OK RUN_ID=$RUN_ID DEVICE=$ACTIVE_DEV"
