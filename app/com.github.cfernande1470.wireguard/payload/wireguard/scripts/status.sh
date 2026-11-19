#!/bin/sh

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/lib.sh"

echo "== state =="
cat "$STATE_FILE" 2>/dev/null || echo "state=stopped"
echo "killswitch=$(ks_status_word)"

echo
echo "== process =="
ps | grep -E 'wireguard-go|watchdog\.sh' | grep -v grep || true

echo
echo "== interface =="
ip addr show "$IFACE" 2>/dev/null || echo "$IFACE does not exist"

echo
echo "== WireGuard =="
"$WG" show "$IFACE" 2>/dev/null || true

echo
echo "== wg0 routes =="
ip route | grep "$IFACE" || true

echo
echo "== endpoint routes =="
cat "$ENDPOINTS_FILE" 2>/dev/null || true

echo
echo "== resolver =="
cat /etc/resolv.conf 2>/dev/null || true

echo
echo "== log =="
tail -40 "$LOGFILE" 2>/dev/null || true

echo
echo "== watchdog log =="
tail -20 "$WATCHDOG_LOG" 2>/dev/null || true
