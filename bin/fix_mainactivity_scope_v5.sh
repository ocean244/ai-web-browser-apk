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
src = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw).replace("\r\n", "\n")

# Wypisz linie zawierające deklaracje klas, mostka i pól przed korektą
for idx, line in enumerate(src.splitlines(), start=1):
    if re.search(r"\b(class|inner class|fun loadTargetUrl|AndroidNativeBridge|modelInput|configStore|searchEngine|aiClient)\b", line):
        print(f"SCAN {idx}: {line}")

# Usuń nadmiarową końcową klamrę zamykającą plik, jeśli plik kończy się podwójnym "}\n}\n"
while re.search(r"\n\}\s*\n\}\s*$", src):
    src = re.sub(r"\n\}\s*$", "\n", src)

lines = src.splitlines()
print(f"MAIN_KT_V5_OK lines={len(lines)} braces={src.count('{')}/{src.count('}')}")
for idx in range(max(0, len(lines) - 20), len(lines)):
    print(f"{idx+1}: {lines[idx]}")

p.write_text(src, encoding="utf-8")
PY

git add -A
git commit -m "fix(aiweb): remove trailing extra closing brace in MainActivity.kt" || true
git push origin main

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

echo "NEW_RUN_ID=$NEW_RUN_ID"
"$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP"
