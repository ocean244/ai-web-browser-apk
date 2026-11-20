#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$HOME/ai-web-browser-apk}"
REMOTE_URL="${2:-}"
BRANCH_NAME="${3:-main}"
RAW_TARGET="${4:-192.168.1.154}"
REVERSE_PORT="${5:-18080}"
PKG_NAME="pl.tomaszewski.aiweb"
MAIN_ACT="pl.tomaszewski.aiweb/.MainActivity"

if [ -z "$REMOTE_URL" ] || [[ "$REMOTE_URL" =~ [<>] ]] || [[ "$REMOTE_URL" =~ (TWOJ_LOGIN|TWOJE_REPO|TWOJA_NAZWA) ]]; then
  echo "ERR: Podaj realny URL repozytorium GitHub jako 2. argument (np. https://github.com/LOGIN/REPO.git)" >&2
  exit 1
fi

cd "$PROJECT_DIR"

cat << 'GITIGNORE' > "$PROJECT_DIR/.gitignore"
.gradle/
build/
**/build/
local.properties
.idea/
*.iml
tmp/
out/apk_artifact/
*.log
GITIGNORE

if [ ! -d "$PROJECT_DIR/.git" ]; then
  git init -b "$BRANCH_NAME"
fi

git config user.name "${GIT_USER_NAME:-Rafal Tomaszewski}"
git config user.email "${GIT_USER_EMAIL:-rafal@tomaszewski.pl}"

if git remote get-url origin >/dev/null 2>&1; then
  git remote set-url origin "$REMOTE_URL"
else
  git remote add origin "$REMOTE_URL"
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -m "feat(aiweb): automated full-stack AI web browser & search engine build"
fi

if [ -n "${GH_TOKEN:-}" ] && [[ "$REMOTE_URL" == https://* ]]; then
  CLEAN_URL="${REMOTE_URL#https://}"
  if [ -n "${GH_USER:-}" ]; then
    AUTH_URL="https://${GH_USER}:${GH_TOKEN}@${CLEAN_URL}"
  else
    AUTH_URL="https://${GH_TOKEN}@${CLEAN_URL}"
  fi
  git push "$AUTH_URL" "$BRANCH_NAME" --force
else
  git push -u origin "$BRANCH_NAME" --force
fi

echo "GITHUB_PUSH=OK BRANCH=$BRANCH_NAME REMOTE=$REMOTE_URL"

if command -v gh >/dev/null 2>&1; then
  REPO_SLUG="$(printf '%s' "$REMOTE_URL" | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##')"
  gh workflow run "build-ai-web-apk.yml" --repo "$REPO_SLUG" --ref "$BRANCH_NAME" >/dev/null 2>&1 || true
  sleep 4
  RUN_ID="$(gh run list --repo "$REPO_SLUG" --branch "$BRANCH_NAME" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  if [ -n "$RUN_ID" ]; then
    echo "GH_RUN_ID=$RUN_ID REPO=$REPO_SLUG"
    gh run watch "$RUN_ID" --repo "$REPO_SLUG" --exit-status
    mkdir -p "$PROJECT_DIR/out/apk_artifact"
    rm -rf "${PROJECT_DIR:?}/out/apk_artifact"/*
    gh run download "$RUN_ID" --repo "$REPO_SLUG" -n "ai-web-browser-debug-apk" -D "$PROJECT_DIR/out/apk_artifact"
    APK_FOUND="$(find "$PROJECT_DIR/out/apk_artifact" -name "*.apk" -type f | head -n 1 || true)"
    if [ -n "$APK_FOUND" ] && [ -x "$PROJECT_DIR/bin/adb_ensure_target.sh" ]; then
      TARGET="$("$PROJECT_DIR/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"
      adb -s "$TARGET" wait-for-device
      adb -s "$TARGET" install -r -d "$APK_FOUND"
      adb -s "$TARGET" reverse "tcp:${REVERSE_PORT}" "tcp:${REVERSE_PORT}" >/dev/null 2>&1 || true
      adb -s "$TARGET" shell am force-stop "$PKG_NAME" >/dev/null 2>&1 || true
      adb -s "$TARGET" shell am start -n "$MAIN_ACT" >/dev/null
      sleep 1.2
      PID_AI="$(adb -s "$TARGET" shell pidof "$PKG_NAME" | tr -d '\r' || true)"
      echo "DEPLOY_FINAL=OK APK=$APK_FOUND TARGET=$TARGET PID_AI=${PID_AI:-<none>}"
    fi
  fi
else
  echo "AUTO_BUILD_TRIGGERED=OK — po zakończeniu workflow na GitHub Actions pobierz artefakt 'ai-web-browser-debug-apk' i zainstaluj go poleceniem adb install -r -d <plik.apk>."
fi
