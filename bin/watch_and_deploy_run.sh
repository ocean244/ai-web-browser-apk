#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

RUN_ID="${1:-44691543814}"
ADB_PORT="${2:-}"
ADB_IP="${3:-192.168.1.154}"
PROJ_DIR="$HOME/ai-web-browser-apk"
OUT_DIR="$PROJ_DIR/out"

mkdir -p "$OUT_DIR"
cd "$PROJ_DIR"

fetch_run_json() {
  local attempt=1
  local max_attempts=6
  local out=""
  while [ "$attempt" -le "$max_attempts" ]; do
    if out="$(gh run view "$RUN_ID" --json status,conclusion,url 2>/dev/null)" && [ -n "$out" ]; then
      printf '%s\n' "$out"
      return 0
    fi
    sleep 3
    attempt=$((attempt + 1))
  done
  return 1
}

STATUS="in_progress"
CONCLUSION=""
RUN_URL="https://github.com/ocean244/ai-web-browser-apk/actions/runs/$RUN_ID"

while true; do
  if JSON_OUT="$(fetch_run_json)"; then
    STATUS="$(printf '%s' "$JSON_OUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("status",""))')"
    CONCLUSION="$(printf '%s' "$JSON_OUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("conclusion") or "")')"
    RUN_URL="$(printf '%s' "$JSON_OUT" | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("url",""))')"
    echo "RUN_ID=$RUN_ID STATUS=$STATUS CONCLUSION=${CONCLUSION:-pending} URL=$RUN_URL"
    if [ "$STATUS" = "completed" ]; then
      break
    fi
  else
    echo "WARN_GH_API_TRANSIENT: ponawiam odczyt RUN_ID=$RUN_ID..."
  fi
  sleep 8
done

if [ "$CONCLUSION" != "success" ]; then
  echo "BUILD_FAILED_RUN_ID=$RUN_ID"
  "$PROJ_DIR/bin/pull_all_github_build_errors.sh" "$RUN_ID" || true
  exit 1
fi

echo "BUILD_SUCCESS_RUN_ID=$RUN_ID"

TARGET_ADB=""
if command -v adb >/dev/null 2>&1; then
  adb start-server >/dev/null 2>&1 || true
  if [ -n "$ADB_PORT" ]; then
    if adb connect "${ADB_IP}:${ADB_PORT}" 2>/dev/null | grep -qiE "connected to|already connected"; then
      TARGET_ADB="${ADB_IP}:${ADB_PORT}"
    fi
  fi
  if [ -z "$TARGET_ADB" ]; then
    for P in 35231 36375 37000 38000 39000 40000 41000 42000 43000 44000 5555; do
      if adb connect "${ADB_IP}:${P}" 2>/dev/null | grep -qiE "connected to|already connected"; then
        TARGET_ADB="${ADB_IP}:${P}"
        break
      fi
    done
  fi
  if [ -z "$TARGET_ADB" ]; then
    TARGET_ADB="$(adb devices | awk '/\tdevice$/{print $1; exit}')"
  fi
fi

if [ -n "$TARGET_ADB" ]; then
  echo "DEPLOY_TARGET=$TARGET_ADB"
  "$PROJ_DIR/bin/trigger_build_and_deploy.sh" "$TARGET_ADB" || true
else
  echo "WARN_NO_ADB_DEVICE: połącz ADB portem debugowania bezprzewodowego (np. adb connect ${ADB_IP}:<PORT>) i uruchom deploy."
fi
