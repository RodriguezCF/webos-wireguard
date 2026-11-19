#!/bin/sh
# Keeps the tunnel usable across TV standby, wake-up and network changes.
#
# Started by start.sh through exec-clean.sh and stopped by stop.sh. It only
# runs while $WATCHDOG_PIDFILE names this process. Every few seconds it:
#   - re-pins the endpoint routes when the default gateway or interface
#     changed or the pinned route vanished (a link restart after standby
#     flushes them, and encrypted packets would then loop into wg0),
#   - re-applies disabled IPv6, the DNS redirection and the kill switch,
#   - probes the tunnel when the last handshake is older than 3 minutes,
#     re-resolves hostname endpoints and repairs what it can,
#   - when the tunnel cannot be repaired: keeps traffic blocked if the kill
#     switch is on; otherwise, after FALLBACK_AFTER failed rounds, removes the
#     VPN catch-all routes so the TV keeps internet access (unprotected) and
#     restores them as soon as the tunnel works again.
set -u

SELF="$(readlink -f "$0" 2>/dev/null || echo "$0")"
HERE="$(CDPATH= cd -- "$(dirname -- "$SELF")" && pwd)"
. "$HERE/lib.sh"

INTERVAL=5
SLOW_INTERVAL=15
STALE_AFTER=180
GRACE=45
PROBE_EVERY=20
FALLBACK_AFTER=6
RESTART_EVERY=60
RESOLVE_EVERY=60

last_state=""
last_detail=""
ks_note=""
fails=0
fallback=0
probe_at=0
resolve_at=0
restart_at=0
started="$(now_s)"
interval="$INTERVAL"

log() {
  [ -n "$*" ] || return 0
  if [ -f "$WATCHDOG_LOG" ] && [ "$(wc -c < "$WATCHDOG_LOG" 2>/dev/null || echo 0)" -gt 65536 ]; then
    # Truncate in place: stdout of this process also points at this file.
    tail -n 200 "$WATCHDOG_LOG" > "$WATCHDOG_LOG.tmp" 2>/dev/null &&
      cat "$WATCHDOG_LOG.tmp" > "$WATCHDOG_LOG"
    rm -f "$WATCHDOG_LOG.tmp"
  fi
  lg_ts="$(date '+%Y-%m-%d %H:%M:%S')"
  echo "$*" | while IFS= read -r lg_line; do
    echo "$lg_ts $lg_line"
  done >> "$WATCHDOG_LOG"
}

set_state() {
  if [ "$1" != "$last_state" ] || [ "${2:-}" != "$last_detail" ]; then
    write_state "$1" "${2:-}"
    log "state: $1${2:+ ($2)}"
    last_state="$1"
    last_detail="${2:-}"
  fi
}

# Runs a repair step in this process (not in a subshell), so stop.sh can end
# every repair by stopping this one PID, and logs what the step printed.
WATCHDOG_OUT="$RUN/watchdog.out"
run_logged() {
  "$@" > "$WATCHDOG_OUT" 2>&1
  rl_rc=$?
  log "$(cat "$WATCHDOG_OUT" 2>/dev/null)"
  return "$rl_rc"
}

latest_handshake() {
  "$WG" show "$IFACE" latest-handshakes 2>/dev/null |
    awk 'BEGIN { m = 0 } $2 > m { m = $2 } END { print m }'
}

# A packet to an address routed through wg0 makes WireGuard start a new
# handshake when the session is old. The tunnel DNS server is preferred.
probe_target() {
  pt="$(head -1 "$DNS_SERVERS_FILE" 2>/dev/null || true)"
  if [ -z "$pt" ] && [ -f "$APPLIED_ROUTES_FILE" ]; then
    if grep -qx '0.0.0.0/1' "$APPLIED_ROUTES_FILE"; then
      pt="1.1.1.1"
    else
      pt="$(head -1 "$APPLIED_ROUTES_FILE" | sed 's#/.*##;s#\.0$#.1#')"
    fi
  fi
  echo "$pt"
}

send_probe() {
  sp_ip="$(probe_target)"
  [ -n "$sp_ip" ] || return 0
  ping -c 1 -W 2 "$sp_ip" >/dev/null 2>&1 || true
}

catchall_remove() {
  for cr_r in 0.0.0.0/1 128.0.0.0/1; do
    if grep -qxF "$cr_r" "$APPLIED_ROUTES_FILE" 2>/dev/null; then
      ip route del "$cr_r" dev "$IFACE" 2>/dev/null || true
    fi
  done
  dns_restore
  cr_probe="$(probe_target)"
  if [ -n "$cr_probe" ] && ip route replace "$cr_probe" dev "$IFACE" 2>/dev/null; then
    echo "$cr_probe" > "$PROBE_ROUTE_FILE"
  fi
}

catchall_restore() {
  if [ -f "$PROBE_ROUTE_FILE" ]; then
    ip route del "$(cat "$PROBE_ROUTE_FILE")" dev "$IFACE" 2>/dev/null || true
    rm -f "$PROBE_ROUTE_FILE"
  fi
  while read -r cs_r; do
    [ -n "$cs_r" ] || continue
    ip route replace "$cs_r" dev "$IFACE" 2>/dev/null || true
  done < "$APPLIED_ROUTES_FILE"
  dns_apply || true
}

# Notes shown with the "up" state, as start.sh reports them.
up_detail() {
  ud=""
  if [ -s "$DNS_SERVERS_FILE" ] && [ ! -f "$DNS_MODE_FILE" ]; then
    ud="dns-not-redirected"
  fi
  echo "$ud"
}

restart_tunnel() {
  rt_out="$(WG_FROM_WATCHDOG=1 "$HERE/start.sh" 2>&1)"
  rt_rc=$?
  log "$(echo "$rt_out" | tail -n 15)"
  return "$rt_rc"
}

log "watchdog started (pid $$)"

while :; do
  sleep "$interval"
  [ "$(cat "$WATCHDOG_PIDFILE" 2>/dev/null)" = "$$" ] || { log "watchdog stopped"; exit 0; }
  operation_busy && continue

  now="$(now_s)"
  ks_on=0
  ks_enabled && ks_on=1

  # 1. The tunnel process and interface must exist.
  if ! tunnel_running; then
    if [ "$ks_on" = 1 ]; then
      set_state blocked "tunnel process stopped"
      # The blackhole routes took over when wg0 vanished; keep them and keep
      # the resolver pointed only at the tunnel DNS (never the LAN router).
      run_logged ks_routes_apply
      run_logged dns_check
    else
      set_state down-unprotected "tunnel process stopped"
      # Without wg0 the tunnel DNS is unreachable; give the TV its resolver back.
      [ -f "$DNS_MODE_FILE" ] && run_logged dns_restore
    fi
    if [ $((now - restart_at)) -ge "$RESTART_EVERY" ]; then
      restart_at="$now"
      log "restarting the tunnel"
      if restart_tunnel; then
        fails=0
        fallback=0
        started="$(now_s)"
        log "tunnel restarted"
      fi
    fi
    interval="$SLOW_INTERVAL"
    continue
  fi

  # 2. Wait for the physical network (standby, Wi-Fi reconnect, cable).
  detect_default4
  detect_default6
  if [ -z "$D4_DEV" ] && [ -z "$D6_DEV" ]; then
    if [ "$ks_on" = 1 ]; then
      set_state blocked "waiting for network"
    else
      set_state repairing "waiting for network"
    fi
    interval="$INTERVAL"
    continue
  fi

  # 3. Endpoint routes must leave through the current physical interface.
  if ! endpoint_routes_ok; then
    log "network changed (default ${D4_GW:-none} dev ${D4_DEV:-none}); pinning endpoint routes again"
    run_logged pin_endpoints
    probe_at=0
  fi

  # 4. IPv6, DNS and kill switch state.
  run_logged ipv6_disable_all "$(cat "$IPV6_KEEP_FILE" 2>/dev/null || true)"
  [ "$fallback" = 1 ] || run_logged dns_check
  ks_enforce > "$WATCHDOG_OUT" 2>&1
  ks_out="$(cat "$WATCHDOG_OUT" 2>/dev/null)"
  if [ "$ks_out" != "$ks_note" ]; then
    log "$ks_out"
    ks_note="$ks_out"
  fi

  # 5. Tunnel health from the latest handshake.
  hs="$(latest_handshake)"
  [ -n "$hs" ] || hs=0
  age=$((now - hs))
  if [ "$hs" -gt 0 ] && [ "$age" -le "$STALE_AFTER" ]; then
    if [ "$fallback" = 1 ]; then
      log "TUNNEL RECOVERED: traffic goes through the VPN again"
      run_logged catchall_restore
      fallback=0
    fi
    fails=0
    interval="$INTERVAL"
    set_state up "$(up_detail)"
    continue
  fi

  [ $((now - started)) -ge "$GRACE" ] || continue

  if [ $((now - probe_at)) -ge "$PROBE_EVERY" ]; then
    probe_at="$now"
    send_probe
    continue
  fi

  fails=$((fails + 1))
  if [ "$hs" -gt 0 ]; then
    log "no handshake for ${age}s; repair attempt $fails"
  else
    log "no handshake yet; repair attempt $fails"
  fi
  if [ $((now - resolve_at)) -ge "$RESOLVE_EVERY" ]; then
    resolve_at="$now"
    run_logged reresolve_endpoints
  fi
  run_logged pin_endpoints

  if [ "$ks_on" = 1 ]; then
    set_state blocked "tunnel down; kill switch blocks traffic"
  elif [ "$fails" -ge "$FALLBACK_AFTER" ]; then
    if [ "$fallback" = 0 ]; then
      log "VPN DOWN: removing the VPN catch-all routes so the TV keeps internet access. TRAFFIC IS NOT PROTECTED."
      run_logged catchall_remove
      fallback=1
    fi
    set_state down-unprotected "tunnel down; traffic uses the normal network"
  else
    set_state repairing "no recent handshake"
  fi

  if [ "$fails" -ge "$FALLBACK_AFTER" ]; then
    interval="$SLOW_INTERVAL"
  else
    interval="$INTERVAL"
  fi
done
