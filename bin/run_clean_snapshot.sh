#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:33131}"
PKG_NAME="pl.tomaszewski.aiweb"
LOG_OUT="$PROJ_DIR/out/last_clean_log.txt"

mkdir -p "$PROJ_DIR/out"

if [ -x "$PROJ_DIR/bin/verify_apk.sh" ]; then
  "$PROJ_DIR/bin/verify_apk.sh" "$ADB_TARGET" || true
fi

timeout 12s "$PROJ_DIR/bin/clean_log.sh" "$ADB_TARGET" | tee "$LOG_OUT" || true

echo "=== PODSUMOWANIE LOGÓW: $LOG_OUT ==="
grep -E "AndroidRuntime|FATAL|Exception|Error|chromium|WebView|ImeTracker" "$LOG_OUT" | tail -n 30 || true
