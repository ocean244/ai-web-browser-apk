#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

RUN_ID="${1:-44694871422}"
ADB_TARGET="${2:-192.168.1.154:42255}"
PROJ_DIR="$HOME/ai-web-browser-apk"
LOG_DIR="$PROJ_DIR/out"
mkdir -p "$LOG_DIR"

cd "$PROJ_DIR"

if ! gh run view "$RUN_ID" --json databaseId >/dev/null 2>&1; then
  RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

FULL_LOG="$LOG_DIR/run_${RUN_ID}_full.log"
gh run view "$RUN_ID" --log > "$FULL_LOG" 2>/dev/null || gh run view "$RUN_ID" --log-failed > "$FULL_LOG" 2>/dev/null || true

echo "RUN_ID=$RUN_ID FULL_LOG=$FULL_LOG LINES=$(wc -l < "$FULL_LOG" 2>/dev/null || echo 0)"
gh run view "$RUN_ID" --json status,conclusion,headSha,url

python3 - "$FULL_LOG" << 'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
lines = p.read_text(encoding="utf-8", errors="replace").splitlines()

patterns = [
    r"(^|\s)e:\s+file://",
    r"Execution failed for task",
    r"Unresolved reference",
    r"Expecting a top level declaration",
    r"Conflicting overloads",
    r"Function declaration must have a name",
    r"Could not find ",
    r"FAILURE: Build failed with an exception",
]
rx = re.compile("|".join(patterns))

hits = []
for i, ln in enumerate(lines):
    if rx.search(ln):
        start = max(0, i - 2)
        end = min(len(lines), i + 4)
        for j in range(start, end):
            if j not in hits:
                hits.append(j)

if not hits:
    print("--- TAIL OF FULL LOG (LAST 60 LINES) ---")
    for idx in range(max(0, len(lines) - 60), len(lines)):
        print(f"{idx+1}: {lines[idx]}")
else:
    print("--- EXTRACTED FAILURE CONTEXT ---")
    prev = -2
    for j in hits[:120]:
        if j > prev + 1:
            print("...")
        print(f"{j+1}: {lines[j]}")
        prev = j
PY

adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb devices -l
