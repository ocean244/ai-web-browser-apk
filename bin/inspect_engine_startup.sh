#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
SVC_FILE="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/LocalEngineService.kt"
CLI_FILE="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/AiBridgeClient.kt"
MAN_FILE="$PROJ_DIR/app/src/main/AndroidManifest.xml"

echo "=== LocalEngineService.kt ==="
[ -f "$SVC_FILE" ] && nl -ba "$SVC_FILE" || echo "MISSING: $SVC_FILE"

echo "=== AiBridgeClient.kt ==="
[ -f "$CLI_FILE" ] && nl -ba "$CLI_FILE" || echo "MISSING: $CLI_FILE"

echo "=== AndroidManifest.xml (service / intent-filter) ==="
[ -f "$MAN_FILE" ] && grep -n -C 5 -E "<service|LocalEngineService|START_STICKY|boot|foregroundService" "$MAN_FILE" || true
