#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_SLUG="ocean244/ai-web-browser-apk"
RUN_ID="44650417142"

echo "=== STATUS RUNA: $RUN_ID ==="
gh run view "$RUN_ID" --repo "$REPO_SLUG" || true

echo "=== LOGI NIEUDANYCH KROKÓW ==="
gh run view "$RUN_ID" --repo "$REPO_SLUG" --log-failed || true
