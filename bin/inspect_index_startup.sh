#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

HTML_FILE="$HOME/ai-web-browser-apk/app/src/main/assets/index.html"
if [ ! -f "$HTML_FILE" ]; then
  echo "MISSING: $HTML_FILE"
  exit 1
fi

echo "=== ROZMIAR I LICZBA WIERSZY ==="
wc -l -c "$HTML_FILE"

echo "=== POTENCJALNIE CIĘŻKIE OPERACJE PRZY STARCIE ==="
grep -n -E "DOMContentLoaded|window\.onload|requestAnimationFrame|setInterval|setTimeout|fetch\(|XMLHttpRequest|WebSocket|localStorage|sessionStorage|indexedDB|eval\(|new Function|backdrop-filter|blur\(|box-shadow|animate|transition|heavy|loop|while\s*\(|for\s*\(" "$HTML_FILE" || true

echo "=== PEŁNA TREŚĆ (Z NUMERACJĄ WIERSZY) ==="
nl -ba "$HTML_FILE"
