#!/usr/bin/env bash
set -euo pipefail

RAW_TARGET="${1:-192.168.1.154:33177}"
REQ_PORT="${2:-18080}"
TARGET="$("$HOME/ai-web-browser-apk/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"

run_case() {
  local model="$1"
  local key="$2"
  local out
  out="$("$HOME/ai-web-browser-apk/bin/verify_ai_payload.sh" "$TARGET" "$REQ_PORT" "$model" "$key")"
  printf '%s\n' "$out"
  printf '%s\n' "$out" | grep -q "\"model\":\"${model}\""
  printf '%s\n' "$out" | grep -q '"role":"user","content":"ping"'
}

"$HOME/ai-web-browser-apk/bin/verify_ai_e2e.sh" "$TARGET" "$REQ_PORT" "--mock"
run_case "gpt-4o-mini" ""
run_case "qwen2.5-coder:7b" ""
run_case "llama3.1:8b" "sk-test-key"
echo "SUITE_STATUS=ALL_PASS TARGET=$TARGET"
