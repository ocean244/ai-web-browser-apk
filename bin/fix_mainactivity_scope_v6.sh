#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_PORT="${1:-}"
ADB_IP="${2:-192.168.1.154}"
PROJ_DIR="$HOME/ai-web-browser-apk"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

[ -f "$MAIN_KT" ] || { echo "ERR_MISSING_MAIN_KT=$MAIN_KT" >&2; exit 1; }
[ -x "$PROJ_DIR/bin/watch_and_deploy_run.sh" ] || { echo "ERR_MISSING_WATCHER=$PROJ_DIR/bin/watch_and_deploy_run.sh" >&2; exit 1; }

cd "$PROJ_DIR"

python3 - "$MAIN_KT" << 'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
raw = p.read_text(encoding="utf-8")
src = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw).replace("\r\n", "\n").rstrip()

opens = src.count("{")
closes = src.count("}")

if opens > closes:
    src = src + ("\n}" * (opens - closes)) + "\n"
elif closes > opens:
    excess = closes - opens
    for _ in range(excess):
        pos = src.rfind("}")
        if pos == -1:
            raise RuntimeError("Nie można usunąć nadmiarowej klamry '}'")
        src = src[:pos] + src[pos + 1 :]
    src = src.rstrip() + "\n"
else:
    src = src + "\n"

opens_final = src.count("{")
closes_final = src.count("}")
assert opens_final == closes_final, f"Niezgodność klamr: {opens_final}/{closes_final}"
assert len(re.findall(r"\bclass\s+MainActivity\b", src)) == 1
assert len(re.findall(r"\bfun\s+loadTargetUrl\b", src)) == 1

p.write_text(src, encoding="utf-8")
lines = src.splitlines()
print(f"MAIN_KT_V6_OK lines={len(lines)} braces={opens_final}/{closes_final}")
for idx in range(max(0, len(lines) - 18), len(lines)):
    print(f"{idx+1}: {lines[idx]}")
PY

git add -A
git commit -m "fix(aiweb): balance closing braces in MainActivity.kt" || true
git push origin main
HEAD_SHA="$(git rev-parse HEAD)"
echo "HEAD_SHA=$HEAD_SHA"

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

echo "NEW_RUN_ID=$NEW_RUN_ID"
"$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP"
