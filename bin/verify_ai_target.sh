#!/usr/bin/env bash
set -euo pipefail

RAW_TARGET="${1:-192.168.1.154:43813}"
ENDPOINT_URL="${2:-http://127.0.0.1:18080/v1/chat/completions}"
MODEL_NAME="${3:-}"
API_KEY_VAL="${4:-}"

TARGET="$("$HOME/ai-web-browser-apk/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"

adb_type_safe() {
  local s="$1"
  local i ch
  for (( i=0; i<${#s}; i++ )); do
    ch="${s:$i:1}"
    case "$ch" in
      ":") adb -s "$TARGET" shell input text ":" >/dev/null ;;
      "/") adb -s "$TARGET" shell input keyevent KEYCODE_SLASH >/dev/null ;;
      ".") adb -s "$TARGET" shell input keyevent KEYCODE_PERIOD >/dev/null ;;
      "-") adb -s "$TARGET" shell input keyevent KEYCODE_MINUS >/dev/null ;;
      "_") adb -s "$TARGET" shell input text "_" >/dev/null ;;
      *)   adb -s "$TARGET" shell input text "$ch" >/dev/null ;;
    esac
  done
}

clear_and_type() {
  local bounds="$1"
  local val="$2"
  [ -z "$bounds" ] || [ -z "$val" ] && return 0
  local cx cy
  cx="$(echo "$bounds" | awk '{print int(($1+$3)/2)}')"
  cy="$(echo "$bounds" | awk '{print int(($2+$4)/2)}')"
  adb -s "$TARGET" shell input tap "$cx" "$cy" >/dev/null
  sleep 0.15
  adb -s "$TARGET" shell input keyevent KEYCODE_MOVE_END >/dev/null || true
  for _ in $(seq 1 95); do
    adb -s "$TARGET" shell input keyevent KEYCODE_DEL >/dev/null || true
  done
  adb_type_safe "$val"
  adb -s "$TARGET" shell input keyevent KEYCODE_ESCAPE >/dev/null 2>&1 || true
  sleep 0.15
}

dump_ui_xml() {
  local xml=""
  local attempt
  for attempt in 1 2 3 4; do
    adb -s "$TARGET" shell rm -f /data/local/tmp/ui_ai_target.xml >/dev/null 2>&1 || true
    adb -s "$TARGET" shell uiautomator dump /data/local/tmp/ui_ai_target.xml >/dev/null 2>&1 || true
    xml="$(adb -s "$TARGET" shell cat /data/local/tmp/ui_ai_target.xml 2>/dev/null | tr -d '\r' || true)"
    adb -s "$TARGET" shell rm -f /data/local/tmp/ui_ai_target.xml >/dev/null 2>&1 || true
    if printf '%s' "$xml" | grep -q 'package="pl.tomaszewski.aiweb"'; then
      printf '%s\n' "$xml"
      return 0
    fi
    sleep 0.4
  done
  printf '%s\n' "$xml"
}

adb -s "$TARGET" wait-for-device
adb -s "$TARGET" shell am start -n pl.tomaszewski.aiweb/.MainActivity >/dev/null
sleep 1.2

UI_XML="$(dump_ui_xml)"
EDIT_LINES="$(printf '%s\n' "$UI_XML" | tr '<' '\n<' | grep 'package="pl.tomaszewski.aiweb"' | grep 'class="android.widget.EditText"' || true)"
BTN_BOUNDS="$(printf '%s\n' "$UI_XML" | tr '<' '\n<' | grep 'package="pl.tomaszewski.aiweb"' | grep -E '(text="TEST AI"|content-desc="TEST AI")' | head -n 1 | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\].*/\1 \2 \3 \4/p' || true)"

EP_BOUNDS="$(printf '%s\n' "$EDIT_LINES" | sed -n '2p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\].*/\1 \2 \3 \4/p' || true)"
MODEL_BOUNDS="$(printf '%s\n' "$EDIT_LINES" | sed -n '3p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\].*/\1 \2 \3 \4/p' || true)"
KEY_BOUNDS="$(printf '%s\n' "$EDIT_LINES" | sed -n '4p' | sed -n 's/.*bounds="\[\([0-9]*\),\([0-9]*\)\]\[\([0-9]*\),\([0-9]*\)\].*/\1 \2 \3 \4/p' || true)"

clear_and_type "$EP_BOUNDS" "$ENDPOINT_URL"
clear_and_type "$MODEL_BOUNDS" "$MODEL_NAME"
clear_and_type "$KEY_BOUNDS" "$API_KEY_VAL"

adb -s "$TARGET" shell am start -n pl.tomaszewski.aiweb/.MainActivity >/dev/null
sleep 1.2

if [ -n "$BTN_BOUNDS" ]; then
  X_TAP="$(echo "$BTN_BOUNDS" | awk '{print int(($1+$3)/2)}')"
  Y_TAP="$(echo "$BTN_BOUNDS" | awk '{print int(($2+$4)/2)}')"
else
  X_TAP="1310"
  Y_TAP="2171"
fi

adb -s "$TARGET" shell input tap "$X_TAP" "$Y_TAP" >/dev/null
sleep 2.5

PID_AI="$(adb -s "$TARGET" shell pidof pl.tomaszewski.aiweb | tr -d '\r' || true)"
echo "TARGET=$TARGET PID_AI=$PID_AI ENDPOINT=$ENDPOINT_URL MODEL=${MODEL_NAME:-<default>} KEY_SET=$([ -n "$API_KEY_VAL" ] && echo 1 || echo 0)"
[ -n "$PID_AI" ] && adb -s "$TARGET" shell logcat -d --pid="$PID_AI" | grep -E "AiWebMainActivity|AndroidNative|E/|F/" | tail -n 10 || true
