#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

RUN_ID="${1:-44694871422}"
ADB_TARGET="${2:-192.168.1.154:42255}"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out/apk_${RUN_ID}"

cd "$PROJ_DIR"

# Upewnij się, że połączenie ADB jest aktywne
adb connect "$ADB_TARGET" >/dev/null 2>&1 || true
adb devices -l

# Jeśli podany RUN_ID nie istnieje, weź najnowszy run na main
if ! gh run view "$RUN_ID" --json databaseId >/dev/null 2>&1; then
  RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

echo "POLLING_RUN_ID=$RUN_ID ADB_TARGET=$ADB_TARGET"

while true; do
  INFO="$(gh run view "$RUN_ID" --json status,conclusion,headSha,url 2>/dev/null || echo '{}')"
  STATUS="$(printf '%s' "$INFO" | jq -r '.status // "unknown"')"
  CONCL="$(printf '%s' "$INFO" | jq -r '.conclusion // ""')"
  SHA="$(printf '%s' "$INFO" | jq -r '.headSha // ""')"
  URL="$(printf '%s' "$INFO" | jq -r '.url // ""')"
  printf '[%s] RUN_ID=%s SHA=%s STATUS=%s CONCLUSION=%s\n' "$(date '+%H:%M:%S')" "$RUN_ID" "${SHA:0:7}" "$STATUS" "$CONCL"
  if [ "$STATUS" = "completed" ]; then
    echo "RUN_URL=$URL"
    break
  fi
  sleep 8
done

if [ "$CONCL" = "success" ]; then
  ADB_PORT="${ADB_TARGET##*:}"
  ADB_IP="${ADB_TARGET%%:*}"
  if [ -x "$PROJ_DIR/bin/watch_and_deploy_run.sh" ]; then
    "$PROJ_DIR/bin/watch_and_deploy_run.sh" "$RUN_ID" "$ADB_PORT" "$ADB_IP" || true
  fi
  APK_PATH="$(find "$PROJ_DIR" -maxdepth 4 -name "*.apk" 2>/dev/null | head -n 1 || true)"
  if [ -z "$APK_PATH" ]; then
    mkdir -p "$OUT_DIR"
    gh run download "$RUN_ID" -D "$OUT_DIR" 2>/dev/null || true
    APK_PATH="$(find "$OUT_DIR" -name "*.apk" 2>/dev/null | head -n 1 || true)"
  fi
  if [ -n "$APK_PATH" ] && [ -f "$APK_PATH" ]; then
    echo "INSTALLING_APK=$APK_PATH -> $ADB_TARGET"
    adb -s "$ADB_TARGET" install -r "$APK_PATH"
    adb -s "$ADB_TARGET" shell pm list packages | grep -i "aiweb\|tomaszewski" || true
  else
    echo "WARN_NO_LOCAL_OR_ARTIFACT_APK_FOUND"
  fi
  echo "DEPLOY_SUCCESS RUN_ID=$RUN_ID"
else
  echo "RUN_FAILED RUN_ID=$RUN_ID CONCLUSION=$CONCL"
  gh run view "$RUN_ID" --log-failed 2>/dev/null | grep -E "^e: |Could not find |FAILURE:|BUILD FAILED|error:" | head -n 50 || true
  exit 1
fi
