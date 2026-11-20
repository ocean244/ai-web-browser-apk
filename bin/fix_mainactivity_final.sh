#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_PORT="${1:-}"
ADB_IP="${2:-192.168.1.154}"
PROJ_DIR="$HOME/ai-web-browser-apk"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

cd "$PROJ_DIR"

python3 - << 'PY'
from pathlib import Path
import re

p = Path.home() / "ai-web-browser-apk/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
src = p.read_text(encoding="utf-8")

# 1. Usuń osierocone bloki/linie " else { ... " lub "try { webView.loadUrl(resolved) }" po fetchPage
src = re.sub(
    r'\n\s*else\s*\{\s*\n\s*"https://\$target"\s*\n\s*\}\s*\n\s*try\s*\{\s*\n\s*(?:binding\.)?webView\.loadUrl\(resolved\)\s*\n\s*\}\s*catch\s*\(_:\s*Throwable\)\s*\{\s*\}\s*\n?',
    '\n',
    src,
    flags=re.DOTALL
)

# 2. Usuń wszelkie istniejące bloki loadTargetUrl, aby wstawić jeden czysty wewnątrz MainActivity
src = re.sub(
    r'\n\s*fun loadTargetUrl\(url: String\)\s*\{.*?\n\s*\}\s*\n?',
    '\n',
    src,
    flags=re.DOTALL
)

# 3. Śledź głębokość klamr od 'class MainActivity' i nie dopuść do zamknięcia MainActivity przed końcem pliku
lines = src.splitlines()
out_lines = []
depth = 0
in_main_class = False

for i, line in enumerate(lines):
    if not in_main_class and re.search(r'\bclass\s+MainActivity\b', line):
        in_main_class = True

    opens = line.count("{")
    closes = line.count("}")

    if in_main_class:
        next_depth = depth + opens - closes
        remaining = "\n".join(lines[i + 1 :]).strip()
        if next_depth <= 0 and remaining:
            excess = 1 - next_depth
            fixed_line = line
            for _ in range(excess):
                pos = fixed_line.rfind("}")
                if pos != -1:
                    fixed_line = fixed_line[:pos] + fixed_line[pos + 1 :]
            opens = fixed_line.count("{")
            closes = fixed_line.count("}")
            depth += opens - closes
            if fixed_line.strip():
                out_lines.append(fixed_line)
            continue

    depth += opens - closes
    out_lines.append(line)

src = "\n".join(out_lines).rstrip() + "\n"

# 4. Zbalansuj klamry do poziomu wnętrza MainActivity (depth == 1) i dopisz loadTargetUrl + domknięcie klasy
while src.rstrip().endswith("}") and src.count("}") >= src.count("{"):
    idx = src.rfind("}")
    src = src[:idx]

opens = src.count("{")
closes = src.count("}")
if opens - closes > 1:
    src = src.rstrip() + ("\n    }" * (opens - closes - 1)) + "\n"
elif opens - closes < 1:
    raise RuntimeError(f"Brak otwartego bloku MainActivity: opens={opens}, closes={closes}")

wv_expr = "binding.webView" if "binding.webView" in src else "webView"
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

src = src.rstrip() + "\n" + load_fn + "}\n"

assert src.count("{") == src.count("}"), f"Niezgodność klamr: {src.count('{')} vs {src.count('}')}"
assert len(re.findall(r'\bfun loadTargetUrl\(', src)) == 1, "Wymagana dokładnie jedna definicja loadTargetUrl"

p.write_text(src, encoding="utf-8")

final_lines = src.splitlines()
print(f"MAIN_KT_CLEAN_OK lines={len(final_lines)} braces={src.count('{')}/{src.count('}')}")
for idx in range(max(0, 319), len(final_lines)):
    print(f"{idx+1}: {final_lines[idx]}")
PY

git add -A
git commit -m "fix(aiweb): remove orphan else block and keep MainActivity open through loadTargetUrl" || true
git push origin main

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

echo "NEW_RUN_ID=$NEW_RUN_ID"
"$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP"
