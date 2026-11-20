#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:36375}"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

cd "$PROJ_DIR"
"$PROJ_DIR/bin/extract_ci_errors.sh" 44688267310 || true

python3 - << 'PY'
from pathlib import Path
import re

p = Path.home() / "ai-web-browser-apk/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
src = p.read_text(encoding="utf-8")

# Sprawdź czy AndroidNativeBridge jest klasą wewnętrzną MainActivity czy samodzielną klasą
is_inner = bool(re.search(r'\b(inner\s+)?class\s+AndroidNativeBridge\b', src))

if is_inner:
    # Zamień wywołania activity.<cos> wewnątrz AndroidNativeBridge na this@MainActivity.<cos>
    def repl_inner(m):
        block = m.group(0)
        block = re.sub(r'\bactivity\.', 'this@MainActivity.', block)
        return block

    src, n = re.subn(r'(class\s+AndroidNativeBridge\b[\s\S]*?\n\})', repl_inner, src, count=1)
    print(f"INNER_BRIDGE_PATCHED={n}")
else:
    # Jeśli klasa ma konstruktor, dodaj private val activity: MainActivity jeśli brak
    def repl_ctor(m):
        header = m.group(0)
        if "activity" in header:
            return header
        if "(" in header and ")" in header:
            return re.sub(r'\)\s*\{', ', private val activity: MainActivity) {', header, count=1)
        return header.rstrip("{") + "(private val activity: MainActivity) {"

    src = re.sub(r'class\s+AndroidNativeBridge[^{]*\{', repl_ctor, src, count=1)
    print("STANDALONE_BRIDGE_CTOR_PATCHED=OK")

p.write_text(src, encoding="utf-8")
PY

git add -A
git commit -m "fix(aiweb): resolve activity reference inside AndroidNativeBridge" || true
git push origin main

"$PROJ_DIR/bin/trigger_build_and_deploy.sh" "$ADB_TARGET"
