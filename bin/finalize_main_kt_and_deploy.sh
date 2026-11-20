#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:36375}"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

cd "$PROJ_DIR"
"$PROJ_DIR/bin/extract_ci_errors.sh" 44689646167 || true

python3 - << 'PY'
from pathlib import Path
import re

p = Path.home() / "ai-web-browser-apk/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
src = p.read_text(encoding="utf-8")

# 1. Usuń nadmiarowe '}' dopisane na samym końcu pliku z poprzedniego kroku jeśli brak równowagi
while src.rstrip().endswith("}") and src.count("}") > src.count("{"):
    idx = src.rfind("}")
    src = src[:idx] + src[idx+1:]

# 2. Upewnij się, że istnieje publiczna fun loadTargetUrl(url: String) w MainActivity
if "fun loadTargetUrl(" not in src:
    wv_expr = "webView"
    if "binding.webView" in src:
        wv_expr = "binding.webView"
    elif "private lateinit var webView" not in src and "var webView" not in src:
        wv_expr = "findViewById<android.webkit.WebView>(android.R.id.webview) ?: webView"

    load_fn = f"""
    fun loadTargetUrl(url: String) {{
        val target = url.trim()
        if (target.isEmpty()) return
        val resolved = if (target.startsWith("http://") || target.startsWith("https://") || target.startsWith("file://")) {{
            target
        }} else {{
            "https://$target"
        }}
        try {{
            {wv_expr}.loadUrl(resolved)
        }} catch (_: Throwable) {{}}
    }}
"""
    # Wstaw przed klasą AndroidNativeBridge lub przed ostatnim '}'
    m_bridge = re.search(r'\n\s*(?:inner\s+)?class\s+AndroidNativeBridge\b', src)
    if m_bridge:
        src = src[:m_bridge.start()] + "\n" + load_fn + src[m_bridge.start():]
        print("LOAD_TARGET_URL_INSERTED_BEFORE_BRIDGE=OK")
    else:
        last_brace = src.rfind("}")
        if last_brace != -1:
            src = src[:last_brace] + load_fn + "}\n"
            print("LOAD_TARGET_URL_APPENDED=OK")

# 3. Domknij brakujące '}' jeśli po wstawkach opens > closes
opens = src.count("{")
closes = src.count("}")
if opens > closes:
    src = src.rstrip() + ("\n}" * (opens - closes)) + "\n"
    print(f"FINAL_BALANCED_BRACES=+{opens - closes}")
else:
    print(f"FINAL_BRACES_OK (opens={opens}, closes={closes})")

p.write_text(src, encoding="utf-8")
PY

git add -A
git commit -m "fix(aiweb): define loadTargetUrl and restore brace balance in MainActivity.kt" || true
git push origin main

"$PROJ_DIR/bin/trigger_build_and_deploy.sh" "$ADB_TARGET"
