#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_TARGET="${1:-192.168.1.154:41717}"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

mkdir -p "$OUT_DIR"
cd "$PROJ_DIR"

echo "=== KROK 1: WERYFIKACJA POŁĄCZENIA ADB ($ADB_TARGET) ==="
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb devices -l

echo "=== KROK 2: INSPEKCJA NAJNOWSZEGO / NIEUDANEGO PRZEBIEGU CI ==="
LATEST_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
FAIL_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --status failure --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
INSPECT_ID="${FAIL_RUN_ID:-$LATEST_RUN_ID}"

if [ -n "${INSPECT_ID:-}" ]; then
  LOG_FILE="$OUT_DIR/inspect_${INSPECT_ID}.log"
  gh run view "$INSPECT_ID" --log > "$LOG_FILE" 2>/dev/null || gh run view "$INSPECT_ID" --log-failed > "$LOG_FILE" 2>/dev/null || true
  echo "INSPECT_RUN_ID=$INSPECT_ID LOG_FILE=$LOG_FILE"
  gh run view "$INSPECT_ID" --json databaseId,status,conclusion,headSha,url
  python3 - "$LOG_FILE" << 'PY'
import re
import sys
from pathlib import Path

lines = Path(sys.argv[1]).read_text(encoding="utf-8", errors="replace").splitlines()
rx = re.compile(r"(^|\s)e:\s+file://|Execution failed for task|Unresolved reference|Expecting a top level declaration|Conflicting overloads|Function declaration must have a name|Could not find |FAILURE: Build failed with an exception")
hits = []
for i, ln in enumerate(lines):
    if rx.search(ln):
        for j in range(max(0, i - 1), min(len(lines), i + 3)):
            if j not in hits:
                hits.append(j)
if hits:
    prev = -2
    for j in hits[:80]:
        if j > prev + 1:
            print("...")
        print(f"{j+1}: {lines[j]}")
        prev = j
else:
    print("Brak dopasowań wzorca błędu w logu; ostatnie 30 linii:")
    for j in range(max(0, len(lines) - 30), len(lines)):
        print(f"{j+1}: {lines[j]}")
PY
fi

echo "=== KROK 3: AUDYT LOKALNY MAINACTIVITY.KT I PRZYGOTOWANIE COMMITU ==="
[ -f "$MAIN_KT" ] || { echo "ERR_MISSING_MAIN_KT=$MAIN_KT" >&2; exit 1; }
python3 - "$MAIN_KT" << 'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
src = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", p.read_text(encoding="utf-8")).replace("\r\n", "\n").rstrip() + "\n"
opens = src.count("{")
closes = src.count("}")
if opens != closes:
    if opens > closes:
        src = src.rstrip() + ("\n}" * (opens - closes)) + "\n"
    else:
        for _ in range(closes - opens):
            idx = src.rfind("}")
            if idx != -1:
                src = src[:idx] + src[idx + 1 :]
        src = src.rstrip() + "\n"
p.write_text(src, encoding="utf-8")
print(f"MAIN_KT_READY braces={src.count('{')}/{src.count('}')} loadTargetUrl={len(re.findall(r'\\bfun loadTargetUrl\\(', src))}")
PY

LOCAL_HEAD="$(git rev-parse HEAD)"
echo "LOCAL_HEAD=$LOCAL_HEAD"

# Sprawdź czy dla bieżącego LOCAL_HEAD istnieje już zakończony sukcesem przebieg
SUCCESS_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 5 --json databaseId,headSha,status,conclusion \
  --jq --arg sha "$LOCAL_HEAD" '[.[] | select(.headSha == $sha and .status == "completed" and .conclusion == "success")][0].databaseId // empty' 2>/dev/null || true)"

if [ -z "$SUCCESS_RUN_ID" ]; then
  echo "=== KROK 4: URUCHOMIENIE I OCZEKIWANIE NA BUILD-APK.YML ==="
  IN_PROG_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId,headSha,status \
    --jq --arg sha "$LOCAL_HEAD" '[.[] | select(.headSha == $sha and .status != "completed")][0].databaseId // empty' 2>/dev/null || true)"
  if [ -n "$IN_PROG_ID" ]; then
    TARGET_RUN_ID="$IN_PROG_ID"
  else
    gh workflow run "build-apk.yml" --ref main >/dev/null 2>&1 || true
    sleep 4
    TARGET_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
  fi
  echo "TARGET_RUN_ID=$TARGET_RUN_ID"
  while true; do
    META="$(gh run view "$TARGET_RUN_ID" --json status,conclusion,headSha,url 2>/dev/null || echo '{}')"
    ST="$(printf '%s' "$META" | jq -r '.status // "unknown"')"
    CN="$(printf '%s' "$META" | jq -r '.conclusion // ""')"
    SH="$(printf '%s' "$META" | jq -r '.headSha // ""')"
    UR="$(printf '%s' "$META" | jq -r '.url // ""')"
    printf '[%s] RUN=%s SHA=%s STATUS=%s CONCLUSION=%s\n' "$(date '+%H:%M:%S')" "$TARGET_RUN_ID" "${SH:0:7}" "$ST" "$CN"
    if [ "$ST" = "completed" ]; then
      echo "COMPLETED_URL=$UR"
      break
    fi
    sleep 8
  done
  if [ "$CN" != "success" ]; then
    echo "BUILD_NOT_SUCCESS RUN_ID=$TARGET_RUN_ID CONCLUSION=$CN"
    gh run view "$TARGET_RUN_ID" --log-failed 2>/dev/null | grep -E "(^|\s)e:\s+file://|Could not find |FAILURE:|BUILD FAILED|Execution failed" | head -n 50 || true
    exit 1
  fi
  SUCCESS_RUN_ID="$TARGET_RUN_ID"
else
  echo "=== KROK 4: ZNALEZIONO GOTOWY SUKCES BUILD-APK.YML (RUN_ID=$SUCCESS_RUN_ID) ==="
fi

echo "=== KROK 5: POBRANIE I INSTALACJA APK NA $ADB_TARGET ==="
APK_DIR="$OUT_DIR/deploy_${SUCCESS_RUN_ID}"
mkdir -p "$APK_DIR"
gh run download "$SUCCESS_RUN_ID" -D "$APK_DIR" 2>/dev/null || true
APK_FILE="$(find "$APK_DIR" "$PROJ_DIR" -maxdepth 4 -name "*.apk" 2>/dev/null | head -n 1 || true)"
[ -n "$APK_FILE" ] && [ -f "$APK_FILE" ] || { echo "ERR_NO_APK_FOUND RUN_ID=$SUCCESS_RUN_ID" >&2; exit 1; }

echo "APK_FILE=$APK_FILE"
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb -s "$ADB_TARGET" install -r "$APK_FILE"
adb -s "$ADB_TARGET" shell pm list packages | grep -iE "aiweb|tomaszewski" || true
echo "ALL_STEPS_COMPLETED_OK RUN_ID=$SUCCESS_RUN_ID ADB=$ADB_TARGET"
