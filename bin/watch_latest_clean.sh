#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_PORT="${1:-}"
ADB_IP="${2:-192.168.1.154}"
PROJ_DIR="$HOME/ai-web-browser-apk"

cd "$PROJ_DIR"
LOCAL_HEAD="$(git rev-parse HEAD)"
echo "LOCAL_HEAD=$LOCAL_HEAD"

# Jeśli najnowszy run nie odpowiada jeszcze bieżącemu LOCAL_HEAD i żaden nie jest w toku, wyzwól build-apk.yml
LATEST_JSON="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId,status,conclusion,headSha,url --jq '.[0]' 2>/dev/null || echo '{}')"
RUN_ID="$(printf '%s' "$LATEST_JSON" | jq -r '.databaseId // empty')"
RUN_STATUS="$(printf '%s' "$LATEST_JSON" | jq -r '.status // empty')"
RUN_SHA="$(printf '%s' "$LATEST_JSON" | jq -r '.headSha // empty')"

if [ -z "$RUN_ID" ] || { [ "$RUN_STATUS" = "completed" ] && [ "$RUN_SHA" != "$LOCAL_HEAD" ]; }; then
  gh workflow run "build-apk.yml" --ref main >/dev/null 2>&1 || true
  sleep 3
  LATEST_JSON="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId,status,conclusion,headSha,url --jq '.[0]')"
  RUN_ID="$(printf '%s' "$LATEST_JSON" | jq -r '.databaseId')"
fi

echo "WATCHING_RUN_ID=$RUN_ID"
gh run watch "$RUN_ID" --exit-status >/dev/null 2>&1 && WATCH_RC=0 || WATCH_RC=$?

FINAL_JSON="$(gh run view "$RUN_ID" --json databaseId,status,conclusion,headSha,url)"
echo "FINAL_RUN=$FINAL_JSON"

CONCLUSION="$(printf '%s' "$FINAL_JSON" | jq -r '.conclusion // "unknown"')"
if [ "$CONCLUSION" = "success" ]; then
  if [ -x "$PROJ_DIR/bin/watch_and_deploy_run.sh" ]; then
    "$PROJ_DIR/bin/watch_and_deploy_run.sh" "$RUN_ID" "$ADB_PORT" "$ADB_IP" || true
  fi
  echo "BUILD_AND_DEPLOY_DONE RUN_ID=$RUN_ID CONCLUSION=success"
else
  echo "BUILD_FAILED RUN_ID=$RUN_ID CONCLUSION=$CONCLUSION"
  gh run view "$RUN_ID" --log-failed 2>/dev/null | grep -E "^e: |FAILURE:|BUILD FAILED|error:" | head -n 40 || true
  exit 1
fi
