#!/usr/bin/env bash
set -euo pipefail

RAW_TARGET="${1:-}"
RETRIES="${2:-3}"
TMP_DIR="${TMPDIR:-$HOME/tmp}"
mkdir -p "$TMP_DIR"
CACHE_FILE="$TMP_DIR/adb_last_target.txt"

extract_ip() {
  local val="$1"
  if [[ "$val" =~ ^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)(:[0-9]+)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
  fi
}

is_device_online() {
  local cand="$1"
  [ -z "$cand" ] && return 1
  adb devices 2>/dev/null | awk -v t="$cand" '$1 == t && $2 == "device" { found=1 } END { exit(found ? 0 : 1) }'
}

find_online_for_ip() {
  local ip="$1"
  [ -z "$ip" ] && return 1
  adb devices 2>/dev/null | awk -v prefix="${ip}:" '$1 ~ "^" prefix && $2 == "device" { print $1; exit }'
}

scan_all_ports_and_connect() {
  local ip="$1"
  [ -z "$ip" ] && return 1
  python3 - "$ip" << 'PY'
import socket, subprocess, sys
from concurrent.futures import ThreadPoolExecutor, as_completed

ip = sys.argv[1]
ports = [39993, 43813, 38911, 5555] + [p for p in range(30000, 65536) if p not in (39993, 43813, 38911, 5555)]

def probe(port):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.03)
    try:
        if s.connect_ex((ip, port)) == 0:
            return port
    except OSError:
        pass
    finally:
        s.close()
    return None

open_ports = []
with ThreadPoolExecutor(max_workers=128) as pool:
    futures = [pool.submit(probe, p) for p in ports]
    for fut in as_completed(futures):
        res = fut.result()
        if res is not None:
            open_ports.append(res)

for p in open_ports:
    try:
        subprocess.run(["adb", "connect", f"{ip}:{p}"], capture_output=True, text=True, timeout=2)
        devs = subprocess.run(["adb", "devices"], capture_output=True, text=True, timeout=2).stdout
        if f"{ip}:{p}\tdevice" in devs:
            print(f"{ip}:{p}")
            sys.exit(0)
    except subprocess.TimeoutExpired:
        subprocess.run(["adb", "disconnect", f"{ip}:{p}"], capture_output=True, text=True, timeout=2)
    except OSError:
        pass

sys.exit(1)
PY
}

adb start-server >/dev/null 2>&1 || true

CANDIDATES=()
if [ -f "$CACHE_FILE" ]; then
  CACHED="$(tr -d '[:space:]' < "$CACHE_FILE" || true)"
  [ -n "$CACHED" ] && CANDIDATES+=("$CACHED")
fi
[ -n "$RAW_TARGET" ] && CANDIDATES+=("$RAW_TARGET")
while IFS= read -r dev_line; do
  [ -n "$dev_line" ] && CANDIDATES+=("$dev_line")
done < <(adb devices 2>/dev/null | awk '$2 == "device" { print $1 }')

for cand in "${CANDIDATES[@]}"; do
  if is_device_online "$cand"; then
    printf '%s\n' "$cand" > "$CACHE_FILE"
    printf '%s\n' "$cand"
    exit 0
  fi
done

TARGET_IP="$(extract_ip "$RAW_TARGET")"
if [ -z "$TARGET_IP" ] && [ -f "$CACHE_FILE" ]; then
  TARGET_IP="$(extract_ip "$(tr -d '[:space:]' < "$CACHE_FILE" || true)")"
fi

for (( attempt=1; attempt<=RETRIES; attempt++ )); do
  if [ -n "$TARGET_IP" ]; then
    ONLINE_IP_DEV="$(find_online_for_ip "$TARGET_IP" || true)"
    if [ -n "$ONLINE_IP_DEV" ]; then
      printf '%s\n' "$ONLINE_IP_DEV" > "$CACHE_FILE"
      printf '%s\n' "$ONLINE_IP_DEV"
      exit 0
    fi

    SCANNED_DEV="$(scan_all_ports_and_connect "$TARGET_IP" 2>/dev/null || true)"
    if [ -n "$SCANNED_DEV" ] && is_device_online "$SCANNED_DEV"; then
      printf '%s\n' "$SCANNED_DEV" > "$CACHE_FILE"
      printf '%s\n' "$SCANNED_DEV"
      exit 0
    fi
  fi

  sleep 0.3
done

echo "ERR: Brak aktywnego urządzenia ADB dla celu=${RAW_TARGET:-<brak>}" >&2
exit 1
