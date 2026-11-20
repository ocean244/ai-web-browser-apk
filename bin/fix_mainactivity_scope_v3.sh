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

# Wytnij wszystko od 'fun fetchPage' do końca pliku i odbuduj końcówkę deterministycznie
anchor = re.search(r'([ \t]*fun fetchPage\(url: String\): String\s*\{[\s\S]*?\n[ \t]*\})', src)
if not anchor:
    raise RuntimeError("Nie znaleziono bloku fun fetchPage(url: String): String")

prefix = src[: anchor.start()]
fetch_block = anchor.group(1)

# Utrzymaj otwarty blok class MainActivity w prefixie (depth >= 1 na końcu prefixu)
lines = prefix.splitlines()
out_lines = []
depth = 0
in_main_class = False

for line in lines:
    if not in_main_class and re.search(r'\bclass\s+MainActivity\b', line):
        in_main_class = True

    opens = line.count("{")
    closes = line.count("}")

    if in_main_class and (depth + opens - closes) < 1:
        excess = 1 - (depth + opens - closes)
        fixed = line
        for _ in range(excess):
            pos = fixed.rfind("}")
            if pos != -1:
                fixed = fixed[:pos] + fixed[pos + 1 :]
        opens = fixed.count("{")
        closes = fixed.count("}")
        depth += opens - closes
        if fixed.strip():
            out_lines.append(fixed)
        continue

    depth += opens - closes
    out_lines.append(line)

# Po dodaniu fetch_block (otwiera i zamyka swój blok, bilans klamr = 0),
# głębokość wewnątrz MainActivity powinna wynosić >= 1 (wnętrze MainActivity).
clean_prefix = "\n".join(out_lines).rstrip()
current_depth = clean_prefix.count("{") - clean_prefix.count("}")
if current_depth < 1:
    raise RuntimeError(f"Głębokość MainActivity po fetchPage < 1: {current_depth}")

# Jeśli przed fetchPage był otwarty blok AndroidNativeBridge (current_depth >= 2),
# domykamy go przed wstawieniem loadTargetUrl na poziomie klasy MainActivity.
close_bridge = "    }\n\n" if current_depth >= 2 else "\n"

wv_expr = "binding.webView" if "binding.webView" in clean_prefix else "webView"
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

# Po domknięciu AndroidNativeBridge (jeśli było otwarte) pozostaje dokładnie 1 otwarty blok: class MainActivity.
# Wstawiamy loadTargetUrl i domykamy class MainActivity.
rebuilt = clean_prefix + "\n" + fetch_block + "\n" + close_bridge + load_fn + "}\n"

# Wyrównaj ewentualne dodatkowe otwarte klamry (jeśli current_depth > 2)
rem_opens = rebuilt.count("{")
rem_closes = rebuilt.count("}")
if rem_opens > rem_closes:
    tail = "\n" + ("}\n" * (rem_opens - rem_closes))
    rebuilt = rebuilt.rstrip() + tail

assert rebuilt.count("{") == rebuilt.count("}"), f"Niezgodność klamr: {rebuilt.count('{')} vs {rebuilt.count('}')}"
assert len(re.findall(r'\bfun loadTargetUrl\(', rebuilt)) == 1, "Wymagana dokładnie jedna definicja loadTargetUrl"
assert "else {" not in rebuilt.splitlines()[-22:], "Wykryto osierocony blok else"

p.write_text(rebuilt, encoding="utf-8")
final_lines = rebuilt.splitlines()
print(f"MAIN_KT_V3_OK lines={len(final_lines)} braces={rebuilt.count('{')}/{rebuilt.count('}')}")
for idx in range(max(0, len(final_lines) - 24), len(final_lines)):
    print(f"{idx+1}: {final_lines[idx]}")
PY

git add -A
git commit -m "fix(aiweb): rebuild fetchPage tail cleanly and keep loadTargetUrl in MainActivity" || true
git push origin main

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi

echo "NEW_RUN_ID=$NEW_RUN_ID"
"$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP"
