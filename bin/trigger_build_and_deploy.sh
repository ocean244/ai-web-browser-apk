#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:36375}"

cd "$PROJ_DIR"
gh workflow run build-apk.yml --ref main
sleep 4

RUN_ID="$(gh run list --workflow="build-apk.yml" --limit 1 --json databaseId --jq '.[0].databaseId')"
echo "TRIGGERED_RUN_ID=${RUN_ID} ADB_TARGET=${ADB_TARGET}"
gh run watch "$RUN_ID" --exit-status

if [ -x "$PROJ_DIR/bin/sync_ci_apk.sh" ]; then
  "$PROJ_DIR/bin/sync_ci_apk.sh" "$ADB_TARGET" "$RUN_ID"
else
  "$PROJ_DIR/bin/build_deploy.sh" "$ADB_TARGET"
fi

if [ -x "$PROJ_DIR/bin/run_clean_snapshot.sh" ]; then
  "$PROJ_DIR/bin/run_clean_snapshot.sh" "$ADB_TARGET"
fi
