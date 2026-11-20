#!/usr/bin/env bash
set -euo pipefail

TARGET="${1:-192.168.1.154:33131}"
PKG="pl.tomaszewski.aiweb"
MAIN_ACT="pl.tomaszewski.aiweb.MainActivity"
REPO_DIR="${HOME}/ai-web-browser-apk"
MAIN_KT="${REPO_DIR}/app/src/main/java/pl/tomaszewski/aiweb/MainActivity.kt"
OUT_DIR="${REPO_DIR}/out"
REPORT_FILE="${OUT_DIR}/verify_report.txt"

mkdir -p "${OUT_DIR}"

{
  echo "=== WERYFIKACJA CELU: ${TARGET} | PAKIET: ${PKG} | $(date -Iseconds) ==="

  adb connect "${TARGET}" >/dev/null 2>&1 || true
  adb -s "${TARGET}" wait-for-device

  echo "--- [1/4] STAN PAKIETU I PROCESU ---"
  adb -s "${TARGET}" shell "pm path ${PKG}; dumpsys package ${PKG} | grep -E 'versionCode|versionName|enabled|stopped' || true; ps -A | grep -E 'aiweb|${PKG}' || true"

  echo "--- [2/4] KONTROLA KODU MainActivity.kt ---"
  if [[ -f "${MAIN_KT}" ]]; then
    awk '{printf "%4d  %s\n", NR, $0}' "${MAIN_KT}"
    grep -E "setContentView|initWebView|addJavascriptInterface|AndroidNative|postChatCompletion|openExternalUrl|goBack|goForward|mainHandler" "${MAIN_KT}" || echo "UWAGA: Brak jednego z kluczowych symboli w MainActivity.kt"
  else
    echo "BŁĄD: Brak pliku ${MAIN_KT}"
    exit 1
  fi

  echo "--- [3/4] CZYSTY RESTART I SNAPSHOT LOGÓW ---"
  adb -s "${TARGET}" shell "am force-stop ${PKG}; monkey -p ${PKG} -c android.intent.category.LAUNCHER 1" >/dev/null
  sleep 2
  "${REPO_DIR}/bin/run_clean_snapshot.sh" "${TARGET}"

  echo "--- [4/4] ANALIZA LOGCAT (CRASH / FATAL / ACTIVITY) ---"
  adb -s "${TARGET}" logcat -d | grep -E "AndroidRuntime|FATAL EXCEPTION|${PKG}|MainActivity" | tail -n 60 || true
  adb -s "${TARGET}" shell "ps -A | grep -E 'aiweb|${PKG}' || echo 'PROCES_NIEAKTYWNY'"
  adb -s "${TARGET}" shell "dumpsys activity activities | grep -A 5 -E '${MAIN_ACT}|${PKG}' || true"
} | tee "${REPORT_FILE}"

echo "RAPORT_ZAPISANY=${REPORT_FILE}"
