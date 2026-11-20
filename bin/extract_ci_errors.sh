#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_FILE="$PROJ_DIR/out/ci_error_blocks.txt"
mkdir -p "$PROJ_DIR/out"

cd "$PROJ_DIR"
RUN_ID="${1:-$(gh run list --workflow="build-apk.yml" --limit 1 --json databaseId --jq '.[0].databaseId')}"
echo "=== CI_ERROR_BLOCKS RUN_ID=${RUN_ID} ===" > "$OUT_FILE"
gh run view "$RUN_ID" --log-failed >> "$OUT_FILE" 2>&1 || gh run view "$RUN_ID" --log >> "$OUT_FILE" 2>&1 || true

grep -n -C 4 -E "(^|[^a-zA-Z0-9_])(error:|FAILURE:|Execution failed|Exception|FATAL|ERR_|Unresolved reference|e: file://)" "$OUT_FILE" || echo "NO_ERROR_BLOCKS_FOUND"
echo "SAVED_TO=$OUT_FILE"
