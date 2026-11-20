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

fn_sig = re.search(r"(?m)^[ \t]*fun loadTargetUrl\(url: String\)\s*\{", src)
if not fn_sig:
    raise RuntimeError("Nie znaleziono nagłówka 'fun loadTargetUrl(url: String) {'")

# Cofnij się przed fun loadTargetUrl i usuń osierocone linie/klamry z końca części poprzedzającej
prefix_lines = src[: fn_sig.start()].splitlines()
while prefix_lines and (
    prefix_lines[-1].strip() in ("", "}", "try {", "} catch (_: Throwable) {}")
    or "webView.loadUrl(" in prefix_lines[-1]
):
    prefix_lines.pop()

# Wyodrębnij ciało funkcji loadTargetUrl od nagłówka do końca pliku
fn_and_tail = src[fn_sig.start() :].splitlines()
# Znajdź koniec bloku loadTargetUrl (pierwsze '}' na kolumnie 4 lub 0 po otwarciu)
fn_lines = []
depth = 0
started = False
tail_extra = []
for ln in fn_and_tail:
    if not started:
        fn_lines.append(ln)
        depth += ln.count("{") - ln.count("}")
        started = True
    else:
        if depth > 0:
            fn_lines.append(ln)
            depth += ln.count("{") - ln.count("}")
        else:
            if ln.strip() not in ("", "}"):
                tail_extra.append(ln)

rebuilt = (
    "\n".join(prefix_lines).rstrip()
    + "\n\n"
    + "\n".join(fn_lines).rstrip()
    + ("\n" + "\n".join(tail_extra) if tail_extra else "")
    + "\n"
)

# Wyrównaj bilans klamr na końcu pliku
opens = rebuilt.count("{")
closes = rebuilt.count("}")
if opens > closes:
    rebuilt = rebuilt.rstrip() + ("\n}" * (opens - closes)) + "\n"
elif closes > opens:
    for _ in range(closes - opens):
        idx = rebuilt.rfind("}")
        if idx != -1:
            rebuilt = rebuilt[:idx] + rebuilt[idx + 1 :]
    rebuilt = rebuilt.rstrip() + "\n"

opens_f = rebuilt.count("{")
closes_f = rebuilt.count("}")
assert opens_f == closes_f, f"Niezgodność klamr: {opens_f}/{closes_f}"
assert len(re.findall(r"\bfun loadTargetUrl\(", rebuilt)) == 1
assert rebuilt.splitlines()[-1].strip() == "}"

p.write_text(rebuilt, encoding="utf-8")
lines = rebuilt.splitlines()
print(f"MAIN_KT_CLEAN_TAIL_OK lines={len(lines)} braces={opens_f}/{closes_f}")
for idx in range(max(0, len(lines) - 24), len(lines)):
    print(f"{idx+1}: {lines[idx]}")
PY

git add -A
git commit -m "fix(aiweb): clean orphaned lines before loadTargetUrl and balance braces" || true
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
