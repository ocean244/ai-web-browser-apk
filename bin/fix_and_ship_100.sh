#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_TARGET="${1:-192.168.1.154:41717}"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

mkdir -p "$OUT_DIR"
cd "$PROJ_DIR"

echo "=== 1. POŁĄCZENIE ADB ($ADB_TARGET) ==="
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb devices -l

echo "=== 2. NAPRAWA KOŃCÓWKI MAINACTIVITY.KT ==="
[ -f "$MAIN_KT" ] || { echo "ERR_MISSING_MAIN_KT=$MAIN_KT" >&2; exit 1; }

python3 - "$MAIN_KT" << 'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
raw = p.read_text(encoding="utf-8")
src = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw).replace("\r\n", "\n")

idx_fn = src.find("fun loadTargetUrl(url: String)")
if idx_fn == -1:
    raise RuntimeError("Brak fun loadTargetUrl(url: String)")

# Cofnij się przed fun loadTargetUrl i usuń puste linie oraz osierocone '}'
prefix = src[:idx_fn]
prefix_lines = prefix.splitlines()
while prefix_lines and prefix_lines[-1].strip() in ("", "}"):
    prefix_lines.pop()

# Jeśli poprzednia linia to 'return activity.searchEngine.fetchUrlText(url).toString()',
# domknij fetchPage (8 spacji + '}') oraz AndroidNativeBridge (4 spacje + '}')
if prefix_lines and "return activity.searchEngine.fetchUrlText(url).toString()" in prefix_lines[-1]:
    prefix_lines.append("        }")
    prefix_lines.append("    }")

# Wyodrębnij wyłącznie blok fun loadTargetUrl(url: String) { ... }
tail_from_fn = src[idx_fn:].splitlines()
fn_block = []
depth = 0
started = False
for ln in tail_from_fn:
    if not started:
        fn_block.append(ln)
        depth += ln.count("{") - ln.count("}")
        started = True
    else:
        if depth > 0:
            fn_block.append(ln)
            depth += ln.count("{") - ln.count("}")

if depth > 0:
    fn_block.append("    }" * 0 + "    }")

rebuilt = "\n".join(prefix_lines).rstrip() + "\n\n" + "\n".join(fn_block).rstrip() + "\n\n}\n"

# Dopasuj bilans klamr na końcu pliku (klasa MainActivity na samym końcu)
opens = rebuilt.count("{")
closes = rebuilt.count("}")
if opens > closes:
    rebuilt = rebuilt.rstrip() + ("\n}" * (opens - closes)) + "\n"
elif closes > opens:
    for _ in range(closes - opens):
        pos = rebuilt.rfind("}")
        if pos != -1:
            rebuilt = rebuilt[:pos] + rebuilt[pos + 1 :]
    rebuilt = rebuilt.rstrip() + "\n"

opens_f = rebuilt.count("{")
closes_f = rebuilt.count("}")
assert opens_f == closes_f, f"Niezgodność klamr: {opens_f}/{closes_f}"
assert rebuilt.count("fun loadTargetUrl(") == 1
assert rebuilt.splitlines()[-1].strip() == "}"

p.write_text(rebuilt, encoding="utf-8")
out_lines = rebuilt.splitlines()
print(f"MAIN_KT_FIXED lines={len(out_lines)} braces={opens_f}/{closes_f}")
for i in range(max(0, len(out_lines) - 24), len(out_lines)):
    print(f"{i+1}: {out_lines[i]}")
PY

echo "=== 3. COMMIT I PUSH NA MAIN ==="
git add -A
if ! git diff --cached --quiet; then
  git commit -m "fix(aiweb): close fetchPage and AndroidNativeBridge cleanly before loadTargetUrl"
fi
git push origin main
TARGET_SHA="$(git rev-parse HEAD)"
echo "TARGET_SHA=$TARGET_SHA"

echo "=== 4. URUCHOMIENIE I OCZEKIWANIE NA BUILD-APK.YML ==="
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

echo "=== 5. POBRANIE ARTEFAKTU I INSTALACJA APK NA $ADB_TARGET ==="
APK_DIR="$OUT_DIR/apk_${RUN_ID}"
mkdir -p "$APK_DIR"
gh run download "$RUN_ID" -D "$APK_DIR" 2>/dev/null || true
APK_PATH="$(find "$APK_DIR" "$PROJ_DIR" -maxdepth 4 -name "*.apk" 2>/dev/null | head -n 1 || true)"
[ -n "$APK_PATH" ] && [ -f "$APK_PATH" ] || { echo "ERR_APK_NOT_FOUND RUN_ID=$RUN_ID" >&2; exit 1; }

echo "APK_PATH=$APK_PATH"
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb -s "$ADB_TARGET" install -r "$APK_PATH"
adb -s "$ADB_TARGET" shell pm list packages | grep -iE "aiweb|tomaszewski" || true
echo "PIPELINE_100_OK RUN_ID=$RUN_ID ADB=$ADB_TARGET"
