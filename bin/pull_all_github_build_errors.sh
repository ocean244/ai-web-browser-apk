#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="${PROJ_DIR:-$HOME/ai-web-browser-apk}"
OUT_DIR="$PROJ_DIR/out"
TS="$(date +%Y%m%d_%H%M%S)"
REPORT="$OUT_DIR/github_build_errors_${TS}.log"
TARGET_RUN_ID="${1:-}"

mkdir -p "$OUT_DIR"
cd "$PROJ_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERR: brak narzędzia 'gh' (GitHub CLI)" >&2
  exit 1
fi

: > "$REPORT"

if [ -n "$TARGET_RUN_ID" ]; then
  RUN_IDS="$TARGET_RUN_ID"
else
  RUN_IDS="$(gh run list --workflow="build-apk.yml" --limit 20 --json databaseId,conclusion --jq '.[] | select(.conclusion == "failure") | .databaseId' || true)"
  if [ -z "$RUN_IDS" ]; then
    RUN_IDS="$(gh run list --limit 20 --json databaseId,conclusion --jq '.[] | select(.conclusion == "failure") | .databaseId' || true)"
  fi
fi

if [ -z "$RUN_IDS" ]; then
  echo "BRAK_FAILED_RUNS" | tee -a "$REPORT"
  exit 0
fi

for RID in $RUN_IDS; do
  {
    echo "============================================================"
    echo "RUN_ID: $RID"
    gh run view "$RID" --json status,conclusion,createdAt,headBranch,headSha,url || true
    echo "--- FAILED LOGS (RAW) ---"
    gh run view "$RID" --log-failed 2>&1 || gh run view "$RID" --log 2>&1 || true
    echo "--- EXTRACTED ERROR LINES ---"
    gh run view "$RID" --log-failed 2>&1 | grep -E -i '(^|[^a-zA-Z0-9_])(error|e:|exception|failed|failure|unresolved reference|missing|cannot find|syntax error|exit code [1-9])([^a-zA-Z0-9_]|$)' || true
  } >> "$REPORT"
done

cp -f "$REPORT" "$OUT_DIR/ci_error_blocks.txt"
echo "SAVED_REPORT=$REPORT"
echo "LATEST_ALIAS=$OUT_DIR/ci_error_blocks.txt"
echo "--- SUMMARY OF EXTRACTED ERRORS ---"
grep -E -i '^(RUN_ID:|={10,}|.*(e:|error:|exception|failed|failure|unresolved reference|missing|exit code [1-9]))' "$REPORT" || cat "$REPORT"
