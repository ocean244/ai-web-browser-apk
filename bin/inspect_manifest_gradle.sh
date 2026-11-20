#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
MAN_FILE="$PROJ_DIR/app/src/main/AndroidManifest.xml"
GRD_FILE="$PROJ_DIR/app/build.gradle.kts"
ROOT_GRD="$PROJ_DIR/build.gradle.kts"

echo "=== AndroidManifest.xml ==="
[ -f "$MAN_FILE" ] && nl -ba "$MAN_FILE" || echo "MISSING: $MAN_FILE"

echo "=== app/build.gradle.kts ==="
[ -f "$GRD_FILE" ] && nl -ba "$GRD_FILE" || echo "MISSING: $GRD_FILE"

echo "=== build.gradle.kts ==="
[ -f "$ROOT_GRD" ] && nl -ba "$ROOT_GRD" || echo "MISSING: $ROOT_GRD"
