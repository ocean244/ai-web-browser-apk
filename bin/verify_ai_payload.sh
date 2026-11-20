#!/usr/bin/env bash
set -euo pipefail

RAW_TARGET="${1:-192.168.1.154:33177}"
REQ_PORT="${2:-18080}"
MODEL_NAME="${3:-gpt-4o-mini}"
API_KEY_VAL="${4:-}"
TMP_DIR="${TMPDIR:-$HOME/tmp}"
mkdir -p "$TMP_DIR"
OUT_JSON="$TMP_DIR/ai_last_payload.json"
PORT_FILE="$TMP_DIR/ai_bound_port.txt"
SRV_SCRIPT="$HOME/ai-web-browser-apk/bin/mock_capture_srv.py"
SRV_PID=""
TARGET=""
PORT=""

cleanup() {
  if [ -n "$SRV_PID" ]; then
    sleep 0.5
    kill "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
  fi
  if [ -n "$TARGET" ] && [ -n "$PORT" ] && adb devices 2>/dev/null | awk -v t="$TARGET" '$1 == t && $2 == "device" { found=1 } END { exit(found ? 0 : 1) }'; then
    adb -s "$TARGET" reverse --remove "tcp:${PORT}" >/dev/null 2>&1 || true
  fi
  rm -f "$OUT_JSON" "$PORT_FILE"
}
trap cleanup EXIT

rm -f "$OUT_JSON" "$PORT_FILE"
TARGET="$("$HOME/ai-web-browser-apk/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"
adb -s "$TARGET" wait-for-device

python3 "$SRV_SCRIPT" "$REQ_PORT" "$OUT_JSON" "$PORT_FILE" &
SRV_PID=$!

for _ in $(seq 1 30); do
  [ -s "$PORT_FILE" ] && break
  sleep 0.1
done

PORT="$(cat "$PORT_FILE")"
adb -s "$TARGET" reverse --remove "tcp:${PORT}" >/dev/null 2>&1 || true
adb -s "$TARGET" reverse "tcp:${PORT}" "tcp:${PORT}" >/dev/null 2>&1 || true

"$HOME/ai-web-browser-apk/bin/verify_ai_target.sh" "$TARGET" "http://127.0.0.1:${PORT}/v1/chat/completions" "$MODEL_NAME" "$API_KEY_VAL"
sleep 2.5

if [ -f "$OUT_JSON" ]; then
  echo "CAPTURED_PAYLOAD=$(cat "$OUT_JSON")"
else
  echo "CAPTURED_PAYLOAD=<none>"
fi
