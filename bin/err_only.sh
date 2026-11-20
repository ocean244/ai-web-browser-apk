#!/data/data/com.termux/files/usr/bin/bash
set -euo pipefail

REPO_SLUG="ocean244/ai-web-browser-apk"
RUN_ID="${1:-$(gh run list --repo "$REPO_SLUG" --limit 1 --json databaseId --jq '.[0].databaseId // empty')}"

if [ -z "$RUN_ID" ]; then
  echo "Brak RUN_ID" >&2
  exit 1
fi

echo "RUN_ID=$RUN_ID"
gh run view "$RUN_ID" --repo "$REPO_SLUG" --json status,conclusion,url --jq '{status, conclusion, url}'

gh run view "$RUN_ID" --repo "$REPO_SLUG" --log-failed 2>/dev/null \
  | grep -v -E "Transforming |Caching disabled|Build cache is disabled|Caching not enabled" \
  | grep -E -i "error:|exception|failed|failure|what went wrong|cannot find|unresolved|invalid keystore|exit code" \
  | tail -n 35 || true
