#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:36375}"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

cd "$PROJ_DIR"
"$PROJ_DIR/bin/extract_ci_errors.sh" 44687472327 || true

python3 - << 'PY'
from pathlib import Path
import re

p = Path.home() / "ai-web-browser-apk/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
if not p.exists():
    print("MAIN_KT_MISSING")
    raise SystemExit(1)

src = p.read_text(encoding="utf-8")

# Usuń ewentualny błędnie doklejony blok na końcu i odbuduj czyste metody w AndroidNativeBridge
src = re.sub(
    r'\n\s*@JavascriptInterface\s+fun saveConfig\(jsonStr: String\): String \{.*?\n\}\s*$',
    '\n',
    src,
    flags=re.S
)

if "private fun loadTargetUrl(" not in src:
    helper = """
    fun loadTargetUrl(url: String) {
        val target = url.trim()
        if (target.isEmpty()) return
        val resolved = if (target.startsWith("http://") || target.startsWith("https://") || target.startsWith("file://")) {
            target
        } else {
            "https://$target"
        }
        try {
            webView.loadUrl(resolved)
        } catch (_: Throwable) {}
    }
"""
    last_brace = src.rfind("}")
    if last_brace != -1:
        src = src[:last_brace] + helper + "}\n"

bridge_methods = """
    @android.webkit.JavascriptInterface
    fun saveConfig(jsonStr: String): String {
        return try {
            val prefs = activity.getSharedPreferences("aiweb_cfg", android.content.Context.MODE_PRIVATE)
            prefs.edit().putString("cfg_json", jsonStr).apply()
            "{\\"ok\\":true,\\"saved\\":true}"
        } catch (e: Throwable) {
            val msg = (e.message ?: "error").replace("\\"", "'")
            "{\\"ok\\":false,\\"error\\":\\"$msg\\"}"
        }
    }

    @android.webkit.JavascriptInterface
    fun getConfig(): String {
        return try {
            val prefs = activity.getSharedPreferences("aiweb_cfg", android.content.Context.MODE_PRIVATE)
            prefs.getString("cfg_json", "{}") ?: "{}"
        } catch (_: Throwable) {
            "{}"
        }
    }

    @android.webkit.JavascriptInterface
    fun openUrl(url: String): String {
        return try {
            activity.runOnUiThread {
                activity.loadTargetUrl(url)
            }
            "{\\"ok\\":true}"
        } catch (e: Throwable) {
            val msg = (e.message ?: "error").replace("\\"", "'")
            "{\\"ok\\":false,\\"error\\":\\"$msg\\"}"
        }
    }
"""

m = re.search(r'(class\s+AndroidNativeBridge[^{]*\{)', src)
if m and "fun saveConfig(jsonStr: String): String" not in src:
    ins_pos = m.end()
    src = src[:ins_pos] + bridge_methods + src[ins_pos:]
    print("INJECTED_INTO_ANDROID_NATIVE_BRIDGE=OK")
else:
    print("BRIDGE_CHECK_DONE")

p.write_text(src, encoding="utf-8")
PY

git add -A
git commit -m "fix(aiweb): place JavascriptInterface methods inside AndroidNativeBridge and add loadTargetUrl" || true
git push origin main

"$PROJ_DIR/bin/trigger_build_and_deploy.sh" "$ADB_TARGET"
