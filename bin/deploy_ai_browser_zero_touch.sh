#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$HOME/ai-web-browser-apk}"
BRANCH_NAME="${2:-main}"
RAW_TARGET="${3:-192.168.1.154}"
REVERSE_PORT="${4:-18080}"
PKG_NAME="pl.tomaszewski.aiweb"
MAIN_ACT="pl.tomaszewski.aiweb/.MainActivity"

is_placeholder_url() {
  local u="$1"
  [ -z "$u" ] && return 0
  case "$u" in
    *"<"*|*">"*|*"TWOJ_LOGIN"*|*"TWOJE_REPO"*|*"TWOJA_NAZWA"*)
      return 0
      ;;
  esac
  return 1
}

cd "$PROJECT_DIR"

for cfg_file in "$HOME/.aiweb_env" "$PROJECT_DIR/.aiweb_env"; do
  if [ -f "$cfg_file" ]; then
    set -a
    # shellcheck disable=SC1090
    source "$cfg_file"
    set +a
  fi
done

REMOTE_URL="${AIWEB_REPO_URL:-${GH_REPO_URL:-${GIT_REMOTE_URL:-}}}"
if [ -z "$REMOTE_URL" ] && git remote get-url origin >/dev/null 2>&1; then
  cand="$(git remote get-url origin)"
  if ! is_placeholder_url "$cand"; then
    REMOTE_URL="$cand"
  fi
fi

GH_USER_VAL="${AIWEB_GH_USER:-${GH_USER:-}}"
GH_TOKEN_VAL="${AIWEB_GH_TOKEN:-${GH_TOKEN:-${GITHUB_TOKEN:-}}}"

if [ -z "$GH_TOKEN_VAL" ] && command -v gh >/dev/null 2>&1; then
  GH_TOKEN_VAL="$(gh auth token 2>/dev/null || true)"
fi

if [ -z "$REMOTE_URL" ] && [ -n "$GH_TOKEN_VAL" ] && command -v gh >/dev/null 2>&1; then
  gh_login="$(gh api user --jq '.login' 2>/dev/null || true)"
  if [ -n "$gh_login" ]; then
    REMOTE_URL="https://github.com/${gh_login}/ai-web-browser-apk.git"
  fi
fi

if is_placeholder_url "$REMOTE_URL"; then
  echo "AUTO_STATUS=WAITING_REMOTE_ENDPOINT"
  echo "Zapisz docelowy URL repozytorium w ~/.aiweb_env jako: AIWEB_REPO_URL=https://github.com/LOGIN/REPO.git (oraz opcjonalnie AIWEB_GH_USER i AIWEB_GH_TOKEN) i uruchom ponownie ten sam skrypt bez argumentów."
  exit 0
fi

cat << 'GITIGNORE' > "$PROJECT_DIR/.gitignore"
.gradle/
build/
**/build/
local.properties
.idea/
*.iml
tmp/
out/apk_artifact/
.aiweb_env
*.log
GITIGNORE

if [ ! -d "$PROJECT_DIR/.git" ]; then
  git init -b "$BRANCH_NAME"
fi

git config user.name "${GIT_USER_NAME:-Rafal Tomaszewski}"
git config user.email "${GIT_USER_EMAIL:-rafal@tomaszewski.pl}"
git remote add origin "$REMOTE_URL" 2>/dev/null || git remote set-url origin "$REMOTE_URL"

git add -A
if ! git diff --cached --quiet; then
  git commit -m "feat(aiweb): zero-touch AI web browser & search engine build"
fi

if [ -n "$GH_TOKEN_VAL" ] && [[ "$REMOTE_URL" == https://* ]]; then
  CLEAN_URL="${REMOTE_URL#https://}"
  if [ -n "$GH_USER_VAL" ]; then
    AUTH_URL="https://${GH_USER_VAL}:${GH_TOKEN_VAL}@${CLEAN_URL}"
  else
    AUTH_URL="https://${GH_TOKEN_VAL}@${CLEAN_URL}"
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
  echo "AUTO_BUILD_TRIGGERED=OK BRANCH=$BRANCH_NAME"
fi
