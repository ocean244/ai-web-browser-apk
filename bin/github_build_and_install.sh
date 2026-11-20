#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$HOME/ai-web-browser-apk}"
REMOTE_URL="${2:-}"
BRANCH_NAME="${3:-main}"
RAW_TARGET="${4:-192.168.1.154}"

if [ -z "$REMOTE_URL" ] || [[ "$REMOTE_URL" == *"TWOJ_LOGIN"* ]] || [[ "$REMOTE_URL" == *"TWOJE_REPO"* ]] || [[ "$REMOTE_URL" == *"TWOJA_NAZWA"* ]] || [[ "$REMOTE_URL" == *"<"* ]] || [[ "$REMOTE_URL" == *">"* ]]; then
  echo "ERR: Podaj realny URL istniejącego repozytorium GitHub jako 2. argument (np. https://github.com/LOGIN/REPO.git)" >&2
  exit 1
fi

if [ -n "${GH_TOKEN:-}" ] && [[ "$REMOTE_URL" == https://* ]]; then
  CLEAN_URL="${REMOTE_URL#https://}"
  if [ -n "${GH_USER:-}" ]; then
    AUTH_URL="https://${GH_USER}:${GH_TOKEN}@${CLEAN_URL}"
  else
    AUTH_URL="https://${GH_TOKEN}@${CLEAN_URL}"
  fi
else
  AUTH_URL="$REMOTE_URL"
fi

"$PROJECT_DIR/bin/deploy_github_full_stack.sh" "$PROJECT_DIR" "$REMOTE_URL" "$BRANCH_NAME"
git -C "$PROJECT_DIR" push "$AUTH_URL" "$BRANCH_NAME" --force

if command -v gh >/dev/null 2>&1; then
  REPO_SLUG="$(printf '%s' "$REMOTE_URL" | sed -E 's#^(https?://[^/]+/|git@[^:]+:)##; s#\.git$##')"
  gh workflow run "build-ai-web-apk.yml" --repo "$REPO_SLUG" --ref "$BRANCH_NAME" >/dev/null 2>&1 || true
  sleep 4
  RUN_ID="$(gh run list --repo "$REPO_SLUG" --branch "$BRANCH_NAME" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)"
  if [ -n "$RUN_ID" ]; then
    echo "GH_RUN_ID=$RUN_ID REPO=$REPO_SLUG"
    gh run watch "$RUN_ID" --repo "$REPO_SLUG" --exit-status
    mkdir -p "$PROJECT_DIR/out/apk_artifact"
    gh run download "$RUN_ID" --repo "$REPO_SLUG" -n "ai-web-browser-debug-apk" -D "$PROJECT_DIR/out/apk_artifact"
    APK_FOUND="$(find "$PROJECT_DIR/out/apk_artifact" -name "*.apk" -type f | head -n 1 || true)"
    if [ -n "$APK_FOUND" ]; then
      "$PROJECT_DIR/bin/install_apk_adb.sh" "$APK_FOUND" "$RAW_TARGET"
    fi
  fi
else
  echo "PUSH_DONE=OK — brak CLI 'gh' w Termux; budowa APK ruszyła z pusha na GitHub Actions (sprawdź zakładkę Actions w repozytorium)."
fi
