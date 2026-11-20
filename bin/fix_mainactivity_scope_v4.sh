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

# Usuń ewentualne znaki kontrolne (poza \n, \r, \t)
src = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw)

# Upewnij się, że za ostatnią klamrą zamykającą plik nie ma żadnego tekstu/śmieci
last_close = src.rfind("}")
if last_close == -1:
    raise RuntimeError("Brak klamry zamykającej w MainActivity.kt")
src = src[: last_close + 1] + "\n"

# Policz klamry w całym pliku
opens = src.count("{")
closes = src.count("}")
if opens != closes:
    raise RuntimeError(f"Niezbalansowane klamry w MainActivity.kt: opens={opens}, closes={closes}")

# Sprawdź definicje klas i metod
main_classes = re.findall(r"\bclass\s+MainActivity\b", src)
load_fns = re.findall(r"\bfun\s+loadTargetUrl\b", src)
assert len(main_classes) == 1, f"Oczekiwano 1 class MainActivity, znaleziono {len(main_classes)}"
assert len(load_fns) == 1, f"Oczekiwano 1 fun loadTargetUrl, znaleziono {len(load_fns)}"

p.write_text(src, encoding="utf-8")
lines = src.splitlines()
print(f"MAIN_KT_V4_OK lines={len(lines)} braces={opens}/{closes} head={src[:120]!r}")
for idx in range(max(0, len(lines) - 22), len(lines)):
    print(f"{idx+1}: {lines[idx]}")
PY

git add -A
git commit -m "chore(aiweb): normalize MainActivity.kt line endings and verify brace balance" || true
git push origin main

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

echo "NEW_RUN_ID=$NEW_RUN_ID"
"$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP"
