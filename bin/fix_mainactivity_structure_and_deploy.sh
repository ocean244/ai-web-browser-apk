#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
ADB_IP="${1:-192.168.1.154}"
shift || true
CANDIDATE_PORTS=("$@" "35231" "36375" "5555")
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

cd "$PROJ_DIR"

python3 - << 'PY'
from pathlib import Path
import re

p = Path.home() / "ai-web-browser-apk/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
src = p.read_text(encoding="utf-8")

# 1. Usuń ewentualne duplikaty loadTargetUrl wstawione wcześniej na złym poziomie
src = re.sub(
    r'\n\s*fun loadTargetUrl\(url: String\)\s*\{.*?\n\s*\}\n',
    '\n',
    src,
    flags=re.DOTALL
)

# 2. Analiza głębokości klamr: klasa MainActivity pozostaje otwarta (depth >= 1)
# aż do samego końca klasy (po wszystkich metodach i AndroidNativeBridge).
lines = src.splitlines()
out_lines = []
depth = 0
in_main_class = False

for i, line in enumerate(lines):
    stripped = line.strip()
    if not in_main_class and re.search(r'\bclass\s+MainActivity\b', stripped):
        in_main_class = True

    opens = line.count("{")
    closes = line.count("}")

    if in_main_class:
        next_depth = depth + opens - closes
        remaining = "\n".join(lines[i+1:]).strip()
        if next_depth <= 0 and remaining:
            excess = 1 - next_depth
            fixed_line = line
            for _ in range(excess):
                pos = fixed_line.rfind("}")
                if pos != -1:
                    fixed_line = fixed_line[:pos] + fixed_line[pos+1:]
            opens = fixed_line.count("{")
            closes = fixed_line.count("}")
            depth += opens - closes
            if fixed_line.strip():
                out_lines.append(fixed_line)
            continue

    depth += opens - closes
    out_lines.append(line)

src = "\n".join(out_lines).rstrip() + "\n"

# 3. Upewnij się, że loadTargetUrl(url: String) znajduje się WEWNĄTRZ MainActivity
wv_expr = "webView"
if "binding.webView" in src:
    wv_expr = "binding.webView"

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

while src.rstrip().endswith("}") and src.count("}") >= src.count("{"):
    idx = src.rfind("}")
    src = src[:idx]

opens = src.count("{")
closes = src.count("}")
if opens - closes > 1:
    src = src.rstrip() + ("\n    }" * (opens - closes - 1)) + "\n"
elif opens - closes < 1:
    raise RuntimeError(f"Nieprawidłowy stan klamr przed domknięciem klasy: opens={opens}, closes={closes}")

src = src.rstrip() + "\n" + load_fn + "}\n"

assert src.count("{") == src.count("}"), f"Niezgodność klamr: {src.count('{')} vs {src.count('}')}"
p.write_text(src, encoding="utf-8")
print(f"MAIN_ACTIVITY_FIXED_OK lines={len(src.splitlines())} braces={src.count('{')}/{src.count('}')}")
PY

git add -A
git commit -m "fix(aiweb): keep MainActivity class scope open for all methods and loadTargetUrl" || true
git push origin main

RESOLVED_ADB=""
if command -v adb >/dev/null 2>&1; then
  adb start-server >/dev/null 2>&1 || true
  for PORT in "${CANDIDATE_PORTS[@]}"; do
    TARGET="${ADB_IP}:${PORT}"
    if adb connect "$TARGET" 2>/dev/null | grep -qiE "connected to|already connected"; then
      RESOLVED_ADB="$TARGET"
      break
    fi
  done
fi

if [ -z "$RESOLVED_ADB" ]; then
  RESOLVED_ADB="${ADB_IP}:5555"
  echo "WARN_ADB_PORT_UNREACHABLE: podaj aktualny port z ekranu Debugowanie bezprzewodowe (np. ~/ai-web-browser-apk/bin/fix_mainactivity_structure_and_deploy.sh 192.168.1.154 <PORT>)"
fi

echo "RESOLVED_ADB=$RESOLVED_ADB"
"$PROJ_DIR/bin/trigger_build_and_deploy.sh" "$RESOLVED_ADB" || true
