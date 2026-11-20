#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_PORT="${1:-}"
ADB_IP="${2:-192.168.1.154}"
PROJ_DIR="$HOME/ai-web-browser-apk"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

[ -f "$MAIN_KT" ] || { echo "ERR_MISSING_MAIN_KT=$MAIN_KT" >&2; exit 1; }
[ -x "$PROJ_DIR/bin/watch_and_deploy_run.sh" ] || { echo "ERR_MISSING_WATCHER=$PROJ_DIR/bin/watch_and_deploy_run.sh" >&2; exit 1; }

cd "$PROJ_DIR"

python3 - "$MAIN_KT" << 'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
src = p.read_text(encoding="utf-8")

# 1. Usuń osierocone linie po fetchPage (np. "} \n } \n else { ... } \n try { ... } catch ...")
src = re.sub(
    r'(\bfun fetchPage\(url: String\): String \{\s*return searchEngine\.fetchUrlText\(url\)\.toString\(\)\s*\})\s*\n\s*\}\s*\n\s*\}\s*\n\s*else\s*\{.*?\n\s*\}\s*catch\s*\(_:\s*Throwable\)\s*\{\s*\}\s*\n?',
    r'\1\n    }\n',
    src,
    flags=re.DOTALL,
)

# 2. Usuń wszelkie wcześniejsze bloki loadTargetUrl
src = re.sub(
    r'\n\s*fun loadTargetUrl\(url: String\)\s*\{.*?\n\s*\}\s*\n?',
    '\n',
    src,
    flags=re.DOTALL,
)

# 3. Utrzymaj otwarty blok class MainActivity aż do samego końca pliku
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

# 4. Zbalansuj klamry do wnętrza MainActivity (depth == 1) i dopisz loadTargetUrl + domknięcie klasy
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
load_fn = (
    "    fun loadTargetUrl(url: String) {\n"
    "        val target = url.trim()\n"
    "        if (target.isEmpty()) return\n"
    '        val resolved = if (target.startsWith("http://") || target.startsWith("https://") || target.startsWith("file://")) {\n'
    "            target\n"
    "        } else {\n"
    '            "https://$target"\n'
    "        }\n"
    "        try {\n"
    f"            {wv_expr}.loadUrl(resolved)\n"
    "        } catch (_: Throwable) {}\n"
    "    }\n"
)

src = src.rstrip() + "\n\n" + load_fn + "}\n"

assert src.count("{") == src.count("}"), f"Niezgodność klamr: {src.count('{')} vs {src.count('}')}"
assert len(re.findall(r'\bfun loadTargetUrl\(', src)) == 1, "Wymagana dokładnie jedna definicja loadTargetUrl"
assert "else {" not in src.splitlines()[-22:], "Wykryto osierocony blok else na końcu MainActivity.kt"

p.write_text(src, encoding="utf-8")
final_lines = src.splitlines()
print(f"MAIN_KT_V2_OK lines={len(final_lines)} braces={src.count('{')}/{src.count('}')}")
for idx in range(max(0, 378), len(final_lines)):
    print(f"{idx+1}: {final_lines[idx]}")
PY

git add -A
git commit -m "fix(aiweb): close AndroidNativeBridge cleanly and keep loadTargetUrl inside MainActivity" || true
git push origin main

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

echo "NEW_RUN_ID=$NEW_RUN_ID"
"$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP"
