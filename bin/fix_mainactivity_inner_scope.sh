#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

ADB_PORT="${1:-}"
ADB_IP="${2:-192.168.1.154}"
PROJ_DIR="$HOME/ai-web-browser-apk"
MAIN_KT="$PROJ_DIR/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"

[ -f "$MAIN_KT" ] || { echo "ERR_MISSING_MAIN_KT=$MAIN_KT" >&2; exit 1; }

cd "$PROJ_DIR"

python3 - "$MAIN_KT" << 'PY'
import re
import sys
from pathlib import Path

p = Path(sys.argv[1])
raw = p.read_text(encoding="utf-8")
src = re.sub(r"[\x00-\x08\x0b\x0c\x0e-\x1f]", "", raw).replace("\r\n", "\n")

load_match = re.search(
    r"(?ms)^[ \t]*fun loadTargetUrl\(url: String\)(?::\s*Unit)?\s*\{.*?^[ \t]*\}\s*$",
    src,
)
if load_match:
    src = (src[: load_match.start()] + src[load_match.end() :]).rstrip() + "\n"

lines = src.splitlines()
while lines and lines[-1].strip() in ("", "}"):
    lines.pop()

in_main = False
depth = 0
fixed_lines = []

for line in lines:
    if not in_main and re.search(r"\bclass\s+MainActivity\b", line):
        in_main = True

    cur_line = line
    if in_main:
        opens = cur_line.count("{")
        closes = cur_line.count("}")
        if depth + opens - closes < 1:
            needed_drop = depth + opens - closes - 1
            while needed_drop < 0 and "}" in cur_line:
                idx = cur_line.rfind("}")
                cur_line = cur_line[:idx] + cur_line[idx + 1 :]
                needed_drop += 1
        depth += cur_line.count("{") - cur_line.count("}")
        if cur_line.strip() != "" or (fixed_lines and fixed_lines[-1].strip() != ""):
            fixed_lines.append(cur_line)
    else:
        fixed_lines.append(cur_line)

body = "\n".join(fixed_lines).rstrip()
current_depth = body.count("{") - body.count("}")

close_bridge = ""
if current_depth >= 2:
    close_bridge = "    }\n\n"
    current_depth -= 1

load_target_fn = (
    "    fun loadTargetUrl(url: String) {\n"
    "        val target = url.trim()\n"
    "        if (target.isEmpty()) return\n"
    '        val resolved = if (target.startsWith("http://") || target.startsWith("https://") || target.startsWith("file://")) {\n'
    "            target\n"
    "        } else {\n"
    '            "https://$target"\n'
    "        }\n"
    "        try {\n"
    "            webView.loadUrl(resolved)\n"
    "        } catch (_: Throwable) {}\n"
    "    }\n"
)

closing_braces = "}\n" * max(1, current_depth)
rebuilt = body + "\n\n" + close_bridge + load_target_fn + closing_braces

opens_f = rebuilt.count("{")
closes_f = rebuilt.count("}")
assert opens_f == closes_f, f"Niezgodność klamr po naprawie: {opens_f}/{closes_f}"
assert len(re.findall(r"\bfun loadTargetUrl\(", rebuilt)) == 1
assert rebuilt.splitlines()[-1].strip() == "}"

p.write_text(rebuilt, encoding="utf-8")
out_lines = rebuilt.splitlines()
print(f"MAIN_KT_INNER_SCOPE_OK lines={len(out_lines)} braces={opens_f}/{closes_f}")
for idx in range(max(0, len(out_lines) - 22), len(out_lines)):
    print(f"{idx+1}: {out_lines[idx]}")
PY

git add -A
git commit -m "fix(aiweb): keep loadTargetUrl inside MainActivity class scope" || true
git push origin main
HEAD_SHA="$(git rev-parse HEAD)"
echo "HEAD_SHA=$HEAD_SHA"

NEW_RUN_ID="$(gh workflow run "build-apk.yml" --ref main --json databaseId --jq '.databaseId' 2>/dev/null || true)"
if [ -z "$NEW_RUN_ID" ]; then
  sleep 2
  NEW_RUN_ID="$(gh run list --workflow="build-apk.yml" --branch main --limit 1 --json databaseId --jq '.[0].databaseId')"
fi
echo "NEW_RUN_ID=$NEW_RUN_ID"

if [ -x "$PROJ_DIR/bin/watch_and_deploy_run.sh" ]; then
  "$PROJ_DIR/bin/watch_and_deploy_run.sh" "$NEW_RUN_ID" "$ADB_PORT" "$ADB_IP" || true
fi

LATEST_ID="$(gh run list --limit 1 --json databaseId --jq '.[0].databaseId')"
echo "LATEST_RUN_ID=$LATEST_ID"
gh run view "$LATEST_ID" --log-failed 2>/dev/null | grep -E "Could not find |FAILURE:|BUILD FAILED|^e: " | head -n 40 || true
