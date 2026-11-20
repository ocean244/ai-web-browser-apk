#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_TARGET="${1:-192.168.1.154:36375}"
ASSET_HTML="$PROJ_DIR/app/src/main/assets/index.html"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

mkdir -p "$(dirname "$ASSET_HTML")"

cat << 'HTML_EOF' > "$ASSET_HTML"
<!DOCTYPE html>
<html lang="pl">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>AI Web Core</title>
  <style>
    * { box-sizing: border-box; font-family: system-ui, -apple-system, sans-serif; }
    body { margin: 0; padding: 10px; background: #0b0e14; color: #e6edf7; }
    .row { display: flex; gap: 6px; margin-bottom: 8px; flex-wrap: wrap; }
    input, select { flex: 1; min-width: 120px; padding: 9px; border-radius: 8px; border: 1px solid #263247; background: #131924; color: #e6edf7; font-size: 13px; }
    button { padding: 9px 12px; border-radius: 8px; border: 0; background: #10b981; color: #05110c; font-weight: 700; cursor: pointer; font-size: 12px; }
    button.blue { background: #2563eb; color: #ffffff; }
    button.dark { background: #1e293b; color: #cbd5e1; border: 1px solid #334155; }
    pre { white-space: pre-wrap; word-break: break-word; background: #111620; border: 1px solid #202a3c; padding: 10px; border-radius: 8px; font-size: 12px; max-height: 240px; overflow: auto; }
    .res { margin-top: 8px; padding: 10px; border-radius: 8px; background: #121824; border: 1px solid #1e293b; }
    .res a { color: #38bdf8; text-decoration: none; font-weight: 700; display: block; margin-bottom: 4px; }
    .snip { font-size: 12px; color: #94a3b8; }
    .meta { font-size: 11px; color: #10b981; margin-bottom: 6px; }
  </style>
</head>
<body>
  <div class="meta" id="meta">Status: READY | Bridge: checking...</div>
  <div class="row">
    <input id="endpoint" type="text" value="https://api.openai.com/v1/chat/completions" placeholder="Endpoint AI (OpenAI / OpenRouter / Local)" />
    <input id="model" type="text" value="gpt-4o-mini" placeholder="Model" />
  </div>
  <div class="row">
    <input id="apikey" type="password" placeholder="API Key (opcjonalnie dla lokalnego/open endpointu)" />
    <button class="dark" onclick="saveCfg()">SAVE CFG</button>
  </div>
  <div class="row">
    <input id="q" type="text" placeholder="Wpisz zapytanie Web / AI lub adres URL..." />
    <button onclick="doSearch()">SEARCH</button>
    <button class="blue" onclick="doAi()">AI</button>
    <button class="dark" onclick="doWebAi()">WEB+AI</button>
  </div>
  <div id="out"><pre id="log">Bridge ready.</pre></div>
  <script>
    function bridge() { return (typeof window.AndroidNative !== "undefined") ? window.AndroidNative : null; }
    function setMeta(msg) { document.getElementById("meta").textContent = msg; }
    function setLog(msg) { document.getElementById("out").innerHTML = '<pre id="log">' + esc(msg) + '</pre>'; }
    function esc(s) { return String(s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c])); }

    (function init() {
      const b = bridge();
      setMeta("Status: READY | Bridge: " + (b ? "AndroidNative" : "NONE"));
      if (b && typeof b.getConfig === "function") {
        try {
          const cfg = JSON.parse(b.getConfig());
          if (cfg.endpoint) document.getElementById("endpoint").value = cfg.endpoint;
          if (cfg.model) document.getElementById("model").value = cfg.model;
          if (cfg.apiKey) document.getElementById("apikey").value = cfg.apiKey;
        } catch (_) {}
      }
    })();

    function saveCfg() {
      const b = bridge();
      const payload = JSON.stringify({
        endpoint: document.getElementById("endpoint").value.trim(),
        model: document.getElementById("model").value.trim(),
        apiKey: document.getElementById("apikey").value.trim()
      });
      if (b && typeof b.saveConfig === "function") {
        setLog(b.saveConfig(payload));
      } else {
        localStorage.setItem("aiweb_cfg", payload);
        setLog("SAVED_LOCALSTORAGE=OK");
      }
    }

    function openUrl(u) {
      if (!u || u === "#") return;
      const b = bridge();
      if (b && typeof b.openUrl === "function") {
        b.openUrl(u);
      } else {
        location.href = u;
      }
    }

    function renderResults(items) {
      if (!Array.isArray(items) || !items.length) {
        setLog("Brak wyników wyszukiwania.");
        return;
      }
      const html = items.map(r => {
        const u = esc(r.url || "#");
        const t = esc(r.title || r.url || "Wynik");
        const s = esc(r.snippet || "");
        return '<div class="res"><a href="' + u + '" onclick="event.preventDefault();openUrl(this.href)">' + t + '</a><div class="snip">' + s + '</div></div>';
      }).join("");
      document.getElementById("out").innerHTML = html;
    }

    function doSearch() {
      const q = document.getElementById("q").value.trim();
      if (!q) return;
      if (/^https?:\/\//i.test(q)) { openUrl(q); return; }
      const b = bridge();
      if (!b || typeof b.webSearch !== "function") { setLog("Brak AndroidNative.webSearch"); return; }
      try {
        const data = JSON.parse(b.webSearch(q, 10));
        renderResults(data.results || []);
      } catch (e) { setLog("SEARCH_ERR: " + e.message); }
    }

    function doAi() {
      const q = document.getElementById("q").value.trim() || "ping";
      const b = bridge();
      if (!b || typeof b.askAi !== "function") { setLog("Brak AndroidNative.askAi"); return; }
      try {
        saveCfg();
        const data = JSON.parse(b.askAi(q, true));
        setLog(data.content || JSON.stringify(data, null, 2));
      } catch (e) { setLog("AI_ERR: " + e.message); }
    }

    function doWebAi() {
      const q = document.getElementById("q").value.trim();
      if (!q) return;
      const b = bridge();
      if (!b || typeof b.webSearch !== "function" || typeof b.askAi !== "function") {
        setLog("Brak pełnego mostka AndroidNative"); return;
      }
      try {
        saveCfg();
        const sData = JSON.parse(b.webSearch(q, 5));
        const ctx = (sData.results || []).map((r, i) => (i+1) + ". " + (r.title||"") + " (" + (r.url||"") + "): " + (r.snippet||"")).join("\n");
        const prompt = "Na podstawie poniższych wyników wyszukiwania odpowiedz zwięźle i konkretnie na pytanie: " + q + "\n\nŹródła:\n" + ctx;
        const aData = JSON.parse(b.askAi(prompt, true));
        const aiText = aData.content || JSON.stringify(aData, null, 2);
        const resHtml = (sData.results || []).map(r =>
          '<div class="res"><a href="' + esc(r.url || "#") + '" onclick="event.preventDefault();openUrl(this.href)">' + esc(r.title || r.url || "Wynik") + '</a><div class="snip">' + esc(r.snippet || "") + '</div></div>'
        ).join("");
        document.getElementById("out").innerHTML = '<pre id="log">' + esc(aiText) + '</pre>' + resHtml;
      } catch (e) { setLog("WEB_AI_ERR: " + e.message); }
    }
  </script>
</body>
</html>
HTML_EOF

if [ -f "$MAIN_KT" ]; then
  python3 - << 'PY'
from pathlib import Path
p = Path.home() / "ai-web-browser-apk/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
txt = p.read_text(encoding="utf-8")
if "@JavascriptInterface\n    fun saveConfig" not in txt and "class AndroidNativeBridge" in txt:
    addition = """
    @JavascriptInterface
    fun saveConfig(jsonStr: String): String {
        return try {
            val prefs = activity.getSharedPreferences("aiweb_cfg", android.content.Context.MODE_PRIVATE)
            prefs.edit().putString("cfg_json", jsonStr).apply()
            "{\\"ok\\":true,\\"saved\\":true}"
        } catch (e: Exception) {
            "{\\"ok\\":false,\\"error\\":\\"${e.message?.replace("\\\"", "")}\\"}"
        }
    }

    @JavascriptInterface
    fun getConfig(): String {
        val prefs = activity.getSharedPreferences("aiweb_cfg", android.content.Context.MODE_PRIVATE)
        return prefs.getString("cfg_json", "{}") ?: "{}"
    }

    @JavascriptInterface
    fun openUrl(url: String): String {
        activity.runOnUiThread {
            try {
                activity.loadTargetUrl(url)
            } catch (_: Exception) {}
        }
        return "{\\"ok\\":true}"
    }
"""
    idx = txt.rfind("}")
    if idx != -1:
        p.write_text(txt[:idx] + addition + "\n}\n", encoding="utf-8")
        print("BRIDGE_METHODS_ADDED=OK")
PY
fi

cd "$PROJ_DIR"
git add -A
git commit -m "feat(aiweb): add native config persistence, Web+AI synthesis and direct link navigation" || true
git push origin main

"$PROJ_DIR/bin/trigger_build_and_deploy.sh" "$ADB_TARGET"
