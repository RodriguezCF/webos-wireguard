#!/bin/sh
# Machine-readable status for the app (key=value lines). Never prints keys.
#   summary.sh         tunnel, watchdog, kill switch, autostart, boot result
#   summary.sh pubip   public IPv4 address as seen from the internet

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/lib.sh"

public_ipv4() {
  command -v curl >/dev/null 2>&1 || return 1
  for pi_url in https://api.ipify.org https://ifconfig.me/ip http://api.ipify.org http://ifconfig.me/ip; do
    pi_ip="$(curl -4 -s --max-time 6 "$pi_url" 2>/dev/null | head -1 | tr -d '\r\n ')"
    if is_ipv4 "$pi_ip"; then
      echo "$pi_ip"
      return 0
    fi
  done
  return 1
}

if [ "${1:-}" = pubip ]; then
  echo "pubip=$(public_ipv4 || true)"
  exit 0
fi

echo "installed=1"

state="$(read_kv "$STATE_FILE" state)"
since="$(read_kv "$STATE_FILE" since)"
detail="$(read_kv "$STATE_FILE" detail)"
running=0
tunnel_running && running=1

if [ "$running" = 0 ]; then
  case "$state" in
    up|repairing) state="stopped"; detail="" ;;
    starting) operation_busy || { state="stopped"; detail=""; } ;;
    "") state="stopped" ;;
  esac
fi
[ -n "$state" ] || state="stopped"

watchdog=0
wd_pid="$(cat "$WATCHDOG_PIDFILE" 2>/dev/null || true)"
[ -n "$wd_pid" ] && kill -0 "$wd_pid" 2>/dev/null && watchdog=1

echo "state=$state"
echo "since=$since"
echo "detail=$detail"
echo "running=$running"
echo "watchdog=$watchdog"
echo "now=$(now_s)"
echo "killswitch=$(ks_status_word)"
if ks_enabled; then echo "ks_setting=1"; else echo "ks_setting=0"; fi
if [ -L "$INIT_FILE" ] && [ -x "$INIT_FILE" ]; then echo "autostart=1"; else echo "autostart=0"; fi

server="$(peer_endpoints_from_conf | head -1 | awk '{ print $2 }')"
echo "server=$(endpoint_host "${server:-}")"

if [ "$running" = 1 ]; then
  # Peer lines only (line 1 holds the interface private key).
  "$WG" show "$IFACE" dump 2>/dev/null | awk '
    NR > 1 {
      if (ep == "" && $3 != "(none)") ep = $3
      if ($5 > hs) hs = $5
      rx += $6
      tx += $7
    }
    END {
      printf "endpoint=%s\nhandshake=%d\nrx=%.0f\ntx=%.0f\n", ep, hs, rx, tx
    }'
fi

if [ -f "$BOOT_RESULT_FILE" ]; then
  sed 's/^/boot_/' "$BOOT_RESULT_FILE"
fi
exit 0
