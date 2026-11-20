#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:36375}"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

cd "$PROJ_DIR"
"$PROJ_DIR/bin/extract_ci_errors.sh" 44689244211 || true

python3 - << 'PY'
from pathlib import Path
import re

p = Path.home() / "ai-web-browser-apk/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
src = p.read_text(encoding="utf-8")

# 1. Zamień this@MainActivity. na activity. wewnątrz bridge, a konstruktor AndroidNativeBridge ustaw na przyjmujący activity
src = src.replace("this@MainActivity.", "activity.")
src = re.sub(
    r'(?:inner\s+)?class\s+AndroidNativeBridge\s*(?:\([^)]*\))?\s*\{',
    'class AndroidNativeBridge(private val activity: MainActivity) {',
    src,
    count=1
)

# 2. Upewnij się, że wywołanie addJavascriptInterface przekazuje activity (`this`)
src = re.sub(
    r'addJavascriptInterface\(\s*AndroidNativeBridge\(\s*\)\s*,',
    'addJavascriptInterface(AndroidNativeBridge(this),',
    src
)

# 3. Wylicz balans nawiasów klamrowych i domknij brakujące '}' na końcu pliku jeśli brakuje
opens = src.count("{")
closes = src.count("}")
if opens > closes:
    src = src.rstrip() + ("\n}" * (opens - closes)) + "\n"
    print(f"BALANCED_BRACES=+{opens - closes}")
else:
    print(f"BALANCED_BRACES=0 (opens={opens}, closes={closes})")

p.write_text(src, encoding="utf-8")
PY

git add -A
git commit -m "fix(aiweb): pass activity into AndroidNativeBridge and balance braces in MainActivity.kt" || true
git push origin main

"$PROJ_DIR/bin/trigger_build_and_deploy.sh" "$ADB_TARGET"
