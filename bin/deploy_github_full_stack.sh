#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$HOME/ai-web-browser-apk}"
REMOTE_URL="${2:-}"
BRANCH_NAME="${3:-main}"

cd "$PROJECT_DIR"

cat << 'GITIGNORE' > "$PROJECT_DIR/.gitignore"
.gradle/
build/
**/build/
local.properties
.idea/
*.iml
tmp/
*.log
GITIGNORE

if [ ! -d "$PROJECT_DIR/.git" ]; then
  git init -b "$BRANCH_NAME"
fi

git config user.name "${GIT_USER_NAME:-Rafal Tomaszewski}"
git config user.email "${GIT_USER_EMAIL:-rafal@tomaszewski.pl}"

if [ -n "$REMOTE_URL" ]; then
  if git remote get-url origin >/dev/null 2>&1; then
    git remote set-url origin "$REMOTE_URL"
  else
    git remote add origin "$REMOTE_URL"
  fi
fi

git add -A
if ! git diff --cached --quiet; then
  git commit -m "feat(aiweb): full-stack AI web browser & search engine + GitHub Actions APK build"
fi

if git remote get-url origin >/dev/null 2>&1; then
  git push -u origin "$BRANCH_NAME" --force
  echo "GITHUB_PUSH=OK BRANCH=$BRANCH_NAME REMOTE=$(git remote get-url origin)"
else
  echo "ERR: Brak zdalnego repozytorium GitHub (podaj URL jako 2. argument: deploy_github_full_stack.sh \"$PROJECT_DIR\" \"https://github.com/USER/REPO.git\")" >&2
  exit 1
fi
