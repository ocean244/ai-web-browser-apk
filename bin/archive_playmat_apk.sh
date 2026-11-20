#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

PROJ_DIR="$HOME/ai-web-browser-apk"
PLAYMAT_DIR="$PROJ_DIR/playmat"
APK_NAME="Duck.ai.ver.1.build.1.apk"
DEST_APK="$PLAYMAT_DIR/$APK_NAME"

mkdir -p "$PLAYMAT_DIR"

CANDIDATES=(
  "$HOME/storage/downloads/$APK_NAME"
  "/sdcard/Download/$APK_NAME"
  "$PROJ_DIR/$APK_NAME"
  "$PWD/$APK_NAME"
)

FOUND_APK=""
for cand in "${CANDIDATES[@]}"; do
  if [ -f "$cand" ]; then
    FOUND_APK="$cand"
    break
  fi
done

if [ -z "$FOUND_APK" ]; then
  FOUND_APK="$(find "$HOME" /sdcard -maxdepth 3 -name "$APK_NAME" 2>/dev/null | head -n 1 || true)"
fi

if [ -z "${FOUND_APK:-}" ] || [ ! -f "$FOUND_APK" ]; then
  echo "APK_SOURCE_NOT_FOUND=$APK_NAME"
  exit 1
fi

cp -f "$FOUND_APK" "$DEST_APK"
sha256sum "$DEST_APK"

python3 - << 'PY'
import zipfile, pathlib

apk_path = pathlib.Path.home() / "ai-web-browser-apk/playmat/Duck.ai.ver.1.build.1.apk"
with zipfile.ZipFile(apk_path, "r") as zf:
    names = zf.namelist()
    print(f"ZIP_ENTRIES={len(names)}")
    for prefix in ("AndroidManifest.xml", "res/xml/shortcuts.xml", "resources.arsc", "classes.dex", "META-INF/"):
        matches = [n for n in names if n == prefix or n.startswith(prefix)]
        print(f"MATCH[{prefix}]={len(matches)} -> {matches[:5]}")
PY

cd "$PROJ_DIR"
git add playmat/
git commit -m "chore(playmat): archive Duck.ai.ver.1.build.1.apk reference package" || true
git push origin main
echo "PLAYMAT_ARCHIVED_OK=$DEST_APK"
