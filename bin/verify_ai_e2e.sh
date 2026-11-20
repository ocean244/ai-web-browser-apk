#!/usr/bin/env bash
set -euo pipefail

RAW_TARGET="${1:-192.168.1.154:38911}"
REQ_PORT="${2:-18080}"
MOCK_MODE="${3:-no-mock}"
TMP_DIR="${TMPDIR:-$HOME/tmp}"
mkdir -p "$TMP_DIR"
MOCK_JSON="$TMP_DIR/ai_e2e_mock.json"
PORT_FILE="$TMP_DIR/ai_e2e_port.txt"
SRV_PID=""
TARGET=""
PORT="$REQ_PORT"

cleanup() {
  if [ -n "$SRV_PID" ]; then
    sleep 0.5
    kill "$SRV_PID" 2>/dev/null || true
    wait "$SRV_PID" 2>/dev/null || true
  fi
  if [ -n "$TARGET" ] && [ -n "$PORT" ]; then
    adb -s "$TARGET" reverse --remove "tcp:${PORT}" 2>/dev/null || true
  fi
  rm -f "$MOCK_JSON" "$PORT_FILE"
}
trap cleanup EXIT

rm -f "$MOCK_JSON" "$PORT_FILE"
TARGET="$("$HOME/ai-web-browser-apk/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"
adb -s "$TARGET" wait-for-device

if [ "$MOCK_MODE" = "--mock" ]; then
  python3 "$HOME/ai-web-browser-apk/bin/mock_capture_srv.py" "$REQ_PORT" "$MOCK_JSON" "$PORT_FILE" &
  SRV_PID=$!
  for _ in $(seq 1 30); do
    [ -s "$PORT_FILE" ] && break
    sleep 0.1
  done
  PORT="$(cat "$PORT_FILE")"
fi

adb -s "$TARGET" reverse "tcp:${PORT}" "tcp:${PORT}" >/dev/null 2>&1 || true

adb -s "$TARGET" shell am start -n pl.tomaszewski.aiweb/.MainActivity >/dev/null
sleep 1

adb -s "$TARGET" shell uiautomator dump /data/local/tmp/ui_verify.xml >/dev/null
BOUNDS="$(adb -s "$TARGET" shell cat /data/local/tmp/ui_verify.xml \
  | tr '<' '\n<' \
  | grep 'package="pl.tomaszewski.aiweb"' \
  | grep 'class="android.widget.Button"' \
  | grep 'text="TEST AI"' \
  | head -n 1 \
  | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\].*/\1 \2 \3 \4/p')"
adb -s "$TARGET" shell rm -f /data/local/tmp/ui_verify.xml

if [ -z "$BOUNDS" ]; then
  echo "ERR: Nie odnaleziono przycisku TEST AI" >&2
  exit 1
fi

X_TAP="$(echo "$BOUNDS" | awk '{print int(($1+$3)/2)}')"
Y_TAP="$(echo "$BOUNDS" | awk '{print int(($2+$4)/2)}')"
adb -s "$TARGET" shell input tap "$X_TAP" "$Y_TAP"
sleep 2

PID_AI="$(adb -s "$TARGET" shell pidof pl.tomaszewski.aiweb | tr -d '\r')"
echo "TARGET=$TARGET PORT=$PORT MOCK=$MOCK_MODE PID_AI=$PID_AI TAP=$X_TAP,$Y_TAP"
[ -n "$PID_AI" ] && adb -s "$TARGET" shell logcat -d --pid="$PID_AI" | grep -E "AiWebMainActivity|AndroidNative|E/|F/" | tail -n 10 || true
