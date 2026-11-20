#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
PLAYMAT_APK="$PROJ_DIR/playmat/Duck.ai.ver.1.build.1.apk"
REPORT_OUT="$PROJ_DIR/out/playmat_audit.txt"

mkdir -p "$PROJ_DIR/out"

if [ ! -f "$PLAYMAT_APK" ]; then
  echo "MISSING_PLAYMAT_APK=$PLAYMAT_APK"
  exit 1
fi

python3 - << 'PY' > "$REPORT_OUT"
import pathlib, re, zipfile

apk = pathlib.Path.home() / "ai-web-browser-apk/playmat/Duck.ai.ver.1.build.1.apk"
print(f"APK_PATH={apk}")
with zipfile.ZipFile(apk, "r") as zf:
    for info in zf.infolist():
        print(f"ENTRY size={info.file_size:7d} compress={info.compress_size:7d} name={info.filename}")
    raw_arsc = zf.read("resources.arsc")
    ascii_strings = sorted(set(
        s.decode("ascii", errors="ignore")
        for s in re.findall(rb"[A-Za-z0-9_./:-]{4,80}", raw_arsc)
    ))
    interesting = [
        s for s in ascii_strings
        if any(k in s.lower() for k in ("duck", "shortcut", "browser", "web", "splash", "host", "url", "http", "ai"))
    ]
    print(f"INTERESTING_STRINGS_COUNT={len(interesting)}")
    for item in interesting[:60]:
        print(f"STR: {item}")
PY

cat "$REPORT_OUT" | tail -n 35
cd "$PROJ_DIR"
git add out/playmat_audit.txt bin/audit_playmat_and_push.sh
git commit -m "feat(playmat): add automated APK manifest/resource audit script and report" || true
git push origin main
echo "PLAYMAT_AUDIT_COMPLETE=$REPORT_OUT"
