#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_DIR="$HOME/ai-web-browser-apk"
REPO_SLUG="ocean244/ai-web-browser-apk"
REMOTE_URL="https://github.com/${REPO_SLUG}.git"
KS_FILE="$REPO_DIR/keystore/release.jks"
KS_ALIAS="aiweb_release_key"
KS_PASS="AIWebRelease2026!"

cd "$REPO_DIR"

if ! gh auth status >/dev/null 2>&1; then
  if [ -n "${GH_TOKEN:-}" ]; then
    printf '%s\n' "$GH_TOKEN" | gh auth login --with-token
  else
    gh auth login -h github.com -p https -w
  fi
fi

rm -rf "$REPO_DIR/.git"
git init -b main
git config user.name "ocean244"
git config user.email "oceanliev@gmail.com"
git add .
git commit -m "Complete Android project + signed release CI"

if ! gh repo view "$REPO_SLUG" >/dev/null 2>&1; then
  gh repo create "$REPO_SLUG" --public --source="$REPO_DIR" --remote=origin --push
else
  git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"
  git push -u origin main --force
fi

if [ -f "$KS_FILE" ]; then
  KS_B64="$(base64 -w 0 "$KS_FILE" 2>/dev/null || base64 "$KS_FILE" | tr -d '\n')"
  printf '%s\n' "$KS_B64" | gh secret set RELEASE_KEYSTORE_BASE64 --repo "$REPO_SLUG"
  printf '%s\n' "$KS_PASS" | gh secret set RELEASE_STORE_PASSWORD --repo "$REPO_SLUG"
  printf '%s\n' "$KS_ALIAS" | gh secret set RELEASE_KEY_ALIAS --repo "$REPO_SLUG"
  printf '%s\n' "$KS_PASS" | gh secret set RELEASE_KEY_PASSWORD --repo "$REPO_SLUG"
fi

gh workflow run "Build & Release Signed APK" --repo "$REPO_SLUG" --ref main
sleep 3
gh run list --repo "$REPO_SLUG" --limit 3
