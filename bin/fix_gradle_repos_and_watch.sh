#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_PORT="${1:-}"
ADB_IP="${2:-192.168.1.154}"
PROJ_DIR="$HOME/ai-web-browser-apk"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

[ -f "$MAIN_KT" ] || { echo "ERR_MISSING_MAIN_KT=$MAIN_KT" >&2; exit 1; }

cd "$PROJ_DIR"

python3 - "$PROJ_DIR" "$MAIN_KT" << 'PY'
import re
import sys
from pathlib import Path

proj = Path(sys.argv[1])
main_kt = Path(sys.argv[2])

# 1. Potwierdź bilans klamr MainActivity.kt
src_kt = main_kt.read_text(encoding="utf-8")
opens = src_kt.count("{")
closes = src_kt.count("}")
assert opens == closes, f"Niezgodność klamr w MainActivity.kt: {opens}/{closes}"
print(f"MAIN_KT_CHECK braces={opens}/{closes}")

# 2. Usuń wymuszenia offline w gradle.properties oraz --offline w skryptach / workflow
candidates = []
for pattern in ("gradle.properties", "app/gradle.properties", "build.gradle", "build.gradle.kts", "app/build.gradle", "app/build.gradle.kts", "settings.gradle", "settings.gradle.kts"):
    fp = proj / pattern
    if fp.exists():
        candidates.append(fp)

wf_dir = proj / ".github" / "workflows"
if wf_dir.is_dir():
    for fp in sorted(wf_dir.glob("*.yml")) + sorted(wf_dir.glob("*.yaml")):
        candidates.append(fp)

for fp in candidates:
    txt = fp.read_text(encoding="utf-8")
    orig = txt
    # Wyłącz org.gradle.offline=true jeśli ustawione
    txt = re.sub(r"(?m)^[ \t]*org\.gradle\.offline\s*=\s*true\s*$", "org.gradle.offline=false", txt)
    # Usuń flagę --offline z wywołań gradle / gradlew
    txt = re.sub(r"[ \t]+--offline\b", "", txt)
    if txt != orig:
        fp.write_text(txt, encoding="utf-8")
        print(f"PATCHED_OFFLINE_FLAG: {fp.relative_to(proj)}")

# Wypisz podsumowanie repozytoriów w build.gradle / settings.gradle dla diagnostyki
for rel in ("settings.gradle", "settings.gradle.kts", "build.gradle", "build.gradle.kts"):
    fp = proj / rel
    if fp.exists():
        repos = [ln.strip() for ln in fp.read_text(encoding="utf-8").splitlines() if any(k in ln for k in ("google()", "mavenCentral()", "gradlePluginPortal()", "maven("))]
        print(f"REPOS[{rel}]: {repos}")
PY

git add -A
git commit -m "fix(ci): ensure gradle dependency resolution is not forced offline" || true
git push origin main
HEAD_SHA="$(git rev-parse HEAD)"
echo "HEAD_SHA=$HEAD_SHA"

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi
echo "NEW_RUN_ID=$NEW_RUN_ID"

if [ -x "$PROJ_DIR/bin/watch_and_deploy_run.sh" ]; then
  "$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP" || true
fi

LATEST_ID="$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')"
echo "LATEST_RUN_ID=$LATEST_ID"
gh run view "$LATEST_ID" --log-failed 2>/dev/null | grep -E "Could not find |FAILURE:|BUILD FAILED|^e: " | head -n 40 || true
