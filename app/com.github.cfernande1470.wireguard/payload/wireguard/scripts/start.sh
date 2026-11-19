#!/bin/sh
set -eu

HERE="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
. "$HERE/lib.sh"

# WG_FROM_WATCHDOG=1: restart requested by the watchdog (it keeps running).
# WG_KEEP_KILLSWITCH=1: a failed start keeps traffic blocked (boot, watchdog).
FROM_WATCHDOG="${WG_FROM_WATCHDOG:-0}"
KEEP_BLOCK=0
START_OK=0
START_NOTES=""

mkdir -p "$RUN" /var/run/wireguard

if ks_enabled && { [ "${WG_KEEP_KILLSWITCH:-0}" = 1 ] || [ "$FROM_WATCHDOG" = 1 ]; }; then
  KEEP_BLOCK=1
fi

cleanup_failed_start() {
  [ "$START_OK" -eq 0 ] || return 0
  echo
  echo "== start failed: cleaning up =="
  if [ "$KEEP_BLOCK" = 1 ]; then
    teardown_tunnel 1
    write_state blocked "start failed; kill switch keeps traffic blocked"
  else
    [ "$FROM_WATCHDOG" = 1 ] || stop_watchdog
    teardown_tunnel 0
    [ "$FROM_WATCHDOG" = 1 ] || write_state failed "start failed"
  fi
}

on_exit() {
  rc=$?
  set +e
  cleanup_failed_start
  release_lock_dir
  exit "$rc"
}

acquire_operation_lock
trap on_exit EXIT
trap 'exit 1' HUP INT TERM

[ -x "$WG" ] || { echo "ERROR: does not exist $WG"; exit 1; }
[ -x "$WGGO" ] || { echo "ERROR: does not exist $WGGO"; exit 1; }
[ -x "$HERE/exec-clean.sh" ] || { echo "ERROR: missing clean launcher"; exit 1; }
[ -x "$HERE/watchdog.sh" ] || { echo "ERROR: missing watchdog"; exit 1; }
[ -f "$CONF" ] || { echo "ERROR: missing $CONF"; exit 1; }

trim() {
  echo "$1" | sed 's/\r$//;s/[[:space:]]*#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//'
}

lower() {
  echo "$1" | tr 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' 'abcdefghijklmnopqrstuvwxyz'
}

get_key() {
  echo "$1" | sed 's/[[:space:]]*=.*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

get_value() {
  echo "$1" | sed 's/^[^=]*=//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

extract_addresses_from_conf() {
  section=""

  while IFS= read -r raw || [ -n "$raw" ]; do
    line="$(trim "$raw")"
    [ -z "$line" ] && continue

    case "$line" in
      \[*\])
        section="$(lower "$line")"
        continue
        ;;
    esac

    if [ "$section" = "[interface]" ]; then
      case "$line" in
        *=*)
          key="$(lower "$(get_key "$line")")"
          if [ "$key" = "address" ]; then
            value="$(get_value "$line")"
            echo "$value" | tr ',' '\n' | while read -r addr; do
              addr="$(trim "$addr")"
              [ -n "$addr" ] && echo "$addr"
            done > "$ADDRESS_FILE.tmp"
            break
          fi
          ;;
      esac
    fi
  done < "$CONF"

  if [ -f "$ADDRESS_FILE.tmp" ]; then
    mv -f "$ADDRESS_FILE.tmp" "$ADDRESS_FILE"
    chmod 600 "$ADDRESS_FILE"
    echo "Address detected in wg0.conf:"
    cat "$ADDRESS_FILE"
  fi
}

extract_mtu_from_conf() {
  mtu="$(conf_interface_values "$CONF" mtu | head -1)"
  case "$mtu" in
    ""|*[!0-9]*)
      mtu="1420"
      ;;
  esac
  echo "$mtu"
}

# Hostname endpoints are resolved here through the original resolver, so a
# restart also works while the resolver points at the (broken) tunnel DNS.
resolve_endpoint_value() {
  ep="$1"
  case "$ep" in
    \[*) echo "$ep"; return 0 ;;
  esac
  ep_host="$(endpoint_host "$ep")"
  ep_port="$(endpoint_port "$ep")"
  if is_ipv4 "$ep_host"; then
    echo "$ep"
    return 0
  fi
  if ep_addr="$(resolve_or_cached "$ep_host")"; then
    echo "endpoint $ep_host resolved" >&2
    case "$ep_addr" in
      *:*) echo "[$ep_addr]:$ep_port" ;;
      *) echo "$ep_addr:$ep_port" ;;
    esac
  else
    echo "endpoint $ep_host left for wg to resolve" >&2
    echo "$ep"
  fi
}

make_wg_setconf_file() {
  section=""
  : > "$SETCONF_FILE"
  chmod 600 "$SETCONF_FILE"

  while IFS= read -r raw || [ -n "$raw" ]; do
    line="$(trim "$raw")"

    [ -z "$line" ] && continue

    case "$line" in
      \[*\])
        section="$(lower "$line")"
        echo "$line" >> "$SETCONF_FILE"
        continue
        ;;
    esac

    case "$line" in
      *=*)
        key="$(lower "$(get_key "$line")")"
        if [ "$section" = "[interface]" ]; then
          case "$key" in
            address|dns|mtu|table|preup|postup|predown|postdown|saveconfig)
              continue
              ;;
          esac
        fi
        if [ "$section" = "[peer]" ] && [ "$key" = "endpoint" ]; then
          echo "Endpoint = $(resolve_endpoint_value "$(get_value "$line")")" >> "$SETCONF_FILE"
          continue
        fi
        ;;
    esac

    echo "$line" >> "$SETCONF_FILE"
  done < "$CONF"
}

add_route() {
  route="$1"

  case "$route" in
    ""|\#*) return ;;
  esac

  case "$route" in
    *:*)
      echo "WARNING: IPv6 route ignored for now: $route"
      return
      ;;
  esac

  if [ "$route" = "0.0.0.0/0" ]; then
    add_route "0.0.0.0/1"
    add_route "128.0.0.0/1"
    return
  fi

  if ! grep -qxF "$route" "$APPLIED_ROUTES_FILE" 2>/dev/null; then
    echo "$route" >> "$APPLIED_ROUTES_FILE"
  fi
}

[ "$FROM_WATCHDOG" = 1 ] || stop_watchdog
[ "$FROM_WATCHDOG" = 1 ] || write_state starting ""

echo "== previous cleanup =="
teardown_tunnel "$KEEP_BLOCK"

echo
echo "== detecting original default route =="
detect_default4
detect_default6

if [ -n "$D4_DEV" ]; then
  echo "$D4_DEV" > "$DEVFILE"
  echo "$D4_GW" > "$GWFILE"
  echo "original default: ${D4_GW:+via $D4_GW }dev $D4_DEV"
else
  echo "WARNING: cannot find an IPv4 default route outside $IFACE"
fi
if [ -n "$D6_DEV" ]; then
  echo "original IPv6 default: ${D6_GW:+via $D6_GW }dev $D6_DEV"
fi

echo
echo "== preparing configuration =="
extract_addresses_from_conf

[ -f "$ADDRESS_FILE" ] || {
  echo "ERROR: missing Address. Add Address = x.x.x.x/xx to wg0.conf or create $ADDRESS_FILE"
  exit 1
}

MTU="$(extract_mtu_from_conf)"
echo "MTU: $MTU"

make_wg_setconf_file
prepare_dns

echo
echo "== generated wg setconf file =="
sed -E 's#^(PrivateKey[[:space:]]*=[[:space:]]*).*#\1REDACTED#;s#^(PresharedKey[[:space:]]*=[[:space:]]*).*#\1REDACTED#' "$SETCONF_FILE"

echo
echo "== starting wireguard-go =="
# Keep the daemon in foreground mode under this shell's background job so $!
# remains the real long-lived PID instead of the short-lived launcher PID.
LOG_LEVEL=info "$HERE/exec-clean.sh" "$WGGO" -f "$IFACE" >"$LOGFILE" 2>&1 &
echo $! > "$PIDFILE"

sleep 2

if ! ip link show "$IFACE" >/dev/null 2>&1; then
  echo "ERROR: interface was not created: $IFACE"
  cat "$LOGFILE" 2>/dev/null || true
  exit 1
fi

echo "== applying WireGuard configuration =="
"$WG" setconf "$IFACE" "$SETCONF_FILE"
# The converted copy holds the private key; WireGuard has it now.
rm -f "$SETCONF_FILE"

echo "== pinning endpoint routes outside the tunnel =="
if ! pin_endpoints; then
  echo "ERROR: could not route every endpoint outside the tunnel"
  exit 1
fi

# Kill switch routes go in before the tunnel routes, so there is no moment
# where wg0 routes exist without the blocking routes behind them.
if ks_enabled; then
  echo "== kill switch routes =="
  if ks_routes_apply; then
    echo "blackhole routes behind the tunnel routes: on"
  else
    echo "ERROR: kill switch is on but its routes could not be added"
    exit 1
  fi
fi

V6_KEEP=""
if grep -q '^6 ' "$ENDPOINTS_FILE" 2>/dev/null; then
  V6_KEEP="$(cat "$DEV6FILE" 2>/dev/null || true)"
  echo "IPv6 endpoint: IPv6 stays enabled on $V6_KEEP; other IPv6 destinations are blocked"
  v6block_apply
fi
echo "$V6_KEEP" > "$IPV6_KEEP_FILE"

echo "== disabling IPv6 outside the tunnel =="
ipv6_disable_all "$V6_KEEP"

echo "== assigning IP address =="
while IFS= read -r addr || [ -n "$addr" ]; do
  addr="$(trim "$addr")"
  [ -z "$addr" ] && continue

  case "$addr" in
    *:*)
      echo "WARNING: IPv6 Address ignored for now: $addr"
      continue
      ;;
  esac

  echo "addr: $addr dev $IFACE"
  ip addr add "$addr" dev "$IFACE" 2>/dev/null || true
done < "$ADDRESS_FILE"

ip link set mtu "$MTU" up dev "$IFACE"

echo "== generating routes from AllowedIPs =="
: > "$APPLIED_ROUTES_FILE"

grep -i '^[[:space:]]*AllowedIPs[[:space:]]*=' "$CONF" \
  | sed 's/^[^=]*=//' \
  | tr ',' '\n' \
  | sed 's/[[:space:]]*#.*$//;s/^[[:space:]]*//;s/[[:space:]]*$//' \
  | while read -r route; do
      add_route "$route"
    done

if [ -f "$ROUTES_EXTRA_FILE" ]; then
  echo "== adding extra routes =="
  while IFS= read -r route || [ -n "$route" ]; do
    route="$(trim "$route")"
    add_route "$route"
  done < "$ROUTES_EXTRA_FILE"
fi

echo "== applying routes =="
while IFS= read -r route || [ -n "$route" ]; do
  [ -z "$route" ] && continue
  echo "route: $route dev $IFACE"
  ip route replace "$route" dev "$IFACE"
done < "$APPLIED_ROUTES_FILE"

echo "== tunnel DNS =="
if [ -s "$DNS_SERVERS_FILE" ]; then
  if ! dns_apply; then
    echo "WARNING: DNS IS NOT REDIRECTED: lookups may leave outside the tunnel"
    START_NOTES="dns-not-redirected"
  fi
fi

echo "== kill switch =="
if ks_enabled; then
  ks_routes_apply || true
  if ! ipt4_usable; then
    echo "Kill switch: on (routes only: this kernel has no usable iptables)"
  elif ks_apply strict; then
    echo "Kill switch: on (firewall and routes)"
  else
    echo "Kill switch: on (routes only: the firewall rules could not be added)"
  fi
else
  ks_remove
  echo "Kill switch: off"
fi

if [ "$FROM_WATCHDOG" != 1 ]; then
  echo "== starting watchdog =="
  "$HERE/exec-clean.sh" "$HERE/watchdog.sh" >>"$WATCHDOG_LOG" 2>&1 &
  echo $! > "$WATCHDOG_PIDFILE"
fi

echo "== status =="
"$WG" show "$IFACE" | sed -E 's#^([[:space:]]*(private key|preshared key):).*#\1 (hidden)#'
ip addr show "$IFACE"

echo
echo "== relevant routes =="
ip route | grep -E "$IFACE|default" || ip route

write_state up "$START_NOTES"
echo
echo "OK: WireGuard started"
START_OK=1
