#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:-$HOME/ai-web-browser-apk}"
REPO_SLUG="${2:-ocean244/ai-web-browser-apk}"
RUN_ID="${3:-44684034089}"
RAW_TARGET="${4:-192.168.1.154}"
REVERSE_PORT="${5:-18080}"
PKG_NAME="pl.tomaszewski.aiweb"
MAIN_ACT="pl.tomaszewski.aiweb/.MainActivity"
OUT_DIR="$PROJECT_DIR/out/release_apk"

mkdir -p "$OUT_DIR"
rm -rf "${OUT_DIR:?}"/*

APK_FILE=""

if command -v gh >/dev/null 2>&1; then
  gh release download --repo "$REPO_SLUG" -p "*.apk" -D "$OUT_DIR" >/dev/null 2>&1 || true
  APK_FILE="$(find "$OUT_DIR" -name "*.apk" -type f | head -n 1 || true)"

  if [ -z "$APK_FILE" ] && [ -n "$RUN_ID" ]; then
    gh run download "$RUN_ID" --repo "$REPO_SLUG" -D "$OUT_DIR" >/dev/null 2>&1 || true
    APK_FILE="$(find "$OUT_DIR" -name "*.apk" -type f | head -n 1 || true)"
  fi
fi

if [ -z "$APK_FILE" ]; then
  API_URL="https://api.github.com/repos/${REPO_SLUG}/releases"
  ASSET_URL="$(curl -fsSL "$API_URL" | grep -oE '"browser_download_url":[[:space:]]*"[^"]+\.apk"' | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)"
  if [ -n "$ASSET_URL" ]; then
    APK_FILE="$OUT_DIR/ai-web-browser-release.apk"
    curl -fSL "$ASSET_URL" -o "$APK_FILE"
  fi
fi

if [ -z "$APK_FILE" ] || [ ! -s "$APK_FILE" ]; then
  echo "ERR: Nie znaleziono pliku APK w GitHub Releases ani w artefaktach runu $RUN_ID dla repozytorium $REPO_SLUG" >&2
  exit 1
fi

TARGET="$("$PROJECT_DIR/bin/adb_ensure_target.sh" "$RAW_TARGET" 3)"
adb -s "$TARGET" wait-for-device
adb -s "$TARGET" install -r -d "$APK_FILE"
adb -s "$TARGET" reverse "tcp:${REVERSE_PORT}" "tcp:${REVERSE_PORT}" >/dev/null 2>&1 || true
adb -s "$TARGET" shell am force-stop "$PKG_NAME" >/dev/null 2>&1 || true
adb -s "$TARGET" shell am start -n "$MAIN_ACT" >/dev/null
sleep 1.2

PID_AI="$(adb -s "$TARGET" shell pidof "$PKG_NAME" | tr -d '\r' || true)"
echo "DEPLOY_RELEASE=OK APK=$APK_FILE TARGET=$TARGET PID_AI=${PID_AI:-<none>}"
[ -n "$PID_AI" ] && adb -s "$TARGET" shell logcat -d --pid="$PID_AI" | grep -E "AiWebMainActivity|AndroidNative|E/|F/" | tail -n 15 || true
